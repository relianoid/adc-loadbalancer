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

use Fcntl ':flock';    #use of lock functions

use Relianoid::Log;

my $lock_file = undef;
my $lock_fh   = undef;

=pod

=head1 Module

Relianoid::Lock

=cut

=pod

=head1 getLockFile

Get a lock file from a resource or file path.

The lock file will be a path in /tmp/ and will have the extension '.lock'.

Parameters:

    lock - string - Resource name.

Returns: string - File name of lock file for the input resource.

=cut

sub getLockFile ($lock) {
    # replace slash with underscore
    $lock =~ s/\//_/g;
    $lock = "/tmp/$lock.lock";

    return $lock;
}

=pod

=head1 openlock

Open file and lock it, return the filehandle.

    Usage:

        my $filehandle = &openlock( $path, 'r' );

    Lock is exclusive when the file is openend for writing.
    Lock is shared when the file is openend for reading.
    So only opening for writing is blocking the file for other uses.

    Opening modes:

        r - Read
        w - Write
        a - Append

        t - text mode. To enforce encoding UTF-8.
        b - binary mode. To make sure no information is lost.

    'r', 'w' and 'a' are mutually exclusive.
    't' and 'b' are mutually exclusive.

    If neither 't' or 'b' are used on the mode parameter, the default Perl mode is used.

    Take in mind, if you are executing process in parallel, if any of them remove the tmp locking file,
    the resource will be unlocked.

Parameters:

    path - Absolute or relative path to the file to be opened.
    mode - Mode used to open the file.

Returns: file handle ref - Referent to the file handle.

=cut

sub openlock ($path, $mode) {
    my $binmode  = $mode =~ s/b//;
    my $textmode = $mode =~ s/t//;

    if ($binmode && $textmode) {
        log_error("Raw and UTF-8 encoding cannot be used at the same time");
        return;
    }

    my $encoding = '';
    if    ($textmode) { $encoding = ":encoding(UTF-8)" }
    elsif ($binmode)  { $encoding = ":raw :bytes" }

    my $open_mode;
    if    ($mode eq 'a') { $open_mode = '>>' }
    elsif ($mode eq 'w') { $open_mode = '>' }
    elsif ($mode eq 'r') { $open_mode = '<' }

    if (not $open_mode) {
        log_error("Bad open mode");
        return;
    }

    my $fh;
    my $open_mode_with_layer = $encoding ? "${open_mode} ${encoding}" : $open_mode;

    if (open($fh, $open_mode_with_layer, $path)) {    ## no critic (RequireBriefOpen)
        if ($binmode) {
            binmode $fh;
        }
    }
    else {
        &log_error("Error opening the file $path: $!");
        return;
    }

    if ($open_mode eq ">") {
        # exclusive lock for writing
        flock $fh, LOCK_EX;
    }
    else {
        # shared lock for reading
        flock $fh, LOCK_SH;
    }

    return $fh;
}

=pod

=head1 ztielock

tie a file and lock it.

Usage:

    $handleArray = &tielock($file);

Examples:

    $handleArray = &tielock("test.dat");
    $handleArray = &tielock($filename);

Parameters:

    array_ref - array ref - Reference to the array to contain the file.
    file_name - Path to File.

Returns: array ref - content of the file.

=cut

sub ztielock ($array_ref, $file_name) {
    require Tie::File;

    my $o = tie @{$array_ref}, "Tie::File", $file_name;
    return $o->flock;
}

=pod

=head1 copyLock

Copy a lock file.

Parameters:

    origin      - string - Path to file to be copied.
    destination - string - Path to copy of file.

Returns: nothing

=cut

sub copyLock ($origin, $destination) {
    my $fh_origin = &openlock($origin, 'r')
      or return 1;

    my $fh_destination;

    unless ($fh_destination = &openlock($destination, 'w')) {
        close $fh_origin;
        return 1;
    }

    while (my $line = <$fh_origin>) {
        print $fh_destination $line;
    }

    close $fh_origin;
    close $fh_destination;

    return 0;
}

=pod

=head1 lockResource

Lock or release an API resource.

TODO: Define here the available resources
bonding
crl
...

Parameters:

    resource - Path to file.
    operation - l (lock), u (unlock), ud (unlock, delete the lock file), r (read)

Returns: nothing

=cut

sub lockResource ($resource, $operation) {
    if ($operation =~ /l/) {
        $lock_file = &getLockFile($resource);
        $lock_fh   = &openlock($lock_file, 'w');
    }
    elsif ($operation =~ /u/) {
        close $lock_fh;
        unlink $lock_file if ($operation =~ /d/);
    }
    elsif ($operation =~ /r/) {
        $lock_file = &getLockFile($resource);
        $lock_fh   = &openlock($lock_file, 'r');
    }

    return;
}

1;

