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

use Relianoid::Log;
use Relianoid::Debug;
use Relianoid::CGI;
use Relianoid::API40::HTTP;
use Relianoid::Zapi;

&setZapiVersion("4.0");

my $q = &getCGI();

##### Debugging messages #############################################
#
#~ use Data::Dumper;
#~ $Data::Dumper::Sortkeys = 1;
#
#~ if ( debug() )
#~ {
&zenlog("REQUEST: $ENV{REQUEST_METHOD} $ENV{SCRIPT_URL}") if &debug;

#~ &zenlog( ">>>>>> CGI REQUEST: <$ENV{REQUEST_METHOD} $ENV{SCRIPT_URL}> <<<<<<" ) if &debug;
#~ &zenlog( "HTTP HEADERS: " . join ( ', ', $q->http() ) );
#~ &zenlog( "HTTP_AUTHORIZATION: <$ENV{HTTP_AUTHORIZATION}>" )
#~ if exists $ENV{ HTTP_AUTHORIZATION };
#~ &zenlog( "HTTP_ZAPI_KEY: <$ENV{HTTP_ZAPI_KEY}>" )
#~ if exists $ENV{ HTTP_ZAPI_KEY };
#~
#~ #my $session = new CGI::Session( $q );
#~
#~ my $param_zapikey = $ENV{'HTTP_ZAPI_KEY'};
#~ my $param_session = new CGI::Session( $q );
#~
#~ my $param_client = $q->param('client');
#~
#~
#~ &zenlog("CGI PARAMS: " . Dumper $params );
#~ &zenlog("CGI OBJECT: " . Dumper $q );
#~ &zenlog("CGI VARS: " . Dumper $q->Vars() );
#~ &zenlog("PERL ENV: " . Dumper \%ENV );
#~
#~
#~ my $post_data = $q->param( 'POSTDATA' );
#~ my $put_data  = $q->param( 'PUTDATA' );
#~
#~ &zenlog( "CGI POST DATA: " . $post_data ) if $post_data && &debug && $ENV{ CONTENT_TYPE } eq 'application/json';
#~ &zenlog( "CGI PUT DATA: " . $put_data )   if $put_data && &debug && $ENV{ CONTENT_TYPE } eq 'application/json';
#~ }

##### Load more basic modules ########################################
require Relianoid::Config;
require Relianoid::Validate;

#### OPTIONS requests ################################################
require Relianoid::API40::Options if ($ENV{REQUEST_METHOD} eq 'OPTIONS');

##### Authentication #################################################
require Relianoid::API40::Auth;
require Relianoid::Zapi;

# Session request
require Relianoid::API40::Session if ($q->path_info eq '/session');

# Verify authentication
unless ((exists $ENV{HTTP_ZAPI_KEY} && &validZapiKey())
    or (exists $ENV{HTTP_COOKIE} && &validCGISession()))
{
    &httpResponse(
        { code => 401, body => { message => 'Authorization required' } });
}

##### Load API routes ################################################
#~ require Relianoid::SystemInfo;
require Relianoid::API40::Routes;

my $desc = 'Request not found';
my $req  = $ENV{PATH_INFO};

&httpErrorResponse(code => 404, desc => $desc, msg => "$desc: $req");
