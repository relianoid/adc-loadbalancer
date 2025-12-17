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

Relianoid::VPN::Tunnel::Config

=cut

use strict;
use warnings;
use feature qw(signatures);

=pod

=head1 createVpnTunnel

Create Tunnel VPN conf,conn and key files and tunnel interface

Parameters: hash reference

tunnel - Tunnel VPN object. A hashref that maps an Tunnel VPN object

    name -
    local -
    localip -
    localmask -
    localtunip -
    localtunmask -
    remote -
    remoteip -
    remotemask -
    remotetunip -
    remotemask -
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

sub createVpnTunnel ($tunnel) {
    my $error_ref = { code => 0 };

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    # validate object
    require Relianoid::VPN::Tunnel::Validate;
    my $error = &checkVpnTunnelObject($tunnel);

    if ($error) {
        my $error_msg = "VPN Object not valid.";
        &log_warn($error_msg, "VPN");
        $error_ref->{code} = -1;
        $error_ref->{desc} = $error_msg;

        return $error_ref;
    }

    # convert ip/mask to net
    my $local_net =
      NetAddr::IP->new($tunnel->{ $vpn_config->{LOCALIP} }, $tunnel->{ $vpn_config->{LOCALMASK} })->network();

    $tunnel->{ $vpn_config->{LOCALNET} } = $local_net;

    my $remote_net =
      NetAddr::IP->new($tunnel->{ $vpn_config->{REMOTEIP} }, $tunnel->{ $vpn_config->{REMOTEMASK} })->network();

    $tunnel->{ $vpn_config->{REMOTENET} } = $remote_net;

    require Relianoid::VPN::Config;

    $error = &createVPNConf($tunnel);

    if ($error) {
        my $error_msg = "Can't create VPN Configuration in VPN $tunnel->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 1;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    require Relianoid::VPN::IPSec::Config;

    if (!$error) {
        # translate params
        my $tunnel_translate;
        my $param_translate;
        require Relianoid::VPN::IPSec::Core;

        for my $param (keys %{$tunnel}) {
            $param_translate = &getVpnIPSecParamName($param, "ipsec");
            if ($param_translate) {
                $tunnel_translate->{$param_translate} = $tunnel->{$param};
            }
        }

        # create auth
        $tunnel_translate->{leftauth}  = $tunnel->{ $vpn_config->{AUTH} };
        $tunnel_translate->{rightauth} = $tunnel->{ $vpn_config->{AUTH} };

        require Relianoid::VPN::IPSec::Config;

        # create Phase1 cryptography
        my $crypt;
        my $proposal;

        $crypt->{encryption} = $tunnel->{ $vpn_config->{P1ENCRYPT} }
          if defined $tunnel->{ $vpn_config->{P1ENCRYPT} };

        $crypt->{authentication} = $tunnel->{ $vpn_config->{P1AUTHEN} }
          if defined $tunnel->{ $vpn_config->{P1AUTHEN} };

        $crypt->{dhgroup} = $tunnel->{ $vpn_config->{P1DHGROUP} }
          if defined $tunnel->{ $vpn_config->{P1DHGROUP} };

        push @{ $proposal->{proposal} }, $crypt;
        $tunnel_translate->{ike} = &getVpnIPSecCipherConvert($proposal, 2) . "!";

        # create Phase2 cryptography
        $crypt    = undef;
        $proposal = undef;

        $crypt->{encryption} = $tunnel->{ $vpn_config->{P2ENCRYPT} }
          if defined $tunnel->{ $vpn_config->{P2ENCRYPT} };

        $crypt->{authentication} = $tunnel->{ $vpn_config->{P2AUTHEN} }
          if defined $tunnel->{ $vpn_config->{P2AUTHEN} };

        $crypt->{dhgroup} = $tunnel->{ $vpn_config->{P2DHGROUP} }
          if defined $tunnel->{ $vpn_config->{P2DHGROUP} };

        $crypt->{function} = $tunnel->{ $vpn_config->{P2PRF} }
          if defined $tunnel->{ $vpn_config->{P2PRF} };

        push @{ $proposal->{proposal} }, $crypt;

        $tunnel_translate->{ $tunnel->{ $vpn_config->{P2PROTO} } } = &getVpnIPSecCipherConvert($proposal, 2) . "!";

        # create encrypt gre traffic
        $tunnel_translate->{leftprotoport}  = "gre";
        $tunnel_translate->{rightprotoport} = "gre";

        # create file conn
        $error = &createVPNIPSecConn($tunnel->{ $vpn_config->{NAME} }, $tunnel_translate);
    }

    if ($error && !$error_ref->{code}) {
        my $error_msg = "Can't create VPN IPSec Conn in VPN $tunnel->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 2;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    if (!$error) {
        # create file key
        $error = &createVPNIPSecKey($tunnel);
    }

    if ($error && !$error_ref->{code}) {
        my $error_msg = "Can't create VPN IPSec Secret in VPN $tunnel->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 3;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    if (!$error) {
        $error = &createVPNTunnelIf(
            $tunnel->{ $vpn_config->{NAME} },
            "gre",
            $tunnel->{ $vpn_config->{LOCALIP} },
            $tunnel->{ $vpn_config->{REMOTEIP} },
            $tunnel->{ $vpn_config->{LOCALTUNIP} },
            $tunnel->{ $vpn_config->{LOCALTUNMASK} }
        );
    }

    if ($error && !$error_ref->{code}) {
        my $error_msg = "Can't create VPN tunnel Interface $tunnel->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 4;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    if (!$error) {
        require Relianoid::VPN::Tunnel::Action;

        # reload conf
        $error = &runVpnTunnelReload();
    }

    if ($error && !$error_ref->{code}) {
        my $error_msg = "Can't Reload VPN $tunnel->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 5;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    if ($error_ref->{code} > 1) {
        &delVPNConf($tunnel->{ $vpn_config->{NAME} });
    }

    if ($error_ref->{code} > 2) {
        &delVPNIPSecConn($tunnel->{ $vpn_config->{NAME} });
    }

    if ($error_ref->{code} > 3) {
        &delVPNIPSecKey($tunnel->{ $vpn_config->{NAME} });
    }

    if ($error_ref->{code} > 4) {
        &delVPNTunnelIf($tunnel->{ $vpn_config->{NAME} }, "gre");
    }

    return $error_ref;
}

=pod

=head1 delVpnTunnel

Remove Tunnel VPN conf,conn and key files and Tunnel interface.

Parameters:

    vpn_name - string - Tunnel VPN name

Returns: integer - error code

0  - success
!0 - error

=cut

sub delVpnTunnel ($vpn_name) {
    my $rc = 0;

    require Relianoid::VPN::Tunnel::Core;

    my $error = &getVpnTunnelExists($vpn_name);
    if ($error) {
        &log_warn("Tunnel VPN $vpn_name doesn't exist.", "VPN");
        return 1;
    }

    require Relianoid::VPN::Core;

    my $vpn_config = &getVpnModuleConfig();
    my $status     = &getVpnTunnelStatus($vpn_name);

    if ($status eq $vpn_config->{STATUS_UP}) {
        &log_warn("Tunnel VPN $vpn_name is running.", "VPN");
        return 2;
    }
    elsif ($status ne $vpn_config->{STATUS_DOWN}) {
        require Relianoid::VPN::Tunnel::Action;

        if (my $error = &runVpnTunnelStop($vpn_name)) {
            &log_error("Tunnel VPN $vpn_name can not be stopped.", "VPN");
            return 2;
        }
    }

    require Relianoid::VPN::Config;

    if (my $error = &delVPNTunnelIf($vpn_name, "gre")) {
        &log_error("Error deleting Tunnel VPN Tunnel Interface $vpn_name.", "VPN");
        return 5;
    }

    require Relianoid::VPN::IPSec::Config;

    $error = &delVPNIPSecKey($vpn_name);
    $error += &delVPNIPSecConn($vpn_name);
    $error += &delVPNConf($vpn_name);

    if ($error) {
        &log_error("Error deleting Tunnel VPN $vpn_name.", "VPN");
        $rc = 3;
    }

    require Relianoid::RRD;
    &delGraph($vpn_name, "vpn");

    require Relianoid::VPN::Tunnel::Action;

    if (my $error = &runVpnTunnelReload()) {
        &log_error("Error Reloading Tunnel VPN $vpn_name.", "VPN");
        $rc = 4;
    }

    return $rc;
}

=pod

=head1 cleanVpnTunnel

Remove Tunnel VPN conf,conn and key files and Tunnel interface without checks.

Parameters:

    vpn_name - Tunnel VPN name

Returns: integer - error code

0  - success
!0 - error

=cut

sub cleanVpnTunnel ($vpn_name) {
    my $rc = 0;

    require Relianoid::Net::Interface;
    my $tunnel_ref = &getSystemInterface($vpn_name);
    if ($tunnel_ref) {
        require Relianoid::Net::Core;
        &delIf($tunnel_ref);
    }

    require Relianoid::VPN::IPSec::Config;
    &delVPNIPSecKey($vpn_name);
    &delVPNIPSecConn($vpn_name);
    require Relianoid::VPN::Config;
    &delVPNConf($vpn_name);

    require Relianoid::RRD;
    &delGraph($vpn_name, "vpn");

    require Relianoid::VPN::Tunnel::Action;
    my $error = &runVpnTunnelReload();
    if ($error) {
        &log_error("Error Reloading Tunnel VPN $vpn_name.", "VPN");
        $rc = 1;
    }
    return $rc;
}

=pod

=head1 setVpnTunnelParams

Set Tunnel VPN conf,conn and key files.

Parameters:

    vpn_name   - Tunnel VPN name
    params_ref - Hash ref of params to set.

Returns: hash reference

error_ref - error object. A hashref that maps error code and description

    code - Integer. Error code. 0 on success.
    desc - String. Description of the error.
    err  - String. Object causing the error.

=cut

sub setVpnTunnelParams ($vpn_name, $params_ref) {
    my $error_ref = { code => 0 };

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    require Relianoid::VPN::Tunnel::Core;
    my $error = &getVpnTunnelExists($vpn_name);
    if ($error) {
        &log_warn("Tunnel VPN $vpn_name doesn't exist.", "VPN");
        $error_ref->{desc} = "Tunnel VPN $vpn_name doesn't exist.";
        $error_ref->{err}  = $vpn_config->{NAME};
        $error_ref->{code} = 1;
        return $error_ref;
    }

    my $vpn_status = &getVpnTunnelStatus($vpn_name);
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

    my $local_net;
    my $remote_net;
    if (   defined $params_ref->{ $vpn_config->{LOCALIP} }
        or defined $params_ref->{ $vpn_config->{LOCALMASK} })
    {
        my $local_ip =
          defined $params_ref->{ $vpn_config->{LOCALIP} }
          ? $params_ref->{ $vpn_config->{LOCALIP} }
          : $vpn_ref->{ $vpn_config->{LOCALIP} };
        my $local_mask =
          defined $params_ref->{ $vpn_config->{LOCALMASK} }
          ? $params_ref->{ $vpn_config->{LOCALMASK} }
          : $vpn_ref->{ $vpn_config->{LOCALMASK} };
        $local_net = NetAddr::IP->new($local_ip, $local_mask)->network();
        $params_ref->{ $vpn_config->{LOCALNET} } = $local_net;
    }

    if (   defined $params_ref->{ $vpn_config->{REMOTEIP} }
        or defined $params_ref->{ $vpn_config->{REMOTEMASK} })
    {
        my $remote_ip =
          defined $params_ref->{ $vpn_config->{REMOTEIP} }
          ? $params_ref->{ $vpn_config->{REMOTEIP} }
          : $vpn_ref->{ $vpn_config->{REMOTEIP} };
        my $remote_mask =
          defined $params_ref->{ $vpn_config->{REMOTEMASK} }
          ? $params_ref->{ $vpn_config->{REMOTEMASK} }
          : $vpn_ref->{ $vpn_config->{REMOTEMASK} };
        $remote_net = NetAddr::IP->new($remote_ip, $remote_mask)->network();
        $params_ref->{ $vpn_config->{REMOTENET} } = $remote_net;
    }

    my $tunnel_translate;
    my $param_translate;

    require Relianoid::VPN::IPSec::Core;

    for my $param (keys %{$params_ref}) {
        $param_translate = &getVpnIPSecParamName($param, "ipsec");
        if ($param_translate) {
            $tunnel_translate->{$param_translate} = $params_ref->{$param};
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
        $tunnel_translate->{ike} = &getVpnIPSecCipherConvert($proposal, 2) . "!";
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

        $tunnel_translate->{ $vpn_ref->{ $vpn_config->{P2PROTO} } } =
          &getVpnIPSecCipherConvert($proposal, 2) . "!";
    }

    if ($tunnel_translate) {
        require Relianoid::VPN::IPSec::Config;
        $error = &setVPNIPSecConn($vpn_name, $tunnel_translate);

        if ($error) {
            $error_ref->{desc} = "Error modifying IPSec connection File.";
            $error_ref->{err}  = "IPSec Connection file";
            $error_ref->{code} = 3;
            &log_error("Error modifying IPSec connection File on vpn $vpn_name.", "VPN");
            return $error_ref;
        }
    }

    # ModifyTunnel
    if (   defined $params_ref->{ $vpn_config->{LOCALTUNIP} }
        or defined $params_ref->{ $vpn_config->{LOCALTUNMASK} })
    {
        my $tunnel_ref = &getInterfaceConfig($vpn_name);

        if (defined $params_ref->{ $vpn_config->{LOCALTUNIP} }) {
            $tunnel_ref->{addr} = $params_ref->{ $vpn_config->{LOCALTUNIP} };
        }

        if (defined $params_ref->{ $vpn_config->{LOCALTUNMASK} }) {
            $tunnel_ref->{mask} = $params_ref->{ $vpn_config->{LOCALTUNMASK} };
        }

        &setInterfaceConfig($tunnel_ref);
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

    require Relianoid::VPN::Tunnel::Action;
    $error = &runVpnTunnelReload();

    if ($error) {
        $error_ref->{desc} = "Error Reloading Tunnel VPN.";
        $error_ref->{err}  = "IPSec Reload";
        $error_ref->{code} = 5;
        &log_error("Error Reloading Tunnel VPN $vpn_name.", "VPN");
        return $error_ref;
    }

    &setVPNRestartStatus($vpn_name, "true")
      if ($vpn_status eq $vpn_config->{STATUS_UP});

    return $error_ref;
}

=pod

=head1 createVpnTunnelRoute

Create a route based on VPN Tunnel.

Parameters:

    vpn_name - string - vpn name

Returns: integer - error code

0  - success
!0 - error

=cut

sub createVpnTunnelRoute ($vpn_name) {
    my $rc = 0;

    require Relianoid::Net::Route;

    if (!&getRoutingTableExists("table_$vpn_name")) {
        &writeRoutes($vpn_name);
    }

    require Relianoid::VPN::Core;

    my $vpn_config = &getVpnModuleConfig();
    my $vpn_ref    = &getVpnObject($vpn_name);
    my $rule       = {
        from  => $vpn_ref->{ $vpn_config->{LOCALNET} },
        to    => $vpn_ref->{ $vpn_config->{REMOTENET} },
        table => "table_$vpn_name",
        type  => 'vpn',
    };

    if (!&isRule($rule)) {
        &applyRule('add', $rule);
    }

    my $route_cmd_param = $vpn_ref->{ $vpn_config->{REMOTENET} };
    $route_cmd_param .= " via " . $vpn_ref->{ $vpn_config->{REMOTETUNIP} };
    $route_cmd_param .= " dev " . $vpn_name;
    $route_cmd_param .= " table table_$vpn_name ";

    if (!&isRoute($route_cmd_param)) {
        my $ip_bin       = &getGlobalConfiguration('ip_bin');
        my $route_params = &getGlobalConfiguration('routeparams');
        my $route_cmd    = "$ip_bin route add ";

        &logAndRunCheck($route_cmd . $route_cmd_param . $route_params);
    }

    return $rc;
}

=pod

=head1 delVpnTunnelRoute

	Remove a route based on VPN Tunnel.

Parameters:
	vpn_name - String : vpn name

Returns:
	Scalar - Integer : 0 on success, other on error.

=cut

sub delVpnTunnelRoute ($vpn_name) {
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
    }

    return $rc;
}

1;
