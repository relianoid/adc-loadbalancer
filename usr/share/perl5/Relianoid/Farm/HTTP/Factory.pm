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

require Relianoid::Core;

my $eload     = eval { require Relianoid::ELoad };
my $configdir = &getGlobalConfiguration('configdir');

=pod

=head1 Module

Relianoid::Farm::HTTP::Factory

=cut

=pod

=head1 runHTTPFarmCreate

Create a HTTP farm

Parameters:

    vip - Virtual IP where the virtual service is listening
    vip_port - Virtual port where the virtual service is listening
    farm_name - Farm name
    farm_type - Specify if farm is HTTP or HTTPS
    status - Set the initial status of the farm. The possible values are: 'down' for creating the farm and do not run it or 'up' (default) for running the farm when it has been created

Returns:

    Integer - return 0 on success or different of 0 on failure

=cut

sub runHTTPFarmCreate ($vip, $vip_port, $farm_name, $farm_type, $status = 'up') {
    require Relianoid::Farm::HTTP::Config;
    require Tie::File;
    require File::Copy;
    File::Copy->import();

    my $output = -1;

    #copy template modyfing values
    my $proxytpl        = &getGlobalConfiguration('proxytpl');
    my $proxy_conf_file = "$configdir/${farm_name}_proxy.cfg";
    &log_info("Copying proxy template ($proxytpl) to $proxy_conf_file", "LSLB");
    copy($proxytpl, $proxy_conf_file);

    #modify strings with variables
    tie my @file, 'Tie::File', $proxy_conf_file;

    for my $line (@file) {
        $line =~ s/\[IP\]/$vip/;
        $line =~ s/\[PORT\]/$vip_port/;
        $line =~ s/\[DESC\]/$farm_name/;
        $line =~ s/\[CONFIGDIR\]/$configdir/;
        if ($farm_type eq "HTTPS") {
            $line =~ s/ListenHTTP/ListenHTTPS/;
            $line =~ s/#Cert/Cert/;
        }
    }
    untie @file;

    #create files with personalized errors
    my $f_err;

    open $f_err, '>', "${configdir}/${farm_name}_Err414.html";
    print $f_err "Request URI is too long.\n";
    close $f_err;

    open $f_err, '>', "${configdir}/${farm_name}_Err500.html";
    print $f_err "An internal server error occurred. Please try again later.\n";
    close $f_err;

    open $f_err, '>', "${configdir}/${farm_name}_Err501.html";
    print $f_err "This method may not be used.\n";
    close $f_err;

    open $f_err, '>', "${configdir}/${farm_name}_Err503.html";
    print $f_err "The service is not available. Please try again later.\n";
    close $f_err;

    #create session file
    open $f_err, '>', "${configdir}/${farm_name}_sessions.cfg";
    close $f_err;

    &setHTTPFarmLogs($farm_name, 'false');

    if ($eload) {
        &eload(
            module => 'Relianoid::EE::Farm::HTTP::Ext',
            func   => 'addHTTPFarmWafBodySize',
            args   => [$farm_name],
        );
    }

    $output = &getHTTPFarmConfigIsOK($farm_name);

    if ($output) {
        require Relianoid::Farm::Action;
        &runFarmDelete($farm_name);
        return 1;
    }

    #run farm
    require Relianoid::System;
    my $proxy  = &getGlobalConfiguration('proxy');
    my $piddir = &getGlobalConfiguration('piddir');

    if ($status eq 'up') {
        my $cmd = "${proxy} -f ${configdir}/${farm_name}_proxy.cfg -p ${piddir}/${farm_name}_proxy.pid";
        &log_info("Running: ${cmd}", "LSLB");

        $output = &run_with_env($cmd);
    }
    else {
        $output = &setHTTPFarmBootStatus($farm_name, 'down');
    }

    return $output;
}

1;
