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

Returns: string | undef

- string - Content of the file.
- undef  - Error opening the file.

=cut

sub getFile ($file_name) {
    unless (-f $file_name) {
        &log_error("Could not find file '$file_name'");
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
        &log_error("Could not open file '$file_name': $!");
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

Returns: integer

    1 - success
    0 - failure

=cut

sub setFile ($path, $content) {
    unless (defined $content) {
        &log_error("Trying to save undefined content");
        return 0;
    }

    if (open(my $fh, '>', $path)) {
        binmode $fh;
        print $fh $content;
        close $fh;
    }
    else {
        &log_error("Could not open file '$path': $!");
        return 0;
    }

    return 1;
}

=pod

=head1 insertFileWithPattern

Insert an array in a file before or after a pattern

Returns: integer - Error code.

    0 - Success.
    1 - Pattern not found.

=cut

sub insertFileWithPattern ($file, $array, $pattern, $opt = 'after') {
    my $index = 0;
    my $found = 0;

    tie my @fileconf, 'Tie::File', $file;

    for my $line (@fileconf) {
        if ($line =~ /$pattern/) {
            $found = 1;
            last;
        }
        $index++;
    }

    if (!$found) {
        untie @fileconf;
        return 1;
    }

    if ($opt eq 'after') {
        $index++;
    }

    splice @fileconf, $index, 0, @{$array};
    untie @fileconf;

    return 0;
}

=pod

=head1 createFile

Create an empty file

Parameters:

    filename

Returns: integer

    0 - success
    1 - file already exists
    2 - error creating file

=cut

sub createFile ($filename) {
    if (-f $filename) {
        &log_error("The file $filename already exists", "System");
        return 1;
    }

    if (open(my $fh, '>', $filename)) {
        close $fh;
    }
    else {
        &log_error("The file $filename could not be created: $!", "System");
        return 2;
    }

    return 0;
}

=pod

=head1 deleteFile

=cut

sub deleteFile ($file) {
    if (!-f $file) {
        &log_error("The file $file doesn't exist", "System");
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

sub getFileDateGmt ($filepath) {
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

sub getFileChecksumMD5 ($filepath) {
    my $md5 = {};

    if (-d $filepath) {
        opendir(my $directory, $filepath);
        my @files = readdir($directory);
        closedir($directory);

        for my $file (@files) {
            next if ($file eq "." or $file eq "..");
            $md5 = { %{$md5}, %{ &getFileChecksumMD5($filepath . "/" . $file) } };
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

sub getFileChecksumAction ($checksum_filepath1, $checksum_filepath2) {
    my $files_changed;

    for my $file (keys %{$checksum_filepath1}) {
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
    for my $file (keys %{$checksum_filepath2}) {
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
        &log_error($msg);
        croak($msg);
    }

    my @lines;
    if (open(my $fh, '<', $file_name)) {
        @lines = <$fh>;
        close $fh;
    }
    else {
        my $msg = "Could not open file '$file_name': $!";
        &log_error($msg);
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
        &log_error($msg);
        croak($msg);
    }
    unless (ref $array_ref eq 'ARRAY') {
        my $msg = "Did not receive an array reference";
        &log_error($msg);
        croak($msg);
    }

    if (open(my $fh, '>', $file_name)) {
        print $fh join("", @{$array_ref});
        close $fh;
    }
    else {
        my $msg = "Could not open file '$file_name': $!";
        &log_error($msg);
        croak($msg);
    }

    return 1;
}

1;
