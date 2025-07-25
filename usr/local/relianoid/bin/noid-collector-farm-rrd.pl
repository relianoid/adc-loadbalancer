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
use Relianoid::Farm::Base;
use Relianoid::Farm::Stats;
use Relianoid::Net::ConnStats;

my $eload = eval { require Relianoid::ELoad; };

my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');

for my $farmfile (&getFarmList()) {
    my $farm_name   = &getFarmName($farmfile);
    my $farm_type   = &getFarmType($farm_name);
    my $farm_status = &getFarmStatus($farm_name);

    if ($farm_type eq "datalink" || $farm_status ne "up") {
        next;
    }

    my $db_farm      = "${farm_name}-farm.rrd";
    my $rrd_filename = "${collector_rrd_dir}/${db_farm}";

    my $synconns;
    my $globalconns;

    if ($farm_type eq 'gslb' && $eload) {
        my $stats = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Stats',
            func   => 'getGSLBFarmStats',
            args   => [$farm_name],
        );

        $synconns    = $stats->{syn};
        $globalconns = $stats->{est};
    }
    elsif ($farm_type eq 'eproxy' && $eload) {
        my $stats = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Stats',
            func   => 'getEproxyFarmStats',
            args   => [ { farm_name => $farm_name } ],
        );

        $synconns    = $stats->{pending};
        $globalconns = $stats->{established};
    }
    else {
        my $vip = &getFarmVip("vip", $farm_name);
        my $netstat;

        if ($farm_type eq 'l4xnat') {
            $netstat = &getConntrack("", $vip, "", "", "");
        }

        $synconns    = &getFarmSYNConns($farm_name, $netstat);    # SYN_RECV connections
        $globalconns = &getFarmEstConns($farm_name, $netstat);    # ESTABLISHED connections
    }

    if ($globalconns eq '' || $synconns eq '') {
        print STDERR "$0: Error: Unable to get the data for farm ${farm_name}\n";
        exit;
    }

    if (!-f $rrd_filename) {
        print "$0: Info: Creating the rrd database ${rrd_filename} ...\n";

        RRDs::create $rrd_filename,                               #
          "--step", "300",                                        #
          "DS:pending:GAUGE:600:0:12500000",                      #
          "DS:established:GAUGE:600:0:12500000",                  #
          "RRA:LAST:0.5:1:288",                                   # daily - every 5 min - 288 reg
          "RRA:MIN:0.5:1:288",                                    # daily - every 5 min - 288 reg
          "RRA:AVERAGE:0.5:1:288",                                # daily - every 5 min - 288 reg
          "RRA:MAX:0.5:1:288",                                    # daily - every 5 min - 288 reg
          "RRA:LAST:0.5:12:168",                                  # weekly - every 1 hour - 168 reg
          "RRA:MIN:0.5:12:168",                                   # weekly - every 1 hour - 168 reg
          "RRA:AVERAGE:0.5:12:168",                               # weekly - every 1 hour - 168 reg
          "RRA:MAX:0.5:12:168",                                   # weekly - every 1 hour - 168 reg
          "RRA:LAST:0.5:96:93",                                   # monthly - every 8 hours - 93 reg
          "RRA:MIN:0.5:96:93",                                    # monthly - every 8 hours - 93 reg
          "RRA:AVERAGE:0.5:96:93",                                # monthly - every 8 hours - 93 reg
          "RRA:MAX:0.5:96:93",                                    # monthly - every 8 hours - 93 reg
          "RRA:LAST:0.5:288:372",                                 # yearly - every 1 day - 372 reg
          "RRA:MIN:0.5:288:372",                                  # yearly - every 1 day - 372 reg
          "RRA:AVERAGE:0.5:288:372",                              # yearly - every 1 day - 372 reg
          "RRA:MAX:0.5:288:372";                                  # yearly - every 1 day - 372 reg

        if (my $error = RRDs::error) {
            print STDERR "$0: Error: Unable to generate the swap rrd database: ${error}\n";
        }
    }

    print "$0: Info: ${farm_name} Farm Connections Stats ...\n";
    print "$0: Info:	Pending: ${synconns}\n";
    print "$0: Info:	Established: ${globalconns}\n";
    print "$0: Info: Updating data in ${rrd_filename} ...\n";

    RRDs::update($rrd_filename, "-t", "pending:established", "N:${synconns}:${globalconns}");

    if (my $error = RRDs::error) {
        print STDERR "$0: Error: Unable to update the rrd database: ${error}\n";
    }
}
