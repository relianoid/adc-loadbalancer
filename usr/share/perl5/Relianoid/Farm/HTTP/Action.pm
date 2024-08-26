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

my $eload = eval { require Relianoid::ELoad };

my $configdir = &getGlobalConfiguration('configdir');

=pod

=head1 Module

Relianoid::Farm::HTTP::Action

=cut

=pod

=head1 _runHTTPFarmStart

Run a HTTP farm

Parameters:

    farm_name - Farm name
    writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:

    Integer - return 0 on success or different of 0 on failure

=cut

sub _runHTTPFarmStart ($farm_name, $writeconf = undef) {
    require Relianoid::System;
    require Relianoid::Farm::HTTP::Backend;
    require Relianoid::Farm::Config;

    my $status        = -1;
    my $farm_filename = &getFarmFile($farm_name);
    my $proxy         = &getGlobalConfiguration('proxy');
    my $piddir        = &getGlobalConfiguration('piddir');

    require Relianoid::Lock;
    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    close $lock_fh;

    &log_info("Checking $farm_name farm configuration", "LSLB");
    return -1 if (&getHTTPFarmConfigIsOK($farm_name));

    my $args = '';
    if ($eload) {
        my $ssyncd_enabled = &getGlobalConfiguration('ssyncd_enabled');
        $args = '-s' if ($ssyncd_enabled eq 'true');
    }

    my $cmd = "$proxy $args -f $configdir\/$farm_filename -p $piddir\/$farm_name\_proxy.pid";
    $status = &run_with_env("$cmd");

    if ($status) {
        &log_error("failed: $cmd", "LSLB");
        return $status;
    }

    # set backend at status before that the farm stopped
    &setHTTPFarmBackendStatusFromFile($farm_name);
    &setHTTPFarmBootStatus($farm_name, "up") if ($writeconf);

    return $status;
}

=pod

=head1 _runHTTPFarmStop

Stop a HTTP farm

Parameters:

    farm_name - Farm name
    writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:

    Integer - return 0 on success or different of 0 on failure

=cut

sub _runHTTPFarmStop ($farm_name, $writeconf = undef) {
    require Relianoid::FarmGuardian;
    my $time = &getGlobalConfiguration("http_farm_stop_grace_time");

    &runFarmGuardianStop($farm_name, "");

    require Relianoid::Farm::HTTP::Config;
    &setHTTPFarmBootStatus($farm_name, "down") if ($writeconf);

    require Relianoid::Farm::HTTP::Config;
    return 0 if &getHTTPFarmStatus($farm_name) eq "down";

    my $piddir = &getGlobalConfiguration('piddir');

    if (&getHTTPFarmConfigIsOK($farm_name) == 0) {
        my @pids = &getFarmPid($farm_name);

        if (!@pids) {
            &log_warn("Not found pid", "LSLB");
        }
        else {
            my $pid = join(', ', @pids);
            &log_info("Stopping HTTP farm $farm_name with PID $pid", "LSLB");
            kill 9, @pids;
            sleep($time);
        }

        unlink("${piddir}/${farm_name}_proxy.pid") if -e "${piddir}/${farm_name}_proxy.pid";
        unlink("/tmp/${farm_name}_proxy.socket")   if -e "/tmp/${farm_name}_proxy.socket";

        require Relianoid::Lock;
        my $lf = &getLockFile($farm_name);
        unlink $lf if -e $lf;
    }
    else {
        &log_info("Farm $farm_name can't be stopped, check the logs and modify the configuration", "LSLB");
        return 1;
    }

    return 0;
}

=pod

=head1 copyHTTPFarm

Function that does a copy of a farm configuration.
If the flag has the value 'del', the old farm will be deleted.

Parameters:

    farm_name   - Farm name
    newfarmname - New farm name
    del         - It expects a 'del' string to delete the old farm.
                  It is used to copy or rename the farm.

Returns:

    Integer - Error code: return 0 on success or -1 on failure

=cut

sub copyHTTPFarm ($farm_name, $new_farm_name, $del = "") {
    use File::Copy qw(copy);
    require Relianoid::File;

    my $output           = 0;
    my @farm_configfiles = (
        "${configdir}/${farm_name}_status.cfg",  "${configdir}/${farm_name}_proxy.cfg",
        "${configdir}/${farm_name}_Err414.html", "${configdir}/${farm_name}_Err500.html",
        "${configdir}/${farm_name}_Err501.html", "${configdir}/${farm_name}_Err503.html",
        "${configdir}/${farm_name}_sessions.cfg",
    );
    my @new_farm_configfiles = (
        "${configdir}/${new_farm_name}_status.cfg",  "${configdir}/${new_farm_name}_proxy.cfg",
        "${configdir}/${new_farm_name}_Err414.html", "${configdir}/${new_farm_name}_Err500.html",
        "${configdir}/${new_farm_name}_Err501.html", "${configdir}/${new_farm_name}_Err503.html",
        "${configdir}/${new_farm_name}_sessions.cfg",
    );

    my $cfg = $configdir;
    my $oFN = $farm_name;        # old farm name
    my $nFN = $new_farm_name;    # new farm name

    for my $farm_file (@farm_configfiles) {
        my $new_farm_filename = shift @new_farm_configfiles;

        next unless (-e $farm_file);

        copy($farm_file, $new_farm_filename) or $output = -1;
        unlink($farm_file) if ($del eq 'del');

        next unless ($farm_file eq "${configdir}/${farm_name}_proxy.cfg");

        my @lines = readFileAsArray($new_farm_filename);

        # Lines to change:
        #Name		BasekitHTTP
        #Control 	"/tmp/BasekitHTTP_proxy.socket"
        #\tErr414 "/usr/local/relianoid/config/BasekitHTTP_Err414.html"
        #\tErr500 "/usr/local/relianoid/config/BasekitHTTP_Err500.html"
        #\tErr501 "/usr/local/relianoid/config/BasekitHTTP_Err501.html"
        #\tErr503 "/usr/local/relianoid/config/BasekitHTTP_Err503.html"
        #\t#Service "BasekitHTTP"
        #NfMarks (for each backend)

        for my $l (@lines) {
            $l =~ s/^(\s*Name\s+"?)${oFN}/$1${nFN}/;
            $l =~ s/\tErr414 "$cfg\/${oFN}_Err414.html"/\tErr414 "$cfg\/${nFN}_Err414.html"/;
            $l =~ s/\tErr500 "$cfg\/${oFN}_Err500.html"/\tErr500 "$cfg\/${nFN}_Err500.html"/;
            $l =~ s/\tErr501 "$cfg\/${oFN}_Err501.html"/\tErr501 "$cfg\/${nFN}_Err501.html"/;
            $l =~ s/\tErr503 "$cfg\/${oFN}_Err503.html"/\tErr503 "$cfg\/${nFN}_Err503.html"/;
            $l =~ s/\t#Service "${oFN}"/\t#Service "${nFN}"/;
        }

        my $match   = qq(Control \t"\/tmp\/${oFN}_proxy.socket");
        my $replace = qq(Control \t"\/tmp\/${nFN}_proxy.socket");

        for my $l (@lines) {
            $l =~ s/${match}/${replace}/;
        }

        writeFileFromArray($new_farm_filename, \@lines);

        &log_info("Configuration saved in $new_farm_filename file", "LSLB");
    }

    if (-e "\/tmp\/$farm_name\_pound.socket" and $del eq 'del') {
        unlink("\/tmp\/$farm_name\_pound.socket");
    }

    return $output;
}

=pod

=head1 checkFarmHTTPSystemStatus

Checks the process and PID file on the system and fixes the inconsistency.

Parameters:

    farm_name - farm that is going to be modified
    status    - Status to check. Only "down" status.
    fix       - True, do the necessary changes to get the inconsistency fixed. 

Returns:

    None

=cut

sub checkFarmHTTPSystemStatus ($farm_name, $status, $fix = undef) {
    if ($status eq "down") {
        my $pid_file = getHTTPFarmPidFile($farm_name);
        if (-e $pid_file) {
            unlink $pid_file if (defined $fix and $fix eq "true");
        }
        my $pgrep = &getGlobalConfiguration("pgrep");
        require Relianoid::Farm::Core;
        my $farm_file    = &getFarmFile($farm_name);
        my $config_dir   = &getGlobalConfiguration("configdir");
        my $proxy        = &getGlobalConfiguration("proxy");
        my @pids_running = @{ &logAndGet("$pgrep -f \"$proxy (-s )?-f $config_dir/$farm_file -p $pid_file\"", "array") };

        if (@pids_running) {
            kill 9, @pids_running if (defined $fix and $fix eq "true");
        }
    }
    return;
}

1;
