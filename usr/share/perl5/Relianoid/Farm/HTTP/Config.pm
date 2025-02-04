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

require Relianoid::Config;
require Relianoid::Lock;

my $configdir = &getGlobalConfiguration('configdir');

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::Farm::HTTP::Config

=cut

=pod

=head1 setHTTPFarmClientTimeout

Configure the client time parameter for a HTTP farm.

Parameters:

    client   - It is the time in seconds for the client time parameter
    farmname - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setHTTPFarmClientTimeout ($client, $farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @filefarmhttp, 'Tie::File', "$configdir/$farm_filename";

    my $i_f         = -1;
    my $array_count = @filefarmhttp;
    my $found       = "false";

    while ($i_f <= $array_count && $found eq "false") {
        $i_f++;

        if ($filefarmhttp[$i_f] =~ /^Client/) {
            &log_info("setting 'ClientTimeout $client' for $farm_name farm http", "LSLB");
            $filefarmhttp[$i_f] = "Client\t\t $client";
            $output             = 0;
            $found              = "true";
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return $output;
}

=pod

=head1 getHTTPFarmClientTimeout

Return the client time parameter for a HTTP farm.

Parameters:

    farmname - Farm name

Returns:

    Integer - Return the seconds for client request timeout or -1 on failure.

=cut

sub getHTTPFarmClientTimeout ($farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    open my $fh, '<', "${configdir}/${farm_filename}";
    my @file = <$fh>;
    close $fh;

    for my $line (@file) {
        if ($line =~ /^Client\s+.*\d+/) {
            my @line_aux = split("\ ", $line);
            $output = $line_aux[1];
        }
    }

    return $output;
}

=pod

=head1 setHTTPFarmSessionType

Configure type of persistence

Parameters:

    session  - type of session: nothing, HEADER, URL, COOKIE, PARAM, BASIC or IP
    farmname - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setHTTPFarmSessionType ($session, $farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    &log_info("Setting 'Session type $session' for $farm_name farm http", "LSLB");
    tie my @contents, 'Tie::File', "$configdir\/$farm_filename";

    my $i     = -1;
    my $found = "false";

    for my $line (@contents) {
        $i++;

        if ($session ne "nothing") {
            if ($line =~ "Session") {
                $contents[$i] = "\t\tSession";
                $found = "true";
            }

            if ($found eq "true" && $line =~ "End") {
                $contents[$i] = "\t\tEnd";
                $found = "false";
            }

            if ($line =~ "Type") {
                $contents[$i] = "\t\t\tType $session";
                $output = 0;
                $contents[ $i + 1 ] =~ s/#//g;

                if (   $session eq "URL"
                    || $session eq "COOKIE"
                    || $session eq "HEADER")
                {
                    $contents[ $i + 2 ] =~ s/#//g;
                }
                else {
                    if ($contents[ $i + 2 ] !~ /#/) {
                        $contents[ $i + 2 ] =~ s/^/#/;
                    }
                }
            }
        }

        if ($session eq "nothing") {
            if ($line =~ "Session") {
                $contents[$i] = "\t\t#Session $session";
                $found = "true";
            }

            if ($found eq "true" && $line =~ "End") {
                $contents[$i] = "\t\t#End";
                $found = "false";
            }

            if ($line =~ "TTL") {
                $contents[$i] = "#$contents[$i]";
            }

            if ($line =~ "Type") {
                $contents[$i] = "#$contents[$i]";
                $output = 0;
            }

            if ($line =~ "ID") {
                $contents[$i] = "#$contents[$i]";
            }
        }
    }

    untie @contents;
    close $lock_fh;

    return $output;
}

=pod

=head1 setHTTPFarmBlacklistTime

Configure check time for resurected back-end. It is a HTTP farm paramter.

Parameters:

    checktime - time for resurrected checks
    farmname  - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setHTTPFarmBlacklistTime ($blacklist_time, $farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @filefarmhttp, 'Tie::File', "$configdir/$farm_filename";

    my $i_f         = -1;
    my $array_count = @filefarmhttp;
    my $found       = "false";

    while ($i_f <= $array_count && $found eq "false") {
        $i_f++;

        if ($filefarmhttp[$i_f] =~ /^Alive/) {
            &log_info("Setting 'Blacklist time $blacklist_time' for $farm_name farm http", "LSLB");

            $filefarmhttp[$i_f] = "Alive\t\t $blacklist_time";
            $output             = 0;
            $found              = "true";
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return $output;
}

=pod

=head1 getHTTPFarmBlacklistTime

Return time for resurrected checks for a HTTP farm.

Parameters:

    farmname - Farm name

Returns:

    integer - seconds for check or -1 on failure.

=cut

sub getHTTPFarmBlacklistTime ($farm_name) {
    my $blacklist_time = -1;
    my $conf_file      = &getFarmFile($farm_name);
    my $conf_path      = "$configdir/$conf_file";

    open(my $fh, '<', $conf_path) or die "Could not open $conf_path: $!";
    while (my $line = <$fh>) {
        next unless $line =~ /^Alive/i;

        my @line_aux = split("\ ", $line);
        $blacklist_time = $line_aux[1];
        last;
    }
    close $fh;

    return $blacklist_time;
}

=pod

=head1 setHTTPFarmHttpVerb

Configure the accepted HTTP verb for a HTTP farm.

The accepted verb sets are:

    0. standardHTTP, for the verbs GET, POST, HEAD.
    1. extendedHTTP, add the verbs PUT, DELETE.
    2. standardWebDAV, add the verbs LOCK, UNLOCK, PROPFIND, PROPPATCH, SEARCH, MKCOL, MOVE, COPY, OPTIONS, TRACE, MKACTIVITY, CHECKOUT, MERGE, REPORT.
    3. MSextWebDAV, add the verbs SUBSCRIBE, UNSUBSCRIBE, NOTIFY, BPROPFIND, BPROPPATCH, POLL, BMOVE, BCOPY, BDELETE, CONNECT.
    4. MSRPCext, add the verbs RPC_IN_DATA, RPC_OUT_DATA.
    5. OptionsHTTP, add the verb OPTIONS to the set extendedHTTP.

Parameters:

    verb     - accepted verbs: 0, 1, 2, 3 or 4
    farmname - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setHTTPFarmHttpVerb ($verb, $farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @filefarmhttp, 'Tie::File', "$configdir/$farm_filename";

    my $i_f         = -1;
    my $array_count = @filefarmhttp;
    my $found       = "false";

    while ($i_f <= $array_count && $found eq "false") {
        $i_f++;

        if ($filefarmhttp[$i_f] =~ /xHTTP/) {
            &log_info("Setting 'Http verb $verb' for $farm_name farm http", "LSLB");

            $filefarmhttp[$i_f] = "\txHTTP $verb";
            $output             = 0;
            $found              = "true";
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return $output;
}

=pod

=head1 getHTTPFarmHttpVerb

Return the available verb set for a HTTP farm.

The possible verb sets are:

    0. standardHTTP, for the verbs GET, POST, HEAD.
    1. extendedHTTP, add the verbs PUT, DELETE.
    2. standardWebDAV, add the verbs LOCK, UNLOCK, PROPFIND, PROPPATCH, SEARCH, MKCOL, MOVE, COPY, OPTIONS, TRACE, MKACTIVITY, CHECKOUT, MERGE, REPORT.
    3. MSextWebDAV, add the verbs SUBSCRIBE, UNSUBSCRIBE, NOTIFY, BPROPFIND, BPROPPATCH, POLL, BMOVE, BCOPY, BDELETE, CONNECT.
    4. MSRPCext, add the verbs RPC_IN_DATA, RPC_OUT_DATA.
    5. OptionsHTTP, add the verb OPTIONS to the set extendedHTTP.

Parameters:

    farmname - Farm name

Returns:

    integer - return the verb set identier or -1 on failure.

=cut

sub getHTTPFarmHttpVerb ($farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    open my $fh, '<', "${configdir}/${farm_filename}";
    my @file = <$fh>;
    close $fh;

    for my $line (@file) {
        if ($line =~ /xHTTP/) {
            my @line_aux = split("\ ", $line);
            $output = $line_aux[1];
        }
    }

    return $output;
}

=pod

=head1 setHTTPFarmListen

Change a HTTP farm between HTTP and HTTPS listener

Parameters:

    farmname - Farm name
    listener - type of listener: http or https

Returns:

    none

FIXME

    not return nothing, use $found variable to return success or error

=cut

sub setHTTPFarmListen ($farm_name, $listener) {
    my $farm_filename = &getFarmFile($farm_name);
    my $i_f           = -1;

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @filefarmhttp, 'Tie::File', "$configdir/$farm_filename";
    my $array_count = @filefarmhttp;

    while ($i_f <= $array_count) {
        $i_f++;
        if ($filefarmhttp[$i_f] =~ /^ListenHTTP/ && $listener eq "http") {
            $filefarmhttp[$i_f] = "ListenHTTP";
        }
        if ($filefarmhttp[$i_f] =~ /^ListenHTTP/ && $listener eq "https") {
            $filefarmhttp[$i_f] = "ListenHTTPS";
        }

        if ($filefarmhttp[$i_f] =~ /.*Cert\ \"/ && $listener eq "http") {
            $filefarmhttp[$i_f] =~ s/Cert\ \"/#Cert\ \"/;
        }
        if ($filefarmhttp[$i_f] =~ /.*Cert\ \"/ && $listener eq "https") {
            $filefarmhttp[$i_f] =~ s/#//g;
        }

        if ($filefarmhttp[$i_f] =~ /.*Ciphers\ \"/ && $listener eq "http") {
            $filefarmhttp[$i_f] =~ s/Ciphers\ \"/#Ciphers\ \"/;
        }
        if ($filefarmhttp[$i_f] =~ /.*Ciphers\ \"/ && $listener eq "https") {
            $filefarmhttp[$i_f] =~ s/#//g;
        }

        # Enable 'Disable TLSv1, TLSv1_1 or TLSv1_2'
        if ($filefarmhttp[$i_f] =~ /.*Disable TLSv1/ && $listener eq "http") {
            $filefarmhttp[$i_f] =~ s/Disable TLSv1/#Disable TLSv1/;
        }
        if ($filefarmhttp[$i_f] =~ /.*Disable TLSv1/ && $listener eq "https") {
            $filefarmhttp[$i_f] =~ s/#//g;
        }
        elsif ($filefarmhttp[$i_f] =~ /.*DisableTLSv1\d$/ && $listener eq "https") {
            $filefarmhttp[$i_f] =~ s/#//g;
        }

        # Enable 'Disable SSLv3 or SSLv2'
        if ($filefarmhttp[$i_f] =~ /.*Disable SSLv\d$/ && $listener eq "http") {
            $filefarmhttp[$i_f] =~ s/Disable SSLv/#Disable SSLv/;
        }
        if ($filefarmhttp[$i_f] =~ /.*Disable SSLv\d$/ && $listener eq "https") {
            $filefarmhttp[$i_f] =~ s/#//g;
        }
        elsif ($filefarmhttp[$i_f] =~ /.*DisableSSLv\d$/ && $listener eq "https") {
            $filefarmhttp[$i_f] =~ s/#//g;
        }

        # Enable SSLHonorCipherOrder
        if ($filefarmhttp[$i_f] =~ /.*SSLHonorCipherOrder/ && $listener eq "http") {
            $filefarmhttp[$i_f] =~ s/SSLHonorCipherOrder/#SSLHonorCipherOrder/;
        }
        if ($filefarmhttp[$i_f] =~ /.*SSLHonorCipherOrder/ && $listener eq "https") {
            $filefarmhttp[$i_f] =~ s/#//g;
        }

        # Enable StrictTransportSecurity
        if ($filefarmhttp[$i_f] =~ /.*StrictTransportSecurity/ && $listener eq "http") {
            $filefarmhttp[$i_f] =~ s/StrictTransportSecurity/#StrictTransportSecurity/;
        }
        if ($filefarmhttp[$i_f] =~ /.*StrictTransportSecurity/ && $listener eq "https") {
            $filefarmhttp[$i_f] =~ s/#//g;
        }

        # Check for ECDHCurve cyphers
        if ($filefarmhttp[$i_f] =~ /ECDHCurve/ && $listener eq "http") {
            $filefarmhttp[$i_f] =~ s/ECDHCurve/\#ECDHCurve/;
        }
        if ($filefarmhttp[$i_f] =~ /ECDHCurve/ && $listener eq "https") {
            $filefarmhttp[$i_f] =~ s/#ECDHCurve/ECDHCurve/;
        }

        # Generate DH Keys if needed
        #my $dhfile = "$configdir\/$farm_name\_dh2048.pem";
        if ($filefarmhttp[$i_f] =~ /^\#*DHParams/ && $listener eq "http") {
            $filefarmhttp[$i_f] =~ s/.*DHParams/\#DHParams/;
        }
        if ($filefarmhttp[$i_f] =~ /^\#*DHParams/ && $listener eq "https") {
            $filefarmhttp[$i_f] =~ s/.*DHParams/DHParams/;
            #$filefarmhttp[$i_f] =~ s/.*DHParams.*/DHParams\t"$dhfile"/;
        }

        if ($filefarmhttp[$i_f] =~ /ZWACL-END/) {
            last;
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return;
}

=pod

=head1 setHTTPFarmRewriteL

Asign a RewriteLocation vaue to a farm HTTP or HTTPS

Parameters:

    farmname - Farm name

    rewritelocation - The options are: disabled, enabled or enabled-backends

Returns: Integer. Error code.

    0 - success
    1 - failure

=cut

sub setHTTPFarmRewriteL ($farm_name, $rewritelocation, $path = undef) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = 1;

    &log_info("setting 'Rewrite Location' for $farm_name to $rewritelocation", "LSLB");

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @filefarmhttp, 'Tie::File', "$configdir/$farm_filename";
    my $i_f         = -1;
    my $array_count = @filefarmhttp;

    while ($i_f <= $array_count) {
        $i_f++;
        if ($filefarmhttp[$i_f] =~ /RewriteLocation\ .*/) {
            my $directive = "\tRewriteLocation $rewritelocation";
            $directive .= " path" if ($path);
            $filefarmhttp[$i_f] = $directive;
            $output = 0;
            last;
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return $output;
}

=pod

=head1 getHTTPFarmRewriteL

Return RewriteLocation Header configuration HTTP and HTTPS farms

Parameters:

    farmname - Farm name

Returns:

    string - The possible values are: 

    - disabled (default)
    - enabled
    - enabled-backends
    - enabled-path
    - enabled-backends-path

=cut

sub getHTTPFarmRewriteL ($farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = "disabled";

    open my $fh, '<', "${configdir}/${farm_filename}";
    my @file = <$fh>;
    close $fh;

    for my $line (@file) {
        if ($line =~ /RewriteLocation\s+(\d)\s*(path)?/) {
            if    ($1 eq 0) { $output = "disabled"; last; }
            elsif ($1 eq 1) { $output = "enabled"; }
            elsif ($1 eq 2) { $output = "enabled-backends"; }

            if (defined $2 and $2 eq 'path') { $output .= "-path"; }
            last;
        }
    }
    return $output;
}

=pod

=head1 setHTTPFarmConnTO

Configure connection time out value to a farm HTTP or HTTPS

Parameters:

    connectionTO - Conection time out in seconds

    farmname - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setHTTPFarmConnTO ($tout, $farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    &log_info("Setting 'ConnTo timeout $tout' for $farm_name farm http", "LSLB");

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @filefarmhttp, 'Tie::File', "$configdir/$farm_filename";

    my $i_f         = -1;
    my $array_count = @filefarmhttp;
    my $found       = "false";

    while ($i_f <= $array_count && $found eq "false") {
        $i_f++;

        if ($filefarmhttp[$i_f] =~ /^ConnTO.*/) {
            $filefarmhttp[$i_f] = "ConnTO\t\t $tout";
            $output             = 0;
            $found              = "true";
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return $output;
}

=pod

=head1 getHTTPFarmConnTO

Return farm connecton time out value for http and https farms

Parameters:

    farmname - Farm name

Returns:

    integer - return the connection time out or -1 on failure

=cut

sub getHTTPFarmConnTO ($farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    open my $fh, '<', "${configdir}/${farm_filename}";
    my @file = <$fh>;
    close $fh;

    for my $line (@file) {
        if ($line =~ /^ConnTO/) {
            my @line_aux = split("\ ", $line);
            $output = $line_aux[1];
        }
    }

    return $output;
}

=pod

=head1 setHTTPFarmTimeout

Asign a timeout value to a farm

Parameters:

    timeout - Time out in seconds

    farmname - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setHTTPFarmTimeout ($timeout, $farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @filefarmhttp, 'Tie::File', "$configdir/$farm_filename";

    my $i_f         = -1;
    my $array_count = @filefarmhttp;
    my $found       = "false";

    while ($i_f <= $array_count && $found eq "false") {
        $i_f++;

        if ($filefarmhttp[$i_f] =~ /^Timeout/) {
            $filefarmhttp[$i_f] = "Timeout\t\t $timeout";
            $output             = 0;
            $found              = "true";
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return $output;
}

=pod

=head1 getHTTPFarmTimeout

Return the farm time out

Parameters:

    farmname - Farm name

Returns:

    Integer - Return time out, or -1 on failure.

=cut

sub getHTTPFarmTimeout ($farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    open my $fh, '<', "${configdir}/${farm_filename}";
    my @file = <$fh>;

    for my $line (@file) {
        if ($line =~ /^Timeout/) {
            my @line_aux = split("\ ", $line);
            $output = $line_aux[1];
        }
    }
    close $fh;

    return $output;
}

=pod

=head1 setHTTPFarmMaxClientTime

Set the maximum time for a client

Parameters:

    track     - Maximum client time
    farm_name - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setHTTPFarmMaxClientTime ($track, $farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;
    my $i_f           = -1;
    my $found         = "false";

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    tie my @filefarmhttp, 'Tie::File', "$configdir/$farm_filename";
    my $array_count = @filefarmhttp;

    while ($i_f <= $array_count && $found eq "false") {
        $i_f++;
        if ($filefarmhttp[$i_f] =~ /TTL/) {
            $filefarmhttp[$i_f] = "\t\t\tTTL $track";
            $output             = 0;
            $found              = "true";
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return $output;
}

=pod

=head1 getHTTPFarmGlobalStatus

Get the status of a farm, sessions and its backends through l7 proxy command.

Parameters:

    farmname - Farm name

Returns:

    array - Return poundctl output

=cut

sub getHTTPFarmGlobalStatus ($farm_name) {
    my $poundctl = &getGlobalConfiguration('poundctl');

    return @{ &logAndGet("$poundctl -c \"/tmp/$farm_name\_proxy.socket\"", "array") };
}

=pod

=head1 setHTTPFarmErr

Configure a error message for http error: WAF, 414, 500, 501 or 503

Parameters:

    farm_name - Farm name
    message   - Message body for the error
    error     - Number of error to set, the options are WAF, 414, 500, 501 or 503

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setHTTPFarmErr ($farm_name, $content, $error) {
    my $output = -1;

    if (not $error) {
        log_error("Setting undefined HTTP Err");
        return $output;
    }

    &log_info("Setting 'Err$error' for $farm_name farm http", "LSLB");

    my $file_path = "${configdir}/${farm_name}_Err${error}.html";

    if (-e $file_path) {
        $output = 0;
        # FIXME
        # $content =~ s/\r\n/\n/;
        # my $fd  = &openlock($file_path, 'w');
        # print $fd "$line\n";
        # close $fd;
        my @err = split("\n", $content);
        my $fd  = &openlock($file_path, 'w');

        for my $line (@err) {
            $line =~ s/\r$//;
            print $fd "$line\n";
        }

        close $fd;
    }

    return $output;
}

=pod

=head1 getHTTPFarmErr

Return the error message for a http error: WAF, 414, 500, 501 or 503

Parameters:

    farmname - Farm name

    error_number - Number of error to set, the options are WAF, 414, 500, 501 or 503

Returns:

    string - Message body for the error

=cut

# Only http function
sub getHTTPFarmErr ($farm_name, $nerr) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output;

    open my $fh, '<', "${configdir}/${farm_filename}";
    my @file = <$fh>;
    close $fh;

    for my $line (@file) {
        if ($line =~ /Err$nerr/) {
            my @line_aux = split("\ ", $line);
            my $err      = $line_aux[1];
            $err =~ s/"//g;

            if (-e $err) {
                open my $fh, '<', $err;
                while (<$fh>) {
                    $output .= $_;
                }
                close $fh;
                chomp($output);
            }
        }
    }

    return $output;
}

=pod

=head1 setHTTPFarmConfErrFile

Comment or uncomment an error config file line from the proxy config file.

Parameters:

    enabled

        - true to uncomment the line ( or to add if it doesn't exist)
        - false to comment the line.

    farmname - Farm name

    err - error file: WAF, 414, 500 ...

Returns:

    None

=cut

sub setHTTPFarmConfErrFile ($enabled, $farm_name, $err) {
    require Relianoid::Farm::Core;
    require Tie::File;

    my $farm_filename = &getFarmFile($farm_name);
    my $i             = -1;
    my $found         = 0;

    tie my @filefarmhttp, 'Tie::File', "$configdir/$farm_filename";

    for my $line (@filefarmhttp) {
        $i++;
        if ($enabled eq "true") {
            if ($line =~ /^.*Err$err/) {
                $line =~ s/#//;
                splice @filefarmhttp, $i, 1, $line;
                $found = 1;
                last;
            }
        }
        else {
            if ($line =~ /^\s*Err$err/) {
                splice @filefarmhttp, $i, 1;
                last;
            }
        }
    }
    if (!$found && $enabled eq "true") {
        $i = -1;
        for my $line (@filefarmhttp) {
            $i++;
            if ($line =~ /^ListenHTTP/) {
                my $directive = "\tErr$err \"$configdir" . "/" . $farm_name . "_Err$err.html\"";
                splice @filefarmhttp, $i + 1, 0, $directive;
                last;
            }
        }
    }
    untie @filefarmhttp;

    return;
}

=pod

=head1 getHTTPFarmBootStatus

Return the farm status at boot relianoid

Parameters:

    farmname - Farm name

Returns:

    scalar - return "down" if the farm not run at boot or "up" if the farm run at boot

=cut

sub getHTTPFarmBootStatus ($farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = "down";
    my $lastline;

    open my $fh, '<', "${configdir}/${farm_filename}";

    while (my $line = <$fh>) {
        $lastline = $line;
    }
    close $fh;

    if ($lastline !~ /^#down/) {
        $output = "up";
    }

    return $output;
}

=pod

=head1 setHTTPFarmBootStatus

Set the farm status in the configuration file to boot relianoid process

Parameters:

    farm_name - Farm name
    value - Write the boot status "up" or "down"

Returns:

    scalar - return "down" if the farm not run at boot or "up" if the farm run at boot

=cut

sub setHTTPFarmBootStatus ($farm_name, $value) {
    my $farm_filename = &getFarmFile($farm_name);

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @configfile, 'Tie::File', "$configdir\/$farm_filename";
    @configfile = grep { !/^\#down/ } @configfile;

    push @configfile, '#down' if ($value eq "down");

    untie @configfile;
    close $lock_fh;

    return;
}

=pod

=head1 getHTTPFarmStatus

Return current farm process status

Parameters:

    farm_name - Farm name

Returns: string - Whether the process is running, with "up" or "down".

=cut

sub getHTTPFarmStatus ($farm_name) {
    my @pid         = &getHTTPFarmPid($farm_name);
    my $running_pid = @pid ? kill(0, @pid) : undef;

    return (@pid && $running_pid) ? "up" : "down";
}

=pod

=head1 getHTTPFarmSocket

Returns socket for HTTP farm.

This funcion is only used in farmguardian functions.

Parameters:

    farmname - Farm name

Returns:

    String - return socket file

=cut

sub getHTTPFarmSocket ($farm_name) {
    return "/tmp/" . $farm_name . "_proxy.socket";
}

=pod

=head1 getHTTPFarmPid

Returns farm PID

Parameters:

    farmname - Farm name

Returns:

    Integer - return a list with the PIDs of the farm

=cut

sub getHTTPFarmPid ($farm_name) {
    my $piddir  = &getGlobalConfiguration('piddir');
    my $pidfile = "$piddir\/$farm_name\_proxy.pid";

    my @pid = ();
    if (-e $pidfile) {
        open my $fh, '<', $pidfile;
        @pid = <$fh>;
        close $fh;
    }

    return @pid;
}

=pod

=head1 getHTTPFarmPidPound

This function returns all the pids of a process looking for in the ps table.

Parameters:

    farmname - Farm name

Returns:

    array - list of pids

=cut

sub getHTTPFarmPidPound ($farm_name) {
    my $ps        = &getGlobalConfiguration('ps');
    my $grep      = &getGlobalConfiguration('grep_bin');
    my @pid       = ();
    my $farm_file = "$configdir/" . &getFarmFile($farm_name);
    my $cmd       = "$ps aux | $grep '\\-f $farm_file' | $grep -v grep";

    my $out = &logAndGet($cmd, 'array');
    for my $l (@{$out}) {
        if ($l =~ /^\s*[^\s]+\s+([^\s]+)\s/) {
            push @pid, $1;
        }
    }

    return @pid;
}

=pod

=head1 getHTTPFarmPidFile

Returns farm PID File

Parameters:

    farmname - Farm name

Returns:

    String - Pid file path

=cut

sub getHTTPFarmPidFile ($farm_name) {
    my $piddir  = &getGlobalConfiguration('piddir');
    my $pidfile = "$piddir\/$farm_name\_proxy.pid";

    return $pidfile;
}

=pod

=head1 getHTTPFarmVip

Returns farm vip or farm port

Parameters:

    tag - requested parameter. The options are 
          - vip, for virtual ip
          - vipp, for virtual port

    farmname - Farm name

Returns:

    Scalar - return vip or port of farm or -1 on failure

=cut

sub getHTTPFarmVip ($info, $farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;
    my $i             = 0;
    my $lw            = 0;

    open my $fh, '<', "${configdir}/${farm_filename}";
    my @file = <$fh>;
    close $fh;

    for my $line (@file) {
        if ($line =~ /^ListenHTTP/) {
            $lw = 1;
        }
        if ($lw) {
            if ($info eq "vip" && $line =~ /^\s+Address\s+(.*)/) {
                $output = $1;
            }

            if ($info eq "vipp" && $line =~ /^\s+Port\s+(.*)/) { $output = $1 }

            last if ($output ne '-1');
        }
        $i++;
    }

    return $output;
}

=pod

=head1 setHTTPFarmVirtualConf

Set farm virtual IP and virtual PORT

Parameters:

    vip - virtual ip
    vip_port - virtual port. If the port is not sent, the port will not be changed
    farm_name - Farm name

Returns:

    Integer - return 0 on success or different on failure

=cut

sub setHTTPFarmVirtualConf ($vip, $vip_port, $farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $stat          = 1;
    my $enter         = 2;
    $enter-- if !$vip_port;

    my $prev_config = getFarmStruct($farm_name);

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @array, 'Tie::File', "$configdir\/$farm_filename";
    my $size = @array;

    for (my $i = 0 ; $i < $size && $enter > 0 ; $i++) {
        if ($array[$i] =~ /Address/) {
            if ($array[$i] =~ s/.*Address\ .*/\tAddress\ $vip/) {
                $stat = 0;
            }
            $enter--;
        }
        if ($array[$i] =~ /Port/ and $vip_port) {
            if ($array[$i] =~ s/.*Port\ .*/\tPort\ $vip_port/) {
                $stat = 0;
            }
            $enter--;
        }
        last if (!$enter);
    }

    untie @array;
    close $lock_fh;

    return $stat;
}

=pod

=head1 getHTTPFarmConfigIsOK

Function that check if the config file is OK.

Parameters:

    farmname - Farm name

Returns:

    scalar - return 0 on success or different on failure

=cut

sub getHTTPFarmConfigIsOK ($farm_name) {
    my $pound         = &getGlobalConfiguration('pound');
    my $farm_filename = &getFarmFile($farm_name);
    my $farm_filepath = "${configdir}/${farm_filename}";
    my $proxy_command = "${pound} -f ${farm_filepath} -c";

    # do not use the function 'logAndGet' here is managing the error output and error code
    my $run = `$proxy_command 2>&1`;
    my $rc  = $?;

    if ($rc or &debug()) {
        if ($rc) {
            &log_error("failed: $proxy_command", "LSLB");
        }
        else {
            &log_debug("running: $proxy_command", "LSLB");
        }

        if ($run =~ / line (\d+)/) {
            my $line_number = $1;
            my $line        = `sed -n '$line_number p' ${farm_filepath}`;

            log_error("${farm_filepath} line $line_number: $line");
        }
    }

    return $rc;
}

=pod

=head1 getHTTPFarmConfigErrorMessage

This function return a message to know what parameter is not correct in a HTTP farm

Parameters:

    farm_name - Farm name

Returns:

    Scalar - If there is an error, it returns a message, else it returns a blank string

=cut

sub getHTTPFarmConfigErrorMessage ($farm_name) {
    my $pound         = &getGlobalConfiguration('pound');
    my $farm_filename = &getFarmFile($farm_name);
    my $farm_filepath = "${configdir}/${farm_filename}";
    my $proxy_command = "${pound} -f ${farm_filepath} -c";

    # do not use the function 'logAndGet' here is managing the error output and error code
    my @run = `$proxy_command 2>&1`;

    return "" if $? == 0;

    chomp @run;
    shift @run if ($run[0] =~ /starting\.\.\./);

    &log_error("Error checking ${farm_filepath}.", "LSLB");
    &log_error($run[0],                            "LSLB");

    $run[0] = $run[1] if ($run[0] =~ /waf/i);
    $run[0] =~ / line (\d+): /;
    my $error_line_number = $1;

    my $current_line_number = 1;
    my $line                = "";
    my $service             = "";

    if ($error_line_number && open my $fh, '<', $farm_filepath) {
        my @lines = <$fh>;
        close $fh;

        for my $current_line (@lines) {
            if ($line =~ /^\s+Service \"(.+)\"/) {
                $service = $1;
            }

            if ($current_line_number == $error_line_number) {
                $line = $current_line;
                last;
            }

            $current_line_number++;
        }
    }

    # examples of error msg
    #	AAAhttps, /usr/local/relianoid/config/AAAhttps_proxy.cfg line 36: unknown directive
    #	AAAhttps, /usr/local/relianoid/config/AAAhttps_proxy.cfg line 40: SSL_CTX_use_PrivateKey_file failed - aborted
    $line =~ /\s*([\w-]+)/;
    my $param = $1;
    my $msg   = "Error in the configuration file";

    # parse line
    if ($param eq "Cert") {
        # return pem name if the pem file is not correct
        $line =~ /([^\/]+)\"$/;
        $msg = "Error loading the certificate: $1" if $1;
    }
    elsif ($param eq "WafRules") {
        # return waf rule name  if the waf rule file is not correct
        $line =~ /([^\/]+)\"$/;
        $msg = "Error loading the WafRuleSet: $1" if $1;
    }
    elsif ($param) {
        $service = "in the service ${service}" if $service;
        $msg     = "Error in the parameter ${param} ${service}";
    }
    elsif (&debug()) {
        $msg = $run[0];
        log_error("${farm_filepath} line $error_line_number: $line");
    }

    &log_debug("Error checking config file: $msg");

    return $msg;
}

=pod

=head1 getHTTPFarmStruct

=cut

sub getHTTPFarmStruct ($farmname, $type = undef) {
    $type //= &getFarmType($farmname);

    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    # Output hash reference or undef if the farm does not exist.
    my $farm;

    return $farm unless $farmname;

    my $vip    = &getFarmVip("vip",  $farmname);
    my $vport  = &getFarmVip("vipp", $farmname) + 0;
    my $status = &getFarmVipStatus($farmname);

    my $connto              = 0 + &getHTTPFarmConnTO($farmname);
    my $alive               = 0 + &getHTTPFarmBlacklistTime($farmname);
    my $timeout             = 0 + &getHTTPFarmTimeout($farmname);
    my $client              = 0 + &getHTTPFarmClientTimeout($farmname);
    my $httpverb            = 0 + &getHTTPFarmHttpVerb($farmname);
    my $rewritelocation     = &getHTTPFarmRewriteL($farmname);
    my $logs                = &getHTTPFarmLogs($farmname);
    my $ignore_100_continue = &getHTTPFarm100Continue($farmname);

    # my $errWAF = &getHTTPFarmErr($farmname, "WAF");
    my $err414 = &getHTTPFarmErr($farmname, "414");
    my $err500 = &getHTTPFarmErr($farmname, "500");
    my $err501 = &getHTTPFarmErr($farmname, "501");
    my $err503 = &getHTTPFarmErr($farmname, "503");

    my @http_verbs = (
        "standardHTTP",      #0
        "extendedHTTP",      #1
        "standardWebDAV",    #2
        "MSextWebDAV",       #3
        "MSRPCext",          #4
        "optionsHTTP",       #5
    );

    $farm = {
        contimeout          => $connto,
        error414            => $err414,
        error500            => $err500,
        error501            => $err501,
        error503            => $err503,
        httpverb            => $http_verbs[$httpverb],
        ignore_100_continue => $ignore_100_continue,
        listener            => $type,
        logs                => $logs,
        name                => $farmname,
        reqtimeout          => $client,
        restimeout          => $timeout,
        resurrectime        => $alive,
        rewritelocation     => $rewritelocation,
        status              => $status,
        vip                 => $vip,
        vport               => $vport,
    };

    # HTTPS parameters
    if ($type eq "https") {
        require Relianoid::Farm::HTTP::HTTPS;

        ## Get farm certificate(s)
        my @cnames = ();

        if ($eload) {
            @cnames = &eload(
                module => 'Relianoid::EE::Farm::HTTP::HTTPS::Ext',
                func   => 'getFarmCertificatesSNI',
                args   => [$farmname],
            );
        }
        else {
            @cnames = (&getFarmCertificate($farmname));
        }

        # Make struct array
        my @cert_list;

        for (my $i = 0 ; $i < scalar @cnames ; $i++) {
            push @cert_list, { file => $cnames[$i], id => $i + 1 };
        }

        ## Get cipher set
        my $ciphers = &getFarmCipherSet($farmname);

        # adapt "ciphers" to required interface values
        if ($ciphers eq "cipherglobal") {
            $ciphers = "all";
        }
        elsif ($ciphers eq "cipherssloffloading") {
            $ciphers = "ssloffloading";
        }
        elsif ($ciphers eq "cipherpci") {
            $ciphers = "highsecurity";
        }
        else {
            $ciphers = "customsecurity";
        }

        ## All HTTPS parameters
        $farm->{certlist}        = \@cert_list;
        $farm->{ciphers}         = $ciphers;
        $farm->{cipherc}         = &getFarmCipherList($farmname);
        $farm->{disable_sslv2}   = (&getHTTPFarmDisableSSL($farmname, "SSLv2"))   ? "true" : "false";
        $farm->{disable_sslv3}   = (&getHTTPFarmDisableSSL($farmname, "SSLv3"))   ? "true" : "false";
        $farm->{disable_tlsv1}   = (&getHTTPFarmDisableSSL($farmname, "TLSv1"))   ? "true" : "false";
        $farm->{disable_tlsv1_1} = (&getHTTPFarmDisableSSL($farmname, "TLSv1_1")) ? "true" : "false";
        $farm->{disable_tlsv1_2} = (&getHTTPFarmDisableSSL($farmname, "TLSv1_2")) ? "true" : "false";
    }

    require Relianoid::Farm::Config;
    $farm = &getHTTPFarmHeadersStruct($farmname, $farm);

    return $farm;
}

=pod

=head1 getHTTPFarmVerbCode

=cut

sub getHTTPFarmVerbCode ($verbs_set) {
    # Default output value in case of missing verb set
    my $verb_code;

    my %http_verbs = (
        standardHTTP   => 0,
        extendedHTTP   => 1,
        standardWebDAV => 2,
        MSextWebDAV    => 3,
        MSRPCext       => 4,
        optionsHTTP    => 5,
    );

    if (exists $http_verbs{$verbs_set}) {
        $verb_code = $http_verbs{$verbs_set};
    }

    return $verb_code;
}

######### l7 proxy Config

# Writing

# add header

=pod

=head1 getHTTPAddReqHeader

Get a list with all the http headers are added by the farm

Parameters:

    farm_name - Farm name

Returns:

    Array ref - headers list

=cut

sub getHTTPAddReqHeader ($farm_name) {
    return &getHTTPFarmHeadersStruct($farm_name)->{addheader};
}

=pod

=head1 addHTTPAddheader

The HTTP farm will add the header to the http communication

Parameters:

    farm_name - Farm name
    header - Header to add

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub addHTTPAddheader ($farm_name, $header) {
    require Relianoid::Farm::Core;
    require Relianoid::Lock;

    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index        = 0;
    my $rewrite_flag = 0;    # it is used to add HeadRemove before than AddHeader

    for my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /[#\s]*RewriteLocation/) {
            $rewrite_flag = 1;
        }
        elsif ($rewrite_flag) {
            # put new headremove before than last one
            if (    $line !~ /^[#\s]*(?:AddHeader|HeadRemove|AddResponseHeader|RemoveResponseHead)\s+"/
                and $rewrite_flag)

            {
                # example: AddHeader "header: to add"
                splice @fileconf, $index, 0, "\tAddHeader \"$header\"";
                $errno = 0;
                last;
            }
        }
        $index++;
    }
    untie @fileconf;

    &log_info("Could not add AddHeader") if $errno;

    return $errno;
}

=pod

=head1 modifyHTTPAddheader

Modify an AddHeader directive from the given farm

Parameters:

    farm_name   - Farm name
    header      - Header to add
    header_ind  - directive index

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub modifyHTTPAddheader ($farm_name, $header, $header_ind) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index = 0;
    my $ind   = 0;
    for my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /^\s*AddHeader\s+"/) {
            # put new headremove before than last one
            if ($header_ind == $ind) {
                splice @fileconf, $index, 1, "\tAddHeader \"$header\"";
                $errno = 0;
                last;
            }
            else {
                $ind++;
            }
        }
        $index++;
    }
    untie @fileconf;

    &log_info("Could not modify AddHeader") if $errno;

    return $errno;
}

=pod

=head1 delHTTPAddheader

Delete a directive "AddHeader".

Parameters:

    farm_name  - Farm name
    header_ind - Header index

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub delHTTPAddheader ($farm_name, $header_ind) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index = 0;
    my $ind   = 0;
    for my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /^\s*AddHeader\s+"/) {
            if ($header_ind == $ind) {
                $errno = 0;
                splice @fileconf, $index, 1;
                last;
            }
            else {
                $ind++;
            }
        }
        $index++;
    }
    untie @fileconf;

    &log_info("Could not remove HeadRemove") if $errno;

    return $errno;
}

# head remove

=pod

=head1 getHTTPRemReqHeader

Get a list with all the http headers are added by the farm

Parameters:

    farm_name - Farm name

Returns:

    Array ref - headers list

=cut

sub getHTTPRemReqHeader ($farm_name) {
    return &getHTTPFarmHeadersStruct($farm_name)->{headremove};
}

=pod

=head1 addHTTPHeadremove

Add a directive "HeadRemove". The HTTP farm will remove the header that match with the sentence

Parameters:

    farm_name - Farm name
    header   - Header to add

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub addHTTPHeadremove ($farm_name, $header) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index        = 0;
    my $rewrite_flag = 0;    # it is used to add HeadRemove before than AddHeader
    for my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /[#\s]*RewriteLocation/) {
            $rewrite_flag = 1;
        }
        elsif ($rewrite_flag) {
            # put new headremove after than last one
            if (    $line !~ /^[#\s]*(?:AddHeader|HeadRemove|AddResponseHeader|RemoveResponseHead)\s+"/
                and $rewrite_flag)
            {
                # example: AddHeader "header: to add"
                splice @fileconf, $index, 0, "\tHeadRemove \"$header\"";
                $errno = 0;
                last;
            }
        }
        $index++;
    }
    untie @fileconf;

    &log_info("Could not add HeadRemove") if $errno;

    return $errno;
}

=pod

=head1 modifyHTTPHeadremove

Modify an Headremove directive from the given farm

Parameters:

    farm_name    - Farm name
    header      - Header to add
    header_ind  - directive index

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub modifyHTTPHeadremove ($farm_name, $header, $header_ind) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index = 0;
    my $ind   = 0;
    for my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /^\s*HeadRemove\s+"/) {
            # put new headremove before than last one
            if ($header_ind == $ind) {
                splice @fileconf, $index, 1, "\tHeadRemove \"$header\"";
                $errno = 0;
                last;
            }
            else {
                $ind++;
            }
        }
        $index++;
    }
    untie @fileconf;

    &log_info("Could not modify HeadRemove") if $errno;

    return $errno;
}

=pod

=head1 delHTTPHeadremove

Delete a directive "HeadRemove".

Parameters:

    farm_name - Farm name
    index    - Header index

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub delHTTPHeadremove ($farm_name, $header_ind) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index = 0;
    my $ind   = 0;
    for my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /^\s*HeadRemove\s+"/) {
            if ($header_ind == $ind) {
                $errno = 0;
                splice @fileconf, $index, 1;
                last;
            }
            else {
                $ind++;
            }
        }
        $index++;
    }
    untie @fileconf;

    &log_info("Could not remove HeadRemove") if $errno;

    return $errno;
}

# add response header

=pod

=head1 getHTTPAddRespHeader

Get a list with all the http headers that load balancer will add to the backend repsonse

Parameters:

    farm_name - Farm name

Returns:

    Array ref - headers list

=cut

sub getHTTPAddRespHeader ($farm_name) {
    return &getHTTPFarmHeadersStruct($farm_name)->{addresponseheader};
}

=pod

=head1 addHTTPAddRespheader

The HTTP farm will add the header to the http response from the backend to the client

Parameters:

    farm_name - Farm name
    header   - Header to add

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub addHTTPAddRespheader ($farm_name, $header) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index        = 0;
    my $rewrite_flag = 0;    # it is used to add HeadRemove before than AddHeader
    for my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /[#\s]*RewriteLocation/) {
            $rewrite_flag = 1;
        }
        elsif ($rewrite_flag) {
            # put new headremove before than last one
            if (    $line !~ /^[#\s]*(?:AddHeader|HeadRemove|AddResponseHeader|RemoveResponseHead)\s+"/
                and $rewrite_flag)
            {
                # example: AddHeader "header: to add"
                splice @fileconf, $index, 0, "\tAddResponseHeader \"$header\"";
                $errno = 0;
                last;
            }
        }
        $index++;
    }
    untie @fileconf;

    &log_info("Could not add AddResponseHeader") if $errno;

    return $errno;
}

=pod

=head1 modifyHTTPAddRespheader

Modify an AddResponseHeader directive from the given farm

Parameters:

    farm_name   - Farm name
    header      - Header to add
    header_ind  - directive index

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub modifyHTTPAddRespheader ($farm_name, $header, $header_ind) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index = 0;
    my $ind   = 0;
    for my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /^\s*AddResponseHeader\s+"/) {
            # put new headremove before than last one
            if ($header_ind == $ind) {
                splice @fileconf, $index, 1, "\tAddResponseHeader \"$header\"";
                $errno = 0;
                last;
            }
            else {
                $ind++;
            }
        }
        $index++;
    }
    untie @fileconf;

    &log_info("Could not modify AddResponseHeader") if $errno;

    return $errno;
}

=pod

=head1 delHTTPAddRespheader

Delete a directive "AddResponseHeader from the farm config file".

Parameters:

    farm_name  - Farm name
    header_ind - Header index

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub delHTTPAddRespheader ($farm_name, $header_ind) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index = 0;
    my $ind   = 0;
    for my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /^\s*AddResponseHeader\s+"/) {
            if ($header_ind == $ind) {
                $errno = 0;
                splice @fileconf, $index, 1;
                last;
            }
            else {
                $ind++;
            }
        }
        $index++;
    }
    untie @fileconf;

    &log_info("Could not remove AddResponseHeader") if $errno;

    return $errno;
}

# remove response header

=pod

=head1 getHTTPRemRespHeader

Get a list with all the http headers that the load balancer will add to the response to the client

Parameters:

    farm_name - Farm name

Returns:

    Array ref - headers list

=cut

sub getHTTPRemRespHeader ($farm_name) {
    return &getHTTPFarmHeadersStruct($farm_name)->{removeresponseheader};
}

=pod

=head1 addHTTPRemRespHeader

Add a directive "HeadResponseRemove". The HTTP farm will remove a reponse
header from the backend that matches with this expression

Parameters:

    farm_name - Farm name
    header    - Header to add

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub addHTTPRemRespHeader ($farm_name, $header) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index        = 0;
    my $rewrite_flag = 0;    # it is used to add HeadRemove before than AddHeader
    for my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /[#\s]*RewriteLocation/) {
            $rewrite_flag = 1;
        }
        elsif ($rewrite_flag) {
            # put new headremove after than last one
            if (    $line !~ /^[#\s]*(?:AddHeader|HeadRemove|AddResponseHeader|RemoveResponseHead)\s+"/
                and $rewrite_flag)
            {
                # example: AddHeader "header: to add"
                splice @fileconf, $index, 0, "\tRemoveResponseHead \"$header\"";
                $errno = 0;
                last;
            }
        }
        $index++;
    }
    untie @fileconf;

    &log_info("Could not add RemoveResponseHead") if $errno;

    return $errno;
}

=pod

=head1 modifyHTTPRemRespHeader

Modify an RemoveResponseHead directive from the given farm

Parameters:

    farm_name     - Farm name
    header        - Header to add
    header_ind    - directive index

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub modifyHTTPRemRespHeader ($farm_name, $header, $header_ind) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index = 0;
    my $ind   = 0;
    for my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /^\s*RemoveResponseHead\s+"/) {
            # put new headremove before than last one
            if ($header_ind == $ind) {
                splice @fileconf, $index, 1, "\tRemoveResponseHead \"$header\"";
                $errno = 0;
                last;
            }
            else {
                $ind++;
            }
        }
        $index++;
    }
    untie @fileconf;

    &log_info("Could not modify RemoveResponseHead") if $errno;

    return $errno;
}

=pod

=head1 delHTTPRemRespHeader

Delete a directive "HeadResponseRemove".

Parameters:

    farm_name  - Farm name
    header_ind - Header index

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub delHTTPRemRespHeader ($farm_name, $header_ind) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index = 0;
    my $ind   = 0;
    for my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /^\s*RemoveResponseHead\s+"/) {
            if ($header_ind == $ind) {
                $errno = 0;
                splice @fileconf, $index, 1;
                last;
            }
            else {
                $ind++;
            }
        }
        $index++;
    }
    untie @fileconf;

    &log_info("Could not remove RemoveResponseHead") if $errno;

    return $errno;
}

=pod

=head1 getHTTPFarmHeadersStruct

It extends the farm struct with parameters exclusive to EE.
If no farm struct was passed to the function, the function will return
a new farm struct with the enterprise fields.

Parameters:

    farmname    - Farm name
    farm struct - Struct with the farm configuration parameters

Returns:

    Hash ref - Farm struct updated with EE parameters

=cut

sub getHTTPFarmHeadersStruct ($farmname, $farm_st = {}) {
    $farm_st->{addheader}            = [];
    $farm_st->{headremove}           = [];
    $farm_st->{addresponseheader}    = [];
    $farm_st->{removeresponseheader} = [];

    my $farm_filename = &getFarmFile($farmname);
    my @lines         = ();

    if (open my $fh, '<', "${configdir}/${farm_filename}") {
        @lines = <$fh>;
        close $fh;
    }

    my $add_req_header_index = 0;
    my $rem_req_header_index = 0;
    my $add_res_header_index = 0;
    my $rem_res_header_index = 0;

    for my $line (@lines) {
        if    ($line =~ /^[#\s]*Service \"/) { last; }
        elsif ($line =~ /^[#\s]*AddHeader\s+"(.+)"/) {
            push @{ $farm_st->{addheader} },
              {
                "id"     => $add_req_header_index++,
                "header" => $1
              };
        }
        elsif ($line =~ /^[#\s]*HeadRemove\s+"(.+)"/) {
            push @{ $farm_st->{headremove} },
              {
                "id"      => $rem_req_header_index++,
                "pattern" => $1
              };
        }
        elsif ($line =~ /^[#\s]*AddResponseHeader\s+"(.+)"/) {
            push @{ $farm_st->{addresponseheader} },
              {
                "id"     => $add_res_header_index++,
                "header" => $1
              };
        }
        elsif ($line =~ /^[#\s]*RemoveResponseHead\s+"(.+)"/) {
            push @{ $farm_st->{removeresponseheader} },
              {
                "id"      => $rem_res_header_index++,
                "pattern" => $1
              };
        }
        elsif ($line =~ /Ignore100Continue (\d).*/) {
            $farm_st->{ignore_100_continue} = ($1 eq '0') ? 'false' : 'true';
        }
        elsif ($line =~ /LogLevel\s+(\d).*/) {
            my $lvl = $1 + 0;
            $farm_st->{logs} = 'true' if ($lvl >= 5);
        }
    }

    return $farm_st;
}

=pod

=head1 moveHeader

Changes the position of a farm header directive.

NOTICE: This function is not currently being used.

Parameters:

    farmname - Farm name
    regex    - Regex to match the directive
    pos      - It is the required position for the rule.
    index    - It is index of the rule in the set

Returns:

    none

=cut

sub moveHeader ($farm_name, $regex, $pos, $index) {
    require Relianoid::Arrays;

    my $farm_filename = &getFarmFile($farm_name);

    require Tie::File;
    tie my @file, 'Tie::File', "$configdir/$farm_filename";

    my $file_index   = 0;
    my $header_index = 0;
    my @headers      = ();
    for my $l (@file) {
        if ($l =~ /^[#\s]*Service \"/) { last; }
        if ($l =~ /^$regex/) {
            $header_index = $file_index unless ($header_index != 0);
            push @headers, $l;
        }
        $file_index++;
    }

    &moveByIndex(\@headers, $index, $pos);

    my $size = scalar @headers;

    splice(@file, $header_index, $size, @headers);

    untie @file;

    return;
}

=pod

=head1 getHTTPFarmLogs

Return the log connection tracking status

Parameters:

    farm_name - Farm name

Returns:

    scalar - The possible values are: 0 on disabled, possitive value on enabled or -1 on failure

=cut

sub getHTTPFarmLogs ($farm_name) {
    my $output = 'false';

    my $farm_filename = &getFarmFile($farm_name);
    my @lines         = ();

    if (open my $fh, '<', "${configdir}/${farm_filename}") {
        @lines = <$fh>;
        close $fh;
    }

    for my $line (@lines) {
        if    ($line =~ /^[#\s]*Service \"/) { last; }
        elsif ($line =~ /LogLevel\s+(\d).*/) {
            my $lvl = $1 + 0;
            $output = 'true' if ($lvl >= 5);
            last;
        }
    }

    return $output;
}

=pod

=head1 setHTTPFarmLogs

Enable or disable the log connection tracking for a http farm

Parameters:

    farmname  - Farm name
    action    - The available actions are: "true" to enable or "false" to disable

Returns:

    scalar - The possible values are: 0 on success or -1 on failure

=cut

sub setHTTPFarmLogs ($farm_name, $action) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    my $loglvl;
    $loglvl = ($action eq "true") ? 5 : 0;

    require Relianoid::File;
    my @lines = readFileAsArray("$configdir/$farm_filename");

    my $match_found = 0;
    for my $line (@lines) {
        if ($line =~ s/^LogLevel\s+(\d).*$/LogLevel\t$loglvl/) {
            $match_found = 1;
            $output      = 0;
        }
    }

    if ($match_found) {
        writeFileFromArray("$configdir/$farm_filename", \@lines);
    }
    else {
        &log_error("Error modifying http logs", "LSLB");
    }

    return $output;
}

=pod

=head1 getHTTPFarm100Continue

Return 100 continue Header configuration HTTP and HTTPS farms

Parameters:

    farmname - Farm name

Returns:

    scalar - The possible values are: 0 on disabled, 1 on enabled

=cut

sub getHTTPFarm100Continue ($farm_name) {
    my $output = 'true';

    my $farm_filename = &getFarmFile($farm_name);
    my @lines;

    if (open my $fh, '<', "${configdir}/${farm_filename}") {
        @lines = <$fh>;
        close $fh;
    }

    for my $line (@lines) {
        if    ($line =~ /^[#\s]*Service \"/) { last; }
        elsif ($line =~ /Ignore100Continue (\d).*/) {
            $output = ($1 eq '0') ? 'false' : 'true';
            last;
        }
    }

    return $output;
}

=pod

=head1 setHTTPFarm100Continue

Enable or disable the HTTP 100 continue header

Parameters:

    farm_name  - Farm name
    action    - The available actions are: 1 to enable or 0 to disable

Returns:

    scalar - The possible values are: 0 on success or -1 on failure

=cut

sub setHTTPFarm100Continue ($farm_name, $action) {
    my $farm_filename = &getFarmFile($farm_name);

    require Relianoid::File;
    my @lines = readFileAsArray("$configdir/$farm_filename");

    # check if 100 continue directive exists
    my $match_found = 0;
    for my $line (@lines) {
        if ($line =~ s/^Ignore100Continue\ .*/Ignore100Continue $action/) {
            $match_found = 1;
        }
    }

    if (not $match_found) {
        for my $line (@lines) {
            if ($line =~ /^Control\s/) {
                $line = "$line\nIgnore100Continue $action\n";
                last;
            }
        }
    }

    writeFileFromArray("$configdir/$farm_filename", \@lines);

    return 0;
}

1;
