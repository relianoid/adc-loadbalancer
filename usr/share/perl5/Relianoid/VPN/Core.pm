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

use Relianoid::Core;

=pod

=head1 Module

Relianoid::VPN::Core

=cut

=pod

=head1 getVpnModuleConfig

Get the Configuration of VPN Module.

Parameters: None

Returns:
    Hash ref - VPN Module Configuration.

=cut

sub getVpnModuleConfig ( ) {
    return {
        STATUS_UP          => "up",
        STATUS_DOWN        => "down",
        STATUS_CONNECTING  => "connecting",
        STATUS_UNLOADED    => "unloaded",
        STATUS_NEEDRESTART => "needed restart",
        STATUS_IPSEC_DOWN  => "ipsec down",
        STATUS_TUNN_DOWN   => "tunnel down",
        STATUS_L2TP_DOWN   => "l2tp down",
        STATUS_ROUTE_DOWN  => "route down",

        NAME           => "name",
        PROFILE        => "profile",
        BOOTSTATUS     => "bootstatus",
        RESTART        => "restart",
        STATUS         => "status",
        LOCAL          => "local",
        LOCALNET       => "localnet",
        LOCALIP        => "localip",
        LOCALMASK      => "localmask",
        LOCALAUTH      => "localauth",
        LOCALTUNIP     => "localtunip",
        LOCALTUNMASK   => "localtunmask",
        REMOTE         => "remote",
        REMOTENET      => "remotenet",
        REMOTEIP       => "remotenetip",
        REMOTEMASK     => "remotemask",
        REMOTEAUTH     => "remoteauth",
        REMOTETUNIP    => "remotetunip",
        REMOTETUNRANGE => "remotetunrange",
        PASS           => "password",
        AUTH           => "auth",
        P1ENCRYPT      => "p1encrypt",
        P1AUTHEN       => "p1authen",
        P1DHGROUP      => "p1dhgroup",
        P2PROTO        => "p2protocol",
        P2ENCRYPT      => "p2encrypt",
        P2AUTHEN       => "p2authen",
        P2DHGROUP      => "p2dhgroup",
        P2PRF          => "p2prfunc",
        VPN_USER       => "vpnuser",
        VPN_PASSWORD   => "vpnpass",
    };
}

=pod

=head1 getVpnConfigPath

Return the path of vpn config files.

Parameters: None

Returns: string - path.

=cut

sub getVpnConfigPath ( ) {
    return &getGlobalConfiguration('configdir') . "/vpn";
}

=pod

=head1 getVpnConfFilePath

Gets the Configuration filepath of a VPN connection.

Parameters:

    vpn_name - vpn connection name.

Returns: string - File path.

=cut

sub getVpnConfFilePath ($vpn_name) {
    my $vpn_config_filename = $vpn_name . "_vpn.conf";
    my $vpn_config_path     = getVpnConfigPath();

    return "${vpn_config_path}/${vpn_config_filename}";
}

=pod

=head1 getVpnInitConfig

Gets the default values of a VPN object.

Parameters: None.

Returns:
    Hash ref - Object with default values.

=cut

sub getVpnInitConfig () {
    my $vpn_config = &getVpnModuleConfig();

    return {
        $vpn_config->{BOOTSTATUS} => $vpn_config->{STATUS_DOWN},
        $vpn_config->{RESTART}    => "false",
    };
}

=pod

=head1 getVpnList

Get all VPNS of a type.

Parameters:

    vpn_types - Array of types. The available options are "site_to_site", "tunnel" or "remote_access". Empty type means all types.

Returns:

    Array - List of VPN names of a type or all types.

=cut

sub getVpnList (@vpn_types) {
    @vpn_types = ("site_to_site", "tunnel", "remote_access") if (scalar @vpn_types == 0 || !defined $vpn_types[0]);

    my @vpn_names = ();

    opendir(my $config_dir, &getVpnConfigPath()) or return \@vpn_names;

    while (readdir $config_dir) {
        if ($_ =~ /^(.*)_vpn\.conf$/) {
            my $vpn_name = $1;
            my $error    = &getVpnExists($vpn_name);

            next if ($error);

            for my $vpn_type (@vpn_types) {
                my $type = &getVpnType($vpn_name);

                if ($type eq $vpn_type) {
                    push(@vpn_names, $vpn_name);
                }
            }
        }
    }

    closedir $config_dir;

    return \@vpn_names;
}

=pod

=head1 getVpnConfObject

Gets a VPN Configuration object with all or selected params.

Parameters:

    vpn_name   - vpn connection name.
    params_ref - Optional. Array of params to get. No array means all params.

Returns:

    Hash Ref - $vpn_ref on success, undef on error.

Variable: $vpn_ref.

    A hashref that maps a VPN connection.

    name       - name.
    profile    - vss.
    status     - up | down | unloaded.
    bootstatus - up | down.
    leftauth   - psk | secret.
    secret     - password.
    ...

=cut

sub getVpnConfObject ($vpn_name, $params_ref = undef) {
    my $conf_file = &getVpnConfFilePath($vpn_name);
    return if (!-f $conf_file);

    return &getTinyObj($conf_file, $vpn_name, $params_ref, "ignore");
}

=pod

=head1 getVpnObject

Gets a VPN object with all or selected params.

Parameters:

    vpn_name   - vpn connection name.
    params_ref - Optional. Array of params to get. No array means all params.

Returns:

    Hash Ref - $vpn_ref on success, undef on error.

Variable: $vpn_ref.

    A hashref that maps a VPN connection.

    name       - name.
    profile    - vss.
    status     - up | down | need restart.
    bootstatus - up | down.
    leftauth   - psk | secret.
    secret     - password.
    ...

=cut

sub getVpnObject ($vpn_name, $params_ref = undef) {
    my $vpn_config = &getVpnModuleConfig();
    my $params_ref_tmp;
    my $show_status = 0;

    if ($params_ref) {
        for my $param (@{$params_ref}) {
            if ($param eq $vpn_config->{STATUS}) {
                $show_status = 1;
                next;
            }
            push @{$params_ref_tmp}, $param;
        }
    }
    else {
        $show_status = 1;
    }

    my $vpn_ref = &getVpnConfObject($vpn_name, $params_ref_tmp);

    # convert to struct
    my $params = [
        $vpn_config->{P1ENCRYPT}, $vpn_config->{P1AUTHEN},  $vpn_config->{P1DHGROUP}, $vpn_config->{P2ENCRYPT},
        $vpn_config->{P2AUTHEN},  $vpn_config->{P2DHGROUP}, $vpn_config->{P2PRF}
    ];

    if (&getVpnType($vpn_name) eq "remote_access") {
        push @{$params}, $vpn_config->{VPN_USER};
    }

    for my $param (@{$params}) {
        if (!$params_ref || defined $vpn_ref->{$param}) {
            my @value = ();

            if ($vpn_ref->{$param}) {
                @value = split " ", $vpn_ref->{$param};
            }

            $vpn_ref->{$param} = \@value;
        }
    }

    if ($show_status) {
        if (&getVpnRestartStatus($vpn_name) eq "true") {
            $vpn_ref->{ $vpn_config->{STATUS} } = $vpn_config->{STATUS_NEEDRESTART};
        }
        else {
            $vpn_ref->{ $vpn_config->{STATUS} } = &getVpnStatus($vpn_name);
        }
    }

    return $vpn_ref;
}

=pod

=head1 getVpnType

Gets the type of a vpn.

Parameters:

    vpn_name - VPN name

Returns: string | undef - Type of VPN on success, undef on error

=cut

sub getVpnType ($vpn_name) {
    my $vpn_config = &getVpnModuleConfig();
    my $obj        = getVpnConfObject($vpn_name, [ $vpn_config->{PROFILE} ]);

    if (not defined $obj) {
        return;
    }

    return $obj->{ $vpn_config->{PROFILE} };
}

=pod

=head1 getVpnBootstatus

Gets the Boot Status of a vpn.

Parameters:

    vpn_name - VPN name

Returns: string

Boot Status of a  VPN. "up", "down" on success, undef on error

=cut

sub getVpnBootstatus ($vpn_name) {
    my $vpn_config = &getVpnModuleConfig();
    my $obj        = getVpnConfObject($vpn_name, [ $vpn_config->{BOOTSTATUS} ]);

    if (not defined $obj) {
        return;
    }

    return $obj->{ $vpn_config->{BOOTSTATUS} };
}

=pod

=head1 getVpnRestartStatus

Gets the Restart Status of a vpn.

Parameters:

    vpn_name - VPN name

Returns: string

Restart Status of a  VPN. "false" not to be restarted , "true" the vpn has to be restarted.

=cut

sub getVpnRestartStatus ($vpn_name) {
    my $vpn_config = &getVpnModuleConfig();
    my $obj        = getVpnConfObject($vpn_name, [ $vpn_config->{RESTART} ]);

    if (defined $obj) {
        return $obj->{ $vpn_config->{RESTART} };
    }

    return "false";
}

=pod

=head1 getVpnStatus

Gets the Status of a vpn.

Parameters:

    vpn_name - VPN name

Returns: string

Status of a  VPN. "UP", "DOWN" , "UNKNOWN" on success, undef on error

=cut

sub getVpnStatus ($vpn_name) {
    my $vpn_config = &getVpnModuleConfig();
    my $vpn        = getVpnConfObject($vpn_name, [ $vpn_config->{PROFILE} ]);
    my $remote_access;

    return if not defined $vpn;

    if ($vpn->{ $vpn_config->{PROFILE} } eq "site_to_site") {
        require Relianoid::VPN::SiteToSite::Core;
        $remote_access = &getVpnSiteToSiteStatus($vpn_name);
    }
    elsif ($vpn->{profile} eq "tunnel") {
        require Relianoid::VPN::Tunnel::Core;
        $remote_access = &getVpnTunnelStatus($vpn_name);
    }
    elsif ($vpn->{profile} eq "remote_access") {
        require Relianoid::VPN::RemoteAccess::Core;
        $remote_access = &getVpnRemoteAccessStatus($vpn_name);
    }
    else {
        my $profile_name = $vpn->{ $vpn_config->{PROFILE} };
        &log_error("Type ${profile_name} not supported in ${vpn_name}", "VPN");
    }

    return $remote_access;
}

=pod

=head1 getVpnExists

Check if VPN exits.

Parameters:

    $vpn_name - vpn connection name.

Returns: integer - error code

0  - success
!0 - error

=cut

sub getVpnExists ($vpn_name) {
    my $rc   = 1;
    my $type = &getVpnType($vpn_name);

    return $rc if !$type;

    if ($type eq "site_to_site") {
        require Relianoid::VPN::SiteToSite::Core;
        $rc = &getVpnSiteToSiteExists($vpn_name);
    }
    elsif ($type eq "tunnel") {
        require Relianoid::VPN::Tunnel::Core;
        $rc = &getVpnTunnelExists($vpn_name);
    }
    elsif ($type eq "remote_access") {
        require Relianoid::VPN::RemoteAccess::Core;
        $rc = &getVpnRemoteAccessExists($vpn_name);
    }
    else {
        &log_error("Type \"$type\" not supported in $vpn_name", "VPN");
    }

    return $rc;
}

=pod

=head1 getVpnParamExists

Check if VPN params values are configured in a VPN.

Parameters:

    $type - Type of VPN to search. Empty type mean all types.
    $params_ref - Hash ref of params.
    $vpn_exclude - Optional. VPN name to exclude of checking.

Returns:

    Integer or String - Error code on failure or vpn_name on success.

=cut

sub getVpnParamExists ($type, $params_ref, $vpn_exclude = undef) {
    my $rc = 1;

    $type = undef if ($type eq "");
    my $vpn_list = &getVpnList(($type));

    my $params;
    for my $param (keys %{$params_ref}) {
        push @{$params}, $param;
    }

    for my $vpn_name (@{$vpn_list}) {
        next if ((defined $vpn_exclude) and ($vpn_name eq $vpn_exclude));
        my $vpn_params = &getVpnConfObject($vpn_name, $params);

        #compare $params_ref $vpn_params
        my $nparams = 0;

        for my $param (@{$params}) {
            $nparams++ if ($params_ref->{$param} eq $vpn_params->{$param});
        }
        return $vpn_name if ($nparams == scalar @{$params});
    }

    return $rc;
}

=pod

=head1 getVpnLocalGateway

Gets the Local Gateway of a vpn.

Parameters:

    vpn_name - VPN name

Returns:

    Scalar -  String . Local Gateway IP of a VPN.

=cut

sub getVpnLocalGateway ($vpn_name) {
    my $vpn_config = &getVpnModuleConfig();
    my $obj        = getVpnConfObject($vpn_name, [ $vpn_config->{LOCAL} ]);

    return if not defined $obj;
    return $obj->{ $vpn_config->{LOCAL} };
}

=pod

=head1 getVpnLocalNetwork

Gets the Local Network of a vpn.

Parameters:

    vpn_name - VPN name

Returns:

    Scalar -  String . Local Network of a VPN.

=cut

sub getVpnLocalNetwork ($vpn_name) {
    my $vpn_config = &getVpnModuleConfig();
    my $obj        = getVpnConfObject($vpn_name, [ $vpn_config->{LOCALNET} ]);

    return if not defined $obj;
    return $obj->{ $vpn_config->{LOCALNET} };
}

=pod

=head1 replaceHashValues

Replaces existing values from one hash into another

Parameters:

    Hash ref - Hash to be replaced
    Hash ref - Hash with new values
    action - String : Action to be performed. add value means add existing and no existing keys.

Returns: integer - error code

0  - success
!0 - error

=cut

sub replaceHashValues ($dest, $ori, $action) {
    for my $key (keys %{$ori}) {
        if (exists $dest->{$key}) {
            $dest->{$key} = $ori->{$key};
        }
        elsif ($action eq "add") {
            $dest->{$key} = $ori->{$key};
        }
    }

    return 0;
}

=pod

=head1 getVpnUsers

Gets VPN Credentials for a VPN

Parameters:

    vpn_name - Optional. Remote Access VPN name. Undef means all VPNs.

Returns:

    user_ref - Array ref : VPN Users names

=cut

sub getVpnUsers ($vpn_name = undef) {
    my $user_ref   = [];
    my $vpn_config = &getVpnModuleConfig();

    require Relianoid::VPN::Core;

    my $vpn_list;
    if ($vpn_name) {
        push @{$vpn_list}, $vpn_name;
    }
    else {
        my $type = "remote_access";
        $vpn_list = &getVpnList(($type));
    }

    require Relianoid::Config;

    for my $vpn (@{$vpn_list}) {
        my $conf_file = &getVpnConfFilePath($vpn);

        next if (!-f $conf_file);

        my $users = &getTinyObj($conf_file, $vpn, [ $vpn_config->{VPN_USER} ], "undef");
        push @{$user_ref}, split(/ /, $users->{ $vpn_config->{VPN_USER} } // "");
    }

    return $user_ref;
}

=pod

=head1 getVpnUserExists

Check if VPN User exits.

Parameters:

    $user_name - vpn user name.

Returns: integer - error code

0  - success
!0 - error

=cut

sub getVpnUserExists ($user_name) {
    my $rc    = 1;
    my $users = &getVpnUsers();

    if ($users) {
        $rc = 0 if (grep { $user_name eq $_ } @{$users});
    }

    return $rc;
}

=pod

=head1 getVpnRunning

Returns the VPN are currently running in the system.

Parameters:

    vpn_types - VPN type. The available options are "site_to_site", "tunnel" or "remote_access". Empty type means all types.

Returns:

    Array ref - List of VPN names

=cut

sub getVpnRunning ($vpn_type) {
    my $vpn_ref    = [];
    my $vpn_config = &getVpnModuleConfig();

    for my $vpn_name (@{ &getVpnList($vpn_type) }) {
        if (&getVpnStatus($vpn_name) ne $vpn_config->{STATUS_DOWN}) {
            push @{$vpn_ref}, $vpn_name;
        }
    }

    return $vpn_ref;
}

1;
