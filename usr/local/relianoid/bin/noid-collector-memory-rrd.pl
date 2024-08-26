#!/usr/bin/perl
###############################################################################
#
#    RELIANOID Software License
#    This file is part of the RELIANOID Load Balancer software package.
#
#    Copyright (C) 2014-today RELIANOID SL, Sevilla (Spain)
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

my $db_mem   = "mem.rrd";
my $db_memsw = "memsw.rrd";

my $ram_rrd_filename  = "${collector_rrd_dir}/${db_mem}";
my $swap_rrd_filename = "${collector_rrd_dir}/${db_memsw}";

my @mem = &getMemStats("b");

my %mem = ();
for my $array_ref (@mem) {
    my ($key, $value) = @{$array_ref};
    $mem{$key} = $value;
}

my $mvalue  = $mem{"MemTotal"};
my $mused   = $mem{"MemUsed"};
my $mfvalue = $mem{"MemFree"};
my $mbvalue = $mem{"Buffers"};
my $mcvalue = $mem{"Cached"};

my $swtvalue = $mem{"SwapTotal"};
my $swfvalue = $mem{"SwapFree"};
my $swused   = $mem{"SwapUsed"};
my $swcvalue = $mem{"SwapCached"};

if (!$mvalue || !$mused || !$mfvalue || !$mcvalue || !$swtvalue || !$swfvalue || !$swused || !$swcvalue) {
    print STDERR "$0: Error: Unable to get the data\n";
    exit;
}

if (!-f $ram_rrd_filename) {
    print "$0: Info: Creating the rrd database ${ram_rrd_filename} ...\n";

    RRDs::create $ram_rrd_filename,    #
      "--step", "300",                 # data-point interval in seconds
      "DS:memt:GAUGE:600:0:U",         # total
      "DS:memu:GAUGE:600:0:U",         # used
      "DS:memf:GAUGE:600:0:U",         # free
      "DS:memc:GAUGE:600:0:U",         # cache
      "RRA:LAST:0.5:1:288",            # daily - every 5 min - 288 reg
      "RRA:MIN:0.5:1:288",             # daily - every 5 min - 288 reg
      "RRA:AVERAGE:0.5:1:288",         # daily - every 5 min - 288 reg
      "RRA:MAX:0.5:1:288",             # daily - every 5 min - 288 reg
      "RRA:LAST:0.5:12:168",           # weekly - every 1 hour - 168 reg
      "RRA:MIN:0.5:12:168",            # weekly - every 1 hour - 168 reg
      "RRA:AVERAGE:0.5:12:168",        # weekly - every 1 hour - 168 reg
      "RRA:MAX:0.5:12:168",            # weekly - every 1 hour - 168 reg
      "RRA:LAST:0.5:96:93",            # monthly - every 8 hours - 93 reg
      "RRA:MIN:0.5:96:93",             # monthly - every 8 hours - 93 reg
      "RRA:AVERAGE:0.5:96:93",         # monthly - every 8 hours - 93 reg
      "RRA:MAX:0.5:96:93",             # monthly - every 8 hours - 93 reg
      "RRA:LAST:0.5:288:372",          # yearly - every 1 day - 372 reg
      "RRA:MIN:0.5:288:372",           # yearly - every 1 day - 372 reg
      "RRA:AVERAGE:0.5:288:372",       # yearly - every 1 day - 372 reg
      "RRA:MAX:0.5:288:372";           # yearly - every 1 day - 372 reg

    if (my $error = RRDs::error) {
        print STDERR "$0: Error: Unable to generate the memory rrd database: ${error}\n";
    }
}

if (!-f $swap_rrd_filename) {
    print "$0: Info: Creating the rrd database ${swap_rrd_filename} ...\n";

    RRDs::create $swap_rrd_filename,    #
      "--step", "300",                  # data-point interval in seconds
      "DS:swt:GAUGE:600:0:U",           # total
      "DS:swu:GAUGE:600:0:U",           # used
      "DS:swf:GAUGE:600:0:U",           # free
      "DS:swc:GAUGE:600:0:U",           # cache
      "RRA:LAST:0.5:1:288",             # daily - every 5 min - 288 reg
      "RRA:MIN:0.5:1:288",              # daily - every 5 min - 288 reg
      "RRA:AVERAGE:0.5:1:288",          # daily - every 5 min - 288 reg
      "RRA:MAX:0.5:1:288",              # daily - every 5 min - 288 reg
      "RRA:LAST:0.5:12:168",            # weekly - every 1 hour - 168 reg
      "RRA:MIN:0.5:12:168",             # weekly - every 1 hour - 168 reg
      "RRA:AVERAGE:0.5:12:168",         # weekly - every 1 hour - 168 reg
      "RRA:MAX:0.5:12:168",             # weekly - every 1 hour - 168 reg
      "RRA:LAST:0.5:96:93",             # monthly - every 8 hours - 93 reg
      "RRA:MIN:0.5:96:93",              # monthly - every 8 hours - 93 reg
      "RRA:AVERAGE:0.5:96:93",          # monthly - every 8 hours - 93 reg
      "RRA:MAX:0.5:96:93",              # monthly - every 8 hours - 93 reg
      "RRA:LAST:0.5:288:372",           # yearly - every 1 day - 372 reg
      "RRA:MIN:0.5:288:372",            # yearly - every 1 day - 372 reg
      "RRA:AVERAGE:0.5:288:372",        # yearly - every 1 day - 372 reg
      "RRA:MAX:0.5:288:372";            # yearly - every 1 day - 372 reg

    if (my $error = RRDs::error) {
        print STDERR "$0: Error: Unable to generate the swap rrd database: ${error}\n";
    }
}

print "$0: Info: Memory Stats ...\n";
print "$0: Info:	Total Memory: ${mvalue} Bytes\n";
print "$0: Info:	Used Memory: ${mused} Bytes\n";
print "$0: Info:	Free Memory: ${mfvalue} Bytes\n";
print "$0: Info:	Cached Memory: ${mcvalue} Bytes\n";
print "$0: Info:	Buffered Memory: ${mbvalue} Bytes\n";
print "$0: Info: Updating data in ${ram_rrd_filename} ...\n";

RRDs::update $ram_rrd_filename, "-t", "memt:memu:memf:memc", "N:${mvalue}:${mused}:${mfvalue}:" . ($mcvalue + $mbvalue);

if (my $error = RRDs::error) {
    print STDERR "$0: Error: Unable to update the rrd database: ${error}\n";
}

print "$0: Info: Swap Stats ...\n";
print "$0: Info:	Total Memory Swap: ${swtvalue} Bytes\n";
print "$0: Info:	Used Memory Swap: ${swused} Bytes\n";
print "$0: Info:	Free Memory Swap: ${swfvalue} Bytes\n";
print "$0: Info:	Cached Memory Swap: ${swcvalue} Bytes\n";
print "$0: Info: Updating data in $swap_rrd_filename ...\n";

RRDs::update $swap_rrd_filename, "-t", "swt:swu:swf:swc", "N:${swtvalue}:${swused}:${swfvalue}:${swcvalue}";

if (my $error = RRDs::error) {
    print STDERR "$0: Error: Unable to update the rrd database: ${error}\n";
}
