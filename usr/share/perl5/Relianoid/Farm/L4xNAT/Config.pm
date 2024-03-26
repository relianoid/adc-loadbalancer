#!/usr/bin/perl
###############################################################################
#
#    RELIANOID Software License
#    This file is part of the RELIANOID Load Balancer software package.
#
#    Copyright (C) 2014-today RELIANOID
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

use strict;
use warnings;
use feature qw(signatures);

use Relianoid::Config;
use Relianoid::Nft;

my $eload     = eval { require Relianoid::ELoad };
my $configdir = &getGlobalConfiguration('configdir');

=pod

=head1 Module

Relianoid::Farm::L4xNAT::Config

=cut

=pod

=head1 getL4FarmParam

Returns farm parameter

Parameters:

    param - requested parameter. The options are:

        "vip":          get the virtual IP
        "vipp":         get the virtual port
        "bootstatus":   get boot status
        "status":       get the current status
        "mode":         get the topology (or nat type)
        "alg":          get the algorithm
        "proto":        get the protocol
        "persist":      get persistence
        "persisttm":    get client persistence timeout
        "limitrst":     limit RST request per second
        "limitrstbrst": limit RST request per second burst
        "limitsec":     connection limit per second
        "limitsecbrst": Connection limit per second burst
        "limitconns":   total connections limit per source IP
        "bogustcpflags": check bogus TCP flags
        "nfqueue":      queue to verdict the packets
        "sourceaddr":   get the source address

    farm_name - Farm name

Returns:

    Scalar - return the parameter as a string or -1 on failure

=cut

sub getL4FarmParam ($param, $farm_name) {
    require Relianoid::Farm::Core;

    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    if ($param eq "status") {
        return &getL4FarmStatus($farm_name);
    }

    if ($param eq "alg") {
        require Relianoid::Farm::L4xNAT::L4sd;
        my $l4sched = &getL4sdType($farm_name);
        return $l4sched if ($l4sched ne "");
    }

    open my $fd, '<', "$configdir/$farm_filename";
    chomp(my @content = <$fd>);
    close $fd;

    $output = &_getL4ParseFarmConfig($param, undef, \@content);

    return $output;
}

=pod

=head1 setL4FarmParam

    Writes a farm parameter

Parameters:

    param - requested parameter. The options are:

        "name":         new farm name
        "family":       write ipv4 or ipv6
        "vip":          write the virtual IP
        "vipp":         write the virtual port
        "status" or "bootstatus":
                        write the status and boot status
        "mode":         write the topology (or nat type)
        "alg":          write the algorithm
        "proto":        write the protocol
        "persist":      write persistence
        "persisttm":    write client persistence timeout
        "limitrst":     limit RST request per second
        "limitrstbrst": limit RST request per second burst
        "limitsec":     connection limit per second
        "limitsecbrst": Connection limit per second burst
        "limitconns":   total connections limit per source IP
        "bogustcpflags": check bogus TCP flags
        "nfqueue":      queue to verdict the packets
        "policy":       policy list to be applied
        "sourceaddr":   set the source address

    value - the new value of the given parameter of a certain farm

    farm_name - Farm name

Returns:

    Scalar - return the parameter as a string or -1 on failure

=cut

sub setL4FarmParam ($param, $value, $farm_name) {
    require Relianoid::Farm::Core;

    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;
    my $srvparam      = "";
    my $addition      = "";
    my $prev_config   = "";
    my $farm_req      = $farm_name;
    my $parameters    = "";

    if ($param eq "name") {
        $farm_filename = "${value}_l4xnat.cfg";
        $farm_req      = $value;
        $parameters    = qq(, "newname" : "$value" );
    }
    elsif ($param eq "family") {
        $parameters = qq(, "family" : "$value" );
    }
    elsif ($param eq "mode") {
        $value      = "snat"     if ($value eq "nat");
        $value      = "stlsdnat" if ($value eq "stateless_dnat");
        $parameters = qq(, "mode" : "$value" );

        # deactivate leastconn and persistence for ingress modes
        if ($value eq "dsr" || $value eq "stateless_dnat") {
            require Relianoid::Farm::L4xNAT::L4sd;
            &setL4sdType($farm_name, "none");

            if ($eload) {

                # unassign DoS & RBL
                &eload(
                    module => 'Relianoid::IPDS::Base',
                    func   => 'runIPDSStopByFarm',
                    args   => [ $farm_name, "dos" ],
                );
                &eload(
                    module => 'Relianoid::IPDS::Base',
                    func   => 'runIPDSStopByFarm',
                    args   => [ $farm_name, "rbl" ],
                );
            }
        }

        # take care of floating interfaces without masquerading
        if ($value eq "snat" && $eload) {
            my $farm_ref = &getL4FarmStruct($farm_name);
            &eload(
                module => 'Relianoid::Net::Floating',
                func   => 'setFloatingSourceAddr',
                args   => [ $farm_ref, undef ],
            );
        }
    }
    elsif ($param eq "vip") {
        $prev_config = &getFarmStruct($farm_name);
        require Relianoid::Net::Validate;
        my $vip_family = "ipv" . &ipversion($value);
        $parameters = qq(, "virtual-addr" : "$value", "family" : "$vip_family" );
    }
    elsif ($param eq "vipp" or $param eq "vport") {
        $value =~ s/\:/\-/g;
        if ($value eq "*") {
            $parameters = qq(, "virtual-ports" : "" );
        }
        else {
            $parameters = qq(, "virtual-ports" : "$value" );
        }
    }
    elsif ($param eq "alg") {
        $value = "rr" if ($value eq "roundrobin");

        if ($value eq "hash_srcip_srcport") {
            $value    = "hash";
            $addition = $addition . qq( , "sched-param" : "srcip srcport" );
        }

        if ($value eq "hash_srcip") {
            $value    = "hash";
            $addition = $addition . qq( , "sched-param" : "srcip" );
        }

        require Relianoid::Farm::L4xNAT::L4sd;
        if ($value eq "leastconn") {
            &setL4sdType($farm_name, $value);
            $value = "weight";
        }
        else {
            &setL4sdType($farm_name, "none");
        }

        $parameters = qq(, "scheduler" : "$value" ) . $addition;
    }
    elsif ($param eq "proto") {
        $srvparam = "protocol";

        &loadL4Modules($value);

        if ($value =~ /^ftp|irc|pptp|sane/) {
            $addition = $addition . qq( , "helper" : "$value" );
            $value    = "tcp";
        }
        elsif ($value =~ /tftp|snmp|amanda|netbios-ns/) {
            $addition = $addition . qq( , "helper" : "$value" );
            $value    = "udp";
        }
        elsif ($value =~ /all/) {
            $addition = $addition . qq( , "helper" : "none" );
            $addition = $addition . qq( , "virtual-ports" : "" );
        }
        elsif ($value =~ /sip|h323/) {
            $addition = $addition . qq( , "helper" : "$value" );
            $value    = "all";
        }
        else {
            $addition = $addition . qq( , "helper" : "none" );
        }

        $parameters = qq(, "protocol" : "$value" ) . $addition;
    }
    elsif ($param eq "status" || $param eq "bootstatus") {
        $parameters = qq(, "state" : "$value" );
    }
    elsif ($param eq "persist") {
        $value      = "srcip" if ($value eq "ip");
        $value      = "none"  if ($value eq "");
        $parameters = qq(, "persistence" : "$value" );
    }
    elsif ($param eq "persisttm") {
        $parameters = qq(, "persist-ttl" : "$value" );
    }
    elsif ($param eq "limitrst") {
        $parameters = qq(, "rst-rtlimit" : "$value" );
    }
    elsif ($param eq "limitrstbrst") {
        $parameters = qq(, "rst-rtlimit-burst" : "$value" );
    }
    elsif ($param eq "limitrst-logprefix") {
        $parameters = qq(, "rst-rtlimit-log-prefix" : "$value" );
    }
    elsif ($param eq "limitsec") {
        $parameters = qq(, "new-rtlimit" : "$value" );
    }
    elsif ($param eq "limitsecbrst") {
        $parameters = qq(, "new-rtlimit-burst" : "$value" );
    }
    elsif ($param eq "limitsec-logprefix") {
        $parameters = qq(, "new-rtlimit-log-prefix" : "$value" );
    }
    elsif ($param eq "limitconns") {
        $parameters = qq(, "est-connlimit" : "$value" );
    }
    elsif ($param eq "limitconns-logprefix") {
        $parameters = qq(, "est-connlimit-log-prefix" : "$value" );
    }
    elsif ($param eq "bogustcpflags") {
        $parameters = qq(, "tcp-strict" : "$value" );
    }
    elsif ($param eq "bogustcpflags-logprefix") {
        $parameters = qq(, "tcp-strict-log-prefix" : "$value" );
    }
    elsif ($param eq "nfqueue") {
        $parameters = qq(, "queue" : "$value" );
    }
    elsif ($param eq "sourceaddr") {
        $parameters = qq(, "source-addr" : "$value" );
    }
    elsif ($param eq 'policy') {
        $parameters = qq(, "policies" : [ { "name" : "$value" } ] );
    }
    elsif ($param eq "logs") {
        $srvparam   = "log";
        $value      = "forward" if ($value eq "true");
        $value      = "none"    if ($value eq "false");
        $parameters = qq(, "$srvparam" : "$value");
    }
    elsif ($param eq "log-prefix") {
        $srvparam   = "log-prefix";
        $value      = "l4:$farm_name ";
        $parameters = qq(, "$srvparam" : "$value");

        # TODO: put a warning msg when farm name is longer than nftables reserved log size
    }
    else {
        return -1;
    }

    require Relianoid::Farm::L4xNAT::Action;

    $output = &sendL4NlbCmd({
        farm          => $farm_name,
        farm_new_name => $farm_req,
        file          => ($param ne 'status') ? "$configdir/$farm_filename" : undef,
        method        => "PUT",
        body          => qq({"farms" : [ { "name" : "$farm_name"$parameters } ] })
    });

    # Finally, reload rules
    if ($param eq "vip") {
        &doL4FarmRules("reload", $farm_name, $prev_config)
          if ($prev_config->{status} eq "up");

        # reload source address maquerade
        require Relianoid::Farm::Config;
        &reloadFarmsSourceAddressByFarm($farm_name);
    }

    return $output;
}

=pod

=head1 _getL4ParseFarmConfig

Parse the farm file configuration and read/write a certain parameter

Parameters:

    param - requested parameter. The options are 
            "family", 
            "vip", 
            "vipp", 
            "status", 
            "mode", 
            "alg", 
            "proto", 
            "persist", 
            "presisttm", 
            "limitsec", 
            "limitsecbrst", 
            "limitconns", 
            "limitrst", 
            "limitrstbrst", 
            "bogustcpflags", 
            "nfqueue", 
            "sourceaddr"

    value - value to be changed in case of write operation, undef for read only cases

    config - reference of an array with the full configuration file

Returns:

    Scalar - return the parameter value on read or the changed value in case of write as a string or -1 in other case

=cut

sub _getL4ParseFarmConfig ($param, $value, $config) {
    my $output = -1;
    my $exit   = 1;

    foreach my $line (@{$config}) {
        if ($line =~ /\"family\"/ && $param eq 'family') {
            my @l = split /"/, $line;
            $output = $l[3];
        }

        if ($line =~ /\"virtual-addr\"/ && $param eq 'vip') {
            my @l = split /"/, $line;
            $output = $l[3];
        }

        if ($line =~ /\"virtual-ports\"/ && $param eq 'vipp') {
            my @l = split /"/, $line;
            $output = $l[3];
            $output = "*" if ($output eq '1-65535' || $output eq '');
            $output =~ s/-/:/g;
        }

        if ($line =~ /\"source-addr\"/ && $param eq 'sourceaddr') {
            my @l = split /"/, $line;
            $output = $l[3];
        }

        if ($line =~ /\"mode\"/ && $param eq 'mode') {
            my @l = split /"/, $line;
            $output = $l[3];
            $output = "nat"            if ($output eq "snat");
            $output = "stateless_dnat" if ($output eq "stlsdnat");
        }

        if ($line =~ /\"protocol\"/ && $param eq 'proto') {
            my @l = split /"/, $line;
            $output = $l[3];
            $exit   = 0;
        }

        if ($line =~ /\"persistence\"/ && $param eq 'persist') {
            my @l   = split /"/, $line;
            my $out = $l[3];
            if ($out =~ /none/) {
                $output = "";
            }
            elsif ($out =~ /srcip/) {
                $output = "ip";
                $output = "srcip_srcport" if ($out =~ /srcport/);
                $output = "srcip_dstport" if ($out =~ /dstport/);
            }
            elsif ($out =~ /srcport/) {
                $output = "srcport";
            }
            elsif ($out =~ /srcmac/) {
                $output = "srcmac";
            }
            $exit = 0;
        }

        if ($line =~ /\"persist-ttl\"/ && $param eq 'persisttm') {
            my @l = split /"/, $line;
            $output = $l[3] + 0;
            $exit   = 0;
        }

        if ($line =~ /\"helper\"/ && $param eq 'proto') {
            my @l   = split /"/, $line;
            my $out = $l[3];

            $output = $out if ($out ne "none");
            $exit   = 1;
        }

        if ($line =~ /\"scheduler\"/ && $param eq 'alg') {
            my @l = split /"/, $line;
            $output = $l[3];

            $exit   = 0            if ($output =~ /hash/);
            $output = "roundrobin" if ($output eq "rr");
        }

        if ($line =~ /\"sched-param\"/ && $param eq 'alg') {
            my @l   = split /"/, $line;
            my $out = $l[3];

            if ($output eq "hash") {
                if ($out =~ /srcip/) {
                    $output = "hash_srcip";
                    $output = "hash_srcip_srcport" if ($out =~ /srcport/);
                }
            }
            $exit = 1;
        }

        if ($line =~ /\"log\"/ && $param eq 'logs') {
            my @l = split /"/, $line;
            $output = "false";
            $output = "true" if ($l[3] ne "none");
        }

        if ($line =~ /\"state\"/ && $param =~ /status/) {
            my @l = split /"/, $line;
            if ($l[3] ne "up") {
                $output = "down";
            }
            else {
                $output = "up";
            }
        }

        if ($line =~ /\"rst-rtlimit\"/ && $param eq "limitrst") {
            my @l = split /"/, $line;
            $output = $l[3];
        }

        if ($line =~ /\"rst-rtlimit-burst\"/ && $param eq "limitrstbrst") {
            my @l = split /"/, $line;
            $output = $l[3];
        }

        if ($line =~ /\"new-rtlimit\"/ && $param eq "limitsec") {
            my @l = split /"/, $line;
            $output = $l[3];
        }

        if ($line =~ /\"new-rtlimit-burst\"/ && $param eq "limitsecbrst") {
            my @l = split /"/, $line;
            $output = $l[3];
        }

        if ($line =~ /\"est-connlimit\"/ && $param eq "limitconns") {
            my @l = split /"/, $line;
            $output = $l[3];
        }

        if ($line =~ /\"tcp-strict\"/ && $param eq "bogustcpflags") {
            my @l = split /"/, $line;
            $output = $l[3];
        }

        if ($line =~ /\"queue\"/ && $param eq "nfqueue") {
            my @l = split /"/, $line;
            $output = $l[3];
        }

        if ($output ne "-1") {
            $line =~ s/$output/$value/g if defined $value;
            return $output              if ($exit);
        }
    }

    return $output;
}

=pod

=head1 modifyLogsParam

It enables or disables the logs for a l4xnat farm

Parameters:

    farmname - Farm name

    log value - The possible values are: 'true' to enable the logs or 'false' to disable them

Returns:

    String - return an error message on error or undef on success

=cut

sub modifyLogsParam ($farmname, $logsValue) {
    my $msg;
    my $err = 0;

    if ($logsValue =~ /(?:true|false)/) {
        $err = &setL4FarmParam('logs',       $logsValue, $farmname);
        $err = &setL4FarmParam('log-prefix', undef,      $farmname)
          if (not $err and $logsValue eq 'true');
    }
    else {
        $msg = "Invalid value for logs parameter.";
    }

    if ($err) {
        $msg = "Error modifying the parameter logs.";
    }
    return $msg;
}

=pod

=head1 getL4FarmStatus

Return current farm status

Parameters:

    farm_name - Farm name

Returns:

    String - "up" or "down"

=cut

sub getL4FarmStatus ($farm_name) {
    require Relianoid::Farm::L4xNAT::Action;

    my $pidfile = &getL4FarmPidFile($farm_name);
    my $output  = "down";

    my $nlbpid = &getNlbPid();
    if ($nlbpid eq "-1") {
        return $output;
    }

    $output = "up" if (-e "$pidfile");

    return $output;
}

=pod

=head1 getL4FarmStruct

Return a hash with all data about a l4 farm

Parameters:

    farmname - Farm name

Returns:

    hash ref - hash with farm values

    # %farm = 
    {
        $name,
        $filename,
        $nattype,
        $lbalg, 
        $vip, 
        $vport, 
        $vproto, 
        $sourceip, 
        $persist, 
        $ttl, 
        $proto, 
        $status, 
        \@servers
    }

    \@servers = [ \%backend1, \%backend2, ... ]

=cut

sub getL4FarmStruct ($farmname) {
    my %farm;

    $farm{name} = $farmname;

    require Relianoid::Farm::L4xNAT::Backend;

    $farm{filename} = &getFarmFile($farm{name});
    require Relianoid::Farm::Config;
    my $config = &getFarmPlainInfo($farm{name});

    $farm{nattype} = &_getL4ParseFarmConfig('mode', undef, $config);
    $farm{mode}    = $farm{nattype};

    require Relianoid::Farm::L4xNAT::L4sd;
    my $l4sched = &getL4sdType($farm{name});
    if ($l4sched ne "") {
        $farm{lbalg} = $l4sched;
    }
    else {
        $farm{lbalg} = &_getL4ParseFarmConfig('alg', undef, $config);
    }

    $farm{vip}      = &_getL4ParseFarmConfig('vip',   undef, $config);
    $farm{vport}    = &_getL4ParseFarmConfig('vipp',  undef, $config);
    $farm{vproto}   = &_getL4ParseFarmConfig('proto', undef, $config);
    $farm{sourceip} = "";
    $farm{sourceip} = &_getL4ParseFarmConfig('sourceaddr', undef, $config);

    my $persist = &_getL4ParseFarmConfig('persist', undef, $config);
    $farm{persist} = ($persist eq "-1") ? '' : $persist;
    my $ttl = &_getL4ParseFarmConfig('persisttm', undef, $config);
    $farm{ttl} = ($ttl == -1) ? 0 : $ttl;

    $farm{proto}      = &getL4ProtocolTransportLayer($farm{vproto});
    $farm{bootstatus} = &_getL4ParseFarmConfig('bootstatus', undef, $config);
    $farm{status}     = &getL4FarmStatus($farm{name});
    $farm{logs}       = &_getL4ParseFarmConfig('logs', undef, $config) if ($eload);
    $farm{servers}    = &_getL4FarmParseServers($config);

    if ($farm{lbalg} eq 'weight') {
        &getL4BackendsWeightProbability(\%farm);
    }

    return \%farm;
}

=pod

=head1 loadL4Modules

Load sip, ftp or tftp conntrack module for l4 farms

Parameters:

    protocol - protocol module to load

Returns:

    Integer - 0 if success, otherwise error

=cut

sub loadL4Modules ($protocol) {
    require Relianoid::Netfilter;

    my $status = 0;

    if ($protocol =~ /sip|tftp|ftp|amanda|h323|irc|netbios-ns|pptp|sane|snmp/) {
        my $params = "";
        $params = &getGlobalConfiguration("l4xnat_sip_params")
          if ($protocol eq "sip");
        $status = &loadNfModule("nf_conntrack_$protocol", $params);
        $status = $status || &loadNfModule("nf_nat_$protocol", "");
    }

    return $status;
}

=pod

=head1 unloadL4Modules

Unload conntrack helpers modules for l4 farms

Parameters:

    protocol - protocol module to load

Returns:

    Integer - 0 if success, otherwise error

=cut

sub unloadL4Modules ($protocol) {
    my $status = 0;

    require Relianoid::Netfilter;

    if ($protocol =~ /sip|tftp|ftp|amanda|h323|irc|netbios-ns|pptp|sane|snmp/) {
        my $n_farms = 0;
        require Relianoid::Farm::Core;
        foreach my $farm (&getFarmsByType("l4xnat")) {
            if (&getL4FarmParam('proto', $farm) eq $protocol) {
                $n_farms++ if (&getL4FarmStatus($farm) ne "down");
            }
        }
        if (not $n_farms) {
            $status = &removeNfModule("nf_nat_$protocol");
            $status = $status || &removeNfModule("nf_conntrack_$protocol");
        }
    }

    return $status;
}

=pod

=head1 getFarmPortList

If port is multiport, it removes range port and it passes it to a port list

Parameters:

    fvipp - Port string

Returns:

    array - return a list of ports

=cut

sub getFarmPortList ($fvipp) {
    my @portlist    = split(',', $fvipp);
    my @retportlist = ();

    if (!grep { /\*/ } @portlist) {
        foreach my $port (@portlist) {
            if ($port =~ /:/) {
                my @intlimits = split(':', $port);

                for (my $i = $intlimits[0] ; $i <= $intlimits[1] ; $i++) {
                    push(@retportlist, $i);
                }
            }
            else {
                push(@retportlist, $port);
            }
        }
    }
    else {
        $retportlist[0] = '*';
    }

    return @retportlist;
}

=pod

=head1 getL4ProtocolTransportLayer

Return basic transport protocol used by l4 farm protocol

Parameters:

    protocol - L4xnat farm protocol

Returns:

    String - "udp" or "tcp"

=cut

sub getL4ProtocolTransportLayer ($vproto) {
    return
        ($vproto =~ /sip|tftp/) ? 'udp'
      : ($vproto eq 'ftp')      ? 'tcp'
      :                           $vproto;
}

=pod

=head1 doL4FarmProbability

Create in the passed hash a new key called "prob". In this key is saved total weight of all backends

Parameters:

    farm - farm hash ref. It is a hash with all information about the farm

Returns:

    none

=cut

sub doL4FarmProbability ($farm) {
    $$farm{prob} = 0;

    foreach my $server_ref (@{ $$farm{servers} }) {
        if ($$server_ref{status} eq 'up') {
            $$farm{prob} += $$server_ref{weight};
        }
    }

    return;
}

=pod

=head1 doL4FarmRules

Created to operate with setBackendRule in order to start, stop or reload ip rules

Parameters:

    action - stop (delete all ip rules), start (create ip rules) or reload (delete old one stored in prev_farm_ref and create new)

    farm_name - farm hash ref. It is a hash with all information about the farm

    prev_farm_ref - farm reference of the old configuration. Optional.

Returns:

    none

=cut

sub doL4FarmRules ($action, $farm_name, $prev_farm_ref = undef) {
    my $farm_ref = &getL4FarmStruct($farm_name);

    require Relianoid::Farm::Backend;

    foreach my $server (@{ $farm_ref->{servers} }) {
        if ($action eq "stop") {
            &setBackendRule("del", $farm_ref, $server->{tag});
        }
        elsif ($action eq "reload") {
            &setBackendRule("del", $prev_farm_ref, $server->{tag});
            &setBackendRule("add", $farm_ref,      $server->{tag});
        }
        elsif ($action eq "start") {
            &setBackendRule("add", $farm_ref, $server->{tag});
        }
    }

    return;
}

=pod

=head1 writeL4NlbConfigFile

Write the L4 config file from a curl Nlb request, by filtering IPDS parameters.

Parameters:

    nftfile - temporary file captured from the nftlb farm configuration

    cfgfile - definitive file where the definitive nftlb farm configuration will be stored

Returns:

    Integer - 0 if success, other if error.

=cut

sub writeL4NlbConfigFile ($nftfile, $cfgfile) {
    require Relianoid::Lock;

    if (!-e "$nftfile") {
        return 1;
    }

    &zenlog("Saving farm conf '$cfgfile'", "debug");

    my $fo = &openlock($cfgfile, 'w');

    my @lines = ();
    if (open(my $fi, '<', "$nftfile")) {
        @lines = <$fi>;
        close $fi;
    }

    my $line  = shift @lines;
    my $write = 1;
    my $next_line;

    while (defined $line) {
        $next_line = shift @lines;
        $write     = 0 if ($line =~ /\"policies\"\:/);

        if (   defined($next_line)
            && $next_line =~ /\"policies\"\:/
            && $line      =~ /\]/)
        {
            $line =~ s/,$//g;
            $line =~ s/\n//g;
        }
        print $fo $line
          if ( $line !~ /new-rtlimit|rst-rtlimit|tcp-strict|queue|^[\s]{24}.est-connlimit/
            && $write == 1);

        if ($write == 0 && $line =~ /\]/) {
            $write = 1;
            if ($next_line =~ /\"sessions\"\:/) {
                print $fo ",\n";
            }
            else {
                print $fo "\n";
            }
        }

        $line = $next_line;
    }

    close $fo;
    unlink $nftfile;

    return 0;
}

=pod

=head1 doL4FarmRules

Reset Connection tracking for a given farm

Parameters:

    farm_name

Returns:

    error: 1 in case of error and 0 otherwise

=cut

sub resetL4FarmConntrack ($farm_name) {
    my $error = 0;

    my $servers = &getL4FarmServers($farm_name);
    foreach my $server (@{$servers}) {
        &resetL4FarmBackendConntrackMark($server);
    }

    # Check there are not connections
    require Relianoid::Farm::L4xNAT::Stats;
    require Relianoid::Net::ConnStats;
    my $vip     = &getL4FarmParam("vip", $farm_name);
    my $netstat = &getConntrack('', $vip, '', '', '');
    my $conns   = &getL4FarmEstConns($farm_name, $netstat);
    $conns += &getL4FarmSYNConns($farm_name, $netstat);

    if ($conns > 0) {
        &zenlog("Error flushing conntrack for $farm_name", "ERROR");
        $error = 1;
    }

    return $error;
}

1;

