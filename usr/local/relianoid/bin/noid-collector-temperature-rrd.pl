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
use Relianoid::SystemInfo;
use Relianoid::Stats;

my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');
my $db_temp           = "temp.rrd";
my $rrd_filename      = "${collector_rrd_dir}/${db_temp}";

# this script is only for ZNA
if (&getApplianceVersion() !~ /ZNA/) {
    exit;
}

my $temp = &getCPUTemp();

if ($temp eq '') {
    print STDERR "$0: Error: Unable to get the data\n";
    exit;
}

if (!-f $rrd_filename) {
    print "$0: Info: Creating the rrd database ${rrd_filename} ...\n";

    RRDs::create $rrd_filename,     #
      "--step", "300",              # data-point interval in seconds
      "DS:temp:GAUGE:600:0:100",    # temperature
      "RRA:LAST:0.5:1:288",         # daily - every 5 min - 288 reg
      "RRA:MIN:0.5:1:288",          # daily - every 5 min - 288 reg
      "RRA:AVERAGE:0.5:1:288",      # daily - every 5 min - 288 reg
      "RRA:MAX:0.5:1:288",          # daily - every 5 min - 288 reg
      "RRA:LAST:0.5:12:168",        # weekly - every 1 hour - 168 reg
      "RRA:MIN:0.5:12:168",         # weekly - every 1 hour - 168 reg
      "RRA:AVERAGE:0.5:12:168",     # weekly - every 1 hour - 168 reg
      "RRA:MAX:0.5:12:168",         # weekly - every 1 hour - 168 reg
      "RRA:LAST:0.5:96:93",         # monthly - every 8 hours - 93 reg
      "RRA:MIN:0.5:96:93",          # monthly - every 8 hours - 93 reg
      "RRA:AVERAGE:0.5:96:93",      # monthly - every 8 hours - 93 reg
      "RRA:MAX:0.5:96:93",          # monthly - every 8 hours - 93 reg
      "RRA:LAST:0.5:288:372",       # yearly - every 1 day - 372 reg
      "RRA:MIN:0.5:288:372",        # yearly - every 1 day - 372 reg
      "RRA:AVERAGE:0.5:288:372",    # yearly - every 1 day - 372 reg
      "RRA:MAX:0.5:288:372";        # yearly - every 1 day - 372 reg

    if (my $error = RRDs::error) {
        print STDERR "$0: Error: Unable to generate the rrd database: ${error}\n";
    }
}

print "$0: Info: Temperature Stats ...\n";
print "$0: Info:	Temp: ${temp}\n";
print "$0: Info: Updating data in ${rrd_filename} ...\n";

RRDs::update $rrd_filename, "-t", "temp", "N:${temp}";

if (my $error = RRDs::error) {
    print STDERR "$0: Error: Unable to update the rrd database: ${error}\n";
}
