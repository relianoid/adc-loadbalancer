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

use Carp;

=pod

=head1 Module

Relianoid::File

=cut

=pod

=head1 getFile

Returns the content of a file as a string. Binary compatible.

Parameters:

    file_name - string with the location of the file

Returns:

    string - Content of the file.

=cut

sub getFile {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my $file_name = shift;

    unless (-f $file_name) {
        &zenlog("Could not find file '$file_name'");
        return;
    }

    my $content;
    if (open(my $fh, '<', $file_name)) {
        binmode $fh;

        local $/ = undef;
        $content = <$fh>;

        close $fh;
    }
    else {
        &zenlog("Could not open file '$file_name': $!");
        return;
    }

    return $content;
}

=pod

=head1 setFile

Writes a file with the content received. Binary compatible.

Parameters:

    path - string with the location of the file

    content - content to write to the files

Returns:

    integer

    1 - success
    0 - failure

=cut

sub setFile {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my $path    = shift;
    my $content = shift;

    unless (defined $content) {
        &zenlog("Trying to save undefined content");
        return 0;
    }

    if (open(my $fh, '>', $path)) {
        binmode $fh;
        print $fh $content;
        close $fh;
    }
    else {
        &zenlog("Could not open file '$path': $!");
        return 0;
    }

    return 1;
}

=pod

=head1 saveFileHandler

Parameters:

    path - string with the location of the file

    file_handler - file handler, as received from open()

Returns:

    integer

    1 - success
    0 - failure

=cut

sub saveFileHandler {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my $path       = shift;
    my $content_fh = shift;

    unless (defined $content_fh) {
        &zenlog("Trying to save undefined file handler");
        return 0;
    }

    if (open(my $fh, '>', $path)) {
        binmode $fh;
        while (my $line = <$content_fh>) {
            print $fh $line;
        }
        close $fh;
    }
    else {
        &zenlog("Could not open file '$path': $!");
        return 0;
    }

    return 1;
}

=pod

=head1 insertFileWithPattern

Insert an array in a file before or after a pattern

=cut

sub insertFileWithPattern {
    my ($file, $array, $pattern, $opt) = @_;
    my $err = 0;

    $opt //= 'after';

    my $index = 0;
    my $found = 0;
    tie my @fileconf, 'Tie::File', $file;

    foreach my $line (@fileconf) {
        if ($line =~ /$pattern/) {
            $found = 1;
            last;
        }
        $index++;
    }

    return 1 if (!$found);

    $index++ if ($opt eq 'after');

    splice @fileconf, $index, 0, @{$array};
    untie @fileconf;

    return $err;
}

=pod

=head1 createFile

Create an empty file

Parameters:

    filename

Returns:

    integer

    0 - success
    1 - file already exists
    2 - error creating file

=cut

sub createFile {
    my $filename = shift;

    if (-f $filename) {
        &zenlog("The file $filename already exists", "error", "System");
        return 1;
    }

    if (open(my $fh, '>', $filename)) {
        close $fh;
    }
    else {
        &zenlog("The file $filename could not be created: $!", "error", "System");
        return 2;
    }

    return 0;
}

=pod

=head1 deleteFile

=cut

sub deleteFile {
    my $file = shift;

    if (!-f $file) {
        &zenlog("The file $file doesn't exist", "error", "System");
        return 1;
    }
    unlink $file;
    return 0;
}

=pod

=head1 getFileDateGmt

It gets the date of last modification of a file and it returns it in GMT format

Parameters:

    file path - File path

Returns:

    String - Date in GMT format

=cut

sub getFileDateGmt {
    my $filepath = shift;

    use File::stat;
    my @eject = split(/ /, gmtime(stat($filepath)->mtime));
    splice(@eject, 0, 1);
    push(@eject, "GMT");

    my $date = join(' ', @eject);
    chomp $date;

    return $date;
}

=pod

=head1 getFileChecksumMD5

Returns the checksum MD5 of the file or directory including subdirs.

Parameters:

    file path - File path or Directory path

Returns:

    Hash ref - Hash ref with filepath as key and checksummd5 as value.

=cut

sub getFileChecksumMD5 {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my $filepath = shift;
    my $md5      = {};

    if (-d $filepath) {
        opendir(my $directory, $filepath);
        my @files = readdir($directory);
        closedir($directory);
        foreach my $file (@files) {
            next if ($file eq "." or $file eq "..");
            $md5 =
              { %{$md5}, %{ &getFileChecksumMD5($filepath . "/" . $file) } };
        }
    }
    elsif (-f $filepath) {
        if (open(my $fh, '<', $filepath)) {
            binmode($fh);
            use Digest::MD5;
            $md5->{$filepath} = Digest::MD5->new->addfile($fh)->hexdigest;
            close $fh;
        }
    }
    return $md5;
}

=pod

=head1 getFileChecksumAction

Compare two Hashes of checksum filepaths and returns the actions to take.

Parameters:

    checksum_filepath1 - Hash ref checksumMD5 file path1
    checksum_filepath2 - Hash ref checksumMD5 file path2

Returns:

    Hash ref - Hash ref with filepath as key and action as value

=cut

sub getFileChecksumAction {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my $checksum_filepath1 = shift;
    my $checksum_filepath2 = shift;
    my $files_changed;

    foreach my $file (keys %{$checksum_filepath1}) {
        if (!defined $checksum_filepath2->{$file}) {
            $files_changed->{$file} = "del";
        }
        elsif ($checksum_filepath1->{$file} ne $checksum_filepath2->{$file}) {
            $files_changed->{$file} = "modify";
            delete $checksum_filepath2->{$file};
        }
        else {
            delete $checksum_filepath2->{$file};
        }
    }
    foreach my $file (keys %{$checksum_filepath2}) {
        $files_changed->{$file} = "add";
    }
    return $files_changed;
}

=pod

=head1 readFileAsArray

Get the content of a file as an array of lines

Parameters:

    file_name - string. path to file

Returns:

    list - list of lines in the file

=cut

sub readFileAsArray ($file_name) {
    unless (-f $file_name) {
        my $msg = "Could not find file '$file_name'";
        &zenlog($msg, 'error');
        croak($msg);
    }

    my @lines;
    if (open(my $fh, '<', $file_name)) {
        @lines = <$fh>;
        close $fh;
    }
    else {
        my $msg = "Could not open file '$file_name': $!";
        &zenlog($msg, 'error');
        croak($msg);
    }

    return @lines;
}

=pod

=head1 writeFileFromArray

Write an array to a file

Parameters:

    file_name - string. path and file name

    array_ref - reference to the array to be written

Returns:

    list - list of files in the directory

=cut

sub writeFileFromArray ($file_name, $array_ref) {
    unless (defined $file_name and length $file_name) {
        my $msg = "The file name is not a valid string";
        &zenlog($msg, 'error');
        croak($msg);
    }
    unless (ref $array_ref eq 'ARRAY') {
        my $msg = "Did not receive an array reference";
        &zenlog($msg, 'error');
        croak($msg);
    }

    if (open(my $fh, '>', $file_name)) {
        print $fh join("", @{$array_ref});
        close $fh;
    }
    else {
        my $msg = "Could not open file '$file_name': $!";
        &zenlog($msg, 'error');
        croak($msg);
    }

    return 1;
}

=pod

=head1 readDirAsArray

Get a list of filenames in a directory

Parameters:

    dir_name - string. path to directory

Returns:

    list - list of files in the directory

=cut

sub readDirAsArray ($dir_name) {
    unless (-d $dir_name) {
        my $msg = "Could not find directory '$dir_name'";
        &zenlog($msg, 'error');
        croak($msg);
    }

    my @files;
    if (opendir(my $dh, $dir_name)) {
        @files = readdir($dh);
        closedir $dh;
    }
    else {
        my $msg = "Could not open directory '$dir_name': $!";
        &zenlog($msg, 'error');
        croak($msg);
    }

    return @files;
}

1;
