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

Relianoid::VPN::Tunnel::Validate

=cut

use strict;
use warnings;
use feature qw(signatures);

=pod

=head1 checkVpnTunnelObject

Parameters:

Returns: 

=cut


sub checkVpnTunnelObject ($vpn_ref) {
    my $rc;

    # check Local

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    if (!defined $vpn_ref->{ $vpn_config->{LOCAL} }) {
        &log_warn("VPN $vpn_config->{LOCAL} is missing in VPN Object.", "VPN");
        $rc = -1;
    }
    if (!defined $vpn_ref->{ $vpn_config->{LOCALIP} }) {
        &log_warn("VPN $vpn_config->{LOCALIP} is missing in VPN Object.", "VPN");
        $rc = -1;
    }
    if (!defined $vpn_ref->{ $vpn_config->{LOCALMASK} }) {
        &log_warn("VPN $vpn_config->{LOCALMASK} is missing in VPN Object.", "VPN");
        $rc = -1;
    }

    if (!defined $vpn_ref->{ $vpn_config->{LOCALTUNIP} }) {
        &log_warn("VPN $vpn_config->{LOCALTUNIP} is missing in VPN Object.", "VPN");
        $rc = -1;
    }

    if (!defined $vpn_ref->{ $vpn_config->{LOCALTUNMASK} }) {
        &log_warn("VPN $vpn_config->{LOCALTUNMASK} is missing in VPN Object.", "VPN");
        $rc = -1;
    }

    # check Remote

    if (!defined $vpn_ref->{ $vpn_config->{REMOTE} }) {
        &log_warn("VPN $vpn_config->{REMOTE} is missing in VPN Object.", "VPN");
        $rc = -1;
    }

    if (!defined $vpn_ref->{ $vpn_config->{REMOTEIP} }) {
        &log_warn("VPN $vpn_config->{REMOTEIP} is missing in VPN Object.", "VPN");
        $rc = -1;
    }

    if (!defined $vpn_ref->{ $vpn_config->{REMOTEMASK} }) {
        &log_warn("VPN $vpn_config->{REMOTEMASK} is missing in VPN Object.", "VPN");
        $rc = -1;
    }

    if (!defined $vpn_ref->{ $vpn_config->{REMOTETUNIP} }) {
        &log_warn("VPN $vpn_config->{REMOTETUNIP} is missing in VPN Object.", "VPN");
        $rc = -1;
    }

    # check auth

    return $rc;
}

=pod

=head1 validateVpnTunnelObject

Validate Params against Tunnel VPN Configuration.

Parameters:

    vpn_ref    - Tunnel VPN Hash ref.
    params_ref - Optional. Hash ref of params to validate.

Returns: hash reference

A hashref that maps error code and description

    code - Integer. Error code. 0 on success.
    desc - String. Description of the error.
    err  - String. Object causing the error.

=cut

sub validateVpnTunnelObject ($vpn_ref, $params_ref = undef) {
    my $error->{code} = 0;

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    $params_ref = $vpn_ref if (!defined $params_ref);

    my $local_gw      = $params_ref->{ $vpn_config->{LOCAL} }      // $vpn_ref->{ $vpn_config->{LOCAL} };
    my $local_ip      = $params_ref->{ $vpn_config->{LOCALIP} }    // $vpn_ref->{ $vpn_config->{LOCALIP} };
    my $local_mask    = $params_ref->{ $vpn_config->{LOCALMASK} }  // $vpn_ref->{ $vpn_config->{LOCALMASK} };
    my $remote_ip     = $params_ref->{ $vpn_config->{REMOTEIP} }   // $vpn_ref->{ $vpn_config->{REMOTEIP} };
    my $remote_mask   = $params_ref->{ $vpn_config->{REMOTEMASK} } // $vpn_ref->{ $vpn_config->{REMOTEMASK} };
    my $remote_gw     = $params_ref->{ $vpn_config->{REMOTE} }     // $vpn_ref->{ $vpn_config->{REMOTE} };
    my $local_net     = NetAddr::IP->new($local_ip, $local_mask)->network();
    my $localtun_ip   = $params_ref->{ $vpn_config->{LOCALTUNIP} }   // $vpn_ref->{ $vpn_config->{LOCALTUNIP} };
    my $localtun_mask = $params_ref->{ $vpn_config->{LOCALTUNMASK} } // $vpn_ref->{ $vpn_config->{LOCALTUNMASK} };
    my $remotetun_ip  = $params_ref->{ $vpn_config->{REMOTETUNIP} }  // $vpn_ref->{ $vpn_config->{REMOTETUNIP} };
    my $localtun_net  = NetAddr::IP->new($localtun_ip, $localtun_mask)->network();

    if (defined $params_ref->{ $vpn_config->{LOCAL} }) {
        # local ( gw ) : must exists on the system . if, vlan , vif ?
        use Relianoid::Net::Interface;
        if (!&getIpAddressExists($local_gw)) {
            $error->{code} = 1;
            $error->{desc} = "Local Gateway $local_gw must exists.";
            $error->{err}  = "Local Gateway";
            return $error;
        }
    }

    if (defined $params_ref->{ $vpn_config->{LOCALIP} }) {
        # local ( ip ) : must exists on the system . if, vlan , vif ?
        use Relianoid::Net::Interface;
        if (!&getIpAddressExists($local_ip)) {
            $error->{code} = 1;
            $error->{desc} = "Local IP $local_ip must exists.";
            $error->{err}  = "Local IP";
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
        my $vpn_name_found = &getVpnParamExists("tunnel", $params_check);
        if ($vpn_name_found !~ /^\d+$/) {
            $error->{code} = 2;
            $error->{desc} = "Local Gateway $local_gw and Remote Gateway $remote_gw already configured in VPN $vpn_name_found.";
            $error->{err}  = "Local Gateway, Remote Gateway";
            return $error;
        }
    }

    if (   defined $params_ref->{ $vpn_config->{LOCALIP} }
        or defined $params_ref->{ $vpn_config->{LOCALMASK} })
    {
        # local net ( net ) : must exists on the system
        use Relianoid::Net::Validate;
        my $if_name = &checkNetworkExists($local_ip, $local_mask, undef, 0);
        if ($if_name eq "") {
            $error->{code} = 3;
            $error->{desc} = "Local Network $local_net must be accessible by an interface.";
            $error->{err}  = "Local Network";
            return $error;
        }
        elsif (&getInterfaceType($if_name) eq 'gre'
            and defined $params_ref->{ $vpn_config->{LOCALIP} })
        {
            $error->{code} = 3;
            $error->{desc} = "Local IP $params_ref->{ $vpn_config->{LOCALIP} } belongs to a wrong Interface type : $if_name.";
            $error->{err}  = "Local Network";
            return $error;
        }
    }
    if (   defined $params_ref->{ $vpn_config->{LOCAL} }
        or defined $params_ref->{ $vpn_config->{LOCALIP} }
        or defined $params_ref->{ $vpn_config->{LOCALMASK} })
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

    if (defined $params_ref->{ $vpn_config->{LOCALTUNIP} }) {
        # localtunip ( ip ) : Do not must exists on the system .
        use Relianoid::Net::Interface;
        if (&getIpAddressExists($localtun_ip)) {
            $error->{code} = 5;
            $error->{desc} = "IP $localtun_ip already exist.";
            $error->{err}  = "Local Tunnel IP";
            return $error;
        }
    }
    if (   defined $params_ref->{ $vpn_config->{LOCALTUNIP} }
        or defined $params_ref->{ $vpn_config->{LOCALTUNMASK} })
    {
        # local tun net ( net ) :  Do not must exists on the system .
        use Relianoid::Net::Validate;
        my $if_found =
          &checkNetworkExists($localtun_ip, $localtun_mask, $vpn_ref->{ $vpn_config->{NAME} }, 0);
        if ($if_found ne "") {
            $error->{code} = 5;
            $error->{desc} = "Local Tunnel Network $localtun_net is already configured in $if_found.";
            $error->{err}  = "Local Tunnel IP, Local Tunnel Mask";
            return $error;
        }
    }
    if (   defined $params_ref->{ $vpn_config->{LOCALTUNIP} }
        or defined $params_ref->{ $vpn_config->{LOCALTUNMASK} }
        or defined $params_ref->{ $vpn_config->{REMOTETUNIP} })
    {
        # local tun  , remote tun ( ip ) :  Must be in the same network .
        use Relianoid::Net::Validate;
        if (!&validateGateway($localtun_ip, $localtun_mask, $remotetun_ip)) {
            $error->{code} = 6;
            $error->{desc} = "Remote Tunnel IP $remotetun_ip does not belong to Local Tunnel Network $localtun_net.";
            $error->{err}  = "Local Tunnel IP, Local Tunnel Mask, Remote Tunnel IP";
            return $error;
        }
    }

    if (   defined $params_ref->{ $vpn_config->{REMOTEIP} }
        or defined $params_ref->{ $vpn_config->{REMOTEMASK} })
    {
        # remote net ( net ) : must not exists on the system
        use Relianoid::Net::Validate;
        my $iface = &checkNetworkExists($remote_ip, $remote_mask, undef, 0);
        if ($iface ne "") {
            $error->{code} = 7;
            $error->{desc} = "Remote Network $remote_ip/$remote_mask is defined in interface $iface.";
            $error->{err}  = "Remote Network";
            return $error;
        }
    }

    return $error;
}

1;
