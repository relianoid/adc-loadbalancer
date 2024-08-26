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

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::HTTP::Auth

=cut

sub validCGISession() {
    require Relianoid::CGI;
    require CGI::Session;

    my $q            = &getCGI();
    my $validSession = 0;

    my $session = CGI::Session->load($q);

    if ($session && $session->param('is_logged_in') && !$session->is_expired) {
        # ignore cluster nodes status to reset session expiration date
        unless ($q->path_info eq '/system/cluster/nodes') {
            my $session_timeout = &getGlobalConfiguration('session_timeout') // 30;
            $session->expire('is_logged_in', '+' . $session_timeout . 'm');
        }

        $validSession = 1;
        require Relianoid::User;
        &setUser($session->param('username'));
    }

    return $validSession;
}

sub getAuthorizationCredentials() {
    my $base64_digest;
    my $username;
    my $password;

    if (exists $ENV{HTTP_AUTHORIZATION}) {
        # Expected header example: 'Authorization': 'Basic aHR0cHdhdGNoOmY='
        $ENV{HTTP_AUTHORIZATION} =~ /^Basic (.+)$/;
        $base64_digest = $1;
    }

    if ($base64_digest) {
        # $decoded_digest format: "username:password"
        require MIME::Base64;
        chomp(my $decoded_digest = MIME::Base64::decode_base64($base64_digest));

        ($username, $password) = split /:/, $decoded_digest, 2;
    }

    &log_error("User not found",     "api") if not length $username;
    &log_error("Password not found", "api") if not length $password;

    return if not length $username or not length $password;

    require Relianoid::User;
    &setUser($username);

    return ($username, $password);
}

sub authenticateCredentials ($user, $pass) {
    return if not defined $user or not defined $pass;

    my $valid_credentials = 0;    # output

    if ($user eq 'root') {
        require Authen::Simple::Passwd;
        Authen::Simple::Passwd->import;

        my $passfile = "/etc/shadow";
        my $simple   = Authen::Simple::Passwd->new(path => "$passfile");

        if ($simple->authenticate($user, $pass)) {
            &log_debug("The user '$user' login locally", "auth");
            $valid_credentials = 1;
        }
    }
    elsif ($eload) {
        $valid_credentials = &eload(
            module => 'Relianoid::EE::RBAC::Runtime',
            func   => 'runRBACAuthUser',
            args   => [ $user, $pass ]
        );
    }

    return $valid_credentials;
}

1;

