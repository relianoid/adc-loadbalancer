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

use Relianoid::Config;

my $configdir = &getGlobalConfiguration('configdir');

=pod

=head1 Module

Relianoid::Farm::Core

=cut

=pod

=head1 getFarmType

Get the farm type for a farm

Parameters:

    farm_name - Farm name

Returns:

    String - "http", "https", "datalink", "l4xnat", "gslb" or 1 on failure

FIXME: Return undefined, or "", or throw an exception on failure.

=cut

sub getFarmType ($farm_name) {
    my $farm_filename = &getFarmFile($farm_name);

    if ($farm_filename =~ /^${farm_name}_proxy.cfg/) {
        require Relianoid::File;

        if (grep { /ListenHTTPS/ } readFileAsArray("${configdir}/${farm_filename}")) {
            return "https";
        }
        else {
            return "http";
        }
    }
    elsif ($farm_filename =~ /^${farm_name}_datalink.cfg/) {
        return "datalink";
    }
    elsif ($farm_filename =~ /^${farm_name}_l4xnat.cfg/) {
        return "l4xnat";
    }
    elsif ($farm_filename =~ /^${farm_name}_gslb.cfg/) {
        return "gslb";
    }
    elsif ($farm_filename =~ /^${farm_name}_eproxy.yaml/) {
        return "eproxy";
    }

    return 1;
}

=pod

=head1 getFarmFile

Returns farm file name

Parameters:

    farm_name - Farm name

Returns:

    String - file name or -1 on failure

=cut

sub getFarmFile ($farm_name) {
    opendir(my $dir, $configdir) || return -1;

    my @farm_files =
      grep {
             /^${farm_name}\_(?:gslb|proxy|datalink|l4xnat)\.cfg$|^${farm_name}\_eproxy\.yaml$/
          && !/^${farm_name}\_.*guardian\.conf$/
          && !/^${farm_name}\_status.cfg$/
      } readdir($dir);

    closedir $dir;

    if (@farm_files) {
        return $farm_files[0];
    }
    else {
        return -1;
    }
}

=pod

=head1 getFarmName

Returns farms configuration filename list

Parameters:

    farm_filename - Farm file

Returns: string - farm name.

=cut

sub getFarmName ($farm_filename) {
    my @filename_split = split("_", $farm_filename);
    return $filename_split[0];
}

=pod

=head1 getFarmList

Returns farms configuration file name list.

Parameters: none

Returns: string array - List of configuration file names.

=cut

sub getFarmList() {
    opendir(my $directory, $configdir);
    my @cfgFiles = sort (grep { /\.cfg$|\.yaml$/ } readdir($directory));
    closedir($directory);

    my @files1 = grep { /_proxy\.cfg$/ } @cfgFiles;
    my @files2 = grep { /_datalink\.cfg$/ } @cfgFiles;
    my @files3 = grep { /_l4xnat\.cfg$/ } @cfgFiles;
    my @files4 = grep { /_gslb\.cfg$/ } @cfgFiles;
    my @files5 = grep { /_eproxy\.yaml$/ } @cfgFiles;
    my @files  = (@files1, @files2, @files3, @files4, @files5);

    return @files;
}

=pod

=head1 getFarmsByType

Get all farms of a type

Parameters:

    type - Farm type. The available options are "http", "https", "datalink", "l4xnat" or "gslb"

Returns:

    Array - List of farm name of a type

=cut

sub getFarmsByType ($farm_type) {
    my @farm_names = ();

    opendir(my $dir, "$configdir") || return -1;

    # gslb uses a directory, not a file
    # my @farm_files = grep { /^.*\_.*\.cfg/ && -f "$configdir/$_" } readdir ( $dir );
    my @farm_files = grep { /^.*\_.*\.cfg$/ } readdir($dir);
    closedir $dir;

    for my $farm_filename (@farm_files) {
        next if $farm_filename =~ /.*status.cfg/;
        next if $farm_filename =~ /.*sessions.cfg/;
        my $farm_name = &getFarmName($farm_filename);

        if (&getFarmType($farm_name) eq $farm_type) {
            push(@farm_names, $farm_name);
        }
    }

    return @farm_names;
}

=pod

=head1 getFarmNameList

Returns a list with the farm names.

Parameters: None

Returns:

    array - list of farm names.

=cut

sub getFarmNameList () {
    my @farm_names = ();

    for my $farm_filename (&getFarmList()) {
        push(@farm_names, &getFarmName($farm_filename));
    }

    return @farm_names;
}

=pod

=head1 getFarmExists

Check if a farm exists

Parameters:

    Farm - Farm name

Returns:

    Integer - 1 if the farm exists or 0 if it is not

=cut

sub getFarmExists ($farmname) {
    my $out = 0;
    $out = 1 if (grep { $farmname eq $_ } &getFarmNameList());
    return $out;
}

1;

