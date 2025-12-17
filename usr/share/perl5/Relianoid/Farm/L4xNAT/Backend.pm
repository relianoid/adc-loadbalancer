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

my $configdir = &getGlobalConfiguration('configdir');
my $eload     = eval { require Relianoid::ELoad; };

=pod

=head1 Module

Relianoid::Farm::L4xNAT::Backend

=cut

=pod

=head1 setL4FarmServer

Edit a backend or add a new one if the id is not found

Parameters:

    farm_name - Farm name
    ids - Backend id
    ip - Backend IP
    port - Backend port
    weight - Backend weight. The backend with more weight will manage more connections
    priority - The priority of this backend (between 1 and 9). Higher priority backends will be used more often than lower priority ones
    max_conns - Maximum connections for the given backend

Returns:

    Integer - return 0 on success, -1 on NFTLB failure or -2 on IP duplicated.

Returns:

    Scalar - 0 on success or other value on failure
    FIXME: Stop returning -2 when IP duplicated, nftlb should do this

=cut

sub setL4FarmServer ($farm_name, $ids, $ip, $port = undef, $weight = undef, $priority = undef, $max_conns = undef) {
    require Relianoid::Farm::L4xNAT::Config;
    require Relianoid::Farm::L4xNAT::Action;
    require Relianoid::Farm::Backend;
    require Relianoid::Netfilter;

    my $farm_filename = &getFarmFile($farm_name);
    my $output        = 0;
    my $json          = qq();
    my $msg           = "setL4FarmServer << farm_name:$farm_name ids:$ids ";

    # load the configuration file first if the farm is down
    my $f_ref = &getL4FarmStruct($farm_name);
    if ($f_ref->{status} ne "up") {
        my $out = &loadL4FarmNlb($farm_name);
        return $out if ($out != 0);
    }

    my $exists = &getFarmServer($f_ref->{servers}, $ids);

    my $rip  = $ip;
    my $mark = "0x0";

    if (defined $port && $port ne "") {
        if (&ipversion($ip) == 4) {
            $rip = "$ip\:$port";
        }
        elsif (&ipversion($ip) == 6) {
            $rip = "[$ip]\:$port";
        }

        if (!defined $exists || (defined $exists && $exists->{port} ne $port)) {
            $json .= qq(, "port" : "$port");
            $msg  .= "port:$port ";
        }
    }
    elsif (defined $port && $port eq "") {
        $json .= qq(, "port" : "$port");
        $msg  .= "port:$port ";
    }

    if (   defined $ip
        && $ip ne ""
        && (!defined $exists || (defined $exists && $exists->{rip} ne $rip)))
    {
        my $existrip = &getFarmServer($f_ref->{servers}, $rip, "rip");
        return -2 if (defined $existrip && ($existrip->{id} ne $ids));
        $json = qq(, "ip-addr" : "$ip") . $json;
        $msg .= "ip:$ip ";

        if (!defined $exists) {
            $mark = &getNewMark($farm_name);
            return -1 if (!defined $mark || $mark eq "");
            $json .= qq(, "mark" : "$mark");
            $msg  .= "mark:$mark ";
        }
        else {
            $mark = $exists->{tag};
        }

        &setBackendRule("add", $f_ref, $mark) if ($f_ref->{status} eq "up");
    }

    if (
           defined $weight
        && $weight ne ""
        && (!defined $exists
            || (defined $exists && $exists->{weight} ne $weight))
      )
    {
        $weight = 1 if ($weight == 0);
        $json .= qq(, "weight" : "$weight");
        $msg  .= "weight:$weight ";
    }

    if (
           defined $priority
        && $priority ne ""
        && (!defined $exists
            || (defined $exists && $exists->{priority} ne $priority))
      )
    {
        $priority = 1 if ($priority == 0);
        $json .= qq(, "priority" : "$priority");
        $msg  .= "priority:$priority ";
    }

    if (
           defined $max_conns
        && $max_conns ne ""
        && (!defined $exists
            || (defined $exists && $exists->{max_conns} ne $max_conns))
      )
    {
        $max_conns = 0 if ($max_conns < 0);
        $json .= qq(, "est-connlimit" : "$max_conns");
        $msg  .= "maxconns:$max_conns ";
    }

    if (!defined $exists) {
        $json .= qq(, "state" : "up");
        $msg  .= "state:up ";
    }

    &log_info("$msg") if &debug();

    $output = &sendL4NlbCmd({
        farm   => $farm_name,
        file   => "$configdir/$farm_filename",
        method => "PUT",
        body   => qq({"farms" : [ { "name" : "$farm_name", "backends" : [ { "name" : "bck$ids"$json } ] } ] })
    });

    # take care of floating interfaces without masquerading
    if ($json =~ /ip-addr/ && $eload) {
        my $farm_ref = &getL4FarmStruct($farm_name);
        &eload(
            module => 'Relianoid::EE::Net::Floating',
            func   => 'setFloatingSourceAddr',
            args   => [ $farm_ref, { ip => $ip, id => $ids, tag => $mark } ],
        );
    }

    return $output;
}

=pod

=head1 runL4FarmServerDelete

Delete a backend from a l4 farm

Parameters:

    ids - Backend id
    farm_name - Farm name

Returns:

    Scalar - 0 on success or other value on failure

=cut

sub runL4FarmServerDelete ($ids, $farm_name) {
    require Relianoid::Farm::L4xNAT::Config;
    require Relianoid::Farm::L4xNAT::Action;
    require Relianoid::Netfilter;

    my $farm_filename = &getFarmFile($farm_name);
    my $output        = 0;
    my $mark          = "0x0";

    # load the configuration file first if the farm is down
    my $f_ref = &getL4FarmStruct($farm_name);

    $output = &sendL4NlbCmd({
        farm    => $farm_name,
        backend => "bck" . $ids,
        file    => "$configdir/$farm_filename",
        method  => "DELETE",
    });

    my $backend;
    for my $server (@{ $f_ref->{servers} }) {
        if ($server->{id} eq $ids) {
            $mark    = $server->{tag};
            $backend = $server;
            last;
        }
    }

    ### Flush conntrack
    &resetL4FarmBackendConntrackMark($backend);

    &setBackendRule("del", $f_ref, $mark);
    &delMarks("", $mark);

    return $output;
}

=pod

=head1 setL4FarmBackendsSessionsRemove

Remove all the active sessions enabled to a backend

Parameters:

    farm_name - Farm name
    backend_ref - Hash ref of Backend

Returns:

    Integer - 0 on success , 1 on failure

=cut

sub setL4FarmBackendsSessionsRemove ($farm_name, $backend_ref = undef) {
    my $output = -1;
    if (not defined $backend_ref) {
        &log_warn("Warning removing sessions for backend id farm '$farm_name': Backend id not found", "lslb");
        return $output;
    }

    $output = &sendL4NlbCmd({
        farm   => $farm_name,
        method => "DELETE",
        uri    => "/farms/" . $farm_name . "/backends/bck" . $backend_ref->{id} . "/sessions",
    });

    if ($output) {
        &log_error("Error removing sessions for backend id '$backend_ref->{id}' in farm '$farm_name'", "lslb");
        $output = 1;
    }
    else {
        &log_info("Removed sessions for backend id '$backend_ref->{id}' in farm '$farm_name'", "lslb");
        $output = 0;
    }

    return $output;
}

=pod

=head1 setL4FarmBackendStatus

Set backend status for an l4 farm and stops traffic to that backend when needed.

Parameters:

    farm_name - Farm name
    backend - Backend id
    status - Backend status. The possible values are: "up", "down", "maintenance" or "fgDOWN".
    cutmode - "cut" to force the traffic stop for such backend

Returns:

    hash reference

    $error_ref->{code}

        - 0 on success
        - 1 on failure changing status,
        - 2 on failure removing sessions
        - 3 on failure removing connections,
        - 4 on failure removing sessions and connections.

    $error_ref->{desc} - error message.

=cut

sub setL4FarmBackendStatus ($farm_name, $backend_id, $status, $cutmode = undef) {
    require Relianoid::Farm::L4xNAT::Config;
    require Relianoid::Farm::L4xNAT::Action;

    my $error_ref->{code} = -1;
    my $farm              = &getL4FarmStruct($farm_name);
    my $farm_filename     = $farm->{filename};
    my @backends;
    my @bks_prio_status;
    my @bks_updated_prio_status;
    my $output;
    my $msg;

    $status = 'off'  if ($status eq "maintenance");
    $status = 'down' if ($status eq "fgDOWN");

    #the following actions are only needed if a high priority backend turns up after being down/off and
    #a lower priority backend(s) turned active during the time the other backends was down/off
    if ($status eq 'up' and @{ $$farm{servers} } > 1) {
        my $i = 0;
        my $bk_index;

        for my $server (@{ $$farm{servers} }) {
            my $bk = {
                status   => $server->{status} eq "up" ? $server->{status} : "down",
                priority => $server->{priority}
            };

            push(@backends, $bk);

            if ($backend_id == $server->{id}) {
                $bk_index = $i;
            }

            $i++;
        }

        require Relianoid::Farm::Backend;
        @bks_prio_status               = @{ &getPriorityAlgorithmStatus(\@backends)->{status} };
        $backends[$bk_index]->{status} = $status;
        @bks_updated_prio_status       = @{ &getPriorityAlgorithmStatus(\@backends)->{status} };
    }

    $output = &sendL4NlbCmd({
        farm   => $farm_name,
        file   => "$configdir/$farm_filename",
        method => "PUT",
        body   =>
          qq({"farms" : [ { "name" : "$farm_name", "backends" : [ { "name" : "bck$backend_id", "state" : "$status" } ] } ] })
    });

    if ($output) {
        $msg = "Status of backend $backend_id in farm '$farm_name' was not changed to $status";
        &log_error($msg, "LSLB");
        $error_ref->{code} = 1;
        $error_ref->{desc} = $msg;
        return $error_ref;
    }
    else {
        $msg = "Status of backend $backend_id in farm '$farm_name' was changed to $status";
        &log_info($msg, "LSLB");
        $error_ref->{code} = 0;
        $error_ref->{desc} = $msg;
    }

    #compare priority status of all backends and delete sessions and connections of backends
    #that have had their priority status changed from true to false.
    my $i = 0;
    for my $bk (@bks_updated_prio_status) {
        if ($bk ne $bks_prio_status[$i]) {
            if (@{ $farm->{servers} }[$i]->{status} eq 'up') {
                if ($farm->{persist} ne '') {
                    # delete backend session
                    $output = &setL4FarmBackendsSessionsRemove($farm_name, @{ $farm->{servers} }[$i]);
                    if ($output) {
                        $error_ref->{code} = 2;
                    }
                }

                # remove conntrack
                $output = &resetL4FarmBackendConntrackMark(@{ $farm->{servers} }[$i]);
                if ($output) {
                    $msg               = "Connections for unused backends in farm '$farm_name' were not deleted";
                    $error_ref->{code} = 3;
                    $error_ref->{desc} = $msg;
                }
            }
        }
        $i++;
    }

    if ($status ne "up" and $cutmode eq "cut") {
        my $server;

        # get backend with id $backend
        for my $srv (@{ $$farm{servers} }) {
            if ($srv->{id} == $backend_id) {
                $server = $srv;
                last;
            }
        }

        if ($farm->{persist} ne '') {
            #delete backend session
            $output = &setL4FarmBackendsSessionsRemove($farm_name, $server);
            if ($output) {
                $error_ref->{code} = 2;
            }
        }

        # remove conntrack
        $output = &resetL4FarmBackendConntrackMark($server);
        if ($output) {
            $msg               = "Connections for backend $server->{ip}:$server->{port} in farm '$farm_name' were not deleted";
            $error_ref->{code} = 3;
            $error_ref->{desc} = $msg;
        }
    }

    if ($farm->{lbalg} eq 'leastconn') {
        require Relianoid::Farm::L4xNAT::L4sd;
        &sendL4sdSignal();
    }

    #~ TODO
    #~ my $stopping_fg = ( $caller =~ /runFarmGuardianStop/ );
    #~ if ( $fg_enabled eq 'true' && !$stopping_fg )
    #~ {
    #~ if ( $0 !~ /farmguardian/ && $fg_pid > 0 )
    #~ {
    #~ kill 'CONT' => $fg_pid;
    #~ }
    #~ }

    return $error_ref;
}

=pod

=head1 getL4FarmServers

Get all backends and their configuration

Parameters:

    farmname - Farm name

Returns:

    Array - array of hash refs of backend struct

=cut

sub getL4FarmServers ($farm_name) {
    my $farm_filename = &getFarmFile($farm_name);

    open my $fh, '<', "${configdir}/${farm_filename}";
    chomp(my @content = <$fh>);
    close $fh;

    return &_getL4FarmParseServers(\@content);
}

=pod

=head1 _getL4FarmParseServers

Return the list of backends with all data about a backend in a l4 farm

Parameters:

    config - plain text server list

Returns:

    array reference - reference to a list of backend hashes

    [
        {
            $id,
            $alias,
            $family,
            $ip,
            $port,
            $tag,
            $weight,
            $priority,
            $status,
            $rip = $ip,
            $max_conns
        },
        ...
    ]

=cut

sub _getL4FarmParseServers ($config) {
    my $stage = 0;
    my $server;
    my @servers;

    require Relianoid::Farm::L4xNAT::Config;
    my $fproto = &_getL4ParseFarmConfig('proto', undef, $config);

    for my $line (@{$config}) {
        if ($line =~ /\"farms\"/) {
            $stage = 1;
        }

        # do not go to the next level if empty
        if ($line =~ /\"backends\"/ && $line !~ /\[\],/) {
            $stage = 2;
        }

        if ($stage == 2 && $line =~ /\{/) {
            $stage = 3;
            undef $server;
        }

        if ($stage == 3 && $line =~ /\}/) {
            $stage = 2;
            push(@servers, $server);
        }

        if ($stage == 2 && $line =~ /\]/) {
            last;
        }

        if ($stage == 3 && $line =~ /\"name\"/) {
            my @l     = split(/"/, $line);
            my $index = $l[3];
            $index =~ s/bck//;
            $server->{id}        = $index + 0;
            $server->{port}      = undef;
            $server->{tag}       = "0x0";
            $server->{max_conns} = 0;
        }

        if ($stage == 3 && $line =~ /\"ip-addr\"/) {
            my @l = split(/"/, $line);
            $server->{ip}  = $l[3];
            $server->{rip} = $l[3];
        }

        if ($stage == 3 && $line =~ /\"source-addr\"/) {
            my @l = split(/"/, $line);
            $server->{sourceip} = $l[3];
        }

        if ($stage == 3 && $line =~ /\"port\"/) {
            my @l = split(/"/, $line);
            $server->{port} = $l[3];

            require Relianoid::Net::Validate;
            if ($server->{port} ne '' && $fproto ne 'all') {
                if (&ipversion($server->{rip}) == 4) {
                    $server->{rip} = "$server->{ip}\:$server->{port}";
                }
                elsif (&ipversion($server->{rip}) == 6) {
                    $server->{rip} = "[$server->{ip}]\:$server->{port}";
                }
            }

            # Convert to number after being used as string.
            if (defined $server->{port} and length $server->{port}) {
                $server->{port} += 0;
            }
        }

        if ($stage == 3 && $line =~ /\"weight\"/) {
            my @l = split(/"/, $line);
            $server->{weight} = $l[3] + 0;
        }

        if ($stage == 3 && $line =~ /\"priority\"/) {
            my @l = split(/"/, $line);
            $server->{priority} = $l[3] + 0;
        }

        if ($stage == 3 && $line =~ /\"mark\"/) {
            my @l = split(/"/, $line);
            $server->{tag} = $l[3];
        }

        if ($stage == 3 && $line =~ /\"est-connlimit\"/) {
            my @l = split(/"/, $line);
            $server->{max_conns} = $l[3] + 0;
        }

        if ($stage == 3 && $line =~ /\"state\"/) {
            my @l = split(/"/, $line);
            $server->{status} = $l[3];
            $server->{status} = "undefined"
              if ($server->{status} eq "config_error");
            $server->{status} = "maintenance" if ($server->{status} eq "off");
            $server->{status} = "fgDOWN"      if ($server->{status} eq "down");
            $server->{status} = "up"          if ($server->{status} eq "available");
        }
    }

    return \@servers;
}

=pod

=head1 getL4BackendsWeightProbability

Get probability for every backend

Parameters:

    farm - Farm hash ref. It is a hash with all information about the farm

Returns:

    none

=cut

sub getL4BackendsWeightProbability ($farm) {
    my $weight_sum = 0;

    &doL4FarmProbability($farm);

    for my $server (@{ $$farm{servers} }) {
        # only calculate probability for the servers running
        if ($$server{status} eq 'up') {
            $weight_sum += $$server{weight};
            $$server{prob} = $weight_sum / $$farm{prob};
        }
        else {
            $$server{prob} = 0;
        }
    }

    return;
}

=pod

=head1 resetL4FarmBackendConntrackMark

Reset Connection tracking for a given backend

Parameters:

    server - Backend hash reference. It uses the backend unique mark in order to deletes the conntrack entries.

Returns:

    scalar - 0 if deleted, 1 if not deleted

=cut

sub resetL4FarmBackendConntrackMark ($server) {
    my $conntrack = &getGlobalConfiguration('conntrack');
    my $cmd       = "$conntrack -D -m $server->{tag}/0x7fffffff";

    &log_info("running: $cmd") if &debug();

    # return_code = 0 -> deleted
    # return_code = 1 -> not found/deleted
    my $return_code = &logAndRunCheck("$cmd");

    #check if error in return_code is because connections were not found
    if ($return_code) {
        require Relianoid::Net::ConnStats;
        my $params = {
            proto => 'tcp sctp',
            mark  => "$server->{tag}/0x7fffffff",
            state => "ESTABLISHED"
        };
        my $conntrack_params = &getConntrackParams($params);
        my $conns            = &getConntrackCount($conntrack_params);

        #if connections are not found, no error
        $return_code = 0 if $conns == 0;
    }

    if (&debug()) {
        if ($return_code) {
            &log_info("Connection tracking for " . $server->{ip} . " not removed.");
        }
        else {
            &log_info("Connection tracking for " . $server->{ip} . " removed.");
        }
    }

    return $return_code;
}

=pod

=head1 getL4FarmBackendAvailableID

Get next available backend ID

Parameters:

    farmname - farm name

Returns:

    integer - backend ID available

=cut

sub getL4FarmBackendAvailableID ($farmname) {
    require Relianoid::Farm::Backend;

    my $backends  = &getL4FarmServers($farmname);
    my $nbackends = $#{$backends} + 1;

    for (my $id = 0 ; $id < $nbackends ; $id++) {
        my $exists = &getFarmServer($backends, $id);
        return $id if (!$exists);
    }

    return $nbackends;
}

=pod

=head1 getL4FarmPriorities

Get the list of the backends priorities in a L4 farm

Parameters:

    farmname - Farm name

Returns:

    Array Ref - it returns an array ref of priority values

=cut

sub getL4FarmPriorities ($farmname) {
    my @priorities;
    my $backends = &getL4FarmServers($farmname);

    for my $backend (@{$backends}) {
        if (defined $backend->{priority}) {
            push @priorities, $backend->{priority};
        }
        else {
            push @priorities, 1;
        }
    }

    return \@priorities;
}

1;

