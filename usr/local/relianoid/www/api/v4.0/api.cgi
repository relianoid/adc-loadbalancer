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

use Relianoid::Log;
use Relianoid::Debug;
use Relianoid::CGI;
use Relianoid::API40::HTTP;
use Relianoid::API;

local $ENV{ZAPI_VERSION} = "4.0";

my $q = &getCGI();

##### Debugging messages #############################################
&zenlog("REQUEST: $ENV{REQUEST_METHOD} $ENV{SCRIPT_URL}") if &debug();

##### Load more basic modules ########################################
require Relianoid::Config;
require Relianoid::Validate;

#### OPTIONS requests ################################################
require Relianoid::API40::Options if ($ENV{REQUEST_METHOD} eq 'OPTIONS');

##### Authentication #################################################
require Relianoid::API40::Auth;

# Session request
require Relianoid::API40::Session if ($q->path_info eq '/session');

# Verify authentication
unless ((exists $ENV{HTTP_ZAPI_KEY} && &isApiKeyValid())
    or (exists $ENV{HTTP_COOKIE} && &validCGISession()))
{
    &httpResponse({ code => 401, body => { message => 'Authorization required' } });
}

##### Load API routes ################################################
#~ require Relianoid::SystemInfo;
require Relianoid::API40::Routes;

my $desc = 'Request not found';
my $req  = $ENV{PATH_INFO};

&httpErrorResponse({ code => 404, desc => $desc, msg => "$desc: $req" });
