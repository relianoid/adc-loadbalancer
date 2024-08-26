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
my $db_cpu            = "cpu.rrd";
my $rrd_filename      = "${collector_rrd_dir}/${db_cpu}";

my @cpu = &getCPU();

my %cpu = ();
for my $array_ref (@cpu) {
    my ($key, $value) = @{$array_ref};
    $cpu{$key} = $value;
}

my $cpu_user    = $cpu{"CPUuser"};
my $cpu_nice    = $cpu{"CPUnice"};
my $cpu_sys     = $cpu{"CPUsys"};
my $cpu_iowait  = $cpu{"CPUiowait"};
my $cpu_irq     = $cpu{"CPUirq"};
my $cpu_softirq = $cpu{"CPUsoftirq"};
my $cpu_idle    = $cpu{"CPUidle"};
my $cpu_usage   = $cpu{"CPUusage"};

if (!$cpu_user || !$cpu_nice || !$cpu_sys || !$cpu_iowait || !$cpu_irq || !$cpu_softirq || !$cpu_idle || !$cpu_usage) {
    print STDERR "$0: Error: Unable to get the data\n";
    exit;
}

if (!-f $rrd_filename) {
    print "$0: Info: Creating the rrd database ${rrd_filename} ...\n";

    RRDs::create $rrd_filename,
      "--step", "300",
      "DS:user:GAUGE:600:0.00:100.00",
      "DS:nice:GAUGE:600:0.00:100.00",
      "DS:sys:GAUGE:600:0.00:100.00",
      "DS:iowait:GAUGE:600:0.00:100.00",
      "DS:irq:GAUGE:600:0.00:100.00",
      "DS:softirq:GAUGE:600:0.00:100.00",
      "DS:idle:GAUGE:600:0.00:100.00",
      "DS:tused:GAUGE:600:0.00:100.00", "RRA:LAST:0.5:1:288",    # daily - every 5 min - 288 reg
      "RRA:MIN:0.5:1:288",                                       # daily - every 5 min - 288 reg
      "RRA:AVERAGE:0.5:1:288",                                   # daily - every 5 min - 288 reg
      "RRA:MAX:0.5:1:288",                                       # daily - every 5 min - 288 reg
      "RRA:LAST:0.5:12:168",                                     # weekly - every 1 hour - 168 reg
      "RRA:MIN:0.5:12:168",                                      # weekly - every 1 hour - 168 reg
      "RRA:AVERAGE:0.5:12:168",                                  # weekly - every 1 hour - 168 reg
      "RRA:MAX:0.5:12:168",                                      # weekly - every 1 hour - 168 reg
      "RRA:LAST:0.5:96:93",                                      # monthly - every 8 hours - 93 reg
      "RRA:MIN:0.5:96:93",                                       # monthly - every 8 hours - 93 reg
      "RRA:AVERAGE:0.5:96:93",                                   # monthly - every 8 hours - 93 reg
      "RRA:MAX:0.5:96:93",                                       # monthly - every 8 hours - 93 reg
      "RRA:LAST:0.5:288:372",                                    # yearly - every 1 day - 372 reg
      "RRA:MIN:0.5:288:372",                                     # yearly - every 1 day - 372 reg
      "RRA:AVERAGE:0.5:288:372",                                 # yearly - every 1 day - 372 reg
      "RRA:MAX:0.5:288:372";                                     # yearly - every 1 day - 372 reg

    if (my $error = RRDs::error) {
        print STDERR "$0: Error: Unable to generate the rrd database: ${error}\n";
    }
}

print "$0: Info: CPU Stats ...\n";
print "$0: Info:	user: ${cpu_user} %\n";
print "$0: Info:	nice: ${cpu_nice} %\n";
print "$0: Info:	sys: ${cpu_sys} %\n";
print "$0: Info:	iowait: ${cpu_iowait} %\n";
print "$0: Info:	irq: ${cpu_irq} %\n";
print "$0: Info:	softirq: ${cpu_softirq} %\n";
print "$0: Info:	idle: ${cpu_idle} %\n";
print "$0: Info:	total used: ${cpu_usage} %\n";
print "$0: Info: Updating data in ${rrd_filename} ...\n";

RRDs::update $rrd_filename,
  "-t", "user:nice:sys:iowait:irq:softirq:idle:tused",
  "N:${cpu_user}:${cpu_nice}:${cpu_sys}:${cpu_iowait}:${cpu_irq}:${cpu_softirq}:${cpu_idle}:${cpu_usage}";

if (my $error = RRDs::error) {
    print STDERR "$0: Error: Unable to update the rrd database: ${error}\n";
}
