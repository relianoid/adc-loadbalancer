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

Relianoid::HTTP::Controllers::API::Session

=cut

use strict;
use warnings;
use feature qw(signatures);

use Relianoid::CGI;
use Relianoid::HTTP;
use Relianoid::HTTP::Auth;

use CGI::Session;

my $LOG_TAG = "";
$LOG_TAG = "API"    if get_http_api_key();
$LOG_TAG = "WEBGUI" if (exists $ENV{HTTP_COOKIE});

=pod

=head1 session_login_controller

C<POST /session>

Authentication via HTTP basic access authentication, using the HTTP header

C<Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==>

B<Arguments>:

IMPORTANT:

- Relianoid::HTTP::POST() has an exception to not include arguments when
C<POST /session> is called, because the web GUI is sending a non-empty body.

- This call should have no body, so also no content type.

=cut

sub session_login_controller () {
    my $desc    = "Login to new session";
    my $session = CGI::Session->new(&getCGI());

    unless ($session && !$session->param('is_logged_in')) {
        my $msg = "Already logged in a session";
        return &httpErrorResponse({ code => 401, desc => $desc, msg => $msg });
    }

    # not validated credentials
    my ($username, $password) = &getAuthorizationCredentials();

    unless (&authenticateCredentials($username, $password)) {
        $session->delete();
        $session->flush();

        my $msg = "The username and/or password are incorrect";
        return &httpErrorResponse({ code => 401, desc => $desc, msg => $msg });
    }

    # check if the user has got permissions
    my (undef, undef, undef, $webgui_group) = getgrnam('webgui');
    if (!grep { /(^| )$username( |$)/ } $webgui_group) {
        my $msg = "The user $username has not web permissions";
        return &httpErrorResponse({ code => 401, desc => $desc, msg => $msg });
    }

    require Relianoid::SystemInfo;

    $session->param('is_logged_in', 1);
    $session->param('username',     $username);
    my $session_timeout = &getGlobalConfiguration('session_timeout') // 30;
    $session->expire('is_logged_in', '+' . $session_timeout . 'm');

    my ($header) = split("\r\n", $session->header());
    my (undef, $session_cookie) = split(': ', $header);

    my $body = {
        host    => &getHostname(),
        user    => $username,
        version => &getGlobalConfiguration("version"),
    };

    if (my $eload = eval { require Relianoid::ELoad }) {
        $body->{key} = eload(module => 'Relianoid::EE::Certificate::Activation', func => 'getNodeKey');
    }

    &log_info("Login successful for user: $username", $LOG_TAG);

    return &httpResponse({
        code    => 200,
        body    => $body,
        headers => { 'Set-cookie' => "${session_cookie}; SameSite=None; Secure; HttpOnly" },
    });
}

# DELETE /session
sub session_logout_controller () {
    my $desc = "Logout of session";
    my $cgi  = &getCGI();

    unless ($cgi->http('Cookie')) {
        my $msg = "Session cookie not found";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $session = CGI::Session->new($cgi);

    unless ($session && $session->param('is_logged_in')) {
        my $msg = "Session expired or not found";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $username = $session->param('username');
    my $ip_addr  = $session->param('_SESSION_REMOTE_ADDR');

    &log_info("Logged out user $username from $ip_addr", $LOG_TAG);

    $session->delete();
    $session->flush();

    return &httpResponse({ code => 200 });
}

1;
