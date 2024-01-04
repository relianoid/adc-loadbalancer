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
no warnings 'experimental::args_array_with_signatures';

my $LOG_TAG = "";
$LOG_TAG = "ZAPI"   if (exists $ENV{HTTP_ZAPI_KEY});
$LOG_TAG = "WEBGUI" if (exists $ENV{HTTP_COOKIE});

my $eload = eval { require Relianoid::ELoad };

my %http_status_codes = (

    # 2xx Success codes
    200 => 'OK',
    201 => 'Created',
    204 => 'No Content',

    # 4xx Client Error codes
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Certificate not valid',
    403 => 'Forbidden',
    404 => 'Not Found',
    406 => 'Not Acceptable',
    415 => 'Unsupported Media Type',
    410 => 'Gone',
    422 => 'Unprocessable Entity',
);

sub GET ($path, $code, $mod = undef) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    return
      unless $ENV{REQUEST_METHOD} eq 'GET'
      or $ENV{REQUEST_METHOD} eq 'HEAD';

    my @captures = ($ENV{PATH_INFO} =~ $path);
    return unless @captures;

    if (ref $code eq 'CODE') {
        $code->(@captures);
    }
    else {
        &eload(module => $mod, func => $code, args => \@captures) if $eload;
    }
    return;
}

sub POST ($path, $code, $mod = undef) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    return unless $ENV{REQUEST_METHOD} eq 'POST';

    my @captures = ($ENV{PATH_INFO} =~ $path);
    return unless @captures;

    my $data = &getCgiParam('POSTDATA');
    my $input_ref;

    if (exists $ENV{CONTENT_TYPE} && $ENV{CONTENT_TYPE} eq 'application/json' && $data) {
        require JSON;

        $input_ref = eval { JSON::decode_json($data) };

        if (&debug()) {
            &zenlog("json: ${data}", "debug", $LOG_TAG);
        }

        if (!$input_ref) {
            my $body = {
                message => 'The body does not look a valid JSON',
                error   => 'true'
            };
            &httpResponse({ code => 400, body => $body });
        }
    }
    elsif (exists $ENV{CONTENT_TYPE} && $ENV{CONTENT_TYPE} eq 'text/plain') {
        $input_ref = $data;
    }
    elsif (exists $ENV{CONTENT_TYPE}
        && $ENV{CONTENT_TYPE} eq 'application/x-pem-file')
    {
        $input_ref = $data;
    }
    elsif (exists $ENV{CONTENT_TYPE}
        && $ENV{CONTENT_TYPE} eq 'application/gzip')
    {
        $input_ref = $data;
    }
    else {
        &zenlog("Content-Type not supported: $ENV{ CONTENT_TYPE }", "error", $LOG_TAG);
        my $body = { message => 'Content-Type not supported', error => 'true' };

        &httpResponse({ code => 415, body => $body });
    }

    my @args = ($input_ref, @captures);

    if (ref $code eq 'CODE') {
        $code->(@args);
    }
    else {
        &eload(module => $mod, func => $code, args => \@args) if $eload;
    }
    return;
}

sub PUT ($path, $code, $mod = undef) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    return unless $ENV{REQUEST_METHOD} eq 'PUT';

    my @captures = ($ENV{PATH_INFO} =~ $path);
    return unless @captures;

    my $data = &getCgiParam('PUTDATA');
    my $input_ref;

    if (exists $ENV{CONTENT_TYPE} && $ENV{CONTENT_TYPE} eq 'application/json' && $data) {
        require JSON;

        $input_ref = eval { JSON::decode_json($data) };

        if (&debug()) {
            &zenlog("json: ${data}", "debug", $LOG_TAG);
        }

        if (!$input_ref) {
            my $body = {
                message => 'The body does not look a valid JSON',
                error   => 'true'
            };
            &httpResponse({ code => 400, body => $body });
        }
    }
    elsif (exists $ENV{CONTENT_TYPE} && $ENV{CONTENT_TYPE} eq 'text/plain') {
        $input_ref = $data;
    }
    elsif (exists $ENV{CONTENT_TYPE} && $ENV{CONTENT_TYPE} eq 'application/x-pem-file') {
        $input_ref = $data;
    }
    elsif (exists $ENV{CONTENT_TYPE} && $ENV{CONTENT_TYPE} eq 'application/gzip') {
        $input_ref = $data;
    }
    else {
        &zenlog("Content-Type not supported: $ENV{ CONTENT_TYPE }", "error", $LOG_TAG);
        my $body = { message => 'Content-Type not supported', error => 'true' };

        &httpResponse({ code => 415, body => $body });
    }

    my @args = ($input_ref, @captures);

    if (ref $code eq 'CODE') {
        $code->(@args);
    }
    else {
        &eload(module => $mod, func => $code, args => \@args) if $eload;
    }

    return;
}

sub DELETE ($path, $code, $mod = undef) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    return unless $ENV{REQUEST_METHOD} eq 'DELETE';

    my @captures = ($ENV{PATH_INFO} =~ $path);
    return unless @captures;

    if (ref $code eq 'CODE') {
        $code->(@captures);
    }
    else {
        &eload(module => $mod, func => $code, args => \@captures) if $eload;
    }

    return;
}

sub OPTIONS ($path, $code) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    return unless $ENV{REQUEST_METHOD} eq 'OPTIONS';

    my @captures = ($ENV{PATH_INFO} =~ $path);
    return unless @captures;

    &zenlog("OPTIONS captures( @captures )", "debug", $LOG_TAG) if &debug();

    $code->(@captures);

    return;
}

=begin nd
	Function: httpResponse

	Render and print zapi response fron data input.

	Parameters:

		Hash reference with these key-value pairs:

		code - HTTP status code digit
		headers - optional hash reference of extra http headers to be included
		body - optional hash reference with data to be sent as JSON

	Returns:

		This function exits the execution uf the current process.
=cut

sub httpResponse ($self) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    return $self unless exists $ENV{GATEWAY_INTERFACE};

    die 'httpResponse: Bad input' if not defined $self or ref $self ne 'HASH';

    die
      if not defined $self->{code}
      or not exists $http_status_codes{ $self->{code} };

    require Relianoid::CGI;

    my $q      = &getCGI();
    my $origin = '*';

    if (!exists $ENV{HTTP_ZAPI_KEY}) {
        $origin =
          (&getGlobalConfiguration('cors_devel_mode') eq "true")
          ? $ENV{HTTP_ORIGIN}
          : "https://$ENV{ HTTP_HOST }";
    }

    # Headers included in _ALL_ the responses, any method, any URI, sucess or error
    my @headers = (
        'Access-Control-Allow-Origin'      => $origin,
        'Access-Control-Allow-Credentials' => 'true',
        'Cache-Control'                    => 'no-cache',
        'Expires'                          => '-1',
        'Pragma'                           => 'no-cache',
    );

    if ($ENV{'REQUEST_METHOD'} eq 'OPTIONS')    # no session info received
    {
        push @headers,
          'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers' =>
          'ZAPI_KEY, Authorization, Set-cookie, Content-Type, X-Requested-With',
          ;
    }

    if (exists $ENV{HTTP_COOKIE} && $ENV{HTTP_COOKIE} =~ /CGISESSID/) {
        require Relianoid::API40::Auth;

        if (&validCGISession()) {
            my $session        = CGI::Session->load($q);
            my $session_cookie = $q->cookie(CGISESSID => $session->id);

            push @headers,
              'Set-Cookie' => $session_cookie . "; SameSite=None; Secure; HttpOnly",
              'Access-Control-Expose-Headers' => 'Set-Cookie, Content-Disposition',
              ;
        }
    }

    if ($q->path_info =~ '/session') {
        push @headers, 'Access-Control-Expose-Headers' => 'Set-Cookie';
    }

    # add possible extra headers
    if (exists $self->{headers} && ref $self->{headers} eq 'HASH') {
        push @headers, %{ $self->{headers} };
    }

    # header
    my $content_type = 'application/json';
    $content_type = $self->{type} if $self->{type} && $self->{body};

    my $output = $q->header(
        -type    => $content_type,
        -charset => 'utf-8',
        -status  => "$self->{ code } $http_status_codes{ $self->{ code } }",

        # extra headers
        @headers,
    );

    # body
    if (exists $self->{body}) {
        if (ref $self->{body} eq 'HASH') {
            require JSON;

            my $json           = JSON->new->utf8->pretty(1);
            my $json_canonical = 1;
            $json->canonical([$json_canonical]);

            $output .= $json->encode($self->{body});
        }
        else {
            $output .= $self->{body};
        }
    }

    print $output;

    # does not log the annoying logs about connections and cluster
    unless (
        $ENV{REQUEST_METHOD} eq 'GET'
        and (  $ENV{SCRIPT_URL} =~ '/stats/system/connections$'
            or $ENV{SCRIPT_URL} =~ '/system/cluster/nodes$'
            or $ENV{SCRIPT_URL} =~ '/system/cluster/nodes/localhost$')
      )
    {
        # log request if debug is enabled
        my $req_msg = "STATUS: $self->{ code } REQUEST: $ENV{REQUEST_METHOD} $ENV{SCRIPT_URL}";

        # include memory usage if debug is 2 or higher
        $req_msg .= " " . &getMemoryUsage() if &debug() > 0;
        &zenlog($req_msg, "info", $LOG_TAG);

        # log error message on error.
        if (ref $self->{body} eq 'HASH' and exists $self->{body}->{message}) {
            &zenlog("$self->{ body }->{ message }", "info", $LOG_TAG);
        }
    }

    exit;
}

sub httpErrorResponse (@args) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my $args;

    eval { $args = @args == 1 ? shift @args : {@args}; };

    # check errors loading the hash reference
    if ($@) {
        &zenlog($@, "debug", "zapi");
        &zdie("httpErrorResponse: Wrong argument received");
    }

    # verify we have a hash reference
    unless (ref($args) eq 'HASH') {
        &zdie("httpErrorResponse: Argument is not a hash reference.");
    }

    # check required arguments: code, desc and msg
    unless ($args->{code} && $args->{desc} && $args->{msg}) {
        &zdie("httpErrorResponse: Missing required argument");
    }

    # check the status code is in a valid range
    unless ($args->{code} =~ /^4[0-9][0-9]$/) {
        &zdie("httpErrorResponse: Non-supported HTTP status code: $args->{ code }");
    }

    my $body = {
        description => $args->{desc},
        error       => "true",
        message     => $args->{msg},
    };

    my $doc_url = &getGlobalConfiguration('doc_v4_0');
    $body->{documentation} = $doc_url if $doc_url;

    &zenlog("$args->{ desc }: $args->{ msg }", "error", $LOG_TAG);
    &zenlog($args->{log_msg},                  "info",  $LOG_TAG) if exists $args->{log_msg};

    my $response = { code => $args->{code}, body => $body };

    if ($0 =~ m!bin/enterprise\.bin$!) {
        return $response;
    }

    &httpResponse($response);
    return;
}

# WARNING: Function unfinished.
sub httpSuccessResponse ($args) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    unless (ref($args) eq 'HASH') {
        &zdie("httpSuccessResponse: Argument is not a hash reference");
    }

    unless ($args->{code} && $args->{desc} && $args->{msg}) {
        &zdie("httpSuccessResponse: Missing required argument");
    }

    unless ($args->{code} =~ /^2[0-9][0-9]$/) {
        &zdie("httpSuccessResponse: Non-supported HTTP status code: $args->{ code }");
    }

    my $body = {
        description => $args->{desc},
        success     => "true",
        message     => $args->{msg},
    };

    &zenlog($args->{log_msg}, "info", $LOG_TAG) if exists $args->{log_msg};
    &httpResponse({ code => $args->{code}, body => $body });
    return;
}

sub httpDownloadResponse (@args) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my $args;

    eval { $args = @args == 1 ? shift @args : {@args}; };

    # check errors loading the hash reference
    if ($@) {
        &zenlog($@, "debug", "zapi");
        &zdie("httpDownloadResponse: Wrong argument received");
    }

    unless (ref($args) eq 'HASH') {
        &zdie("httpDownloadResponse: Argument is not a hash reference");
    }

    unless ($args->{desc} && $args->{dir} && $args->{file}) {
        &zdie("httpDownloadResponse: Missing required argument");
    }

    unless (-d $args->{dir}) {
        my $msg = "Invalid directory '$args->{ dir }'";
        &httpErrorResponse(code => 400, desc => $args->{desc}, msg => $msg);
    }

    my $path = "$args->{ dir }/$args->{ file }";
    unless (-f $path) {
        my $msg = "The requested file $path could not be found.";
        &httpErrorResponse(code => 400, desc => $args->{desc}, msg => $msg);
    }

    require Relianoid::File;

    my $body = &getFile($path);

    unless (defined $body) {
        my $msg = "Could not open file $path: $!";
        &httpErrorResponse(code => 400, desc => $args->{desc}, msg => $msg);
    }

    # make headers
    my $origin = '*';
    if (!exists $ENV{HTTP_ZAPI_KEY}) {
        $origin =
          (&getGlobalConfiguration('cors_devel_mode') eq "true")
          ? $ENV{HTTP_ORIGIN}
          : "https://$ENV{ HTTP_HOST }";
    }
    my $headers = {
        -type                              => 'application/x-download',
        -attachment                        => $args->{file},
        'Content-length'                   => -s $path,
        'Access-Control-Allow-Origin'      => $origin,
        'Access-Control-Allow-Credentials' => 'true'
    };

    # optionally, remove the downloaded file, useful for temporal files
    unlink $path if $args->{remove} eq 'true';

    &zenlog("[Download] $args->{ desc }: $path", "info", $LOG_TAG);

    &httpResponse({ code => 200, headers => $headers, body => $body });
    return;
}

sub buildAPIParams ($out_b, $api_keys, $translate) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    # Delete not visible params
    if (ref $out_b eq "ARRAY") {
        foreach my $backend (@{$out_b}) {
            &buildBackendAPIParams($backend, $api_keys, $translate);
        }
    }
    elsif (ref $out_b eq "HASH") {
        &buildBackendAPIParams($out_b, $api_keys, $translate);
    }

    return $out_b;
}

sub buildBackendAPIParams ($out_b, $api_keys, $translate) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my @bk_keys = keys(%{$out_b});

    foreach my $param (keys %{$translate}) {
        foreach my $opt (keys %{ $translate->{$param} }) {
            $out_b->{$param} =~ s/$opt/$translate->{$param}->{$opt}/i;
        }
    }

    foreach my $param (@bk_keys) {
        delete $out_b->{$param} if (!grep { /^$param$/ } @{$api_keys});
    }

    if (&debug()) {
        foreach my $param (@{$api_keys}) {
            &zenlog("API parameter $param is missing", 'error', 'API')
              if (!grep { /^$param$/ } @bk_keys);
        }
    }

    return;
}

1;
