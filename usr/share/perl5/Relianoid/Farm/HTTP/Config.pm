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

require Relianoid::Lock;

my $configdir = &getGlobalConfiguration('configdir');

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::Farm::HTTP::Config

=cut

=pod

=head1 setFarmClientTimeout

Configure the client time parameter for a HTTP farm.

Parameters:

    client   - It is the time in seconds for the client time parameter
    farmname - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setFarmClientTimeout ($client, $farm_name) {
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
            &zenlog("setting 'ClientTimeout $client' for $farm_name farm http", "info", "LSLB");
            $filefarmhttp[$i_f] = "Client\t\t $client";
            $output             = $?;
            $found              = "true";
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return $output;
}

=pod

=head1 getFarmClientTimeout

Return the client time parameter for a HTTP farm.

Parameters:

    farmname - Farm name

Returns:

    Integer - Return the seconds for client request timeout or -1 on failure.

=cut

sub getFarmClientTimeout ($farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    open my $fd, '<', "$configdir\/$farm_filename";
    my @file = <$fd>;
    close $fd;

    foreach my $line (@file) {
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

    &zenlog("Setting 'Session type $session' for $farm_name farm http", "info", "LSLB");
    tie my @contents, 'Tie::File', "$configdir\/$farm_filename";
    my $i     = -1;
    my $found = "false";
    foreach my $line (@contents) {
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
                $output = $?;
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
                $output = $?;
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
            &zenlog("Setting 'Blacklist time $blacklist_time' for $farm_name farm http", "info", "LSLB");
            $filefarmhttp[$i_f] = "Alive\t\t $blacklist_time";
            $output             = $?;
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

=head1 setFarmHttpVerb

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

sub setFarmHttpVerb ($verb, $farm_name) {
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
            &zenlog("Setting 'Http verb $verb' for $farm_name farm http", "info", "LSLB");
            $filefarmhttp[$i_f] = "\txHTTP $verb";
            $output             = $?;
            $found              = "true";
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return $output;
}

=pod

=head1 getFarmHttpVerb

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

sub getFarmHttpVerb ($farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    open my $fh, '<', "$configdir\/$farm_filename";
    my @file = <$fh>;
    close $fh;

    foreach my $line (@file) {
        if ($line =~ /xHTTP/) {
            my @line_aux = split("\ ", $line);
            $output = $line_aux[1];
        }
    }

    return $output;
}

=pod

=head1 setFarmListen

Change a HTTP farm between HTTP and HTTPS listener

Parameters:

    farmname - Farm name
    listener - type of listener: http or https

Returns:

    none

FIXME

    not return nothing, use $found variable to return success or error

=cut

sub setFarmListen ($farm_name, $flisten) {
    my $farm_filename = &getFarmFile($farm_name);
    my $i_f           = -1;
    my $found         = "false";

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @filefarmhttp, 'Tie::File', "$configdir/$farm_filename";
    my $array_count = @filefarmhttp;

    while ($i_f <= $array_count && $found eq "false") {
        $i_f++;
        if ($filefarmhttp[$i_f] =~ /^ListenHTTP/ && $flisten eq "http") {
            $filefarmhttp[$i_f] = "ListenHTTP";
        }
        if ($filefarmhttp[$i_f] =~ /^ListenHTTP/ && $flisten eq "https") {
            $filefarmhttp[$i_f] = "ListenHTTPS";
        }

        #
        if ($filefarmhttp[$i_f] =~ /.*Cert\ \"/ && $flisten eq "http") {
            $filefarmhttp[$i_f] =~ s/Cert\ \"/#Cert\ \"/;
        }
        if ($filefarmhttp[$i_f] =~ /.*Cert\ \"/ && $flisten eq "https") {
            $filefarmhttp[$i_f] =~ s/#//g;
        }

        #
        if ($filefarmhttp[$i_f] =~ /.*Ciphers\ \"/ && $flisten eq "http") {
            $filefarmhttp[$i_f] =~ s/Ciphers\ \"/#Ciphers\ \"/;
        }
        if ($filefarmhttp[$i_f] =~ /.*Ciphers\ \"/ && $flisten eq "https") {
            $filefarmhttp[$i_f] =~ s/#//g;
        }

        # Enable 'Disable TLSv1, TLSv1_1 or TLSv1_2'
        if ($filefarmhttp[$i_f] =~ /.*Disable TLSv1/ && $flisten eq "http") {
            $filefarmhttp[$i_f] =~ s/Disable TLSv1/#Disable TLSv1/;
        }
        if ($filefarmhttp[$i_f] =~ /.*Disable TLSv1/ && $flisten eq "https") {
            $filefarmhttp[$i_f] =~ s/#//g;
        }
        elsif ($filefarmhttp[$i_f] =~ /.*DisableTLSv1\d$/
            && $flisten eq "https")
        {
            $filefarmhttp[$i_f] =~ s/#//g;
        }

        # Enable 'Disable SSLv3 or SSLv2'
        if ($filefarmhttp[$i_f] =~ /.*Disable SSLv\d$/ && $flisten eq "http") {
            $filefarmhttp[$i_f] =~ s/Disable SSLv/#Disable SSLv/;
        }
        if ($filefarmhttp[$i_f] =~ /.*Disable SSLv\d$/ && $flisten eq "https") {
            $filefarmhttp[$i_f] =~ s/#//g;
        }
        elsif ($filefarmhttp[$i_f] =~ /.*DisableSSLv\d$/
            && $flisten eq "https")
        {
            $filefarmhttp[$i_f] =~ s/#//g;
        }

        # Enable SSLHonorCipherOrder
        if (   $filefarmhttp[$i_f] =~ /.*SSLHonorCipherOrder/
            && $flisten eq "http")
        {
            $filefarmhttp[$i_f] =~ s/SSLHonorCipherOrder/#SSLHonorCipherOrder/;
        }
        if (   $filefarmhttp[$i_f] =~ /.*SSLHonorCipherOrder/
            && $flisten eq "https")
        {
            $filefarmhttp[$i_f] =~ s/#//g;
        }

        # Enable StrictTransportSecurity
        if (   $filefarmhttp[$i_f] =~ /.*StrictTransportSecurity/
            && $flisten eq "http")
        {
            $filefarmhttp[$i_f] =~ s/StrictTransportSecurity/#StrictTransportSecurity/;
        }
        if (   $filefarmhttp[$i_f] =~ /.*StrictTransportSecurity/
            && $flisten eq "https")
        {
            $filefarmhttp[$i_f] =~ s/#//g;
        }

        # Check for ECDHCurve cyphers
        if ($filefarmhttp[$i_f] =~ /ECDHCurve/ && $flisten eq "http") {
            $filefarmhttp[$i_f] =~ s/ECDHCurve/\#ECDHCurve/;
        }
        if ($filefarmhttp[$i_f] =~ /ECDHCurve/ && $flisten eq "https") {
            $filefarmhttp[$i_f] =~ s/#ECDHCurve/ECDHCurve/;
        }

        # Generate DH Keys if needed
        #my $dhfile = "$configdir\/$farm_name\_dh2048.pem";
        if ($filefarmhttp[$i_f] =~ /^\#*DHParams/ && $flisten eq "http") {
            $filefarmhttp[$i_f] =~ s/.*DHParams/\#DHParams/;
        }
        if ($filefarmhttp[$i_f] =~ /^\#*DHParams/ && $flisten eq "https") {
            $filefarmhttp[$i_f] =~ s/.*DHParams/DHParams/;

            #$filefarmhttp[$i_f] =~ s/.*DHParams.*/DHParams\t"$dhfile"/;
        }

        if ($filefarmhttp[$i_f] =~ /ZWACL-END/) {
            $found = "true";
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return;
}

=pod

=head1 setFarmRewriteL

Asign a RewriteLocation vaue to a farm HTTP or HTTPS

Parameters:

    farmname - Farm name

    rewritelocation - The options are: disabled, enabled or enabled-backends

Returns:

    none

=cut

sub setFarmRewriteL ($farm_name, $rewritelocation, $path = undef) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    &zenlog("setting 'Rewrite Location' for $farm_name to $rewritelocation", "info", "LSLB");

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @filefarmhttp, 'Tie::File', "$configdir/$farm_filename";
    my $i_f         = -1;
    my $array_count = @filefarmhttp;
    my $found       = "false";

    while ($i_f <= $array_count && $found eq "false") {
        $i_f++;
        if ($filefarmhttp[$i_f] =~ /RewriteLocation\ .*/) {
            my $directive = "\tRewriteLocation $rewritelocation";
            $directive .= " path" if ($path);
            $filefarmhttp[$i_f] = $directive;
            $output             = $?;
            $found              = "true";
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return;
}

=pod

=head1 getFarmRewriteL

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

sub getFarmRewriteL ($farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = "disabled";

    open my $fd, '<', "$configdir\/$farm_filename";
    my @file = <$fd>;
    close $fd;

    foreach my $line (@file) {
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

=head1 setFarmConnTO

Configure connection time out value to a farm HTTP or HTTPS

Parameters:

    connectionTO - Conection time out in seconds

    farmname - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setFarmConnTO ($tout, $farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    &zenlog("Setting 'ConnTo timeout $tout' for $farm_name farm http", "info", "LSLB");

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
            $output             = $?;
            $found              = "true";
        }
    }

    untie @filefarmhttp;
    close $lock_fh;

    return $output;
}

=pod

=head1 getFarmConnTO

Return farm connecton time out value for http and https farms

Parameters:

    farmname - Farm name

Returns:

    integer - return the connection time out or -1 on failure

=cut

sub getFarmConnTO ($farm_name) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    open my $fd, '<', "$configdir\/$farm_filename";
    my @file = <$fd>;
    close $fd;

    foreach my $line (@file) {
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
            $output             = $?;
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

    open my $fd, '<', "$configdir\/$farm_filename";
    my @file = <$fd>;

    foreach my $line (@file) {
        if ($line =~ /^Timeout/) {
            my @line_aux = split("\ ", $line);
            $output = $line_aux[1];
        }
    }
    close $fd;

    return $output;
}

=pod

=head1 setHTTPFarmMaxClientTime

Set the maximum time for a client

Parameters:

    maximumTO - Maximum client time

    farmname - Farm name

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
            $output             = $?;
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

    array - Return proxyctl output

=cut

sub getHTTPFarmGlobalStatus ($farm_name) {
    my $proxyctl = &getGlobalConfiguration('proxyctl');

    return @{ &logAndGet("$proxyctl -c \"/tmp/$farm_name\_proxy.socket\"", "array") };
}

=pod

=head1 setFarmErr

Configure a error message for http error: WAF, 414, 500, 501 or 503

Parameters:

    farmname - Farm name

    message - Message body for the error

    error_number - Number of error to set, the options are WAF, 414, 500, 501 or 503

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setFarmErr ($farm_name, $content, $nerr) {
    my $output = -1;

    &zenlog("Setting 'Err $nerr' for $farm_name farm http", "info", "LSLB");

    if (-e "$configdir\/$farm_name\_Err$nerr.html" && $nerr ne "") {
        $output = 0;
        my @err = split("\n", "$content");
        my $fd  = &openlock("$configdir\/$farm_name\_Err$nerr.html", 'w');

        foreach my $line (@err) {
            $line =~ s/\r$//;
            print $fd "$line\n";
            $output = $? || $output;
        }

        close $fd;
    }

    return $output;
}

=pod

=head1 getFarmErr

Return the error message for a http error: WAF, 414, 500, 501 or 503

Parameters:

    farmname - Farm name

    error_number - Number of error to set, the options are WAF, 414, 500, 501 or 503

Returns:

    string - Message body for the error

=cut

# Only http function
sub getFarmErr ($farm_name, $nerr) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output;

    open my $fd, '<', "$configdir\/$farm_filename";
    my @file = <$fd>;
    close $fd;

    foreach my $line (@file) {
        if ($line =~ /Err$nerr/) {
            my @line_aux = split("\ ", $line);
            my $err      = $line_aux[1];
            $err =~ s/"//g;

            if (-e $err) {
                open my $fd, '<', "$err";
                while (<$fd>) {
                    $output .= $_;
                }
                close $fd;
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

    foreach my $line (@filefarmhttp) {
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
        foreach my $line (@filefarmhttp) {
            $i++;
            if ($line =~ /^ListenHTTP/) {
                my $directive = "\tErr$err \"$configdir" . "/" . $farm_name . "_Err$err.html\"";
                splice @filefarmhttp, $i + 1, 0, $directive;
                last;
            }
        }
    }
    untie @filefarmhttp;

    if ($eload) {
        if ($enabled eq "true") {
            if (!-f "$configdir\/$farm_name\_ErrWAF.html") {
                my $f_err;
                open $f_err, '>', "$configdir\/$farm_name\_ErrWAF.html";
                print $f_err "The request was rejected by the server.\n";
                close $f_err;
            }
        }
        else {
            if (-f "$configdir\/$farm_name\_ErrWAF.html") {
                unlink "$configdir\/$farm_name\_ErrWAF.html";
            }
        }
    }

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

    open my $fd, '<', "$configdir/$farm_filename";

    while (my $line = <$fd>) {
        $lastline = $line;
    }
    close $fd;

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

    farmname - Farm name

Returns:

    string - return "up" if the process is running or "down" if it isn't

=cut

sub getHTTPFarmStatus ($farm_name) {
    my @pid    = &getHTTPFarmPid($farm_name);
    my $output = -1;
    my $running_pid;
    $running_pid = kill(0, @pid) if @pid;

    if (@pid && $running_pid) {
        $output = "up";
    }
    else {
        $output = "down";
    }

    return $output;
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
        open my $fd, '<', $pidfile;
        @pid = <$fd>;
        close $fd;
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
    foreach my $l (@{$out}) {
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

    open my $fi, '<', "$configdir/$farm_filename";
    my @file = <$fi>;
    close $fi;

    foreach my $line (@file) {
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

    # Finally, reload rules and source address
    if (&getGlobalConfiguration('proxy_ng') eq "true") {
        if (&getGlobalConfiguration("mark_routing_L7") eq 'true' and $prev_config->{status} eq "up") {
            &doL7FarmRules("reload", $farm_name, $prev_config);
        }

        # reload source address maquerade
        require Relianoid::Farm::Config;
        &reloadFarmsSourceAddressByFarm($farm_name);
    }

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
    my $proxy         = &getGlobalConfiguration('proxy');
    my $farm_filename = &getFarmFile($farm_name);
    my $proxy_command = "$proxy -f $configdir\/$farm_filename -c";

    # do not use the function 'logAndGet' here is managing the error output and error code
    my $run = `$proxy_command 2>&1`;
    my $rc  = $?;

    if ($rc or &debug()) {
        my $tag     = ($rc) ? 'error'  : 'debug';
        my $message = $rc   ? 'failed' : 'running';
        &zenlog("$message: $proxy_command", $tag, "LSLB");
        &zenlog("output: $run ",            $tag, "LSLB");
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
    my $service;
    my $proxy         = &getGlobalConfiguration('proxy');
    my $farm_filename = &getFarmFile($farm_name);
    my $proxy_command = "$proxy -f $configdir\/$farm_filename -c";

    # do not use the function 'logAndGet' here is managing the error output and error code
    my @run = `$proxy_command 2>&1`;
    my $rc  = $?;

    return "" unless ($rc);

    shift @run if ($run[0] =~ /starting\.\.\./);
    chomp @run;
    my $msg;

    &zenlog("Error checking $configdir\/$farm_filename.", "Error", "LSLB");
    &zenlog($run[0],                                      "Error", "LSLB");

    $run[0] = $run[1] if ($run[0] =~ /waf/i);

    $run[0] =~ / line (\d+): /;
    my $line_num = $1;

    # get line
    my $file_id = 0;
    my $file_line;
    my $srv;

    if (open my $fileconf, '<', "$configdir/$farm_filename") {
        my @lines = <$fileconf>;
        close $fileconf;

        while (my $line = @lines) {
            if ($line =~ /^\s+Service \"(.+)\"/) { $srv = $1; }
            if ($file_id == $line_num - 1) {
                $file_line = $line;
                last;
            }
            $file_id++;
        }
    }

    # examples of error msg
    #	AAAhttps, /usr/local/relianoid/config/AAAhttps_proxy.cfg line 36: unknown directive
    #	AAAhttps, /usr/local/relianoid/config/AAAhttps_proxy.cfg line 40: SSL_CTX_use_PrivateKey_file failed - aborted
    $file_line =~ /\s*([\w-]+)/;
    my $param = $1;
    $msg = "Error in the configuration file";

    # parse line
    if ($param eq "Cert") {

        # return pem name if the pem file is not correct
        $file_line =~ /([^\/]+)\"$/;
        $msg = "Error loading the certificate: $1" if $1;
    }
    elsif ($param eq "WafRules") {

        # return waf rule name  if the waf rule file is not correct
        $file_line =~ /([^\/]+)\"$/;
        $msg = "Error loading the WafRuleSet: $1" if $1;
    }
    elsif ($param) {
        $srv = "in the service $srv" if ($srv);
        $msg = "Error in the parameter $param ${srv}";
    }

    elsif (&debug()) {
        $msg = $run[0];
    }

    &zenlog("Error checking config file: $msg", 'debug');

    return $msg;
}

=pod

=head1 getHTTPFarmStruct

=cut

sub getHTTPFarmStruct ($farmname, $type = undef) {
    $type //= &getFarmType($farmname);

    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    my $proxy_ng = &getGlobalConfiguration('proxy_ng');

    # Output hash reference or undef if the farm does not exist.
    my $farm;

    return $farm unless $farmname;

    my $vip    = &getFarmVip("vip",  $farmname);
    my $vport  = &getFarmVip("vipp", $farmname) + 0;
    my $status = &getFarmVipStatus($farmname);

    my $connto          = 0 + &getFarmConnTO($farmname);
    my $timeout         = 0 + &getHTTPFarmTimeout($farmname);
    my $alive           = 0 + &getHTTPFarmBlacklistTime($farmname);
    my $client          = 0 + &getFarmClientTimeout($farmname);
    my $rewritelocation = &getFarmRewriteL($farmname);
    my $httpverb        = 0 + &getFarmHttpVerb($farmname);

    if    ($httpverb == 0) { $httpverb = "standardHTTP"; }
    elsif ($httpverb == 1) { $httpverb = "extendedHTTP"; }
    elsif ($httpverb == 2) { $httpverb = "standardWebDAV"; }
    elsif ($httpverb == 3) { $httpverb = "MSextWebDAV"; }
    elsif ($httpverb == 4) { $httpverb = "MSRPCext"; }
    elsif ($httpverb == 5) { $httpverb = "optionsHTTP"; }

    my $errWAF = &getFarmErr($farmname, "WAF");
    my $err414 = &getFarmErr($farmname, "414");
    my $err500 = &getFarmErr($farmname, "500");
    my $err501 = &getFarmErr($farmname, "501");
    my $err503 = &getFarmErr($farmname, "503");

    $farm = {
        status          => $status,
        restimeout      => $timeout,
        contimeout      => $connto,
        resurrectime    => $alive,
        reqtimeout      => $client,
        rewritelocation => $rewritelocation,
        httpverb        => $httpverb,
        listener        => $type,
        vip             => $vip,
        vport           => $vport,
        error500        => $err500,
        error414        => $err414,
        error501        => $err501,
        error503        => $err503,
        name            => $farmname
    };

    if ($eload and $proxy_ng eq 'true') {
        $farm->{errorWAF} = $errWAF;
    }

    # HTTPS parameters
    if ($type eq "https") {
        require Relianoid::Farm::HTTP::HTTPS;

        ## Get farm certificate(s)
        my @cnames;

        if ($eload) {
            @cnames = &eload(
                module => 'Relianoid::Farm::HTTP::HTTPS::Ext',
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
        $farm->{certlist} = \@cert_list;
        $farm->{ciphers}  = $ciphers;
        $farm->{cipherc}  = &getFarmCipherList($farmname);
        $farm->{disable_sslv2} =
          (&getHTTPFarmDisableSSL($farmname, "SSLv2")) ? "true" : "false";
        $farm->{disable_sslv3} =
          (&getHTTPFarmDisableSSL($farmname, "SSLv3")) ? "true" : "false";
        $farm->{disable_tlsv1} =
          (&getHTTPFarmDisableSSL($farmname, "TLSv1")) ? "true" : "false";
        $farm->{disable_tlsv1_1} =
          (&getHTTPFarmDisableSSL($farmname, "TLSv1_1")) ? "true" : "false";
        $farm->{disable_tlsv1_2} =
          (&getHTTPFarmDisableSSL($farmname, "TLSv1_2")) ? "true" : "false";
    }

    $farm->{logs} = &getHTTPFarmLogs($farmname);
    require Relianoid::Farm::Config;
    $farm = &get_http_farm_headers_struct($farmname, $farm);

    $farm->{ignore_100_continue} = &getHTTPFarm100Continue($farmname);

    return $farm;
}

=pod

=head1 getHTTPVerbCode

=cut

sub getHTTPVerbCode ($verbs_set) {

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

=pod

=head1 setFarmProxyNGConf

It changes the meaning of params Priority and weight in config file.

Parameters:

    proxy_mode - 'true' if ProxyNG is used, 'false' if not.
    farm_name - Name of the farm.

Returns:

    Integer - return 0 on success or different on failure

=cut

sub setFarmProxyNGConf ($proxy_mode, $farm_name) {
    require Relianoid::Farm::HTTP::Backend;

    my $farm_filename = &getFarmFile($farm_name);
    my $stat          = 0;

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @array, 'Tie::File', "$configdir\/$farm_filename";
    my @array_bak = @array;
    my @wafs;
    my $sw = 0;
    my $bw = 0;
    my $connto;

    for (my $i = 0 ; $i < @array ; $i++) {
        $sw = 1 if ($array[$i] =~ /^\s+Service/);
        $bw = 1 if ($array[$i] =~ /^\s+BackEnd/ && $sw == 1);
        $sw = 0 if ($array[$i] =~ /^\tEnd/      && $sw == 1 && $bw == 0);
        $bw = 0 if ($array[$i] =~ /^\t\tEnd/    && $sw == 1 && $bw == 1);

        if ($proxy_mode eq "false") {

            if ($array[$i] =~ /^\s*(#?)RewriteLocation\s+(\d)/) {
                if ($1 ne "#") {
                    $array[$i] = "\tRewriteLocation $2";
                }
            }
        }

        if ($bw == 0 and $sw == 0 and $proxy_mode eq "true") {
            if ($array[$i] =~ /^\s*ConnTO\s+(\d+)/) {
                $connto = $1;
            }
            if ($array[$i] =~ /^(\s*Alive\s+)(\d+)/) {
                if (defined $connto and $2 <= $connto) {
                    $array[$i] = "$1" . ($connto + 1);
                }
            }
        }

        if ($bw == 1) {
            if ($proxy_mode eq "true") {
                $array[$i] =~ s/Priority/Weight/;
            }
            elsif ($proxy_mode eq "false") {
                if ($array[$i] =~ /Priority|ConnLimit/) {
                    splice @array, $i, 1;
                    $i--;
                }
                else {

                    # Replace Priority value with Weight value
                    $array[$i] =~ s/Weight/Priority/;
                }
            }
        }

        # Service level all directives
        if (   $sw == 1
            && $array[$i] =~
            /^\s*(#?)(PinnedConnection|RoutingPolicy|RewriteLocation|AddHeader|AddResponseHeader|HeadRemove|RemoveResponseHeader|RewriteUrl|ReplaceHeader)/
          )
        {
            if ($proxy_mode eq "false") {
                if ($1 ne "#") {
                    $array[$i] =~ s/$1/\t\t#$2/;
                }
            }
            elsif ($proxy_mode eq "true") {
                $array[$i] =~ s/#//;
            }
        }

        # Farm level ReplaceHeader directives
        elsif ($sw == 0 && $array[$i] =~ /^\s*(#?)(ReplaceHeader)/) {
            if ($proxy_mode eq "false") {
                if ($1 ne "#") {
                    $array[$i] =~ s/$1/\t#$2/;
                }
            }
            elsif ($proxy_mode eq "true") {
                $array[$i] =~ s/#//;
            }
        }

        if ($array[$i] =~ /^([\s#]*)(WafRules.*)/) {
            push @wafs, "\t" . $2 if ($proxy_mode eq "true");
            push @wafs, $2        if ($proxy_mode eq "false");
            splice @array, $i, 1;
            $i--;
        }
    }
    for (my $i = 0 ; $i < @array ; $i++) {
        if ($array[$i] =~ /#HTTP\(S\) LISTENERS/) {
            if ($proxy_mode eq "false") {
                my $sizewaf = @wafs;
                splice @array, $i, 0, @wafs;
                $i = $i + $sizewaf;
                next;
            }
        }
        if ($array[$i] =~ /#ZWACL-INI/) {
            if ($proxy_mode eq "true") {
                my $sizewaf = @wafs;
                splice @array, $i + 1, 0, @wafs;
                $i = $i + $sizewaf;
                next;
            }
        }
    }

    untie @array;

    &migrateHTTPFarmLogs($farm_name, $proxy_mode);
    if ($eload) {
        my $func =
          ($proxy_mode eq 'false')
          ? 'addHTTPFarmWafBodySize'
          : 'delHTTPFarmWafBodySize';
        &eload(
            module => 'Relianoid::Farm::HTTP::Ext',
            func   => $func,
            args   => [$farm_name],
        );
    }

    require Relianoid::Farm::HTTP::Sessions;
    my $farm_sessions_filename = &getSessionsFileName($farm_name);
    if ($proxy_mode eq "true") {
        &setHTTPFarmConfErrFile("true", $farm_name, "WAF");
        &setHTTPFarmBackendsMarks($farm_name);

        if (!-f "$farm_sessions_filename") {
            my $f_err;
            open $f_err, '>', "$farm_sessions_filename";
            close $f_err;
        }

        require Relianoid::Farm::Config;
        &reloadFarmsSourceAddressByFarm($farm_name);

    }
    else {
        &setHTTPFarmConfErrFile("false", $farm_name, "WAF");
        &removeHTTPFarmBackendsMarks($farm_name);

        if (-f "$farm_sessions_filename") {
            unlink "$farm_sessions_filename";
        }

        &eload(
            module => 'Relianoid::Net::Floating',
            func   => 'removeL7FloatingSourceAddr',
            args   => [$farm_name],
        ) if ($eload);
    }

    if (&getHTTPFarmConfigIsOK($farm_name)) {
        tie my @array, 'Tie::File', "$configdir\/$farm_filename";
        @array = @array_bak;
        untie @array;
        $stat = 1;
        &zenlog("Error in $farm_name config file!", "error", "SYSTEM");
    }
    else {
        $stat = 0;
    }

    close $lock_fh;

    return $stat;
}

=pod

=head1 doL7FarmRules

Created to operate with setBackendRule in order to start, stop or reload ip rules

Parameters:

    action        - stop (delete all ip rules), start (create ip rules) or reload (delete old one stored in prev_farm_ref and create new)
    farm_name     - the farm name.
    prev_farm_ref - farm ref of the old configuration

Returns:

    none

=cut

sub doL7FarmRules ($action, $farm_name, $prev_farm_ref) {
    return if &getGlobalConfiguration('mark_routing_L7') ne 'true';

    require Relianoid::Farm::Backend;
    require Relianoid::Farm::HTTP::Config;
    require Relianoid::Farm::HTTP::Backend;
    require Relianoid::Farm::HTTP::Service;

    my $farm_ref;
    $farm_ref->{name} = $farm_name;
    $farm_ref->{vip}  = &getHTTPFarmVip("vip", $farm_name);

    my @backends;
    foreach my $service (&getHTTPFarmServices($farm_name)) {
        my $bckds = &getHTTPFarmBackends($farm_name, $service, "false");
        push @backends, @{$bckds};
    }

    foreach my $backend (@backends) {
        if ($backend->{tag}) {
            my $mark = sprintf("0x%x", $backend->{tag});
            &setBackendRule("del", $farm_ref,      $mark) if ($action eq "stop");
            &setBackendRule("del", $prev_farm_ref, $mark) if ($action eq "reload");
            &setBackendRule("add", $farm_ref,      $mark) if ($action eq "start" || $action eq "reload");
        }
    }

    return;
}

# Add request headers

=pod

=head1 getHTTPAddReqHeader

Get a list with all the http headers are added by the farm

Parameters:

    farm_name - Farm name

Returns:

    Array ref - headers list

=cut

sub getHTTPAddReqHeader ($farm_name) {
    return &get_http_farm_headers_struct($farm_name)->{addheader};
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

    foreach my $line (@fileconf) {
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

    &zenlog("Could not add AddHeader") if $errno;

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
    foreach my $line (@fileconf) {
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

    &zenlog("Could not modify AddHeader") if $errno;

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
    foreach my $line (@fileconf) {
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

    &zenlog("Could not remove HeadRemove") if $errno;

    return $errno;
}

# remove request header

=pod

=head1 getHTTPRemReqHeader

Get a list with all the http headers are added by the farm

Parameters:

    farm_name - Farm name

Returns:

    Array ref - headers list

=cut

sub getHTTPRemReqHeader ($farm_name) {
    return &get_http_farm_headers_struct($farm_name)->{headremove};
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
    foreach my $line (@fileconf) {
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

    &zenlog("Could not add HeadRemove") if $errno;

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
    foreach my $line (@fileconf) {
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

    &zenlog("Could not modify HeadRemove") if $errno;

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
    foreach my $line (@fileconf) {
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

    &zenlog("Could not remove HeadRemove") if $errno;

    return $errno;
}

# Add response headers

=pod

=head1 getHTTPAddRespHeader

Get a list with all the http headers that load balancer will add to the backend repsonse

Parameters:

    farm_name - Farm name

Returns:

    Array ref - headers list

=cut

sub getHTTPAddRespHeader ($farm_name) {
    return &get_http_farm_headers_struct($farm_name)->{addresponseheader};
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
    foreach my $line (@fileconf) {
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

    &zenlog("Could not add AddResponseHeader") if $errno;

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
    foreach my $line (@fileconf) {
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

    &zenlog("Could not modify AddResponseHeader") if $errno;

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
    foreach my $line (@fileconf) {
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

    &zenlog("Could not remove AddResponseHeader") if $errno;

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
    return &get_http_farm_headers_struct($farm_name)->{removeresponseheader};
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
    foreach my $line (@fileconf) {
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

    &zenlog("Could not add RemoveResponseHead") if $errno;

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
    foreach my $line (@fileconf) {
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

    &zenlog("Could not modify RemoveResponseHead") if $errno;

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
    foreach my $line (@fileconf) {
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

    &zenlog("Could not remove RemoveResponseHead") if $errno;

    return $errno;
}

=pod

=head1 addHTTPReplaceHeaders

Add a directive ReplaceHeader to a zproxy farm.

Parameters:

    farm_name - Farm name
    type      - Request | Response
    header
    match
    replace

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub addHTTPReplaceHeaders ($farm_name, $type, $header, $match, $replace) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index               = 0;
    my $rewrite_flag        = 0;    # it is used to add HeadRemove before than AddHeader
    my $rewritelocation_ind = 0;
    my $replace_found       = 0;
    foreach my $line (@fileconf) {
        if ($replace_found) {
            if ($line =~ /^[#\s]*ReplaceHeader\s+$type\s+"/) { $index++; next; }

            # example: ReplaceHeader Request "header" "match" "replace"
            splice @fileconf, $index, 0, "\tReplaceHeader $type \"$header\" \"$match\" \"$replace\"";
            $errno = 0;
            last;
        }
        if ($line =~ /^[#\s]*Service \"/) {
            if ($rewrite_flag == 1) {
                splice @fileconf, $rewritelocation_ind + 1, 0, "\tReplaceHeader $type \"$header\" \"$match\" \"$replace\"";
                $errno = 0;
            }
            last;
        }
        if ($line =~ /[#\s]*RewriteLocation/) {
            $rewrite_flag        = 1;
            $rewritelocation_ind = $index;
        }
        elsif ($rewrite_flag) {

            # put new ReplaceHeader after the last one
            if ($line =~ /^[#\s]*ReplaceHeader\s+$type\s+"/) {
                $replace_found = 1;
            }
        }
        $index++;
    }
    untie @fileconf;

    &zenlog("Could not add ReplaceHeader") if $errno;

    return $errno;
}

=pod

=head1 modifyHTTPReplaceHeaders

Modify an ReplaceHeader directive from the given farm

Parameters:

    farm_name   - Farm name
    type
    header      - Header to add
    match
    replace
    header_ind  - directive index

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub modifyHTTPReplaceHeaders ($farm_name, $type, $header, $match, $replace, $header_ind) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index = 0;
    my $ind   = 0;
    foreach my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /^\s*ReplaceHeader\s+$type\s+(.+)/) {

            # put new headremove before than last one
            if ($header_ind == $ind) {
                splice @fileconf, $index, 1, "\tReplaceHeader $type \"$header\" \"$match\" \"$replace\"";
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

    &zenlog("Could not modify ReplaceHeader") if $errno;

    return $errno;
}

=pod

=head1 getHTTPReplaceHeaders

Parameters:

    farm_name - Farm name
    type

Returns:

    list

=cut

sub getHTTPReplaceHeaders ($farm_name, $type) {
    if ($type eq "Request") {
        return &get_http_farm_headers_struct($farm_name)->{replacerequestheader};
    }

    if ($type eq "Response") {
        return &get_http_farm_headers_struct($farm_name)->{replaceresponseheader};
    }

    return;
}

=pod

=head1 delHTTPReplaceHeaders

Delete a directive "ReplaceHeader".

Parameters:

    farmname - Farm name
    header_ind - Header index
    deltype

Returns:

    Integer - Error code: 0 on success or 1 on failure

=cut

sub delHTTPReplaceHeaders ($farm_name, $header_ind, $deltype) {
    require Relianoid::Farm::Core;
    my $ffile = &getFarmFile($farm_name);
    my $errno = 1;

    require Relianoid::Lock;
    &ztielock(\my @fileconf, "$configdir/$ffile");

    my $index = 0;
    my $ind   = 0;
    foreach my $line (@fileconf) {
        if ($line =~ /^[#\s]*Service \"/) { last; }
        if ($line =~ /^\s*ReplaceHeader\s+(.+)/) {
            (my $type) = split(/\s+/, $1);
            if ($deltype eq $type) {
                if ($header_ind == $ind) {
                    $errno = 0;
                    splice @fileconf, $index, 1;
                    last;
                }
                else {
                    $ind++;
                }
            }
        }
        $index++;
    }
    untie @fileconf;

    &zenlog("Could not remove ReplaceHeader") if $errno;

    return $errno;
}

=pod

=head1 get_http_farm_headers_struct

It extends farm struct with the parameters exclusives of the EE.
It no farm struct was passed to the function. The function will returns a new
farm struct with the enterprise fields

Parameters:

    farmname    - Farm name
    farm struct - Struct with the farm configuration parameters

Returns:

    Hash ref - Farm struct updated with EE parameters

=cut

sub get_http_farm_headers_struct ($farmname, $farm_st = {}, $proxy_ng = undef) {
    $proxy_ng //= &getGlobalConfiguration('proxy_ng');

    $farm_st->{addheader}             = [];
    $farm_st->{headremove}            = [];
    $farm_st->{addresponseheader}     = [];
    $farm_st->{removeresponseheader}  = [];
    $farm_st->{replacerequestheader}  = [];
    $farm_st->{replaceresponseheader} = [];

    my $farm_filename = &getFarmFile($farmname);
    my @lines         = ();

    if (open my $fileconf, '<', "$configdir/$farm_filename") {
        @lines = <$fileconf>;
        close $fileconf;
    }

    my $add_req_head_index  = 0;
    my $rem_req_head_index  = 0;
    my $add_resp_head_index = 0;
    my $rem_resp_head_index = 0;
    my $rep_req_head_index  = 0;
    my $rep_res_head_index  = 0;

    foreach my $line (@lines) {
        if    ($line =~ /^[#\s]*Service \"/) { last; }
        elsif ($line =~ /^[#\s]*AddHeader\s+"(.+)"/) {
            push @{ $farm_st->{addheader} },
              {
                "id"     => $add_req_head_index++,
                "header" => $1
              };
        }
        elsif ($line =~ /^[#\s]*HeadRemove\s+"(.+)"/) {
            push @{ $farm_st->{headremove} },
              {
                "id"      => $rem_req_head_index++,
                "pattern" => $1
              };
        }
        elsif ($line =~ /^[#\s]*AddResponseHeader\s+"(.+)"/) {
            push @{ $farm_st->{addresponseheader} },
              {
                "id"     => $add_resp_head_index++,
                "header" => $1
              };
        }
        elsif ($line =~ /^[#\s]*RemoveResponseHead\s+"(.+)"/) {
            push @{ $farm_st->{removeresponseheader} },
              {
                "id"      => $rem_resp_head_index++,
                "pattern" => $1
              };
        }
        elsif ($proxy_ng eq 'true'
            && $line =~ /^[#\s]*ReplaceHeader\s+(.+)\s+"(.+)"\s+"(.+)"\s+"(.*)"/)
        {

            #( my $type, my $header, my $match, my $replace ) = split ( /\s+/, $1 );
            push @{ $farm_st->{replacerequestheader} },
              {
                "id"      => $rep_req_head_index++,
                "header"  => $2,
                "match"   => $3,
                "replace" => $4
              }
              if $1 eq "Request";
            push @{ $farm_st->{replaceresponseheader} },
              {
                "id"      => $rep_res_head_index++,
                "header"  => $2,
                "match"   => $3,
                "replace" => $4
              }
              if $1 eq "Response";
        }
        elsif ($line =~ /Ignore100Continue (\d).*/) {
            $farm_st->{ignore_100_continue} = ($1 eq '0') ? 'false' : 'true';
        }
        elsif ($line =~ /LogLevel\s+(\d).*/) {
            my $lvl = $1 + 0;
            if ($proxy_ng eq 'true') {
                $farm_st->{logs} = 'true' if ($lvl >= 6);
            }
            else {
                $farm_st->{logs} = 'true' if ($lvl >= 5);
            }
        }
    }

    if ($proxy_ng ne 'true') {
        delete $farm_st->{replacerequestheader};
        delete $farm_st->{replaceresponseheader};
    }

    return $farm_st;
}

=pod

=head1 moveHeader

Changes the position of a farm header directive.

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
    foreach my $l (@file) {
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

    farmname - Farm name
    ng_proxy - It is used to set the log parameter depending on the zproxy or pound. It is termporary, it should disappear when pound will be removed from Relianoid

Returns:

    scalar - The possible values are: 0 on disabled, possitive value on enabled or -1 on failure

=cut

sub getHTTPFarmLogs ($farm_name, $proxy_ng = undef) {
    $proxy_ng //= &getGlobalConfiguration('proxy_ng');

    my $output = 'false';

    my $farm_filename = &getFarmFile($farm_name);
    my @lines         = ();

    if (open my $fileconf, '<', "$configdir/$farm_filename") {
        @lines = <$fileconf>;
        close $fileconf;
    }

    foreach my $line (@lines) {
        if    ($line =~ /^[#\s]*Service \"/) { last; }
        elsif ($line =~ /LogLevel\s+(\d).*/) {
            my $lvl = $1 + 0;
            if ($proxy_ng eq 'true') {
                $output = 'true' if ($lvl >= 6);
            }
            else {
                $output = 'true' if ($lvl >= 5);
            }
            last;
        }
    }

    return $output;
}

=pod

=head1 migrateHTTPFarmLogs

This function is temporary. It is used while zproxy and pound are available in relianoid.
This should disappear when pound will be removed

Parameters:

    farmname - Farm name
    proxy_mode

Returns:

    scalar - The possible values are: 0 on disabled, possitive value on enabled or -1 on failure

=cut

sub migrateHTTPFarmLogs ($farm_name, $proxy_mode) {

    # invert the log
    my $read_log = ($proxy_mode eq 'true') ? 'false' : 'true';
    my $log      = &getHTTPFarmLogs($farm_name, $read_log);
    &setHTTPFarmLogs($farm_name, $log, $proxy_mode);

    return;
}

=pod

=head1 setHTTPFarmLogs

Enable or disable the log connection tracking for a http farm

Parameters:

    farmname  - Farm name
    action    - The available actions are: "true" to enable or "false" to disable
    ng_proxy  - It is used to set the log parameter depending on the zproxy or pound. 
                It is termporary, it should disappear when pound will be removed from Relianoid

Returns:

    scalar - The possible values are: 0 on success or -1 on failure

=cut

sub setHTTPFarmLogs ($farm_name, $action, $proxy_ng = undef) {
    $proxy_ng //= &getGlobalConfiguration('proxy_ng');

    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    my $loglvl;
    if ($proxy_ng eq 'true') {
        $loglvl = ($action eq "true") ? 6 : 5;
    }
    else {
        $loglvl = ($action eq "true") ? 5 : 0;
    }

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
        &zenlog("Error modifying http logs", "error", "LSLB");
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

    if (open my $fileconf, '<', "$configdir/$farm_filename") {
        @lines = <$fileconf>;
        close $fileconf;
    }

    foreach my $line (@lines) {
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
