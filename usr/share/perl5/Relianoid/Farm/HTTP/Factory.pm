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

require Relianoid::Core;

my $eload = eval { require Relianoid::ELoad };
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

    port - Virtual port where the virtual service is listening

    farmname - Farm name

    type - Specify if farm is HTTP or HTTPS

    status - Set the initial status of the farm. The possible values are: 'down' for creating the farm and do not run it or 'up' (default) for running the farm when it has been created

Returns:

    Integer - return 0 on success or different of 0 on failure

=cut

sub runHTTPFarmCreate    # ( $vip, $vip_port, $farm_name, $farm_type )
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    require Relianoid::Farm::HTTP::Config;
    my ($vip, $vip_port, $farm_name, $farm_type, $status) = @_;
    $status = 'up' if not defined $status;

    my $proxy_ng = &getGlobalConfiguration('proxy_ng');

    require Tie::File;
    require File::Copy;
    File::Copy->import();

    my $output = -1;

    #copy template modyfing values
    my $proxytpl        = &getGlobalConfiguration('proxytpl');
    my $proxy_conf_file = "$configdir/${farm_name}_proxy.cfg";
    &zenlog("Copying proxy template ($proxytpl) to $proxy_conf_file", "info", "LSLB");
    copy($proxytpl, $proxy_conf_file);

    #modify strings with variables
    tie my @file, 'Tie::File', $proxy_conf_file;

    foreach my $line (@file) {
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
    if ($eload) {
        open $f_err, '>', "$configdir\/$farm_name\_ErrWAF.html";
        print $f_err "The request was rejected by the server.\n";
        close $f_err;
    }
    open $f_err, '>', "$configdir\/$farm_name\_Err414.html";
    print $f_err "Request URI is too long.\n";
    close $f_err;
    open $f_err, '>', "$configdir\/$farm_name\_Err500.html";
    print $f_err "An internal server error occurred. Please try again later.\n";
    close $f_err;
    open $f_err, '>', "$configdir\/$farm_name\_Err501.html";
    print $f_err "This method may not be used.\n";
    close $f_err;
    open $f_err, '>', "$configdir\/$farm_name\_Err503.html";
    print $f_err "The service is not available. Please try again later.\n";
    close $f_err;

    #create session file
    open $f_err, '>', "$configdir\/$farm_name\_sessions.cfg";
    close $f_err;

    &setHTTPFarmLogs($farm_name, 'false');

    if ($eload) {

        &eload(
            module => 'Relianoid::Farm::HTTP::Ext',
            func   => 'addHTTPFarmWafBodySize',
            args   => [$farm_name],
        ) if ($proxy_ng eq 'false');
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
        &zenlog(
            "Running $proxy -f $configdir\/$farm_name\_proxy.cfg -p $piddir\/$farm_name\_proxy.pid",
            "info", "LSLB"
        );

        $output = &zsystem(
            "$proxy -f $configdir\/$farm_name\_proxy.cfg -p $piddir\/$farm_name\_proxy.pid 2>/dev/null"
        );

        if ($proxy_ng eq 'true') {
            if (&getGlobalConfiguration("mark_routing_L7") eq 'true') {

                # create L4 farm type local
                require Relianoid::Net::Validate;
                my $vip_family;
                if (&ipversion($vip) == 6) {
                    $vip_family = "ipv6";
                }
                else {
                    $vip_family = "ipv4";
                }
                my $body =
                  qq({"farms" : [ { "name" : "$farm_name", "virtual-addr" : "$vip", "virtual-ports" : "$vip_port", "mode" : "local", "state": "up", "family" : "$vip_family" }]});
                require Relianoid::Nft;
                my $error = &httpNlbRequest(
                    {
                        farm   => $farm_name,
                        method => "PUT",
                        uri    => "/farms",
                        body   => $body
                    }
                );
                if ($error) {
                    &zenlog("L4xnat Farm Type local for '$farm_name' can not be created.",
                        "warning", "LSLB");
                }
            }

            if ($eload) {
                if (&getGlobalConfiguration("floating_L7") eq 'true') {
                    &eload(
                        module => 'Relianoid::Farm::Config',
                        func   => 'reloadFarmsSourceAddressByFarm',
                        args   => [$farm_name],
                    );
                }
            }
        }
    }
    else {
        $output = &setHTTPFarmBootStatus($farm_name, 'down');
    }

    return $output;
}

1;
