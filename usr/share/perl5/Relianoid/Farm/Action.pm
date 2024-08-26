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

my $eload = eval { require Relianoid::ELoad };

my $configdir = &getGlobalConfiguration('configdir');

=pod

=head1 Module

Relianoid::Farm::Action

=cut

=pod

=head1 _runFarmStart

Run a farm

Parameters:

    farm_name - Farm name
    writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:

    Integer - return 0 on success, 2 if the ip:port is busy for another farm or another value on another failure

=cut

sub _runFarmStart ($farm_name, $writeconf = 0) {
    # The parameter expect "undef" to not write it
    $writeconf = 0 if ($writeconf eq 'false');

    require Relianoid::Farm::Base;
    require Relianoid::Farm::Config;

    my $status = -1;

    # finish the function if the farm is already up
    if (&getFarmStatus($farm_name) eq "up") {
        log_info("Farm $farm_name already up", "FARMS");
        return 0;
    }

    # check if the ip exists in any interface
    my $ip = &getFarmVip("vip", $farm_name);

    require Relianoid::Net::Interface;

    if (!&getIpAddressExists($ip)) {
        &log_info("The virtual interface $ip is not defined in any interface.");
        return $status;
    }

    require Relianoid::Net::Interface;

    my $farm_type = &getFarmType($farm_name);

    if ($farm_type ne "datalink") {
        my $port = &getFarmVip("vipp", $farm_name);
        if (!&validatePort($ip, $port, undef, $farm_name)) {
            &log_info("The networking '$ip:$port' is being used.");
            return 2;
        }
    }

    &log_info("Starting farm $farm_name with type $farm_type", "FARMS");

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Action;
        $status = &_runHTTPFarmStart($farm_name, $writeconf);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Action;
        $status = &startL4Farm($farm_name, $writeconf);
    }
    elsif ($farm_type eq "datalink") {
        $status = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Action',
            func   => '_runDatalinkFarmStart',
            args   => [ $farm_name, $writeconf ],
        );
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $status = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Action',
            func   => '_runGSLBFarmStart',
            args   => [ $farm_name, $writeconf ],
        );
    }

    &setFarmNoRestart($farm_name);

    return $status;
}

=pod

=head1 runFarmStart

Run a farm completely a farm. Run farm, its farmguardian, ipds rules and ssyncd

Parameters:

    farm_name - Farm name
    writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:

    Integer - return 0 on success, 2 if the ip:port is busy for another farm or another value on another failure

NOTE:

    Generic function

=cut

sub runFarmStart ($farm_name, $writeconf = 0) {
    my $status = &_runFarmStart($farm_name, $writeconf);
    &log_info("Farm start status: $status");

    return $status if ($status != 0);

    require Relianoid::FarmGuardian;
    my $fg_status = &runFarmGuardianStart($farm_name, "");
    &log_info("Farm guardian start status: $fg_status");

    if ($eload) {
        &eload(
            module => 'Relianoid::EE::IPDS::Base',
            func   => 'runIPDSStartByFarm',
            args   => [$farm_name],
        );

        require Relianoid::Farm::Config;
        if (&getPersistence($farm_name) == 0) {
            &eload(
                module => 'Relianoid::EE::Ssyncd',
                func   => 'setSsyncdFarmUp',
                args   => [$farm_name],
            );
        }
    }
    return $status;
}

=pod

=head1 runFarmStop

Stop a farm completely a farm. Stop the farm, its farmguardian, ipds rules and ssyncd

Parameters:

    farm_name - Farm name
    writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:

    Integer - return 0 on success or different of 0 on failure

NOTE:

    Generic function

=cut

sub runFarmStop ($farm_name, $writeconf = 0) {
    if ($eload) {
        &eload(
            module => 'Relianoid::EE::IPDS::Base',
            func   => 'runIPDSStopByFarm',
            args   => [$farm_name],
        );
        &eload(
            module => 'Relianoid::EE::Ssyncd',
            func   => 'setSsyncdFarmDown',
            args   => [$farm_name],
        );
    }

    require Relianoid::FarmGuardian;
    &runFGFarmStop($farm_name);

    my $status = &_runFarmStop($farm_name, $writeconf);

    return $status;
}

=pod

=head1 _runFarmStop

Stop a farm

Parameters:

    farm_name - Farm name
    writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:

    Integer - return 0 on success or different of 0 on failure

=cut

sub _runFarmStop ($farm_name, $writeconf = 0) {
    $writeconf = 0 if ($writeconf eq 'false');

    require Relianoid::Farm::Base;

    my $farm_filename = &getFarmFile($farm_name);
    if ($farm_filename eq '-1') {
        return -1;
    }

    my $farm_type = &getFarmType($farm_name);
    my $status    = $farm_type;

    &log_info("Stopping farm $farm_name with type $farm_type", "FARMS");

    if ($farm_type =~ /http/) {
        require Relianoid::Farm::HTTP::Action;
        $status = &_runHTTPFarmStop($farm_name, $writeconf);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Action;
        $status = &stopL4Farm($farm_name, $writeconf);
    }
    elsif ($farm_type eq "datalink") {
        $status = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Action',
            func   => '_runDatalinkFarmStop',
            args   => [ $farm_name, $writeconf ],
        );
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $status = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Action',
            func   => '_runGSLBFarmStop',
            args   => [ $farm_name, $writeconf ],
        );
    }

    &setFarmNoRestart($farm_name);

    return $status;
}

=pod

=head1 runFarmDelete

Delete a farm

Parameters:

    farmname - Farm name

Returns:

    String - farm name

NOTE:

    Generic function

=cut

sub runFarmDelete ($farm_name) {
    require Relianoid::Netfilter;

    my $configdir = &getGlobalConfiguration('configdir');

    if ($eload) {
        &eload(
            module => 'Relianoid::EE::IPDS::Base',
            func   => 'runIPDSDeleteByFarm',
            args   => [$farm_name],
        );

        &eload(
            module => 'Relianoid::EE::RBAC::Group::Config',
            func   => 'delRBACResource',
            args   => [ $farm_name, 'farms' ],
        );
    }

    # stop and unlink farmguardian
    require Relianoid::FarmGuardian;
    &delFGFarm($farm_name);

    my $farm_type = &getFarmType($farm_name);
    my $status    = 1;

    &log_info("running 'Delete' for $farm_name", "FARMS");

    if ($farm_type eq "gslb") {
        require File::Path;
        File::Path->import('rmtree');

        $status = 0
          if rmtree(["$configdir/$farm_name\_gslb.cfg"]);
    }
    elsif ($farm_type eq "http" || $farm_type eq "https") {
        unlink glob("$configdir/$farm_name\_*\.html");

        # For HTTPS farms only
        my $dhfile = "$configdir\/$farm_name\_dh2048.pem";
        unlink("$dhfile") if -e "$dhfile";
        &delMarks($farm_name, "");

        # Check if local farm exists and delete it
        require Relianoid::Nft;
        my $output = &httpNlbRequest({
            method => "GET",
            uri    => "/farms/" . $farm_name,
            check  => 1,
        });

        if (!$output) {
            $output = &httpNlbRequest({
                farm   => $farm_name,
                method => "DELETE",
                uri    => "/farms/" . $farm_name,
            });
        }
    }
    elsif ($farm_type eq "datalink") {
        # delete cron task to check backends
        require Tie::File;
        tie my @filelines, 'Tie::File', "/etc/cron.d/relianoid";
        @filelines = grep { !/\# \_\_$farm_name\_\_/ } @filelines;
        untie @filelines;
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Factory;
        &runL4FarmDelete($farm_name);
    }

    unlink glob("$configdir/$farm_name\_*\.cfg");

    if (!-f "$configdir/$farm_name\_*\.cfg") {
        $status = 0;
    }

    require Relianoid::RRD;

    &delGraph($farm_name, "farm");

    return $status;
}

=pod

=head1 runFarmReload

Reload a farm

Parameters:

    farm_name - Farm name

Returns:

    Integer - return 0 on success, another value on another failure

=cut

sub runFarmReload ($farm_name) {
    require Relianoid::Farm::Action;

    if (&getFarmRestartStatus($farm_name)) {
        &log_info("'Reload' on $farm_name is not executed. 'Restart' is needed.", "FARMS");
        return 2;
    }
    my $status = 0;

    &log_info("running 'Reload' for $farm_name", "FARMS");

    $status = &_runFarmReload($farm_name);

    # Reload Farm status from its cfg file
    require Relianoid::Farm::HTTP::Backend;
    &setHTTPFarmBackendStatusFromFile($farm_name);

    return $status;
}

=pod

=head1 _runFarmReload

It reloads a farm to update the configuration.

Parameters:

    Farm - It is the farm name

Returns:

    Integer - It returns 0 on success or another value on failure.

=cut

sub _runFarmReload ($farm) {
    my $err = 0;

    require Relianoid::Farm::Base;
    return 0 if (&getFarmStatus($farm) ne 'up');

    require Relianoid::Farm::HTTP::Config;
    my $proxy_ctl = &getGlobalConfiguration('proxyctl');
    my $socket    = &getHTTPFarmSocket($farm);

    $err = &logAndRun("$proxy_ctl -c $socket -R 0");

    return $err;
}

=pod

=head1 getFarmRestartFile

This function returns a file name that indicates that a farm is waiting to be restarted

Parameters:

    farmname - Farm name

Returns:

    sting - path to flag file

NOTE:

    Generic function

=cut

sub getFarmRestartFile ($farm_name) {
    return "/tmp/_farm_need_restart_$farm_name";
}

=pod

=head1 getFarmRestartStatus

This function responses if a farm has pending changes waiting for restarting

Parameters:

    farmname - Farm name

Returns:

    Integer - 1 if the farm has to be restarted or 0 if it is not

NOTE:

    Generic function

=cut

sub getFarmRestartStatus ($fname) {
    require Relianoid::Farm::Action;
    my $lfile = &getFarmRestartFile($fname);

    return 1 if (-e $lfile);
    return 0;
}

=pod

=head1 setFarmRestart

This function creates a file to tell that the farm needs to be restarted to apply changes

Parameters:

    farmname - Farm name

Returns:

    undef

NOTE:

    Generic function

=cut

sub setFarmRestart ($farm_name) {
    # do nothing if the farm is not running
    require Relianoid::Farm::Base;
    return if &getFarmStatus($farm_name) ne 'up';

    require Relianoid::Lock;
    my $lf = &getFarmRestartFile($farm_name);
    my $fh = &openlock($lf, 'w');
    close $fh;

    return;
}

=pod

=head1 setFarmNoRestart

This function deletes the file marking the farm to be restarted to apply changes

Parameters:

    farmname - Farm name

Returns:

    none

NOTE:

    Generic function

=cut

sub setFarmNoRestart ($farm_name) {
    my $lf = &getFarmRestartFile($farm_name);
    unlink($lf) if -e $lf;

    return;
}

=pod

=head1 setNewFarmName

Function that renames a farm. Before call this function, stop the farm.

Parameters:

    farmname    - Farm name
    newfarmname - New farm name

Returns:

    Integer - return 0 on success or -1 on failure

=cut

sub setNewFarmName ($farm_name, $new_farm_name) {
    my $collector_rrd_dir   = &getGlobalConfiguration('collector_rrd_dir');

    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    # farmguardian renaming
    require Relianoid::FarmGuardian;
    require File::Copy;

    &runFGFarmStop($farm_name);
    &setFGFarmRename($farm_name, $new_farm_name);

    # end of farmguardian renaming

    &log_info("setting 'NewFarmName $new_farm_name' for $farm_name farm $farm_type", "FARMS");

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Action;
        $output = &copyHTTPFarm($farm_name, $new_farm_name, 'del');
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Action;
        $output = &setL4NewFarmName($farm_name, $new_farm_name);
    }
    elsif ($farm_type eq "datalink" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Action',
            func   => 'copyDatalinkFarm',
            args   => [ $farm_name, $new_farm_name, 'del' ],
        );
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Action',
            func   => 'copyGSLBFarm',
            args   => [ $farm_name, $new_farm_name, 'del' ],
        );
    }

    # farmguardian renaming
    if ($output == 0) {
        &log_info("restarting farmguardian", 'FG') if &debug();
        &runFGFarmStart($farm_name);
    }

    # end of farmguardian renaming

    # rename rrd
    File::Copy::move("$collector_rrd_dir/$farm_name-farm.rrd", "$collector_rrd_dir/$new_farm_name-farm.rrd");

    # delete old graphs
    unlink("img/graphs/bar$farm_name.png");

    if ($eload) {
        &eload(
            module => 'Relianoid::EE::IPDS::Base',
            func   => 'runIPDSRenameByFarm',
            args   => [ $farm_name, $new_farm_name ],
        );

        &eload(
            module => 'Relianoid::EE::RBAC::Group::Config',
            func   => 'setRBACRenameByFarm',
            args   => [ $farm_name, $new_farm_name ],
        );
    }

    # FIXME: logfiles
    return $output;
}

=pod

=head1 copyFarm

Function that copies the configuration file of a farm to create a new one.

Parameters:

    farmname - Farm name
    newfarmname - New farm name

Returns:

    Integer - return 0 on success or -1 on failure

=cut

sub copyFarm ($farm_name, $new_farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    &log_info("copying the farm '$farm_name' to '$new_farm_name'", "FARMS");

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Action;
        $output = &copyHTTPFarm($farm_name, $new_farm_name);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Action;
        $output = &copyL4Farm($farm_name, $new_farm_name);
    }
    elsif ($farm_type eq "datalink" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Action',
            func   => 'copyDatalinkFarm',
            args   => [ $farm_name, $new_farm_name ],
        );
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Action',
            func   => 'copyGSLBFarm',
            args   => [ $farm_name, $new_farm_name ],
        );
    }

    return $output;
}

1;

