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

=pod

=head1 Module

Relianoid::Net::Util

=cut

=pod

=head1 getIfacesFromIf

Get List of Vinis or Vlans from a network interface.

Parameters:

    if_name - interface name.
    type - "vini" or "vlan".

Returns:

    list - list of interface references.

See Also:

    Only used in: <setIfacesUp>

=cut

# Get List of Vinis or Vlans from an interface
sub getIfacesFromIf ($if_name, $type) {
    my @ifaces;
    my @configured_interfaces = @{ &getConfigInterfaceList() };

    for my $interface (@configured_interfaces) {
        next if $$interface{name} !~ /^$if_name.+/;

        # get vinis
        if ($type eq "vini" && $$interface{vini} ne '') {
            push @ifaces, $interface;
        }

        # get vlans (including vlan:vini)
        elsif ($type eq "vlan"
            && $$interface{vlan} ne ''
            && $$interface{vini} eq '')
        {
            push @ifaces, $interface;
        }
    }

    return @ifaces;
}

=pod

=head1 setIfacesUp

Bring up all Virtual or VLAN interfaces on a network interface.

Parameters:

    if_name - Name of interface.
    type - "vini" or "vlan".

Returns:

    undef - .

Bugs:

    Set VLANs up.

=cut

# Check if there are some Virtual Interfaces or Vlan with IPv6 and previous UP status to get it up.
sub setIfacesUp ($if_name, $type) {
    if (not($type eq 'vlan' or $type eq 'vini')) {
        die("setIfacesUp: type variable must be 'vlan' or 'vini'");
    }

    my @ifaces = &getIfacesFromIf($if_name, $type);

    if (@ifaces) {
        for my $iface (@ifaces) {
            if ($iface->{status} eq 'up') {
                &addIp($iface);
                if ($iface->{type} eq 'vlan') {
                    &applyRoutes("local", $iface);
                }
            }
        }

        if ($type eq "vini") {
            &log_info("Virtual interfaces of $if_name have been put up.", "NETWORK");
        }
        elsif ($type eq "vlan") {
            &log_info("VLAN interfaces of $if_name have been put up.", "NETWORK");
        }
    }

    return;
}

=pod

=head1 sendGPing

Send gratuitous ICMP packets for L3 aware.

Parameters:

    pif - ping interface name.

Returns:

    none

See Also:

    <sendGArp>

=cut

# send gratuitous ICMP packets for L3 aware
sub sendGPing ($pif) {
    my $if_conf = &getInterfaceConfig($pif);
    my $gw      = $if_conf->{gateway};

    if ($gw) {
        my $ping_bin = &getGlobalConfiguration('ping_bin');
        my $pingc    = &getGlobalConfiguration('pingc');
        my $ping_cmd = "$ping_bin -c $pingc -I $if_conf->{addr} $gw";

        &log_info("Sending $pingc ping(s) to gateway $gw from $if_conf->{addr}", "NETWORK");
        &logAndRunBG("$ping_cmd");
    }
    return;
}

=pod

=head1 sendGArp

Send gratuitous ARP frames.

Broadcast an ip address with ARP frames through a network interface.
Also, pings the interface gateway.

Parameters:

    if - interface name.
    ip - ip address.

Returns:

    none

See Also:

    <broadcastInterfaceDiscovery>, <sendGPing>

=cut

# send gratuitous ARP frames
sub sendGArp ($if, $ip) {
    require Relianoid::Net::Validate;

    my @iface = split(':', $if);
    my $ip_v  = &ipversion($ip);

    if ($ip_v == 4) {
        my $arping_bin      = &getGlobalConfiguration('arping_bin');
        my $arp_unsolicited = &getGlobalConfiguration('arp_unsolicited');

        my $arp_arg    = $arp_unsolicited ? '-U' : '-A';
        my $arping_cmd = "$arping_bin $arp_arg -c 2 -I $iface[0] $ip";

        &log_info("$arping_cmd", "NETWORK");
        &logAndRunBG("$arping_cmd");
    }
    elsif ($ip_v == 6) {
        my $arpsend_bin = &getGlobalConfiguration('arpsend_bin');
        my $arping_cmd  = "$arpsend_bin -U -i $ip $iface[0]";

        &log_info("$arping_cmd", "NETWORK");
        &logAndRunBG("$arping_cmd");
    }

    &sendGPing($iface[0]);
    return;
}

=pod

=head1 setArpAnnounce

Set a cron task to cast a ARP packet each minute

Parameters:

    none

Returns:

    Integer - Error code: 0 on success or another value on failure

=cut

sub setArpAnnounce () {
    my $script = &getGlobalConfiguration("arp_announce_bin");
    my $path   = &getGlobalConfiguration("arp_announce_cron_path");
    my $err    = 0;

    my $fh = &openlock($path, 'w') or return 1;
    print $fh "* * * * *	root	$script &>/dev/null\n";
    close $fh;

    if (!$err) {
        $err = &setGlobalConfiguration('arp_announce', "true");
    }

    return $err;
}

=pod

=head1 unsetArpAnnounce

Remove the cron task to cast a ARP packet each minute

Parameters:

    none

Returns:

    Integer - Error code: 0 on success or another value on failure

=cut

sub unsetArpAnnounce () {
    my $path         = &getGlobalConfiguration("arp_announce_cron_path");

    if (-f $path) {
        my $rem = unlink $path;
        if (!$rem) {
            &log_error("Error deleting the file '$path'", "NETWORK");
            return 1;
        }
    }

    return &setGlobalConfiguration('arp_announce', "false");
}

=pod

=head1 iponif

Get the (primary) ip address on a network interface.

A copy of this function is in noid-cluster-notify.

Parameters:

    if - interface namm.

Returns:

    scalar - string with IP address.

See Also:

    <getInterfaceOfIp>, <_runDatalinkFarmStart>, <_runDatalinkFarmStop>, <noid-cluster-notify>

=cut

#know if and return ip
sub iponif ($if) {
    require IO::Socket;
    require Relianoid::Net::Interface;

    my $s      = IO::Socket::INET->new(Proto => 'udp');
    my $iponif = $s->if_addr($if);

    # fixes virtual interfaces IPs
    unless ($iponif) {
        my $if_ref = &getInterfaceConfig($if);
        $iponif = $if_ref->{addr};
    }

    return $iponif;
}

=pod

=head1 maskonif

Get the network mask of an network interface (primary) address.

Parameters:

    if - interface namm.

Returns:

    scalar - string with network address.

See Also:

    <_runDatalinkFarmStart>, <_runDatalinkFarmStop>

=cut

# return the mask of an if
sub maskonif ($if) {
    require IO::Socket;

    my $s        = IO::Socket::INET->new(Proto => 'udp');
    my $maskonif = $s->if_netmask($if);

    return $maskonif;
}

=pod

=head1 listallips

List all IPs used for interfaces

Parameters:

    none - .

Returns:

    list - All IP addresses.

Bugs:

    $ip !~ /127.0.0.1/
    $ip !~ /0.0.0.0/

=cut

sub listallips () {
    require Relianoid::Net::Interface;

    my @listinterfaces = ();

    for my $if_name (&getInterfaceList()) {
        my $if_ref = &getInterfaceConfig($if_name);
        push @listinterfaces, $if_ref->{addr} if ($if_ref->{addr});
    }

    return @listinterfaces;
}

=pod

=head1 setIpForward

Set IP forwarding on/off

Parameters:

    arg - "true" to turn it on or other to turn it off.

Returns:

    scalar - return

See Also:

    <_runDatalinkFarmStart>

=cut

# Enable(true) / Disable(false) IP Forwarding
sub setIpForward ($arg) {
    my $status = 0;
    my $switch = $arg eq 'true';

    &log_info("setting $arg to IP forwarding ", "NETWORK");

    # switch forwarding as requested
    $status += &logAndRun("echo $switch > /proc/sys/net/ipv4/conf/all/forwarding");
    $status += &logAndRun("echo $switch > /proc/sys/net/ipv4/ip_forward");
    $status += &logAndRun("echo $switch > /proc/sys/net/ipv6/conf/all/forwarding");

    return $status;
}

=pod

=head1 getInterfaceOfIp

Get the name of the interface with such IP address.

Parameters:

    ip - string with IP address.

Returns:

    scalar - Name of interface, if found, undef otherwise.

See Also:

    <enable_cluster>, <new_farm>, <modify_datalink_farm>

=cut

sub getInterfaceOfIp ($ip) {
    require Relianoid::Net::Interface;
    require NetAddr::IP;

    my $ref_addr = NetAddr::IP->new($ip);

    for my $iface (&getInterfaceList()) {
        # return interface if found in the listç
        my $if_ip = &iponif($iface);
        next if (!$if_ip);

        my $if_addr = NetAddr::IP->new($if_ip);

        return $iface if ($if_addr eq $ref_addr);
    }

    # returns an invalid interface name, an undefined variable
    &log_info("Warning: No interface was found configured with IP address $ip", "NETWORK");

    return;
}

1;
