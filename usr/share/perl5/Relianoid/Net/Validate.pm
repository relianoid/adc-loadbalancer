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

use Carp;
use Relianoid::Core;

=pod

=head1 Module

Relianoid::Net::Validate

=cut

=pod

=head1 getNetIpFormat

It gets an IP and it retuns the same IP with the format that system uses for
the binary choosed

Parameters:

    ip - String with the ipv6
    bin - It is the binary for the format

Returns: string

IPv6 with the format of the binary parameter.

=cut

sub getNetIpFormat ($ip, $bin) {
    require Net::IPv6Addr;
    my $x = Net::IPv6Addr->new($ip);

    if ($bin eq 'netstat') {
        return $x->to_string_compressed();
    }
    else {
        &zenlog("The bin '$bin' is not recoignized. The ip '$ip' couldn't be converted", "error", "networking");
    }

    return $ip;
}

=pod

=head1 getProtoTransport

It returns the protocols of layer 4 that use a profile or another protocol.

Parameters:

    profile - This parameter accepts a load balancer profile 
              (for Layer 4 it returns the default one when the farm is created): 
                "http", "https", "l4xnat", "gslb"
              or another protocol:
                "tcp", "udp", "sctp", "amanda", "tftp", "netbios-ns",
                "snmp", "ftp", "irc", "pptp", "sane", "all", "sip" or "h323"

Returns: array reference

List of transport protocols that use the passed protocol.
The possible values are "udp", "tcp" or "sctp".

=cut

sub getProtoTransport ($profile) {
    my $proto = [];
    my $all   = [ "tcp", "udp", "sctp" ];

    # profiles
    if ($profile eq "gslb") {
        $proto = [ "tcp", "udp" ];
    }
    elsif ($profile eq "l4xnat") {
        $proto = ["tcp"];    # default protocol when a l4xnat farm is created
    }
    elsif ($profile =~ /^(?:tcp|udp|sctp)$/) {    # protocols
        $proto = [$profile];
    }
    elsif ($profile =~ /^(?:amanda|tftp|netbios-ns|snmp)$/) {    # udp
        $proto = ["udp"];
    }
    elsif ($profile =~ /^(?:ftp|irc|pptp|sane|https?)$/) {       # tcp
        $proto = ["tcp"];
    }
    elsif ($profile eq "all") {                                  # mix
        $proto = $all;
    }
    elsif ($profile eq "sip") {
        $proto = [ "tcp", "udp" ];
    }
    elsif ($profile eq "h323") {
        $proto = [ "tcp", "udp" ];
    }
    else {
        &zenlog("The funct 'getProfileProto' does not understand the parameter '$profile'", "error", "networking");
    }

    return $proto;
}

=pod

=head1 validatePortKernelSpace

It checks if the IP, port and protocol are used in some l4xnat farm.
This function does the following actions to validate that the protocol
is not used:

    * Remove the incoming farmname from the farm list
    * Check only with l4xnat farms
    * Check with farms with up status
    * Check that farms contain the same VIP
    * There is not collision with multiport

Parameters:

    vip      - virtual IP
    port     - It accepts multiport string format
    proto    - it is an array reference with the list of protocols to check in the port. 
                The protocols can be 'sctp', 'udp', 'tcp' or 'all'
    farmname - It is the farm that is being modified, if this parameter is passed, 
                the configuration of this farm is ignored to avoid checking with itself. 
                This parameter is optional

Returns: integer

- 1: the incoming info is valid
- 0: there is a(nother) farm with that networking information

=cut

sub validatePortKernelSpace ($ip, $port, $proto, $farmname = undef) {
    # get l4 farms
    require Relianoid::Farm::Base;
    require Relianoid::Arrays;

    my @farm_list = &getFarmListByVip($ip);
    return 1 if !@farm_list;

    if (defined $farmname) {
        @farm_list = grep { !/^$farmname$/ } @farm_list;
        return 1 if !@farm_list;
    }

    # check intervals
    my $port_list = &getMultiporExpanded($port);

    for my $farm (@farm_list) {
        next if (&getFarmType($farm) ne 'l4xnat');
        next if (&getFarmStatus($farm) ne 'up');

        # check protocol collision
        my $f_proto = &getProtoTransport(&getL4FarmParam('proto', $farm));
        next if (!&getArrayCollision($proto, $f_proto));

        my $f_port = &getFarmVip('vipp', $farm);

        # check if farm is all ports
        if ($port eq '*' or $f_port eq '*') {
            &zenlog("Port collision with farm '$farm' for using all ports", "warning", "net");
            return 0;
        }

        # check port collision
        my $f_port_list = &getMultiporExpanded($f_port);
        my $col         = &getArrayCollision($f_port_list, $port_list);

        if (defined $col) {
            &zenlog("Port collision ($col) with farm '$farm'", "warning", "net");
            return 0;
        }
    }

    return 1;
}

=pod

=head1 getMultiporExpanded

It returns the list of ports that a multiport string contains.

Parameters:

    port - multiport port

Returns: array reference

List of ports used by the farm

=cut

sub getMultiporExpanded ($port) {
    my @total_port = ();

    if ($port ne '*') {
        for my $p (split(',', $port)) {
            my ($init, $end) = split(':', $p);

            if   (defined $end) { push @total_port, ($init .. $end); }
            else                { push @total_port, $init; }
        }
    }

    return \@total_port;
}

=pod

=head1 getMultiportRegex

It creates a regular expression to look for a list of ports.
It expands the l4xnat port format (':' for ranges and ',' for listing ports).

Parameters:

    port - port or multiport

Returns: string - Regular expression

=cut

sub getMultiportRegex ($port) {
    my $reg = $port;

    if ($port eq '*') {
        $reg = '\d+';
    }
    elsif ($port =~ /[:,]/) {
        my $total_port = &getMultiporExpanded($port);
        $reg = '(?:' . join('|', @{$total_port}) . ')';
    }

    return $reg;
}

=pod

=head1 validatePortUserSpace

It validates if the port is being used for some process in the user space

Parameters:

    ip       - IP address. If the IP is '0.0.0.0', it checks that other farm or process are not using the port
    port     - TCP port number. It accepts l4xnat multport format: intervals (55:66,70), all ports (*).
    protocol - It is an array reference with the protocols to check ("udp", "tcp" and "sctp"), if some of them is used, the function returns 0.
    farmname - If the configuration is set in this farm, the check is ignored and true. This parameters is optional.
    process  - It is the process name to ignore. It is used when a process wants to be modified with all IPs parameter. 
               The services to ignore are: "cherokee", "sshd" and "snmp"

Returns: integer

- 1: if the port and IP are valid to be used
- 0: if the port and IP are already applied in the system

=cut

sub validatePortUserSpace ($ip, $port, $proto, $farmname, $process = undef) {
    my $override;

    # skip if the running farm is itself
    if (defined $farmname) {
        require Relianoid::Farm::Base;

        my $type = &getFarmType($farmname);
        if ($type =~ /http|gslb/) {
            my $cur_vip  = &getFarmVip('vip',  $farmname);
            my $cur_port = &getFarmVip('vipp', $farmname);

            if (    &getFarmStatus($farmname) eq 'up'
                and $cur_vip eq $ip
                and $cur_port eq $port)
            {
                &zenlog("The networking configuration matches with the own farm", "debug", "networking");
                return 1;
            }
        }
        elsif ($type eq "l4xnat") {
            $override = 1;
        }
    }

    my $netstat = &getGlobalConfiguration('netstat_bin');

    my $f_ipversion = (&ipversion($ip) == 6) ? "6" : "4";
    $ip = &getNetIpFormat($ip, 'netstat') if ($f_ipversion eq '6');

    my $f       = "lpnW";
    my $f_proto = "";

    for my $p (@{$proto}) {
        # it is not supported in the system
        if   ($p eq 'sctp') { next; }
        else                { $f_proto .= "--$p "; }
    }

    my $cmd = "$netstat -$f_ipversion -${f} ${f_proto} ";
    my @out = @{ &logAndGet($cmd, 'array') };
    shift @out;
    shift @out;

    if (defined $process) {
        my $filter = '^\s*(?:[^\s]+\s+){5,6}\d+\/' . $process;
        @out = grep { !/$filter/ } @out;
        return 1 if (!@out);
    }

    # This code was modified for a bugfix. There was a issue when a l4 farm
    # is set and some management interface is set to use all the interfaces
    # my $ip_reg = ( $ip eq '0.0.0.0' ) ? '[^\s]+' : "(?:0.0.0.0|::1|$ip)";

    my $ip_reg;
    if (defined $override and $override) {
        # L4xnat overrides the user space daemons that are listening on all interfaces
        $ip_reg = ($ip eq '0.0.0.0') ? '[^\s]+' : "(?:$ip)";
    }
    else {
        # L4xnat farms does not override the user space daemons
        $ip_reg = ($ip eq '0.0.0.0') ? '[^\s]+' : "(?:0.0.0.0|::1|$ip)";
    }

    my $port_reg = &getMultiportRegex($port);

    my $filter = '^\s*(?:[^\s]+\s+){3,3}' . $ip_reg . ':' . $port_reg . '\s';
    @out = grep { /$filter/ } @out;

    if (@out) {
        &zenlog("The ip '$ip' and the port '$port' are being used for some process", "warning", "networking");
        return 0;
    }

    return 1;
}

=pod

=head1 validatePort

It checks if an IP and a port (checking the protocol) are already configured in the system.
This is used to validate that more than one process or farm are not running with the same
networking configuration.

It checks the information with the "netstat" command, if the port is not found it will look for
between the l4xnat farms (that are up).

If this function is called with more than one protocol. It will recall itself recursively
for each one.

Parameters:

    ip       - IP address. If the IP is '0.0.0.0', it checks that other farm or process are not using the port
    port     - TCP port number. It accepts l4xnat multport format: intervals (55:66,70), all ports (*).
    protocol - It is an array reference with the protocols to check, if some of them is used, the function returns 0. 
                The accepted protocols are: 'all' (no one is checked), sctp, tcp and udp
    farmname - If the configuration is set in this farm, the check is ignored and true. This parameters is optional.
    process  - It is the process name to ignore. It is used when a process wants to be modified with all IPs parameter. 
                The services to ignore are: "cherokee", "sshd" and "snmp"

Returns: integer

    1 - if the port and IP are available to be used
    0 - if the port and IP are already being used in the system

=cut

sub validatePort ($ip, $port, $proto, $farmname = undef, $process = undef) {
    if ($ip eq '*') {
        $ip = '0.0.0.0';
    }

    if (!defined $proto && !defined $farmname) {
        &zenlog("Check port needs the protocol to validate the ip '$ip' and the port '$port'", "error", "networking");
        return 0;
    }

    if (!defined $proto) {
        $proto = &getFarmType($farmname);
        if ($proto eq 'l4xnat') {
            require Relianoid::Farm::L4xNAT::Config;
            $proto = &getL4FarmParam('proto', $farmname);
        }
    }

    $proto = &getProtoTransport($proto);

    # TODO: add check for avoiding collision with datalink VIPs
    return 0 if (!&validatePortUserSpace($ip, $port, $proto, $farmname, $process));
    return 0 if (!&validatePortKernelSpace($ip, $port, $proto, $farmname));
    return 1;
}

=pod

=head1 ipisok

Check if a string has a valid IP address format.

Parameters:

    checkip - IP address string.
    version - Optional. 4 or 6 to validate IPv4 or IPv6 only.

Returns: string - "true" or "false".

=cut

sub ipisok ($checkip, $version = undef) {
    require Data::Validate::IP;
    Data::Validate::IP->import();

    if (!$version || $version == 4) {
        return "true" if is_ipv4($checkip)
    }

    if (!$version || $version == 6) {
        return "true" if is_ipv6($checkip)
    }

    return "false";
}

=pod

=head1 validIpAndNet

Validate if the input is a valid IP or networking segement

Parameters:

    ip - IP address or IP network segment. ipv4 or ipv6

Returns: integer

- 1: The IP address is valid
- 0: The IP address is not valid

=cut

sub validIpAndNet ($ip) {
    use NetAddr::IP;
    my $out = NetAddr::IP->new($ip);

    return int(defined $out);
}

=pod

=head1 ipversion

IP version number of an input IP address

Parameters:

    ip - string - IP address

Returns: integer

- 4: ipv4
- 6: ipv6
- 0: unknown

=cut

sub ipversion ($ip) {
    require Data::Validate::IP;
    Data::Validate::IP->import();

    return 4 if is_ipv4($ip);
    return 6 if is_ipv6($ip);
    return 0;
}

=pod

=head1 validateGateway

Check if the network configuration is valid. This function receive two IP
address and a net segment and check if both address are in the segment.
It is usefull to check if the gateway is correct or to check a new IP
for a interface

Parameters:

    ip      - IP from net segment
    netmask - Net segment
    new_ip  - IP to check if it is from net segment

Returns: integer

    1 - the configuration is correct
    0 - the configuration is not correct

=cut

sub validateGateway ($ip, $mask, $ip2, $mask2 = undef) {
    require NetAddr::IP;

    unless (defined $mask2) {
        $mask2 = $mask;
    }

    my $addr1 = NetAddr::IP->new($ip,  $mask);
    my $addr2 = NetAddr::IP->new($ip2, $mask2);

    return (defined $addr1 && defined $addr2 && ($addr1->network() eq $addr2->network())) ? 1 : 0;
}

=pod

=head1 ifexist

Check if an interface exists.

Look for link interfaces, Virtual interfaces return "false".
If the interface is IFF_RUNNING or configuration file exists return "true".
If interface found but not IFF_RUNNING nor configutaion file exists returns "created".

Parameters:

    nif - network interface name.

Returns: string - "true", "false" or "created".

=cut

sub ifexist ($nif) {
    use IO::Interface qw(:flags);    # Needs to load with 'use'

    require IO::Socket;
    require Relianoid::Net::Interface;

    my $s          = IO::Socket::INET->new(Proto => 'udp');
    my @interfaces = &getInterfaceList();
    my $configdir  = &getGlobalConfiguration('configdir');
    my $status;

    for my $if (@interfaces) {
        next if $if ne $nif;

        my $flags = $s->if_flags($if);

        if   ($flags & IFF_RUNNING) { $status = "up"; }
        else                        { $status = "down"; }

        if ($status eq "up" || -e "$configdir/if_$nif\_conf") {
            return "true";
        }

        return "created";
    }

    return "false";
}

=pod

=head1 checkNetworkExists

Check if a network exists in other interface

Parameters:

    ip         - string - IP address
    mask       - string - Netmask
    exception  - string - Optional. Interface name to be excluded.
                          It is used to exclude the interface that is been changed
    duplicated - string - Optional. Overrides the "check duplicated network" option.
                                    Expects "true" or "false" when defined.

Returns: string

- interface name - if the network is found
- empty string   - if the network is not found

=cut

sub checkNetworkExists ($net, $mask, $exception = undef, $duplicated = undef) {
    # $duplicated will override the configured default
    if (defined $duplicated) {
        return "" if $duplicated eq "true";
    }
    else {
        return "" if &getGlobalConfiguration("duplicated_net") eq "true";
    }

    require Relianoid::Net::Interface;
    require NetAddr::IP;

    my $net1 = NetAddr::IP->new($net, $mask);
    my @interfaces;

    my @system_interfaces = &getInterfaceList();
    my $params            = [ "name", "addr", "mask" ];

    for my $if_name (@system_interfaces) {
        next if (&getInterfaceType($if_name) !~ /^(?:nic|bond|vlan|gre)$/);

        my $output_if = &getInterfaceConfigParam($if_name, $params) || &getSystemInterface($if_name);
        push(@interfaces, $output_if);
    }

    my $found = 0;

    for my $if_ref (@interfaces) {
        next if defined $exception and $if_ref->{name} eq $exception;
        next if !$if_ref->{addr};

        # found
        my $net2 = NetAddr::IP->new($if_ref->{addr}, $if_ref->{mask});

        eval {
            if ($net1->contains($net2) or $net2->contains($net1)) {
                $found = 1;
            }
        };

        return $if_ref->{name} if $found;
    }

    return "";
}

=pod

=head1 checkDuplicateNetworkExists

Check if duplicate network exists in the interfaces

Parameters: None

Returns: string

- interface name - if the network is found
- empty string   - if the network is not found

=cut

sub checkDuplicateNetworkExists () {
    #if duplicated network is not allowed then don't check if network exists.
    require Relianoid::Config;

    return "" if &getGlobalConfiguration("duplicated_net") eq "false";

    require Relianoid::Net::Interface;
    require NetAddr::IP;

    my @interfaces = map { &getInterfaceTypeList($_) } qw(nic bond vlan);

    for my $if_ref (@interfaces) {
        my $iface = &checkNetworkExists($if_ref->{addr}, $if_ref->{mask}, $if_ref->{name}, "false");
        return $iface if $iface;
    }

    return "";
}

=pod

=head1 validBackendStack

Check if a list of backends have their IP address in the same stack (IP version) as an IP address of reference

Parameters:

    be_aref - array reference - Array of backend hashes
    ip      - string - IP address

Returns: integer

    1 - the ip is valid
    0 - the IP address is not in the same network segment

=cut

sub validBackendStack ($be_aref, $ip) {
    my $ip_stack     = &ipversion($ip);
    my $ipv_mismatch = 0;

    # check every backend ip version
    for my $be (@{$be_aref}) {
        my $current_stack = &ipversion($be->{ip});
        $ipv_mismatch = $current_stack ne $ip_stack;
        last if $ipv_mismatch;
    }

    return (!$ipv_mismatch);
}

=pod

=head1 validateNetmask

It validates if a netmask is valid for IPv4 or IPv6

Parameters:

    netmask    - string - Netmask
    ip_version - integer - Optional. 4 or 6 are the expected values.
                           If no value is passed, it checks if the netmask is valid for any IP version

Returns: integer

    1 - success
    0 - error

=cut

sub validateNetmask ($mask, $ipversion = undef) {
    unless (defined $mask) {
        croak("mask is required");
    }

    $ipversion //= 0;
    my $success = 0;
    my $ip      = "127.0.0.1";

    if ($ipversion == 0 or $ipversion == 6) {
        return 1 if ($mask =~ /^\d+$/ and $mask <= 64);
    }
    if ($ipversion == 0 or $ipversion == 4) {
        if ($mask =~ /^\d+$/) {
            $success = 1 if $mask <= 32;
        }
        else {
            require Net::Netmask;
            my $block = Net::Netmask->new($ip, $mask);
            $success = (!exists $block->{ERROR});
        }
    }

    return $success;
}

1;
