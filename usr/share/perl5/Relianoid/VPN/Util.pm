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

=pod

=head1 Module

Relianoid::VPN::Util

=cut

use strict;
use warnings;
use feature qw(signatures);

=pod

=head1 getVpnByIp

	Search for a VPN using the IP as Local gateway.

Parameters:
	ip - IP address to search for

Returns:
	scalar - Array ref of vpns if the IP address is used as Local Gateway in a VPN.

=cut

sub getVpnByIp ($ip) {
    my @vpns = ();

    return \@vpns if (!defined $ip);

    require Relianoid::VPN::Core;

    my $vpn_config = &getVpnModuleConfig();
    my $vpn_list   = &getVpnList();

    use Relianoid::Net::Util;

    for my $vpn_name (@{$vpn_list}) {
        my $vpn_ref = &getVpnConfObject($vpn_name, [ $vpn_config->{LOCAL} ]);
        push @vpns, $vpn_name if ($vpn_ref->{ $vpn_config->{LOCAL} } eq $ip);
    }

    return \@vpns;
}

=pod

=head1 getVpnByNet

	Search for a VPN using the Net as Local Network.

Parameters:
	ip - IP address to search for

Returns:
	scalar - Array ref of vpns if the IP address is used as Local Network in a VPN.

=cut

sub getVpnByNet ($net) {
    my @vpns = ();

    return \@vpns if (!defined $net);

    my ($ip, $mask) = split(/\//, $net);

    require Relianoid::VPN::Core;

    my $vpn_config = &getVpnModuleConfig();
    my $vpn_list   = &getVpnList();

    use Relianoid::Net::Validate;

    for my $vpn_name (@{$vpn_list}) {
        my $vpn_ref = &getVpnConfObject($vpn_name);
        my ($local_ip, $local_mask) = split(/\//, $vpn_ref->{ $vpn_config->{LOCALNET} });
        push(@vpns, $vpn_name) if (&validateGateway($local_ip, $local_mask, $ip, $mask));
    }

    return \@vpns;
}

=pod

=head1 getVpnByTunIp

	Search for a VPN using the IP as Local Tunnel IP.

Parameters:
	ip - IP address to search for

Returns:
	scalar - Array ref of vpns if the IP address is used as Local Tunnel IP in a VPN.

=cut

sub getVpnByTunIp ($ip) {
    my @vpns = ();

    return \@vpns if (!defined $ip);

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();
    my $vpn_list = &getVpnList();

    use Relianoid::Net::Util;

    for my $vpn_name (@{$vpn_list}) {
        my $vpn_ref = &getVpnConfObject($vpn_name, [ $vpn_config->{LOCALTUNIP} ]);
        push(@vpns, $vpn_name) if ($vpn_ref->{ $vpn_config->{LOCALTUNIP} } eq $ip);
    }

    return \@vpns;
}

1;
