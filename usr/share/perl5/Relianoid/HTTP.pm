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

Relianoid::HTTP

=cut

use strict;
use warnings;
use feature qw(signatures);

use Carp;

use Relianoid::API;

my $LOG_TAG = "";
$LOG_TAG = "API"    if get_http_api_key();
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

# Examples of path regexes:
# - Non-capturing: (?^:^/interfaces/nic$)
# - Capturing:     (?^:^/farms/([a-zA-Z0-9\-]+)$)
my $CAPTURING_REGEX = qr{\/.+\(};

sub GET ($path, $code, $mod = undef) {
    return
      unless $ENV{REQUEST_METHOD} eq 'GET'
      or $ENV{REQUEST_METHOD} eq 'HEAD';

    my @captures = ($ENV{PATH_INFO} =~ $path);

    # if @capture is false, there was no match
    return unless @captures;

    # When there is nothing to be captured: @captures = (1)
    # Only attempt to save captured text when there are parenthesis on the url regex '('
    if ($path !~ $CAPTURING_REGEX) {
        @captures = ();
    }

    if (ref $code eq 'CODE') {
        $code->(@captures);
    }
    else {
        &eload(module => $mod, func => $code, args => \@captures) if $eload;
    }
    return;
}

sub POST ($path, $code, $mod = undef) {
    return unless $ENV{REQUEST_METHOD} eq 'POST';

    my @captures = ($ENV{PATH_INFO} =~ $path);

    # if @capture is false, there was no match
    return unless @captures;

    # When there is nothing to be captured: @captures = (1)
    # Only attempt to save captured text when there are parenthesis on the url regex '('
    if ($path !~ $CAPTURING_REGEX) {
        @captures = ();
    }

    require Relianoid::CGI;
    my $data = &getCgiParam('POSTDATA');
    my $input_ref;

    if (exists $ENV{CONTENT_TYPE} && $ENV{CONTENT_TYPE} eq 'application/json' && $data) {
        require JSON;

        $input_ref = eval { JSON::decode_json($data) };

        if (&debug()) {
            &log_debug("json: ${data}", $LOG_TAG);
        }

        if (!$input_ref) {
            my $body = {
                message => 'The body does not look a valid JSON',
                error   => 'true'
            };
            return &httpResponse({ code => 400, body => $body });
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
    elsif ($ENV{PATH_INFO} eq '/session' && !exists $ENV{CONTENT_TYPE} && !$data) {
        # Exception for /session. Allow no content, so content type too.
    }
    else {
        &log_error("Content-Type not supported: $ENV{CONTENT_TYPE}", $LOG_TAG);
        my $body = { message => 'Content-Type not supported', error => 'true' };

        return &httpResponse({ code => 415, body => $body });
    }

    my @args = ($input_ref, @captures);

    # stubborn web gui needs to send no body for POST /session
    if ($ENV{PATH_INFO} eq '/session') {
        @args = ();
    }

    if (ref $code eq 'CODE') {
        $code->(@args);
    }
    else {
        &eload(module => $mod, func => $code, args => \@args) if $eload;
    }

    return;
}

sub PUT ($path, $code, $mod = undef) {
    return unless $ENV{REQUEST_METHOD} eq 'PUT';

    my @captures = ($ENV{PATH_INFO} =~ $path);

    # if @capture is false, there was no match
    return unless @captures;

    # When there is nothing to be captured: @captures = (1)
    # Only attempt to save captured text when there are parenthesis on the url regex '('
    if ($path !~ $CAPTURING_REGEX) {
        @captures = ();
    }

    require Relianoid::CGI;
    my $data = &getCgiParam('PUTDATA');
    my $input_ref;

    if (exists $ENV{CONTENT_TYPE} && $ENV{CONTENT_TYPE} eq 'application/json' && $data) {
        require JSON;

        $input_ref = eval { JSON::decode_json($data) };

        if (&debug()) {
            &log_debug("json: ${data}", $LOG_TAG);
        }

        if (!$input_ref) {
            my $body = {
                message => 'The body does not look a valid JSON',
                error   => 'true'
            };

            return &httpResponse({ code => 400, body => $body });
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
        &log_error("Content-Type not supported: $ENV{CONTENT_TYPE}", $LOG_TAG);
        my $body = { message => 'Content-Type not supported', error => 'true' };

        return &httpResponse({ code => 415, body => $body });
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
    return unless $ENV{REQUEST_METHOD} eq 'DELETE';

    my @captures = ($ENV{PATH_INFO} =~ $path);

    # if @capture is false, there was no match
    return unless @captures;

    # When there is nothing to be captured: @captures = (1)
    # Only attempt to save captured text when there are parenthesis on the url regex '('
    if ($path !~ $CAPTURING_REGEX) {
        @captures = ();
    }

    if (ref $code eq 'CODE') {
        $code->(@captures);
    }
    else {
        &eload(module => $mod, func => $code, args => \@captures) if $eload;
    }

    return;
}

sub OPTIONS ($path, $code) {
    return unless $ENV{REQUEST_METHOD} eq 'OPTIONS';

    my @captures = ($ENV{PATH_INFO} =~ $path);

    # if @capture is false, there was no match
    return unless @captures;

    # When there is nothing to be captured: @captures = (1)
    # Only attempt to save captured text when there are parenthesis on the url regex '('
    if ($path !~ $CAPTURING_REGEX) {
        @captures = ();
    }

    &log_debug("OPTIONS captures( @captures )", $LOG_TAG) if &debug();

    $code->(@captures);

    return;
}

=pod

=head1 httpResponse

Serialize and send to STDOUT API response from data input.

Parameters: hash reference

    code    - HTTP status code digit
    headers - Optional. Hash reference of extra http headers to be included
    body    - Optional. Hash reference with data to be sent as JSON
    type    - Optional. HTTP Content-type header. Example: 'text/plain'

Returns: Nothing

=cut

sub httpResponse ($response) {
    return $response unless exists $ENV{GATEWAY_INTERFACE};

    if (not defined $response or ref $response ne 'HASH') {
        die 'httpResponse: Bad input';
    }

    if (not defined $response->{code} or not exists $http_status_codes{ $response->{code} }) {
        die 'httpResponse: Bad http status code';
    }

    require Relianoid::CGI;

    my $q      = &getCGI();
    my $origin = '*';

    if (my $is_cors_devel_mode_enabled = &getGlobalConfiguration('cors_devel_mode') eq "true") {
        # When CORS devel mode is enabled and an Origin is received
        # the allowed origin is set. Defaults to *.
        if ($ENV{HTTP_ORIGIN}) {
            $origin = $ENV{HTTP_ORIGIN};
        }
    }

    # Headers included in all the responses, any method, any URI, sucess or error
    my %headers = (
        'Access-Control-Allow-Origin'      => $origin,
        'Access-Control-Allow-Credentials' => 'true',
        'Cache-Control'                    => 'no-cache',
        'Expires'                          => '-1',
        'Pragma'                           => 'no-cache',
    );

    # no session info received
    if ($ENV{REQUEST_METHOD} eq 'OPTIONS') {
        $headers{'Access-Control-Allow-Methods'} = 'GET, POST, PUT, DELETE, OPTIONS';
        $headers{'Access-Control-Allow-Headers'} =
          'API_KEY, ZAPI_KEY, Authorization, Set-cookie, Content-Type, X-Requested-With';
    }

    if (exists $ENV{HTTP_COOKIE} && $ENV{HTTP_COOKIE} =~ /CGISESSID/) {
        require Relianoid::HTTP::Auth;

        if (&validCGISession()) {
            my $session        = CGI::Session->load($q);
            my $session_cookie = $q->cookie(CGISESSID => $session->id);

            $headers{'Set-Cookie'}                    = "${session_cookie}; SameSite=None; Secure; HttpOnly";
            $headers{'Access-Control-Expose-Headers'} = "Set-Cookie, Content-Disposition";
        }
    }

    if ($q->path_info =~ '/session') {
        $headers{'Access-Control-Expose-Headers'} = "Set-Cookie";
    }

    if (exists $response->{headers} && ref $response->{headers} eq 'HASH') {
        %headers = (%headers, %{ $response->{headers} });
    }

    if ($response->{body}) {
        my $json_type = 'application/json';

        use Data::Dumper;
        log_debug("Response Headers: " . Dumper \%headers);

        if (not $headers{-type}) {
            $headers{-type} = $response->{type} || $json_type;
        }

        if ($headers{-type} eq $json_type) {
            $headers{-charset} = 'utf-8';
        }
    }

    print $q->header(
        -status => "$response->{code} $http_status_codes{$response->{code}}",
        %headers,
    );

    if ($response->{body}) {
        if (ref $response->{body} eq 'HASH') {
            require JSON;
            require Relianoid::Debug;

            my $canonical = debug();
            my $pretty    = debug();
            my $json      = JSON->new->utf8->pretty($pretty)->canonical([$canonical]);

            print $json->encode($response->{body});
        }
        elsif (ref $response->{body} eq 'GLOB') {
            my $fh = $response->{body};
            binmode $fh;

            local $/ = \4096;
            print while <$fh>;
            close $fh;
        }
        else {
            print $response->{body};
        }
    }

    # avoid logging frequent requests
    my @path_exceptions = ('/stats/system/connections', '/system/cluster/nodes', '/system/cluster/nodes/localhost');
    my $is_exception    = $ENV{REQUEST_METHOD} eq 'GET' && grep { $ENV{PATH_INFO} eq $_ } @path_exceptions;

    if (not $is_exception) {
        # log request if debug is enabled
        my $req_msg = "STATUS: $response->{code} REQUEST: $ENV{REQUEST_METHOD} $ENV{SCRIPT_URL}";

        # include memory usage if debug is 2 or higher
        $req_msg = sprintf("%s %s", $req_msg, &getMemoryUsage()) if &debug();
        &log_info($req_msg, $LOG_TAG);

        # log error message on error.
        if (ref $response->{body} eq 'HASH' and exists $response->{body}{message}) {
            &log_info($response->{body}{message}, $LOG_TAG);
        }
    }

    exit;
}

sub httpErrorResponse ($args) {
    unless (ref($args) eq 'HASH') {
        my $message = "httpErrorResponse: Argument is not a hash reference.";
        &log_info($message);
        carp($message);
    }

    # check required arguments: code, desc and msg
    unless ($args->{code} && $args->{desc} && $args->{msg}) {
        my $message = "httpErrorResponse: Missing required argument";
        &log_info($message);
        carp($message);
    }

    # check the status code is in a valid range
    unless ($args->{code} =~ /^4[0-9][0-9]$/) {
        my $message = "httpErrorResponse: Non-supported HTTP status code: $args->{code}";
        &log_info($message);
        carp($message);
    }

    my $body = {
        description => $args->{desc},
        error       => "true",
        message     => $args->{msg},
    };

    my $doc_url = &getGlobalConfiguration('doc_v4_0');
    $body->{documentation} = $doc_url if $doc_url;

    &log_error("$args->{desc}: $args->{msg}", $LOG_TAG);
    &log_info($args->{log_msg}, $LOG_TAG) if exists $args->{log_msg};

    my $response = { code => $args->{code}, body => $body };

    if ($0 =~ m!bin/enterprise\.bin$!) {
        return $response;
    }

    return &httpResponse($response);
}

sub httpSuccessResponse ($args) {
    unless (ref($args) eq 'HASH') {
        my $message = "httpSuccessResponse: Argument is not a hash reference";
        &log_info($message);
        carp($message);
    }

    unless ($args->{code} && $args->{desc} && $args->{msg}) {
        my $message = "httpSuccessResponse: Missing required argument";
        &log_info($message);
        carp($message);
    }

    unless ($args->{code} =~ /^2[0-9][0-9]$/) {
        my $message = "httpSuccessResponse: Non-supported HTTP status code: $args->{code}";
        &log_info($message);
        carp($message);
    }

    my $body = {
        description => $args->{desc},
        success     => "true",
        message     => $args->{msg},
    };

    &log_info($args->{log_msg}, $LOG_TAG) if exists $args->{log_msg};

    return &httpResponse({ code => $args->{code}, body => $body });
}

=pod

=head1 httpDownloadResponse

Arguments: array | hash

Receives a hash, or an array with hash parameters.

Hash keys:

    desc - string - Description of the API response
    dir  - string - Location of the file
    file - string - File name

Returns: Nothing

=cut

sub httpDownloadResponse (@args) {
    my $args;

    eval { $args = @args == 1 ? shift @args : {@args}; };

    # check errors loading the hash reference
    if ($@) {
        my $message = "httpDownloadResponse: Wrong argument received";
        &log_info($message);
        carp($message);
    }

    unless (ref($args) eq 'HASH') {
        my $message = "httpDownloadResponse: Argument is not a hash reference";
        &log_info($message);
        carp($message);
    }

    unless ($args->{desc} && $args->{dir} && $args->{file}) {
        my $message = "httpDownloadResponse: Missing required argument";
        &log_info($message);
        carp($message);
    }

    unless (-d $args->{dir}) {
        my $msg = "Invalid directory '$args->{dir}'";
        return &httpErrorResponse({ code => 400, desc => $args->{desc}, msg => $msg });
    }

    my $path = "$args->{dir}/$args->{file}";
    unless (-f $path) {
        my $msg = "The requested file $path could not be found.";
        return &httpErrorResponse({ code => 400, desc => $args->{desc}, msg => $msg });
    }

    my $fh;

    unless (open($fh, "<", $path)) { ## no critic (InputOutput::RequireBriefOpen)
        my $msg = "Could not open file $path: $!";
        return &httpErrorResponse({ code => 400, desc => $args->{desc}, msg => $msg });
    }

    my $type    = 'application/x-download';
    my $headers = {
        -type            => $type,
        -attachment      => $args->{file},
        'Content-length' => -s $path,
    };

    &log_info("[Download] $args->{desc}: $path", $LOG_TAG);

    return &httpResponse({ code => 200, headers => $headers, body => $fh, type => $type });
}

1;
