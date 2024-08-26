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
use RRDs;
use Relianoid::Config;
use Relianoid::Stats;

my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');
my $db_load           = "load.rrd";
my $rrd_filename      = "${collector_rrd_dir}/${db_load}";

my @load = &getLoadStats();

my %load = ();
for my $array_ref (@load) {
    my ($key, $value) = @{$array_ref};
    $load{$key} = $value;
}

my $last   = $load{"Last"};
my $last5  = $load{"Last 5"};
my $last15 = $load{"Last 15"};

if (!$last || !$last5 || !$last15) {
    print STDERR "$0: Error: Unable to get the data\n";
    exit;
}

if (!-f $rrd_filename) {
    print "$0: Info: Creating the rrd database ${rrd_filename} ...\n";

    RRDs::create $rrd_filename,             #
      "--step",                             #
      "300",                                #
      "DS:load:GAUGE:600:0.00:100.00",      #
      "DS:load5:GAUGE:600:0.00:100.00",     #
      "DS:load15:GAUGE:600:0.00:100.00",    #
      "RRA:LAST:0.5:1:288",                 # daily - every 5 min - 288 reg
      "RRA:MIN:0.5:1:288",                  # daily - every 5 min - 288 reg
      "RRA:AVERAGE:0.5:1:288",              # daily - every 5 min - 288 reg
      "RRA:MAX:0.5:1:288",                  # daily - every 5 min - 288 reg
      "RRA:LAST:0.5:12:168",                # weekly - every 1 hour - 168 reg
      "RRA:MIN:0.5:12:168",                 # weekly - every 1 hour - 168 reg
      "RRA:AVERAGE:0.5:12:168",             # weekly - every 1 hour - 168 reg
      "RRA:MAX:0.5:12:168",                 # weekly - every 1 hour - 168 reg
      "RRA:LAST:0.5:96:93",                 # monthly - every 8 hours - 93 reg
      "RRA:MIN:0.5:96:93",                  # monthly - every 8 hours - 93 reg
      "RRA:AVERAGE:0.5:96:93",              # monthly - every 8 hours - 93 reg
      "RRA:MAX:0.5:96:93",                  # monthly - every 8 hours - 93 reg
      "RRA:LAST:0.5:288:372",               # yearly - every 1 day - 372 reg
      "RRA:MIN:0.5:288:372",                # yearly - every 1 day - 372 reg
      "RRA:AVERAGE:0.5:288:372",            # yearly - every 1 day - 372 reg
      "RRA:MAX:0.5:288:372";                # yearly - every 1 day - 372 reg

    if (my $error = RRDs::error) {
        print STDERR "$0: Error: Unable to generate the rrd database: ${error}\n";
    }
}

print "$0: Info: Load Stats ...\n";
print "$0: Info:	Last minute: ${last}\n";
print "$0: Info:	Last 5 minutes: ${last5}\n";
print "$0: Info:	Last 15 minutes: ${last15}\n";
print "$0: Info: Updating data in ${rrd_filename} ...\n";

RRDs::update $rrd_filename, "-t", "load:load5:load15", "N:${last}:${last5}:${last15}";

if (my $error = RRDs::error) {
    print STDERR "$0: Error: Unable to update the rrd database: ${error}\n";
}
