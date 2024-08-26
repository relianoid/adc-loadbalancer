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

require Relianoid::User;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::System::User

=cut

my $eload = eval { require Relianoid::ELoad };

# 	GET /system/users
sub get_system_user_controller () {
    my $user = &getUser();

    my $desc = "Retrieve the user $user";

    if ('root' eq $user) {
        require Relianoid::API;

        my $api_status = &getAPI("status");
        my $params     = {
            user             => $user,
            api_permissions  => $api_status,
            zapi_permissions => $api_status,
            service          => 'local'

            # it is configured if the status is up
            # 'api_key'	=> &getAPI( "api_key" ),
        };

        return &httpResponse({
            code => 200,
            body => { description => $desc, params => $params }
        });
    }

    elsif ($eload) {
        my $params = &eload(
            module => 'Relianoid::EE::HTTP::Controllers::API::RBAC::User',
            func   => 'get_system_user_rbac',
        );

        if ($params) {
            return &httpResponse({
                code => 200,
                body => { description => $desc, params => $params }
            });
        }
    }

    my $msg = "The user is not found";
    return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
}

#  POST /system/users
sub set_system_user_controller ($json_obj) {
    require Relianoid::Login;

    my $error = 0;
    my $user  = &getUser();
    my $desc  = "Modify the user $user";

    my $params = &getAPIModel("system_user-modify.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # check to change password
    if ($json_obj->{newpassword}) {
        if (not exists $json_obj->{password}) {
            my $msg = "The parameter password is required.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        elsif ($json_obj->{newpassword} eq $json_obj->{password}) {
            my $msg = "The new password must be different to the current password.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
        if ($eload) {
            my $local_user = &eload(
                module => 'Relianoid::EE::RBAC::User::Core',
                func   => 'getRBACUserLocal',
                args   => [$user],
            );
            if (!$local_user) {
                my $msg = "The $user User is not valid to change password.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        if (!&checkValidUser($user, $json_obj->{password})) {
            my $msg = "Invalid current password.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    if ($json_obj->{password}) {
        if (not exists $json_obj->{newpassword}) {
            my $msg = "The parameter newpassword is required.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    if ($user eq 'root') {
        # modify password
        if (exists $json_obj->{newpassword}) {
            $error = &changePassword($user, $json_obj->{newpassword}, $json_obj->{newpassword});

            if ($error) {
                my $msg = "Modifying $user.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        # modify api_key. change this parameter before than API permissions
        if (exists $json_obj->{api_key}) {
            if ($eload) {
                my $api_user = &eload(
                    module => 'Relianoid::EE::RBAC::User::Core',
                    func   => 'getRBACUserByAPIKey',
                    args   => [ $json_obj->{api_key} ],
                );

                if ($api_user and $api_user ne $user) {
                    my $msg = "The api_key is not valid.";
                    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
                }
            }
            &setAPI('key', $json_obj->{api_key});
        }

        # modify API permissions
        my $json_api_permissions = $json_obj->{api_permissions} // $json_obj->{zapi_permissions};

        if (defined $json_api_permissions) {
            if ($json_api_permissions eq 'true' && !&getAPI('api_key')) {
                my $msg = "It is necessary a api_key to enable the API permissions.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }

            if ($json_api_permissions eq 'true' && &getAPI("status") eq 'false') {
                &setAPI("enable");
            }
            elsif ($json_api_permissions eq 'false' && &getAPI("status") eq 'true') {
                &setAPI("disable");
            }
        }
    }

    elsif ($eload) {
        $error = &eload(
            module => 'Relianoid::EE::HTTP::Controllers::API::RBAC::User',
            func   => 'set_system_user_rbac',
            args   => [$json_obj],
        );
    }

    else {
        my $msg = "The user is not found";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $msg  = "Settings was changed successfully.";
    my $body = { description => $desc, message => $msg };

    return &httpResponse({ code => 200, body => $body });
}

1;

