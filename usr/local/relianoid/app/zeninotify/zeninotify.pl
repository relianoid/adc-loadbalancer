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

use Linux::Inotify2;
use Sys::Hostname;

# Load configuration
require "/usr/local/relianoid/app/ucarp/etc/cluster.conf";
#

my $hostname = hostname();
my $sync     = "firstime";
my @alert    = "";
push(@alert, $configdir);
push(@alert, $rttables);

#log file
open STDERR, '>>', "$zeninolog" or die "Error creating log file";
open STDOUT, '>>', "$zeninolog" or die "Error creating log file";

print "Running the firs replication...\n";
if ($exclude ne "") {
    print "$rsync $zenrsync $exclude $configdir\/ root\@$remote_ip:$configdir\/\n";
    my @eject = `$rsync $zenrsync  $exclude $configdir\/ root\@$remote_ip:$configdir\/`;
    print @eject;
    print "$rsync $zenrsync $rttables root\@$remote_ip:$rttables\n";
    my @eject = `$rsync $zenrsync $rttables root\@$remote_ip:$rttables`;
    print @eject;
}
print "Terminated the first replication...\n";

my $inotify = Linux::Inotify2->new();

#foreach ($configdir $rttable)
foreach (@alert) {
    $inotify->watch($_, IN_MODIFY | IN_CREATE | IN_DELETE);

}

while (1) {

    # By default this will block until something is read
    my @events = $inotify->read();
    if (scalar(@events) == 0) {
        print "read error: $!";
        last;
    }

    foreach (@events) {
        if ($_->name !~ /^\..*/ && $_->name !~ /.*\~$/) {
            $action = sprintf("%d", $_->mask);
            $name   = sprintf($_->fullname);
            $file   = sprintf($_->name);
            if ($action eq 512) {
                $action = "DELETED";
            }
            if ($action eq 2) {
                $action = "MODIFIED";
            }
            if ($action eq 256) {
                $action = "CREATED";
            }
            printf "File: $file; Action: $action Fullname: $name\n";

            if ($name =~ /config/) {
                print "Exclude files: $exclude\n";
                my @eject = `$rsync $zenrsync $exclude $configdir\/ root\@$remote_ip:$configdir\/`;
                print @eject;
                print
                  "run replication process: $rsync $zenrsync $exclude $configdir\/ root\@$remote_ip:$configdir\/\n";
            }

            if ($name =~ /iproute2/) {
                my @eject = `$rsync $zenrsync $rttables root\@$remote_ip:$rttables`;
                print @eject;
                print
                  "run replication process: $rsync $zenrsync $rttables root\@$remote_ip:$rttables\n";
            }
        }
    }

}
