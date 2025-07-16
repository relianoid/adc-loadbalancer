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

my $ip_bin = &getGlobalConfiguration('ip_bin');
my $eload  = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::Net::Core

=cut

=pod

=head1 createIf

Create VLAN network interface

Parameters:

    if_ref - Network interface hash reference.

Returns: integer - errno if ip command.

=cut

# create network interface
sub createIf ($if_ref) {
    my $status = 1;

    if (defined $$if_ref{vlan} && $$if_ref{vlan} ne '') {
        &log_info("Creating vlan $$if_ref{name}", "NETWORK");

        my $ip_cmd = "$ip_bin link add link $$if_ref{dev} name $$if_ref{name} type vlan id $$if_ref{vlan}";
        $status = &logAndRun($ip_cmd);
    }

    return $status;
}

=pod

=head1 upIf

Bring up network interface in system and optionally in configuration file

Parameters:

    if_ref - network interface hash reference.
    writeconf - true value to apply change in interface configuration file. Optional.

Returns: integer - errno of ip command.

=cut

# up network interface
sub upIf ($if_ref, $writeconf = 0) {
    my $configdir = &getGlobalConfiguration('configdir');
    my $status    = 0;
    $if_ref->{status} = 'up';

    my $ip_cmd = "$ip_bin link set dev $$if_ref{name} up";

    $status = &logAndRun($ip_cmd);

    # not check virtual interfaces
    if ($if_ref->{type} ne "virtual") {
        require Relianoid::File;

        #check if link is up after ip link up; checks /sys/class/net/$$if_ref{name}/operstate
        my $status_if = &getFile("/sys/class/net/$$if_ref{name}/operstate") // '';
        chomp($status_if);

        &log_info("Link status for $$if_ref{name} is $status_if", "NETWORK");

        if ($status_if eq 'down') {
            use Time::HiRes qw(usleep);

            &log_info("Waiting link up for $$if_ref{name}", "NETWORK");

            my $max_retry = 50;
            my $retry     = 0;

            while ($status_if eq 'down' and $retry < $max_retry) {
                $status_if = &getFile("/sys/class/net/$$if_ref{name}/operstate") // '';
                chomp($status_if);

                if ($status_if eq 'up') {
                    &log_info("Link up for $$if_ref{name}", "NETWORK");
                    last;
                }

                $retry++;
                usleep 100_000;
            }

            if ($status_if eq 'down') {
                $status = 1;
                &log_warn("No link up for $$if_ref{name}", "NETWORK");
                &downIf({ name => $if_ref->{name} });
            }
        }
    }

    if ($writeconf) {
        my $file = "$configdir/if_$$if_ref{name}_conf";

        require Config::Tiny;
        my $fileHandler = Config::Tiny->new();
        $fileHandler = Config::Tiny->read($file) if (-f $file);

        $fileHandler->{ $if_ref->{name} }{status} = "up";
        $fileHandler->write($file);
    }

    if (not $status and $eload and $if_ref->{dhcp} eq 'true') {
        $status = &eload(
            module => 'Relianoid::EE::Net::DHCP',
            func   => 'startDHCP',
            args   => [ $if_ref->{name} ],
        );
    }

    # calculate new backend masquerade IPs
    require Relianoid::Farm::Config;
    &reloadFarmsSourceAddress();

    return $status;
}

=pod

=head1 downIf

Bring down network interface in system and optionally in configuration file

Parameters:

    if_ref - network interface hash reference.
    writeconf - true value to apply change in interface configuration file. Optional.

Returns: integer - errno of ip command.

=cut

# down network interface in system and configuration file
sub downIf ($if_ref, $writeconf = 0) {
    my $status;

    if (ref $if_ref ne 'HASH') {
        &log_error("Wrong argument putting down the interface", "NETWORK");
        return -1;
    }

    if ($eload and $if_ref->{dhcp} and $if_ref->{dhcp} eq 'true') {
        $status = &eload(
            module => 'Relianoid::EE::Net::DHCP',
            func   => 'stopDHCP',
            args   => [ $if_ref->{name} ],
        );
    }

    my $ip_cmd;

    # For Eth and Vlan
    if (not defined $$if_ref{vini} or not length $$if_ref{vini}) {
        $ip_cmd = "$ip_bin link set dev $$if_ref{name} down";
    }

    # For Vini
    else {
        my ($routed_iface) = split(":", $$if_ref{name});

        $ip_cmd = "$ip_bin addr del $$if_ref{addr}/$$if_ref{mask} dev $routed_iface";

        &eload(
            module => 'Relianoid::EE::Net::Routing',
            func   => 'applyRoutingDependIfaceVirt',
            args   => [ 'del', $if_ref ]
        ) if $eload;
    }

    &setRuleIPtoTable($$if_ref{name}, $$if_ref{addr}, "del");
    $status = &logAndRun($ip_cmd);

    # Set down status in configuration file
    if ($writeconf) {
        my $configdir = &getGlobalConfiguration('configdir');
        my $file      = "$configdir/if_$$if_ref{name}_conf";

        require Config::Tiny;
        my $fileHandler = Config::Tiny->new();
        $fileHandler = Config::Tiny->read($file) if (-f $file);

        $fileHandler->{ $if_ref->{name} }{status} = "down";
        $fileHandler->write($file);
    }

    # calculate new backend masquerade IPs
    require Relianoid::Farm::Config;
    &reloadFarmsSourceAddress();

    return $status;
}

=pod

=head1 stopIf

Stop network interface, this removes the IP address instead of putting the interface down.

This is an alternative to downIf which performs better in hardware
appliances. Because if the interface is not brought down it wont take
time to bring the interface back up and enable the link.

Parameters:

    if_ref - network interface hash reference.

Returns: integer - errno of ip command.

Bugs:

    Remove VLAN interface and bring it up.

=cut

# stop network interface
sub stopIf ($if_ref) {
    &log_info("Stopping interface $$if_ref{name}", "NETWORK");

    my $status = 0;
    my $if     = $$if_ref{name};

    # If $if is Vini do nothing
    if (!$$if_ref{vini}) {
        # If $if is a Interface, delete that IP
        my $ip_cmd = "$ip_bin address flush dev $$if_ref{name}";
        $status = &logAndRun($ip_cmd);

        # If $if is a Vlan, delete Vlan
        if ($$if_ref{vlan} ne '') {
            $ip_cmd = "$ip_bin link delete $$if_ref{name} type vlan";
            $status = &logAndRun($ip_cmd);
        }

        #ensure Link Up
        if ($$if_ref{status} eq 'up') {
            $ip_cmd = "$ip_bin link set dev $$if_ref{name} up";
            $status = &logAndRun($ip_cmd);
        }

        my $rttables = &getGlobalConfiguration('rttables');

        # Delete routes table
        open my $fh, '<', $rttables;
        my @contents = <$fh>;
        close $fh;

        @contents = grep { !/^...\ttable_$if$/ } @contents;

        open $fh, '>', $rttables;
        print $fh @contents;
        close $fh;
    }
    else {
        my @ifphysic = split(/:/, $if);
        my $ip       = $$if_ref{addr};

        if ($ip =~ /\./) {
            use Net::IPv4Addr qw(ipv4_network);
            my (undef, $mask) = ipv4_network("$ip / $$if_ref{mask}");
            my $cmd = "$ip_bin addr del $ip/$mask brd + dev $ifphysic[0] label $if";

            &logAndRun("$cmd");

            &eload(
                module => 'Relianoid::EE::Net::Routing',
                func   => 'applyRoutingDependIfaceVirt',
                args   => [ 'del', $if_ref ]
            ) if $eload;
        }
    }

    return $status;
}

=pod

=head1 delIf

Remove system and stored settings and statistics of a network interface.

Parameters:

    if_ref - network interface hash reference.

Returns: integer - errno of ip command.

=cut

sub delIf ($if_ref) {
    my $status;

    # remove dhcp configuration
    if (exists $if_ref->{dhcp} and $if_ref->{dhcp} eq 'true') {
        &eload(
            module => 'Relianoid::EE::Net::DHCP',
            func   => 'disableDHCP',
            args   => [$if_ref],
        );
    }

    require Relianoid::Net::Interface;
    $status = &cleanInterfaceConfig($if_ref);
    if ($status) {
        return $status;
    }

    &setRuleIPtoTable($$if_ref{name}, $$if_ref{addr}, "del");

    # Block for any kind of network interface, except virtual interfaces
    if (not(defined $$if_ref{vini} && length $$if_ref{vini})) {
        # If $if is a gre Tunnel, delete gre
        if ($$if_ref{type} eq 'gre') {
            my $ip_cmd = "$ip_bin tunnel delete $$if_ref{name} mode gre";
            $status = &logAndRun($ip_cmd);
        }
        else {
            my $is_dhcp = defined $if_ref->{dhcp} && $if_ref->{dhcp} eq 'true';

            if (!$is_dhcp && $$if_ref{addr}) {
                # If $if is a Interface, delete that IP
                my $ip_cmd = "$ip_bin addr del $$if_ref{addr}/$$if_ref{mask} dev $$if_ref{name}";

                if (length $if_ref->{addr} && length $if_ref->{mask}) {
                    $status = &logAndRun($ip_cmd);
                }
            }

            # If $if is a Vlan, delete Vlan
            if (defined $$if_ref{vlan} and length $$if_ref{vlan}) {
                my $ip_cmd = "$ip_bin link delete $$if_ref{name} type vlan";
                $status = &logAndRun($ip_cmd);
            }
        }

        #delete custom routes
        &eload(
            module => 'Relianoid::EE::Net::Routing',
            func   => 'delRoutingDependIface',
            args   => [ $$if_ref{name} ],
        ) if ($eload);

        # check if alternative stack is in use
        my $ip_v_to_check = ($$if_ref{ip_v} == 4) ? 6 : 4;
        my $interface     = &getInterfaceConfig($$if_ref{name}, $ip_v_to_check);

        if (!$interface
            || ($interface->{type} eq "bond" and not exists $interface->{addr}))
        {
            &deleteRoutesTable($$if_ref{name});
        }
    }

    # delete graphs
    require Relianoid::RRD;
    &delGraph($$if_ref{name}, "iface");

    if ($eload) {
        # delete alias
        &eload(
            module => 'Relianoid::EE::Alias',
            func   => 'delAlias',
            args   => [ 'interface', $$if_ref{name} ]
        );

        #delete from RBAC
        &eload(
            module => 'Relianoid::EE::RBAC::Group::Config',
            func   => 'delRBACResource',
            args   => [ $$if_ref{name}, 'interfaces' ],
        );

        #reload netplug
        if (!defined($$if_ref{vini}) || $$if_ref{vini} eq '') {
            &eload(
                module => 'Relianoid::EE::Net::Ext',
                func   => 'reloadNetplug',
            );
        }
    }

    return $status;
}

=pod

=head1 delIp

Deletes an IP address from an interface

Parameters:

    if      - string - Name of interface.
    ip      - string - IP address.
    netmask - string - Network mask.

Returns: integer - errno of ip command.

=cut

# Execute command line to delete an IP from an interface
sub delIp ($if, $ip, $netmask) {
    if (!defined $ip || $ip eq '') {
        return 0;
    }

    &log_info("Deleting ip $ip/$netmask from interface $if", "NETWORK");

    # Vini
    if ($if =~ /\:/) {
        ($if) = split(/\:/, $if);
    }

    &setRuleIPtoTable($if, $ip, "del");
    my $ip_cmd = "$ip_bin addr del $ip/$netmask dev $if";
    my $status = &logAndRun($ip_cmd);

    return $status;
}

=pod

=head1 isIp

It checks if an IP is already applied to the network interface.

Parameters:

    if_ref - network interface hash reference.

Returns: integer

- 0: if the IP is not configured on the interface.
- 1: if the IP is configured on the interface.

=cut

sub isIp ($if_ref) {
    # finish if the address is already assigned
    my $routed_iface = $$if_ref{dev};
    $routed_iface .= ".$$if_ref{vlan}" if defined $$if_ref{vlan} && $$if_ref{vlan} ne '';

    my @ip_output = @{ &logAndGet("$ip_bin -$$if_ref{ip_v} addr show dev $routed_iface", "array") };

    if (grep { /$$if_ref{addr}\// } @ip_output) {
        &log_debug2("The IP '$$if_ref{addr}' already is applied in '$routed_iface'", "NETWORK");
        return 1;
    }

    return 0;
}

=pod

=head1 addIp

Add an IPv4 to an Interface, Vlan or Vini

Parameters:

    if_ref - network interface hash reference.

Returns: integer - errno of ip command.

=cut

# Execute command line to add an IPv4 to an Interface, Vlan or Vini
sub addIp ($if_ref) {
    unless (ref $if_ref eq 'HASH') {
        croak("required network interface hash reference");
    }

    unless (exists $$if_ref{addr}) {
        carp("network interface has no address field");
        return 0;
    }

    unless ($$if_ref{addr} and length $$if_ref{addr}) {
        return 0;
    }

    &log_info("Adding IP $$if_ref{addr}/$$if_ref{mask} to interface $$if_ref{name}", "NETWORK");

    # Do not add automatically route in the main table
    # The routes are managed by relianoid
    my $extra_params = "noprefixroute";
    my $ip_cmd;
    my $if_announce   = "";
    my $broadcast_opt = ($$if_ref{ip_v} == 4) ? 'broadcast +' : '';

    if ($$if_ref{ip_v} == 6) {
        $extra_params .= ' nodad';
    }

    # $if is a Virtual Network Interface
    if (defined $$if_ref{vini} && $$if_ref{vini} ne '') {
        my ($toif) = split(':', $$if_ref{name});

        $ip_cmd = "$ip_bin addr add $$if_ref{addr}/$$if_ref{mask} $broadcast_opt dev $toif label $$if_ref{name} $extra_params";
        $if_announce = $toif;
    }

    # $if is a Network Interface
    else {
        $ip_cmd      = "$ip_bin addr add $$if_ref{addr}/$$if_ref{mask} $broadcast_opt dev $$if_ref{name} $extra_params";
        $if_announce = "$$if_ref{name}";
    }

    my $status = 0;

    # The command will fail if the address already exists
    unless (isIp($if_ref)) {
        $status = &logAndRun($ip_cmd);
    }

    #if arp_announce is enabled then send garps to network
    eval {
        if ($eload) {
            my $cl_status = &eload(
                module => 'Relianoid::EE::Cluster',
                func   => 'getClusterNodeStatus',
                args   => [],
            );
            my $cl_maintenance = &eload(
                module => 'Relianoid::EE::Cluster',
                func   => 'getClMaintenanceManual',
                args   => [],
            );

            if (   &getGlobalConfiguration('arp_announce') eq "true"
                && ($cl_status and $cl_status eq "master")
                && $cl_maintenance ne "true")
            {
                require Relianoid::Net::Util;

                &log_info("Announcing garp $if_announce and $$if_ref{addr} ");
                &sendGArp($if_announce, $$if_ref{addr});
            }
        }
    };

    &setRuleIPtoTable($$if_ref{name}, $$if_ref{addr}, "add");

    return $status;
}

=pod

=head1 setRuleIPtoTable

Add / delete a rule for the IP in order to force the traffic to the associated table_<nic>
it only applies if global param $duplicated_net is true

Parameters:

    iface  - string - Main interface, nic, bond o vlan
    ip     - string - main IP or VIP
    action - string - add / del

Returns: integer - errno. 0 if ok, 1 if failed

=cut

sub setRuleIPtoTable ($iface, $ip, $action) {
    if (!defined($ip) || $ip eq '') {
        return 0;
    }

    my $prio = &getGlobalConfiguration('routingRulePrioIfacesDuplicated');

    if (&getGlobalConfiguration('duplicated_net') ne "true") {
        #this feature is not in use
        return 0;
    }

    #In case <if>:<name> is sent
    my @ifname = split(/:/, $iface);
    my $ip_cmd = "$ip_bin rule $action from $ip/32 lookup table_$ifname[0] prio $prio";
    return (&execIpCmd($ip_cmd) > 0);
}

=pod

=head1 execIpCmd

This function replaces to logAndRun to exec ip commands. It does not print
error message if the command already was applied or removed.

Parameters:

    command - string - command line with the ip command

Returns: integer - errno.

- 0: on success.
- -1: the command is already applied.
- 1: there was an error.

=cut

sub execIpCmd ($command) {
    # do not use the logAndGet function, this function is managing the error output and error code
    my @cmd_output  = `$command 2>&1`;
    my $return_code = $?;

    if ($return_code == 512)    # code 2 in shell
    {
        my $msg =
          ($command =~ /add/)
          ? "Trying to apply the rule but it already was applied"
          : "Trying to remove the rule but it was not found";
        &log_debug($msg,                "net");
        &log_debug("running: $command", "SYSTEM");
        &log_debug2("out: @cmd_output", "SYSTEM");
        $return_code = -1;
    }
    elsif ($return_code) {
        &log_error("Command failed: $command", "SYSTEM");
        &log_error("out: @cmd_output",         "SYSTEM");
        $return_code = 1;
    }
    else {
        &log_debug("running: $command", "SYSTEM");
        &log_debug2("out: @cmd_output", "SYSTEM");
        $return_code = 0;
    }

    return $return_code;
}

1;
