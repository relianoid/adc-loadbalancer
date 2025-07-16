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

Relianoid API 4.0

=cut

use strict;
use warnings;
use feature qw(signatures);

use Relianoid::Log;
use Relianoid::HTTP;

local $ENV{API_VERSION} = "4.0";

##### Debugging messages #############################################
&log_info("REQUEST: $ENV{REQUEST_METHOD} $ENV{SCRIPT_URL}") if &debug();

##### No authentication required #####################################
if ($ENV{REQUEST_METHOD} eq 'OPTIONS') {
    OPTIONS qr{^/.*$} => sub { return &httpResponse({ code => 200 }); };
}

if ($ENV{PATH_INFO} eq '/system/language' && $ENV{REQUEST_METHOD} eq 'GET') {
    require Relianoid::HTTP::Controllers::API::System::Info;
    GET qr{^/system/language$}, \&get_language_controller;
}

if ($ENV{PATH_INFO} eq '/session') {
    require Relianoid::HTTP::Controllers::API::Session;
    POST qr{^/session$} => \&session_login_controller;
    DELETE qr{^/session$} => \&session_logout_controller;
}

##### Authentication #################################################
require Relianoid::API;
require Relianoid::HTTP::Auth;

# Verify authentication
unless ((get_http_api_key() && is_api_key_valid())
    or (exists $ENV{HTTP_COOKIE} && &validCGISession()))
{
    &httpResponse({ code => 401, body => { message => 'Authorization required' } });
}

##### Load API routes ################################################
require Relianoid::API40::Routes;

my $desc = 'Request not found';
&httpErrorResponse({ code => 404, desc => $desc, msg => "${desc}: $ENV{PATH_INFO}" });
