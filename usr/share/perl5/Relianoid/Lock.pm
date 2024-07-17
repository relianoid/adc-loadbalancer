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

require Relianoid::Log;

my $lock_file = undef;
my $lock_fh   = undef;

=pod

=head1 Module

Relianoid::Lock

=cut

=pod

=head1 getLockFile

Write a lock file based on a input path

=cut

sub getLockFile ($lock) {
    $lock =~ s/\//_/g;
    $lock = "/tmp/$lock.lock";

    return $lock;
}

=pod

=head1 openlock

Open file and lock it, return the filehandle.

    Usage:

        my $filehandle = &openlock( $path );
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

Returns:

    scalar - Filehandle

=cut

sub openlock ($path, $mode = '') {
    $mode =~ s/a/>>/;    # append
    $mode =~ s/w/>/;     # write
    $mode =~ s/r/</;     # read

    my $binmode  = $mode =~ s/b//;
    my $textmode = $mode =~ s/t//;

    my $encoding = '';
    $encoding = ":encoding(UTF-8)" if $textmode;
    $encoding = ":raw :bytes"      if $binmode;

    my $fh;
    if (open($fh, "$mode $encoding", $path)) {    ## no critic (RequireBriefOpen)
        if ($binmode) {
            binmode $fh;
        }
    }
    else {
        &zenlog("Error opening the file $path: $!");
        return;
    }

    if ($mode =~ />/) {
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

tie aperture with lock

    Usage:

        $handleArray = &tielock($file);

    Examples:

        $handleArray = &tielock("test.dat");
        $handleArray = &tielock($filename);

Parameters:

    file_name - Path to File.

Returns:

    scalar - Reference to the array with the content of the file.

Bugs:

    Not used yet.

=cut

sub ztielock ($array_ref, $file_name) {
    require Tie::File;

    my $o = tie @{$array_ref}, "Tie::File", $file_name;
    return $o->flock;
}

=pod

=head1 copyLock

=cut

sub copyLock ($ori, $dst) {
    my $fhOri = &openlock($ori, 'r') or return 1;
    my $fhDst = &openlock($dst, 'w') or do { close $fhOri; return 1; };

    while (my $line = <$fhOri>) {
        print $fhDst $line;
    }

    close $fhOri;
    close $fhDst;

    return 0;
}

=pod

=head1 lockResource

    lock or release an API resource.

Parameters:

    resource - Path to file.
    operation - l (lock), u (unlock), ud (unlock, delete the lock file), r (read)

Bugs:

    Not used yet.

=cut

sub lockResource ($resource, $oper) {
    # TODO: Define here the available resources
    # bonding
    # crl
    # ...

    if ($oper =~ /l/) {
        $lock_file = &getLockFile($resource);
        $lock_fh   = &openlock($lock_file, 'w');
    }
    elsif ($oper =~ /u/) {
        close $lock_fh;
        unlink $lock_file if ($oper =~ /d/);
    }
    elsif ($oper =~ /r/) {
        $lock_file = &getLockFile($resource);
        $lock_fh   = &openlock($lock_file, 'r');
    }

    return;
}

1;

