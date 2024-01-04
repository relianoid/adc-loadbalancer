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

my $eload = eval { require Relianoid::ELoad };

# 	GET /system/users
sub get_system_user {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    require Relianoid::User;
    my $user = &getUser();

    my $desc = "Retrieve the user $user";

    if ('root' eq $user) {
        require Relianoid::API;
        my $params = {
            'user'             => $user,
            'zapi_permissions' => &getAPI("status"),
            'service'          => 'local'

              # it is configured if the status is up
              # 'zapikey'	=> &getAPI( "zapikey" ),
        };

        &httpResponse(
            {
                code => 200,
                body => { description => $desc, params => $params }
            }
        );
    }

    elsif ($eload) {
        my $params = &eload(
            module => 'Relianoid::API40::RBAC::User',
            func   => 'get_system_user_rbac',
        );

        if ($params) {
            &httpResponse(
                {
                    code => 200,
                    body => { description => $desc, params => $params }
                }
            );
        }
    }

    else {
        my $msg = "The user is not found";
        &httpErrorResponse(code => 404, desc => $desc, msg => $msg);
    }
    return;
}

#  POST /system/users
sub set_system_user {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my $json_obj = shift;

    require Relianoid::User;
    require Relianoid::Login;

    my $error = 0;
    my $user  = &getUser();
    my $desc  = "Modify the user $user";

    my $params = &getAPIModel("system_user-modify.json");

    # Check allowed parameters
    my $error_msg = &checkApiParams($json_obj, $params, $desc);
    return &httpErrorResponse(code => 400, desc => $desc, msg => $error_msg)
      if ($error_msg);

    # check to change password
    if ($json_obj->{'newpassword'}) {
        if (not exists $json_obj->{'password'}) {
            my $msg = "The parameter password is required.";
            return &httpErrorResponse(code => 400, desc => $desc, msg => $msg);
        }

        elsif ($json_obj->{'newpassword'} eq $json_obj->{'password'}) {
            my $msg = "The new password must be different to the current password.";
            return &httpErrorResponse(code => 400, desc => $desc, msg => $msg);
        }
        if ($eload) {
            my $local_user = &eload(
                module => 'Relianoid::RBAC::User::Core',
                func   => 'getRBACUserLocal',
                args   => [$user],
            );
            if (!$local_user) {
                my $msg = "The $user User is not valid to change password.";
                return &httpErrorResponse(
                    code => 400,
                    desc => $desc,
                    msg  => $msg
                );
            }
        }

        if (!&checkValidUser($user, $json_obj->{'password'})) {
            my $msg = "Invalid current password.";
            return &httpErrorResponse(code => 400, desc => $desc, msg => $msg);
        }
    }

    if ($json_obj->{'password'}) {
        if (not exists $json_obj->{'newpassword'}) {
            my $msg = "The parameter newpassword is required.";
            return &httpErrorResponse(code => 400, desc => $desc, msg => $msg);
        }
    }

    if ($user eq 'root') {

        # modify password
        if (exists $json_obj->{'newpassword'}) {
            $error = &changePassword($user, $json_obj->{'newpassword'}, $json_obj->{'newpassword'});

            if ($error) {
                my $msg = "Modifying $user.";
                return &httpErrorResponse(
                    code => 400,
                    desc => $desc,
                    msg  => $msg
                );
            }
        }

        # modify zapikey. change this parameter before than zapi permissions
        if (exists $json_obj->{'zapikey'}) {
            if ($eload) {
                my $zapi_user = &eload(
                    module => 'Relianoid::RBAC::User::Core',
                    func   => 'getRBACUserbyZapikey',
                    args   => [ $json_obj->{'zapikey'} ],
                );
                if ($zapi_user and $zapi_user ne $user) {
                    my $msg = "The zapikey is not valid.";
                    return &httpErrorResponse(
                        code => 400,
                        desc => $desc,
                        msg  => $msg
                    );
                }
            }
            &setAPI('key', $json_obj->{'zapikey'});
        }

        # modify zapi permissions
        if (exists $json_obj->{'zapi_permissions'}) {
            if ($json_obj->{'zapi_permissions'} eq 'true'
                && !&getAPI('zapikey'))
            {
                my $msg = "It is necessary a zapikey to enable the zapi permissions.";
                return &httpErrorResponse(
                    code => 400,
                    desc => $desc,
                    msg  => $msg
                );
            }
            if (   $json_obj->{'zapi_permissions'} eq 'true'
                && &getAPI("status") eq 'false')
            {
                &setAPI("enable");
            }
            elsif ($json_obj->{'zapi_permissions'} eq 'false'
                && &getAPI("status") eq 'true')
            {
                &setAPI("disable");
            }
        }
    }

    elsif ($eload) {
        $error = &eload(
            module => 'Relianoid::API40::RBAC::User',
            func   => 'set_system_user_rbac',
            args   => [$json_obj],
        );
    }

    else {
        my $msg = "The user is not found";
        &httpErrorResponse(code => 404, desc => $desc, msg => $msg);
    }

    my $msg  = "Settings was changed successfully.";
    my $body = { description => $desc, message => $msg };

    &httpResponse({ code => 200, body => $body });
    return;
}

1;

