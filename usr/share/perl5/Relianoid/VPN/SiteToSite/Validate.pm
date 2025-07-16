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

Relianoid::VPN::SiteToSite::Validate

=cut

sub checkVpnSiteToSiteObject ($vpn_ref) {
    my $rc;

    # check Local

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    if (!defined $vpn_ref->{ $vpn_config->{LOCAL} }) {
        &log_warn("VPN $vpn_config->{LOCAL} is missing in VPN Object.", "VPN");
        $rc = -1;
    }
    if (!defined $vpn_ref->{ $vpn_config->{LOCALNET} }) {
        &log_warn("VPN $vpn_config->{LOCALNET} is missing in VPN Object.", "VPN");
        $rc = -1;
    }

    # check Remote

    if (!defined $vpn_ref->{ $vpn_config->{REMOTE} }) {
        &log_warn("VPN $vpn_config->{REMOTE} is missing in VPN Object.", "VPN");
        $rc = -1;
    }
    if (!defined $vpn_ref->{ $vpn_config->{REMOTENET} }) {
        &log_warn("VPN $vpn_config->{REMOTENET} is missing in VPN Object.", "VPN");
        $rc = -1;
    }

    # check auth

    return $rc;
}

=pod

=head1 validateVpnSiteToSiteObject

Validate Params against Site-to-Site VPN Configuration.

Parameters:

	vpn_ref    - Site-to-Site VPN Hash ref.
	params_ref - Optional. Hash ref of params to validate.

Returns: hash reference

error_ref - error object. A hashref that maps error code and description

    code - Integer. Error code. 0 on success.
    desc - String. Description of the error.
    err  - String. Object causing the error.

=cut

sub validateVpnSiteToSiteObject ($vpn_ref, $params_ref = undef) {
    my $error->{code} = 0;

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    $params_ref = $vpn_ref if (!defined $params_ref);

    my $local_gw   = $params_ref->{ $vpn_config->{LOCAL} }     // $vpn_ref->{ $vpn_config->{LOCAL} };
    my $local_net  = $params_ref->{ $vpn_config->{LOCALNET} }  // $vpn_ref->{ $vpn_config->{LOCALNET} };
    my $remote_net = $params_ref->{ $vpn_config->{REMOTENET} } // $vpn_ref->{ $vpn_config->{REMOTENET} };
    my $remote_gw  = $params_ref->{ $vpn_config->{REMOTE} }    // $vpn_ref->{ $vpn_config->{REMOTE} };
    my ($local_ip,  $local_mask)  = split(/\//, $local_net);
    my ($remote_ip, $remote_mask) = split(/\//, $remote_net);

    if (defined $params_ref->{ $vpn_config->{LOCAL} }) {
        # local ( ip ) : must exists on the system . if, vlan , vif ?
        use Relianoid::Net::Interface;
        if (!&getIpAddressExists($local_gw)) {
            $error->{code} = 1;
            $error->{desc} = "Local Gateway $local_gw must exists.";
            $error->{err}  = "Local Gateway";
            return $error;
        }
    }

    if (   defined $params_ref->{ $vpn_config->{LOCAL} }
        or defined $params_ref->{ $vpn_config->{REMOTE} })
    {
        my $params_check = {
            $vpn_config->{LOCAL}  => $local_gw,
            $vpn_config->{REMOTE} => $remote_gw,
        };
        my $vpn_name_found = &getVpnParamExists("site_to_site", $params_check);
        if ($vpn_name_found !~ /^\d+$/) {
            $error->{code} = 2;
            $error->{desc} = "Local Gateway $local_gw and Remote Gateway $remote_gw already configured in VPN $vpn_name_found.";
            $error->{err}  = "Local Gateway, Remote Gateway";
            return $error;
        }
    }

    if (defined $params_ref->{ $vpn_config->{LOCALNET} }) {
        # local net ( net ) : must exists on the system
        use Relianoid::Net::Validate;
        if (&checkNetworkExists($local_ip, $local_mask, undef, 0) eq "") {
            $error->{code} = 3;
            $error->{desc} = "Local Network $local_net must be accessible by an interface.";
            $error->{err}  = "Local Network";
            return $error;
        }
    }
    if (   defined $params_ref->{ $vpn_config->{LOCAL} }
        or defined $params_ref->{ $vpn_config->{LOCALNET} })
    {
        # local not in localnet
        use Relianoid::Net::Validate;
        if (&validateGateway($local_ip, $local_mask, $local_gw)) {
            $error->{code} = 4;
            $error->{desc} = "Local Gateway $local_gw cannot be in Local Network $local_net.";
            $error->{err}  = "Local Gateway, Local Network";
            return $error;
        }
    }

    if (defined $params_ref->{ $vpn_config->{REMOTENET} }) {
        # remote net ( net ) : must not exists on the system
        use Relianoid::Net::Validate;
        my $iface = &checkNetworkExists($remote_ip, $remote_mask, undef, 0);
        if ($iface ne "") {
            $error->{code} = 5;
            $error->{desc} = "Remote Network $remote_net is defined in interface $iface.";
            $error->{err}  = "Remote Network";
            return $error;
        }
    }

    return $error;
}

1;
