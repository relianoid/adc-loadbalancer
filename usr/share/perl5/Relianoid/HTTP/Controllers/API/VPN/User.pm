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

use Relianoid::Config;
use Relianoid::HTTP;

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::VPN::User

=cut

# POST /vpns/(vpn_re)/users
sub add_vpn_user_controller ($json_obj, $vpn_name) {
    my $desc = "Add VPN User";

    require Relianoid::VPN::Core;

    if (my $error = &getVpnExists($vpn_name)) {
        my $msg = "The VPN $vpn_name does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getVpnType($vpn_name);

    if ($type eq "remote_access") {
        require Relianoid::HTTP::Controllers::API::VPN::RemoteAccess;
        &_add_vpn_remote_access_user_controller($vpn_name, $json_obj);
    }

    my $msg = "Error trying to add VPN User in a wrong VPN type.";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# DELETE /vpns/(vpn_re)/users/(user_re)
sub delete_vpn_user_controller ($vpn_name, $user_name) {
    my $desc = "Delete VPN User";

    require Relianoid::VPN::Core;

    if (my $error = &getVpnExists($vpn_name)) {
        my $msg = "The VPN $vpn_name does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getVpnType($vpn_name);

    if ($type eq "remote_access") {
        require Relianoid::HTTP::Controllers::API::VPN::RemoteAccess;
        &_delete_vpn_remote_access_user_controller($vpn_name, $user_name);
    }

    my $msg = "Error trying to delete VPN User in a wrong VPN type.";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# PUT /vpns/(vpn_re)/users/(user_re)
sub modify_vpn_user_controller ($json_obj, $vpn_name, $user_name) {
    my $desc = "Modify VPN User";

    require Relianoid::VPN::Core;

    if (my $error = &getVpnExists($vpn_name)) {
        my $msg = "The VPN $vpn_name does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getVpnType($vpn_name);

    if ($type eq "remote_access") {
        require Relianoid::HTTP::Controllers::API::VPN::RemoteAccess;
        &_modify_vpn_remote_access_user_controller($vpn_name, $user_name, $json_obj);
    }

    my $msg = "Error trying to modify VPN User to $vpn_name.";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# POST /vpns/(vpn_re)/users
sub _add_vpn_remote_access_user_controller ($vpn_name, $json_obj) {
    my $desc = "Create Remote Access VPN User";

    my $params = {
        vpnuser => {
            valid_format => 'vpn_user',
            non_blank    => 'true',
            required     => 'true',
        },
        vpnpass => {
            non_blank => 'true',
            required  => 'true',
        },
    };

    # check api params
    require Relianoid::Validate;
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # integrity checks
    require Relianoid::VPN::Config;
    unless (&getVpnUserExists($json_obj->{vpnuser})) {
        my $error_msg = "VPN user $json_obj->{vpnuser} already exists in the system.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    if (!$eload) {
        my @users = @{ getVpnUsers() };
        if (scalar @users) {
            my $error_msg = "Remote Access VPN $vpn_name already has an user.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
        }
    }

    # add user
    require Relianoid::HTTP::Controllers::API::VPN::Structs;
    my $remote_access = &getVpnObjectResponse($json_obj, "4.0", "config");

    require Relianoid::VPN::RemoteAccess::Config;
    my $error = &createVpnRemoteAccessUser($vpn_name, $remote_access);

    if ($error->{code}) {
        my $error_msg = "Some errors happened trying to create VPN user. " . $error->{desc} . ".";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    if ($eload) {
        my @args = ('vpn', 'add-user', $vpn_name, $json_obj->{vpnuser}, $json_obj->{vpnpass});
        eload(module => 'Relianoid::EE::Cluster', func => 'runClusterRemoteManager', args => \@args);
    }

    require Relianoid::VPN::Config;
    my $out_obj = &getVpnObject($vpn_name);
    my $api_obj = &getVpnObjectResponse($out_obj, "4.0", "api");

    my $msg  = "The VPN user $json_obj->{vpnuser} has been created successfully.";
    my $body = { description => $desc, params => $api_obj, message => $msg };

    return &httpResponse({ code => 201, body => $body });
}

# DELETE /vpns/<vpn_re>/users/<user_re>
sub _delete_vpn_remote_access_user_controller ($vpn_name, $user_name) {
    my $desc = "Delete Remote Access VPN User";

    # integrity checks
    require Relianoid::VPN::Config;
    if (&getVpnUserExists($user_name)) {
        my $error_msg = "VPN user $user_name does not exists in the system.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # delete user
    require Relianoid::VPN::RemoteAccess::Config;
    my $error = &deleteVpnRemoteAccessUser($vpn_name, $user_name);

    if ($error->{code}) {
        my $error_msg = "Some errors happened trying to delete VPN user. " . $error->{desc} . ".";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    if ($eload) {
        my @args = ('vpn', 'del-user', $vpn_name, $user_name);
        eload(module => 'Relianoid::EE::Cluster', func => 'runClusterRemoteManager', args => \@args);
    }

    require Relianoid::VPN::Config;
    my $out_obj = &getVpnObject($vpn_name);

    require Relianoid::HTTP::Controllers::API::VPN::Structs;
    my $api_obj = &getVpnObjectResponse($out_obj, "4.0", "api");

    my $msg  = "The VPN user $user_name has been deleted.";
    my $body = { description => $desc, params => $api_obj, message => $msg };

    return &httpResponse({ code => 200, body => $body });
}

# PUT /vpns/<vpn_re>/users/<user_re>
sub _modify_vpn_remote_access_user_controller ($vpn_name, $user_name, $json_obj) {
    my $desc = "Modify Remote Access VPN User";

    my $params = {
        vpnpass => {
            non_blank => 'true',
            required  => 'true',
        },
    };

    # check api params
    require Relianoid::Validate;
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # integrity checks
    require Relianoid::VPN::Config;
    if (&getVpnUserExists($user_name)) {
        my $error_msg = "VPN user $user_name does not exists in the system.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # modify user
    require Relianoid::HTTP::Controllers::API::VPN::Structs;
    my $remote_access = &getVpnObjectResponse($json_obj, "4.0", "config");

    require Relianoid::VPN::RemoteAccess::Config;
    my $error = &setVpnRemoteAccessUser($vpn_name, $user_name, $remote_access);

    if ($error->{code}) {
        my $error_msg = "Some errors happened trying to modify VPN user. " . $error->{desc} . ".";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    if ($eload) {
        my @args = ('vpn', 'modify-user', $vpn_name, $user_name, $json_obj->{vpnpass});
        eload(module => 'Relianoid::EE::Cluster', func => 'runClusterRemoteManager', args => \@args);
    }

    my $out_obj = &getVpnObject($vpn_name);
    my $api_obj = &getVpnObjectResponse($out_obj, "4.0", "api");

    my $msg  = "Some parameters have been changed in VPN user $user_name.";
    my $body = { description => $desc, params => $api_obj, message => $msg };

    return &httpResponse({ code => 200, body => $body });
}

1;
