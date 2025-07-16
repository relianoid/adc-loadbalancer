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

Relianoid::VPN::Validate

=cut

use strict;
use warnings;
use feature qw(signatures);

sub checkVPNObject ($vpn_ref) {
    my $rc = -1;

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    # check object name
    if (!defined $vpn_ref->{ $vpn_config->{NAME} }) {
        &log_warn("VPN '$vpn_config->{NAME}' is missing in VPN Object.", "VPN");
        return -1;
    }

    # check profile
    if (!defined $vpn_ref->{ $vpn_config->{PROFILE} }) {
        &log_warn("VPN '$vpn_config->{PROFILE}' is missing in VPN Object.", "VPN");
        return -2;
    }

    if ($vpn_ref->{ $vpn_config->{PROFILE} } eq "site_to_site") {
        require Relianoid::VPN::SiteToSite::Validate;
        $rc = &checkVpnSiteToSiteObject($vpn_ref);
    }
    elsif ($vpn_ref->{ $vpn_config->{PROFILE} } eq "tunnel") {
        require Relianoid::VPN::Tunnel::Validate;
        $rc = &checkVpnTunnelObject($vpn_ref);
    }
    elsif ($vpn_ref->{ $vpn_config->{PROFILE} } eq "remote_access") {
        require Relianoid::VPN::RemoteAccess::Validate;
        $rc = &checkVpnRemoteAccessObject($vpn_ref);
    }

    return $rc;
}

1;
