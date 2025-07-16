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

Relianoid::VPN::RemoteAccess::Validate

=cut

sub checkVpnRemoteAccessObject ($vpn_ref) {
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

    if (!defined $vpn_ref->{ $vpn_config->{REMOTETUNRANGE} }) {
        &log_warn("VPN $vpn_config->{REMOTETUNRANGE} is missing in VPN Object.", "VPN");
        $rc = -1;
    }

    return $rc;
}

=pod

=head1 validateVpnRemoteAccessObject

Validate Params against Remote Access VPN Configuration.

Parameters:

    vpn_ref    - Remote Access VPN Hash ref.
    params_ref - Optional. Hash ref of params to validate.

Returns: hash reference

error_ref - error object. A hashref that maps error code and description

    code - Integer. Error code. 0 on success.
    desc - String. Description of the error.
    err  - String. Object causing the error.

=cut

sub validateVpnRemoteAccessObject ($vpn_ref, $params_ref = undef) {
    my $error->{code} = 0;

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    $params_ref = $vpn_ref if (!defined $params_ref);

    my $local_gw      = $params_ref->{ $vpn_config->{LOCAL} }     // $vpn_ref->{ $vpn_config->{LOCAL} };
    my $local_ip      = $params_ref->{ $vpn_config->{LOCALIP} }   // $vpn_ref->{ $vpn_config->{LOCALIP} };
    my $local_mask    = $params_ref->{ $vpn_config->{LOCALMASK} } // $vpn_ref->{ $vpn_config->{LOCALMASK} };
    my $local_net     = NetAddr::IP->new($local_ip, $local_mask)->network();
    my $localtun_ip   = $params_ref->{ $vpn_config->{LOCALTUNIP} }   // $vpn_ref->{ $vpn_config->{LOCALTUNIP} };
    my $localtun_mask = $params_ref->{ $vpn_config->{LOCALTUNMASK} } // $vpn_ref->{ $vpn_config->{LOCALTUNMASK} };
    my $localtun_net  = NetAddr::IP->new($localtun_ip, $localtun_mask)->network();
    my $remote_range  = $params_ref->{ $vpn_config->{REMOTETUNRANGE} } // $vpn_ref->{ $vpn_config->{REMOTETUNRANGE} };

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

    if (defined $params_ref->{ $vpn_config->{LOCAL} }) {
        my $params_check   = { $vpn_config->{LOCAL} => $local_gw, };
        my $vpn_name_found = &getVpnParamExists("remote_access", $params_check);
        if ($vpn_name_found !~ /^\d+$/) {
            $error->{code} = 2;
            $error->{desc} = "Local Gateway $local_gw already configured in VPN $vpn_name_found.";
            $error->{err}  = "Local Gateway";
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

        my $if_type = &getInterfaceType($if_name);
        if (($if_type eq 'gre' or $if_type eq 'ppp')
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
        or defined $params_ref->{ $vpn_config->{REMOTETUNRANGE} })
    {
        # local tun  , remote tun ( ip ) :  Must be in the same network .
        use Relianoid::Net::Validate;
        my ($first_ip, $last_ip) = split("-", $remote_range);
        my $status = &validateGateway($localtun_ip, $localtun_mask, $first_ip);
        $status = &validateGateway($localtun_ip, $localtun_mask, $last_ip)
          if ($status);
        if (!$status) {
            $error->{code} = 6;
            $error->{desc} = "Remote Tunnel IP Range $remote_range does not belong to Local Tunnel Network $localtun_net.";
            $error->{err}  = "Local Tunnel IP, Local Tunnel Mask, Remote Tunnel IP Range";
            return $error;
        }
    }

    return $error;
}

1;
