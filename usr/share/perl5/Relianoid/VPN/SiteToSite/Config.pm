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

Relianoid::VPN::SiteToSite::Config

=cut

=pod

=head1 createVpnSiteToSite

Create Site-to-Site VPN conf,conn and key files.

Parameters: hash reference

site_to_site - Site-to-Site VPN object. A hashref that maps an Site-to-Site VPN object

    name -
    local -
    remote -
    localnet -
    remotenet -
    password -
    auth -
    p1encrypt - Defines the encryption of Phase1.
    p1authen - Defines the authentication of Phase1.
    p1dhgroups - Defines the DH Groups of Phase1.
    p2protocol - Defines the protocol of Phase2.
    p2encrypt - Defines the encryptions of Phase2.
    p2authen - Defines the authentication of Phase2.
    p2dhgroups - Defines the DH Groups of Phase2.
    p2prffunct - Defines the Pseudo Random Functions of Phase2.

Returns: hash reference

error_ref - error object. A hashref that maps error code and description

    code - Integer. Error code. 0 on success.
    desc - String. Description of the error.
    err  - String. Object causing the error.

=cut

sub createVpnSiteToSite ($site_to_site) {
    my $error_ref = { code => 0 };

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    # validate object
    require Relianoid::VPN::SiteToSite::Validate;
    my $error = &checkVpnSiteToSiteObject($site_to_site);

    if ($error) {
        my $error_msg = "VPN Object not valid.";
        &log_warn($error_msg, "VPN");
        $error_ref->{code} = -1;
        $error_ref->{desc} = $error_msg;
        return $error_ref;
    }

    require Relianoid::VPN::Config;
    $error = &createVPNConf($site_to_site);

    if ($error) {
        my $error_msg = "Can't create VPN Configuration in VPN $site_to_site->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 1;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    require Relianoid::VPN::IPSec::Config;

    if (!$error) {
        # translate params
        my $site_to_site_translate;
        my $param_translate;

        require Relianoid::VPN::IPSec::Core;

        for my $param (keys %{$site_to_site}) {
            $param_translate = &getVpnIPSecParamName($param, "ipsec");

            if ($param_translate) {
                $site_to_site_translate->{$param_translate} = $site_to_site->{$param};
            }
        }

        # create auth
        $site_to_site_translate->{leftauth}  = $site_to_site->{ $vpn_config->{AUTH} };
        $site_to_site_translate->{rightauth} = $site_to_site->{ $vpn_config->{AUTH} };

        require Relianoid::VPN::IPSec::Config;

        # create Phase1 cryptography
        my $crypt;
        my $proposal;

        $crypt->{encryption} = $site_to_site->{ $vpn_config->{P1ENCRYPT} }
          if defined $site_to_site->{ $vpn_config->{P1ENCRYPT} };
        $crypt->{authentication} = $site_to_site->{ $vpn_config->{P1AUTHEN} }
          if defined $site_to_site->{ $vpn_config->{P1AUTHEN} };
        $crypt->{dhgroup} = $site_to_site->{ $vpn_config->{P1DHGROUP} }
          if defined $site_to_site->{ $vpn_config->{P1DHGROUP} };

        push @{ $proposal->{proposal} }, $crypt;
        $site_to_site_translate->{ike} = &getVpnIPSecCipherConvert($proposal, 2) . "!";

        # create Phase2 cryptography
        $crypt               = undef;
        $proposal            = undef;
        $crypt->{encryption} = $site_to_site->{ $vpn_config->{P2ENCRYPT} }
          if defined $site_to_site->{ $vpn_config->{P2ENCRYPT} };
        $crypt->{authentication} = $site_to_site->{ $vpn_config->{P2AUTHEN} }
          if defined $site_to_site->{ $vpn_config->{P2AUTHEN} };
        $crypt->{dhgroup} = $site_to_site->{ $vpn_config->{P2DHGROUP} }
          if defined $site_to_site->{ $vpn_config->{P2DHGROUP} };
        $crypt->{function} = $site_to_site->{ $vpn_config->{P2PRF} }
          if defined $site_to_site->{ $vpn_config->{P2PRF} };

        push @{ $proposal->{proposal} }, $crypt;
        $site_to_site_translate->{ $site_to_site->{ $vpn_config->{P2PROTO} } } =
          &getVpnIPSecCipherConvert($proposal, 2) . "!";

        # create file conn
        $error = &createVPNIPSecConn($site_to_site->{ $vpn_config->{NAME} }, $site_to_site_translate);
    }

    if ($error && !$error_ref->{code}) {
        my $error_msg = "Can't create VPN IPSec Conn in VPN $site_to_site->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 2;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    if (!$error) {
        # create file key
        $error = &createVPNIPSecKey($site_to_site);
    }
    if ($error && !$error_ref->{code}) {
        my $error_msg = "Can't create VPN IPSec Secret in VPN $site_to_site->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 3;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    if (!$error) {
        require Relianoid::VPN::SiteToSite::Action;

        # reload conf
        $error = &runVpnSiteToSiteReload();
    }
    if ($error && !$error_ref->{code}) {
        my $error_msg = "Can't Reload VPN $site_to_site->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 4;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    if ($error_ref->{code} > 0) {
        &delVPNConf($site_to_site->{ $vpn_config->{NAME} });
    }
    if ($error_ref->{code} > 1) {
        &delVPNIPSecConn($site_to_site->{ $vpn_config->{NAME} });
    }
    if ($error_ref->{code} > 2) {
        &delVPNIPSecKey($site_to_site->{ $vpn_config->{NAME} });
    }

    return $error_ref;
}

=pod

=head1 delVpnSiteToSite

Remove Site-to-Site VPN conf,conn and key files.

Parameters:

	vpn_name - Site-to-Site VPN name

Returns: integer - error code

0  - success
!0 - error

=cut

sub delVpnSiteToSite ($vpn_name) {
    my $rc = 0;

    require Relianoid::VPN::SiteToSite::Core;
    my $error = &getVpnSiteToSiteExists($vpn_name);
    if ($error) {
        &log_warn("Site-to-Site VPN $vpn_name doesn't exist.", "VPN");
        return 1;
    }

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    my $status = &getVpnSiteToSiteStatus($vpn_name);
    if ($status eq $vpn_config->{STATUS_UP}) {
        &log_warn("Site-to-Site VPN $vpn_name is running.", "VPN");
        return 2;
    }

    # stop running processes
    elsif ($status ne $vpn_config->{STATUS_DOWN}) {
        require Relianoid::VPN::SiteToSite::Action;
        $error = &runVpnSiteToSiteStop($vpn_name);
        if ($error) {
            &log_error("Site-to-Site VPN $vpn_name can not be stopped.", "VPN");
            return 2;
        }
    }

    require Relianoid::VPN::IPSec::Config;
    require Relianoid::VPN::Config;
    $error = &delVPNIPSecKey($vpn_name);
    $error += &delVPNIPSecConn($vpn_name);
    $error += &delVPNConf($vpn_name);
    if ($error) {
        &log_error("Error deleting Site-to-Site VPN $vpn_name.", "VPN");
        $rc = 3;
    }

    require Relianoid::RRD;
    &delGraph($vpn_name, "vpn");

    require Relianoid::VPN::SiteToSite::Action;
    $error = &runVpnSiteToSiteReload();
    if ($error) {
        &log_error("Error Reloading Site-to-Site VPN $vpn_name.", "VPN");
        $rc = 4;
    }
    return $rc;
}

=pod

=head1 setVpnSiteToSiteParams

Set Site-to-Site VPN conf,conn and key files.

Parameters:

	vpn_name - Site-to-Site VPN name
	params_ref - Hash ref of params to set.

Returns: hash reference

error_ref - error object. A hashref that maps error code and description

    code - Integer. Error code. 0 on success.
    desc - String. Description of the error.
    err  - String. Object causing the error.

=cut

sub setVpnSiteToSiteParams ($vpn_name, $params_ref) {
    my $error_ref = { code => 0 };

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    require Relianoid::VPN::SiteToSite::Core;
    my $error = &getVpnSiteToSiteExists($vpn_name);
    if ($error) {
        &log_warn("Site-to-Site VPN $vpn_name doesn't exist.", "VPN");
        $error_ref->{desc} = "Site-to-Site VPN $vpn_name doesn't exist.";
        $error_ref->{err}  = $vpn_config->{NAME};
        $error_ref->{code} = 1;
        return $error_ref;
    }

    my $vpn_status = &getVpnSiteToSiteStatus($vpn_name);
    my $vpn_ref    = &getVpnObject($vpn_name);

    # Modify key
    my $key_ref;
    $key_ref->{ $vpn_config->{LOCAL} } = $params_ref->{ $vpn_config->{LOCAL} }
      if (defined $params_ref->{ $vpn_config->{LOCAL} });
    $key_ref->{ $vpn_config->{REMOTE} } = $params_ref->{ $vpn_config->{REMOTE} }
      if (defined $params_ref->{ $vpn_config->{REMOTE} });
    $key_ref->{ $vpn_config->{PASS} } = $params_ref->{ $vpn_config->{PASS} }
      if (defined $params_ref->{ $vpn_config->{PASS} });

    if ($key_ref) {
        require Relianoid::VPN::IPSec::Config;
        my $error = &setVPNIPSecKey($vpn_name, $key_ref);

        if ($error) {
            $error_ref->{desc} = "Error modifying IPSec Key File.";
            $error_ref->{err}  = "IPSec Key file";
            $error_ref->{code} = 2;
            &log_error("Error modifying IPSec Key File on vpn $vpn_name.", "VPN");
            return $error_ref;
        }
    }

    # Modify conn

    my $site_to_site_translate;
    my $param_translate;
    require Relianoid::VPN::IPSec::Core;
    for my $param (keys %{$params_ref}) {
        $param_translate = &getVpnIPSecParamName($param, "ipsec");
        if ($param_translate) {
            $site_to_site_translate->{$param_translate} = $params_ref->{$param};
        }
    }
    if (   defined $params_ref->{ $vpn_config->{P1ENCRYPT} }
        or defined $params_ref->{ $vpn_config->{P1AUTHEN} }
        or defined $params_ref->{ $vpn_config->{P1DHGROUP} })
    {
        my $proposal;
        my $crypt;
        $crypt->{encryption} =
          defined $params_ref->{ $vpn_config->{P1ENCRYPT} }
          ? $params_ref->{ $vpn_config->{P1ENCRYPT} }
          : $vpn_ref->{ $vpn_config->{P1ENCRYPT} };
        $crypt->{authentication} =
          defined $params_ref->{ $vpn_config->{P1AUTHEN} }
          ? $params_ref->{ $vpn_config->{P1AUTHEN} }
          : $vpn_ref->{ $vpn_config->{P1AUTHEN} };
        $crypt->{dhgroup} =
          defined $params_ref->{ $vpn_config->{P1DHGROUP} }
          ? $params_ref->{ $vpn_config->{P1DHGROUP} }
          : $vpn_ref->{ $vpn_config->{P1DHGROUP} };
        push @{ $proposal->{proposal} }, $crypt;

        require Relianoid::VPN::IPSec::Config;
        $site_to_site_translate->{ike} = &getVpnIPSecCipherConvert($proposal, 2) . "!";
    }
    if (   defined $params_ref->{ $vpn_config->{P2ENCRYPT} }
        or defined $params_ref->{ $vpn_config->{P2AUTHEN} }
        or defined $params_ref->{ $vpn_config->{P2DHGROUP} }
        or defined $params_ref->{ $vpn_config->{P2PRF} })
    {
        my $proposal;
        my $crypt;
        $crypt->{encryption} =
          defined $params_ref->{ $vpn_config->{P2ENCRYPT} }
          ? $params_ref->{ $vpn_config->{P2ENCRYPT} }
          : $vpn_ref->{ $vpn_config->{P2ENCRYPT} };
        $crypt->{authentication} =
          defined $params_ref->{ $vpn_config->{P2AUTHEN} }
          ? $params_ref->{ $vpn_config->{P2AUTHEN} }
          : $vpn_ref->{ $vpn_config->{P2AUTHEN} };
        $crypt->{dhgroup} =
          defined $params_ref->{ $vpn_config->{P2DHGROUP} }
          ? $params_ref->{ $vpn_config->{P2DHGROUP} }
          : $vpn_ref->{ $vpn_config->{P2DHGROUP} };
        $crypt->{function} =
          defined $params_ref->{ $vpn_config->{P2PRF} }
          ? $params_ref->{ $vpn_config->{P2PRF} }
          : $vpn_ref->{ $vpn_config->{P2PRF} };
        push @{ $proposal->{proposal} }, $crypt;

        require Relianoid::VPN::IPSec::Config;
        $site_to_site_translate->{ $vpn_ref->{ $vpn_config->{P2PROTO} } } =
          &getVpnIPSecCipherConvert($proposal, 2) . "!";
    }

    if ($site_to_site_translate) {
        require Relianoid::VPN::IPSec::Config;
        $error = &setVPNIPSecConn($vpn_name, $site_to_site_translate);
        if ($error) {
            $error_ref->{desc} = "Error modifying IPSec connection File.";
            $error_ref->{err}  = "IPSec Connection file";
            $error_ref->{code} = 3;
            &log_error("Error modifying IPSec connection File on vpn $vpn_name.", "VPN");
            return $error_ref;
        }
    }

    # Modify conf
    require Relianoid::VPN::Config;
    $error = &setVPNConfObject($vpn_name, $params_ref);
    if ($error) {
        $error_ref->{desc} = "Error modifying Configuration File.";
        $error_ref->{err}  = "VPN Configuration file";
        $error_ref->{code} = 4;
        &log_error("Error modifying Configuration File on vpn $vpn_name.", "VPN");
        return $error_ref;
    }

    require Relianoid::VPN::SiteToSite::Action;
    $error = &runVpnSiteToSiteReload();
    if ($error) {
        $error_ref->{desc} = "Error Reloading Site-to-Site VPN.";
        $error_ref->{err}  = "IPSec Reload";
        $error_ref->{code} = 5;
        &log_error("Error Reloading Site-to-Site VPN $vpn_name.", "VPN");
        return $error_ref;
    }

    &setVPNRestartStatus($vpn_name, "true")
      if ($vpn_status eq $vpn_config->{STATUS_UP});

    return $error_ref;
}

=pod

=head1 createVpnSiteToSiteRoute

Create a route based on VPN Site-to-Site.

Parameters:

	vpn_name - String : vpn name

Returns: integer - error code

0  - success
!0 - error

=cut

sub createVpnSiteToSiteRoute ($vpn_name) {
    my $rc = 0;

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();
    my $vpn_ref    = &getVpnObject($vpn_name);

    require Relianoid::Net::Route;

    if (!&getRoutingTableExists("table_$vpn_name")) {
        &writeRoutes($vpn_name);
    }

    my $rule = {
        from  => $vpn_ref->{ $vpn_config->{LOCALNET} },
        to    => $vpn_ref->{ $vpn_config->{REMOTENET} },
        table => "table_$vpn_name",
        type  => 'vpn',
    };

    if (!&isRule($rule)) {
        &applyRule('add', $rule);
    }

    require Relianoid::Net::Interface;

    my $ip_bin       = &getGlobalConfiguration('ip_bin');
    my $route_params = &getGlobalConfiguration('routeparams');

    my $route_cmd       = "$ip_bin route add ";
    my $dev             = &getInterfaceByIp($vpn_ref->{ $vpn_config->{LOCAL} });
    my $route_cmd_param = $vpn_ref->{ $vpn_config->{REMOTENET} };
    $route_cmd_param .= " via " . $vpn_ref->{ $vpn_config->{REMOTE} };
    $route_cmd_param .= " dev " . $dev;
    $route_cmd_param .= " table table_$vpn_name ";

    if (!&isRoute($route_cmd_param)) {
        &logAndRunCheck($route_cmd . $route_cmd_param . $route_params);
    }

    return $rc;
}

=pod

=head1 delVpnSiteToSiteRoute

Remove a route based on VPN Site-to-Site.

Parameters:

	vpn_name - String : vpn name

Returns: integer - error code

0  - success
!0 - error

=cut

sub delVpnSiteToSiteRoute ($vpn_name) {
    my $rc = 0;

    require Relianoid::Net::Route;

    if (&getRoutingTableExists("table_$vpn_name")) {
        my $system_route = &listRoutingTableSys("table_$vpn_name");

        my $ip_bin    = &getGlobalConfiguration('ip_bin');
        my $route_cmd = "$ip_bin route del ";

        if (@{$system_route} > 0) {
            &logAndRunCheck($route_cmd . @{$system_route}[0]->{raw});
        }

        my $rule_filter = { table => "table_$vpn_name" };

        my $system_rule = &listRoutingRulesSys($rule_filter);

        if (@{$system_rule} > 0) {
            &applyRule('del', @{$system_rule}[0]);
        }

        &deleteRoutesTable($vpn_name);
    }

    return $rc;
}

1;
