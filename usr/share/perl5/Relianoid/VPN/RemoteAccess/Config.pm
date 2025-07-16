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

Relianoid::VPN::RemoteAccess::Config

=cut

=pod

=head1 createVpnRemoteAccess

	Create Remote Access VPN conf,conn and key files for IPSec and conf, ppp option for L2TP

Parameters: hash reference

    remote_access - Remote Access VPN object

    name -
    local -
    localip -
    localmask -
    localtunip -
    localtunmask -
    remotetunrange -
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

error_ref - error object.

A hashref that maps error code and description

    code - Integer. Error code. 0 on success.
    desc - String. Description of the error.
    err  - String. Object causing the error.

=cut

sub createVpnRemoteAccess ($remote_access) {
    my $error_ref = { code => 0 };

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    # validate object
    require Relianoid::VPN::RemoteAccess::Validate;
    my $error = &checkVpnRemoteAccessObject($remote_access);
    if ($error) {
        my $error_msg = "VPN Remote Access Object not valid.";
        &log_warn($error_msg, "VPN");
        $error_ref->{code} = -1;
        $error_ref->{desc} = $error_msg;
        return $error_ref;
    }

    # convert ip/mask to net
    my $local_net =
      NetAddr::IP->new($remote_access->{ $vpn_config->{LOCALIP} }, $remote_access->{ $vpn_config->{LOCALMASK} })->network();
    $remote_access->{ $vpn_config->{LOCALNET} } = $local_net;

    require Relianoid::VPN::Config;
    $error = &createVPNConf($remote_access);
    if ($error) {
        my $error_msg = "Can't create VPN Configuration in VPN $remote_access->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 1;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    require Relianoid::VPN::IPSec::Config;
    if (!$error) {
        # translate params
        my $remote_access_translate;
        my $param_translate;
        require Relianoid::VPN::IPSec::Core;

        for my $param (keys %{$remote_access}) {
            $param_translate = &getVpnIPSecParamName($param, "ipsec");
            if ($param_translate) {
                $remote_access_translate->{$param_translate} = $remote_access->{$param};
            }
        }

        # create auth
        $remote_access_translate->{leftauth}  = $remote_access->{ $vpn_config->{AUTH} };
        $remote_access_translate->{rightauth} = $remote_access->{ $vpn_config->{AUTH} };

        require Relianoid::VPN::IPSec::Config;

        # create Phase1 cryptography
        my $crypt;
        my $proposal;
        $crypt->{encryption} = $remote_access->{ $vpn_config->{P1ENCRYPT} }
          if defined $remote_access->{ $vpn_config->{P1ENCRYPT} };
        $crypt->{authentication} = $remote_access->{ $vpn_config->{P1AUTHEN} }
          if defined $remote_access->{ $vpn_config->{P1AUTHEN} };
        $crypt->{dhgroup} = $remote_access->{ $vpn_config->{P1DHGROUP} }
          if defined $remote_access->{ $vpn_config->{P1DHGROUP} };

        push @{ $proposal->{proposal} }, $crypt;
        $remote_access_translate->{ike} = &getVpnIPSecCipherConvert($proposal, 2) . "!";

        # create Phase2 cryptography
        $crypt               = undef;
        $proposal            = undef;
        $crypt->{encryption} = $remote_access->{ $vpn_config->{P2ENCRYPT} }
          if defined $remote_access->{ $vpn_config->{P2ENCRYPT} };
        $crypt->{authentication} = $remote_access->{ $vpn_config->{P2AUTHEN} }
          if defined $remote_access->{ $vpn_config->{P2AUTHEN} };
        $crypt->{dhgroup} = $remote_access->{ $vpn_config->{P2DHGROUP} }
          if defined $remote_access->{ $vpn_config->{P2DHGROUP} };
        $crypt->{function} = $remote_access->{ $vpn_config->{P2PRF} }
          if defined $remote_access->{ $vpn_config->{P2PRF} };

        push @{ $proposal->{proposal} }, $crypt;
        $remote_access_translate->{ $remote_access->{ $vpn_config->{P2PROTO} } } =
          &getVpnIPSecCipherConvert($proposal, 2) . "!";

        # create encrypt l2tp traffic
        $remote_access_translate->{leftprotoport}  = "17/1701";
        $remote_access_translate->{rightprotoport} = "17/%any";
        $remote_access_translate->{right}          = "%any";
        $remote_access_translate->{type}           = "transport";

        # override leftsubnet
        $remote_access_translate->{leftsubnet} =
          $remote_access->{ $vpn_config->{LOCAL} } . "/32";

        # create file conn
        $error = &createVPNIPSecConn($remote_access->{ $vpn_config->{NAME} }, $remote_access_translate);
    }

    if ($error && !$error_ref->{code}) {
        my $error_msg = "Can't create VPN IPSec Conn in VPN $remote_access->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 2;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    if (!$error) {
        # create file key
        $error = &createVPNIPSecKey($remote_access);
    }
    if ($error && !$error_ref->{code}) {
        my $error_msg = "Can't create VPN IPSec Secret in VPN $remote_access->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 3;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    if (!$error) {
        # create l2tp config
        require Relianoid::VPN::L2TP::Core;
        my $remote_access_translate = &getVpnL2TPParams($remote_access, "l2tp");
        require Relianoid::VPN::L2TP::Config;
        $error = &createVPNL2TPConf($remote_access->{ $vpn_config->{NAME} }, $remote_access_translate);
    }

    if ($error && !$error_ref->{code}) {
        my $error_msg = "Can't create VPN Remote Access L2TP Configuration $remote_access->{ $vpn_config->{NAME} }.";
        $error_ref->{code} = 4;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    if ($error_ref->{code} > 1) {
        &delVPNConf($remote_access->{ $vpn_config->{NAME} });
    }
    if ($error_ref->{code} > 2) {
        &delVPNIPSecConn($remote_access->{ $vpn_config->{NAME} });
    }
    if ($error_ref->{code} > 3) {
        &delVPNIPSecKey($remote_access->{ $vpn_config->{NAME} });
    }

    return $error_ref;
}

=pod

=head1 delVpnRemoteAccess

	Remove Remote Access VPN conf,conn and key files for IPSec and conf, ppp option for L2TP

Parameters:
	vpn_name - Remote Access VPN name

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub delVpnRemoteAccess ($vpn_name) {
    my $rc = 0;

    require Relianoid::VPN::RemoteAccess::Core;
    my $error = &getVpnRemoteAccessExists($vpn_name);
    if ($error) {
        &log_warn("Remote Access VPN $vpn_name doesn't exist.", "VPN");
        return 1;
    }

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    my $status = &getVpnRemoteAccessStatus($vpn_name);
    if ($status eq $vpn_config->{STATUS_UP}) {
        &log_warn("Remote Access VPN $vpn_name is running.", "VPN");
        return 2;
    }

    # stop running processes
    elsif ($status ne $vpn_config->{STATUS_DOWN}) {
        require Relianoid::VPN::RemoteAccess::Action;
        $error = &runVpnRemoteAccessStop($vpn_name);
        if ($error) {
            &log_warn("Remote Access VPN $vpn_name can not be stopped.", "VPN");
            return 2;
        }
    }

    require Relianoid::VPN::IPSec::Config;
    $error = &delVPNIPSecKey($vpn_name);
    $error += &delVPNIPSecConn($vpn_name);

    require Relianoid::VPN::L2TP::Config;
    $error = &delVPNL2TPConf($vpn_name);
    $error = &delVPNL2TPPppFile($vpn_name);

    require Relianoid::VPN::Config;
    my $users = getVpnUsers($vpn_name);

    for my $user (@{$users}) {
        $error += &unsetVPNL2TPPppSecret($vpn_name, $user);
    }
    $error += &delVPNConf($vpn_name);
    if ($error) {
        &log_error("Error deleting Remote Access VPN $vpn_name.", "VPN");
        $rc = 3;
    }

    require Relianoid::RRD;
    &delGraph($vpn_name, "vpn");

    return $rc;
}

=pod

=head1 cleanVpnRemoteAccess

	Remove Remote Access VPN conf,conn and key files for IPSec and conf, ppp option for L2TP without checks.

Parameters:
	vpn_name - Remote Access VPN name

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub cleanVpnRemoteAccess ($vpn_name) {
    my $rc = 0;

    require Relianoid::VPN::IPSec::Config;
    &delVPNIPSecKey($vpn_name);
    &delVPNIPSecConn($vpn_name);

    require Relianoid::VPN::L2TP::Config;
    &delVPNL2TPConf($vpn_name);
    &delVPNL2TPPppFile($vpn_name);

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    require Relianoid::VPN::L2TP::Core;
    my $users = getVpnL2TPPppUsers($vpn_name);
    for my $user (@{ $users->{$vpn_name} }) {
        &unsetVPNL2TPPppSecret($vpn_name, $user->{ $vpn_config->{VPN_USER} });
    }

    require Relianoid::VPN::Config;
    &delVPNConf($vpn_name);

    require Relianoid::RRD;
    &delGraph($vpn_name, "vpn");

    require Relianoid::VPN::RemoteAccess::Action;
    my $error = &runVpnRemoteAccessReload();
    if ($error) {
        &log_error("Error Reloading Remote Access VPN $vpn_name.", "VPN");
        $rc = 1;
    }
    return $rc;
}

=pod

=head1 setVpnRemoteAccessParams

Set Remote Access VPN conf, conn, key files for IPSec, and conf, ppp for L2TP.

Parameters:

	vpn_name - Remote Access VPN name
	params_ref - Hash ref of params to set.

Returns: hash reference

error_ref - error object. A hashref that maps error code and description

    code - Integer. Error code. 0 on success.
    desc - String. Description of the error.
    err  - String. Object causing the error.

=cut

sub setVpnRemoteAccessParams ($vpn_name, $params_ref) {
    my $error_ref = { code => 0 };

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    require Relianoid::VPN::RemoteAccess::Core;
    my $error = &getVpnRemoteAccessExists($vpn_name);
    if ($error) {
        &log_warn("Remote Access VPN $vpn_name doesn't exist.", "VPN");
        $error_ref->{desc} = "Remote Access VPN $vpn_name doesn't exist.";
        $error_ref->{err}  = $vpn_config->{NAME};
        $error_ref->{code} = 1;
        return $error_ref;
    }

    my $vpn_ref = &getVpnObject($vpn_name);

    # Modify key
    my $key_ref;
    $key_ref->{ $vpn_config->{LOCAL} } = $params_ref->{ $vpn_config->{LOCAL} }
      if (defined $params_ref->{ $vpn_config->{LOCAL} });
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

    my $remote_access_translate;
    my $param_translate;
    require Relianoid::VPN::IPSec::Core;
    for my $param (keys %{$params_ref}) {
        $param_translate = &getVpnIPSecParamName($param, "ipsec");
        if ($param_translate) {
            $remote_access_translate->{$param_translate} = $params_ref->{$param};
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
        $remote_access_translate->{ike} = &getVpnIPSecCipherConvert($proposal, 2) . "!";
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
        $remote_access_translate->{ $vpn_ref->{ $vpn_config->{P2PROTO} } } =
          &getVpnIPSecCipherConvert($proposal, 2) . "!";
    }

    if ($remote_access_translate) {
        require Relianoid::VPN::IPSec::Config;
        $error = &setVPNIPSecConn($vpn_name, $remote_access_translate);
        if ($error) {
            $error_ref->{desc} = "Error modifying IPSec connection File.";
            $error_ref->{err}  = "IPSec Connection file";
            $error_ref->{code} = 3;
            &log_error("Error modifying IPSec connection File on vpn $vpn_name.", "VPN");
            return $error_ref;
        }
    }

    # Modify L2TP
    if (   defined $params_ref->{ $vpn_config->{LOCAL} }
        or defined $params_ref->{ $vpn_config->{REMOTETUNRANGE} }
        or defined $params_ref->{ $vpn_config->{LOCALTUNIP} })
    {
        require Relianoid::VPN::L2TP::Config;
        my $l2tp_ref_translate = &getVpnL2TPParams($params_ref, "l2tp");
        $error = &setVPNL2TPConf($vpn_name, $l2tp_ref_translate);
        if ($error) {
            $error_ref->{desc} = "Error modifying L2TP Configuration.";
            $error_ref->{err}  = "L2TP Configuration";
            $error_ref->{code} = 4;
            &log_error("Error modifying L2TP Configuration on vpn $vpn_name.", "VPN");
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

    &setVPNRestartStatus($vpn_name, "true")
      if (&getVpnRemoteAccessStatus($vpn_name) eq $vpn_config->{STATUS_UP});

    return $error_ref;
}

=pod

=head1 createVpnRemoteAccessRoute

	Create a route based on VPN Remote Access.

Parameters:
	vpn_name - String : vpn name

Returns:
	Scalar - Integer : 0 on success, other on error.

=cut

sub createVpnRemoteAccessRoute ($vpn_name) {
    my $rc = 0;

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    my $vpn_ref = &getVpnObject($vpn_name);

    require Relianoid::Net::Route;

    if (!&getRoutingTableExists("table_$vpn_name")) {
        &writeRoutes($vpn_name);
    }

    my $local_net =
      NetAddr::IP->new($vpn_ref->{ $vpn_config->{LOCALIP} }, $vpn_ref->{ $vpn_config->{LOCALMASK} })->network();
    my $remote_net =
      NetAddr::IP->new($vpn_ref->{ $vpn_config->{LOCALTUNIP} }, $vpn_ref->{ $vpn_config->{LOCALTUNMASK} })->network();

    my $rule = {
        from  => $local_net,
        to    => $remote_net,
        table => "table_$vpn_name",
        type  => 'vpn',
    };

    if (!&isRule($rule)) {
        &applyRule('add', $rule);
    }

    my $ip_bin = &getGlobalConfiguration('ip_bin');
    require Relianoid::Net::Interface;
    my $route_params = &getGlobalConfiguration('routeparams');

    my $route_cmd       = "$ip_bin route add ";
    my $route_cmd_param = $remote_net;
    $route_cmd_param .= " via " . $vpn_ref->{ $vpn_config->{LOCALIP} };
    $route_cmd_param .= " table table_$vpn_name ";

    &logAndRunCheck($route_cmd . $route_cmd_param . $route_params)
      if !&isRoute($route_cmd_param);

    return $rc;
}

=pod

=head1 delVpnRemoteAccessRoute

	Remove a route based on VPN Remote Access.

Parameters:
	vpn_name - String : vpn name

Returns:
	Scalar - Integer : 0 on success, other on error.

=cut

sub delVpnRemoteAccessRoute ($vpn_name) {
    my $rc = 0;

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    my $vpn_ref = &getVpnObject($vpn_name);

    require Relianoid::Net::Route;

    if (&getRoutingTableExists("table_$vpn_name")) {
        require Relianoid::Net::Interface;

        my $local_net =
          NetAddr::IP->new($vpn_ref->{ $vpn_config->{LOCALIP} }, $vpn_ref->{ $vpn_config->{LOCALMASK} })->network();
        my $remote_net =
          NetAddr::IP->new($vpn_ref->{ $vpn_config->{LOCALTUNIP} }, $vpn_ref->{ $vpn_config->{LOCALTUNMASK} })->network();

        my $ip_bin          = &getGlobalConfiguration('ip_bin');
        my $route_cmd       = "$ip_bin route del ";
        my $route_cmd_param = $remote_net;
        $route_cmd_param .= " via " . $vpn_ref->{ $vpn_config->{LOCALIP} };
        $route_cmd_param .= " table table_$vpn_name";

        &logAndRunCheck($route_cmd . $route_cmd_param)
          if &isRoute($route_cmd_param);

        my $rule = {
            from  => $local_net,
            to    => $remote_net,
            table => "table_$vpn_name",
            type  => 'vpn',
        };

        if (&isRule($rule)) {
            &applyRule('del', $rule);
        }

        &deleteRoutesTable($vpn_name);
    }

    return $rc;
}

=pod

=head1 createVpnRemoteAccessUser

	Create Remote Access VPN user for a VPN

Parameters:
	vpn_name - Remote Access VPN name
	user_ref - VPN Credentials object

Returns:
	error_ref - error object. code = 0, on success

=cut

sub createVpnRemoteAccessUser ($vpn_name, $user_ref) {
    my $error_ref = { code => 0 };

    require Relianoid::VPN::Core;
    require Relianoid::VPN::Config;
    require Relianoid::VPN::L2TP::Config;

    my $vpn_config = &getVpnModuleConfig();
    my $user_name  = $user_ref->{ $vpn_config->{VPN_USER} };
    my $password   = $user_ref->{ $vpn_config->{VPN_PASSWORD} };

    if (my $error = &setVPNL2TPPppSecret($vpn_name, $user_name, $password)) {
        my $error_msg = "Can't create L2TP User Configuration for VPN $vpn_name.";
        &log_warn($error_msg, "VPN");

        %$error_ref = (
            code => 2,
            desc => $error_msg,
        );

        return $error_ref;
    }

    if (my $error = &createVPNUser($vpn_name, $user_ref)) {
        &unsetVPNL2TPPppSecret($vpn_name, $user_ref->{ $vpn_config->{VPN_USER} });

        my $error_msg = "Can't create VPN User Configuration for VPN $vpn_name.";
        &log_warn($error_msg, "VPN");

        %$error_ref = (
            code => 1,
            desc => $error_msg,
        );
    }

    return $error_ref;
}

=pod

=head1 deleteVpnRemoteAccessUser

	Delete Remote Access VPN user for a VPN

Parameters:
	vpn_name - Remote Access VPN name
	user_name - VPN User name

Returns:
	error_ref - error object. code = 0, on success

=cut

sub deleteVpnRemoteAccessUser ($vpn_name, $user_name) {
    my $error_ref = { code => 0 };

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    require Relianoid::VPN::L2TP::Core;
    my $users_ppp = getVpnL2TPPppUsers($vpn_name);
    require Relianoid::VPN::L2TP::Config;
    my $error = &unsetVPNL2TPPppSecret($vpn_name, $user_name);
    if ($error) {
        my $error_msg = "Can't delete L2TP User Configuration for VPN $vpn_name.";
        $error_ref->{code} = 2;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
        return $error_ref;
    }

    require Relianoid::VPN::Config;
    $error = &deleteVPNUser($vpn_name, $user_name);
    if ($error) {
        &setVPNL2TPPppSecret(
            $vpn_name,
            $users_ppp->{$vpn_name}{ $vpn_config->{VPN_USER} },
            $users_ppp->{$vpn_name}{ $vpn_config->{VPN_PASSWORD} }
        );
        my $error_msg = "Can't delete VPN User Configuration for VPN $vpn_name.";
        $error_ref->{code} = 1;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }
    return $error_ref;
}

=pod

=head1 setVpnRemoteAccessUser

	Modify Remote Access VPN user for a VPN

Parameters:
	vpn_name - Remote Access VPN name
	user_name - VPN User Name
	user_ref - VPN Credentials object

Returns:
	error_ref - error object. code = 0, on success

=cut

sub setVpnRemoteAccessUser ($vpn_name, $user_name, $user_ref) {
    my $error_ref = { code => 0 };

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    require Relianoid::VPN::L2TP::Config;
    my $error = &setVPNL2TPPppSecret($vpn_name, $user_name, $user_ref->{ $vpn_config->{VPN_PASSWORD} });
    if ($error) {
        my $error_msg = "Can't create L2TP User Configuration for VPN $vpn_name.";
        $error_ref->{code} = 2;
        $error_ref->{desc} = $error_msg;
        &log_warn($error_msg, "VPN");
    }

    return $error_ref;
}

1;
