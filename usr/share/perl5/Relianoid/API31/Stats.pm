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

use Relianoid::System;

my $eload;
if (eval { require Relianoid::ELoad; }) {
    $eload = 1;
}

# Get all farm stats
sub getAllFarmStats {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    my @farm_names = &getFarmNameList();
    my @farms;

    # FIXME: Verify stats are working with every type of farm

    foreach my $name (@farm_names) {
        my $type   = &getFarmType($name);
        my $status = &getFarmVipStatus($name);

        # datalink has not got stats
        next if ($type eq 'datalink');

        my $vip         = &getFarmVip('vip',  $name);
        my $port        = &getFarmVip('vipp', $name);
        my $established = 0;
        my $pending     = 0;

        if ($status ne "down") {
            require Relianoid::Net::ConnStats;
            require Relianoid::Farm::Stats;

            my $netstat;
            $netstat = &getConntrack('', $vip, '', '', '')
              if $type !~ /^https?$/;

            $pending     = &getFarmSYNConns($name, $netstat);
            $established = &getFarmEstConns($name, $netstat);
        }

        push @farms,
          {
            farmname    => $name,
            profile     => $type,
            status      => $status,
            vip         => $vip,
            vport       => $port,
            established => $established,
            pending     => $pending,
          };
    }

    return \@farms;
}

#Get Farm Stats
sub farm_stats    # ( $farmname, $servicename )
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my $farmname    = shift;
    my $servicename = shift;
    if ($farmname eq 'modules') { return; }
    if ($farmname eq 'total')   { return; }

    require Relianoid::Farm::Core;

    my $desc = "Get farm stats";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        &httpErrorResponse(code => 400, desc => $desc, msg => $msg);
    }

    my $type = &getFarmType($farmname);

    if (defined $servicename
        && ($type ne 'http' && $type ne 'https' && $type ne 'gslb'))
    {
        my $msg = "The $type farm profile does not support services.";
        &httpErrorResponse(code => 400, desc => $desc, msg => $msg);
    }

    if ($type eq "http" || $type eq "https") {
        require Relianoid::Farm::HTTP::Stats;

        if (defined $servicename) {

            # validate SERVICE
            require Relianoid::Farm::Service;
            my @services      = &getFarmServices($farmname);
            my $found_service = grep { $servicename eq $_ } @services;

            if (not $found_service) {
                my $msg = "The service $servicename does not exist for $farmname.";
                &httpErrorResponse(code => 404, desc => $desc, msg => $msg);
            }
        }

        my $stats = &getHTTPFarmBackendsStats($farmname, $servicename);

        # Force not appear new v4.0 params
        delete $_->{ttl}          foreach @{ $stats->{sessions} };
        delete $_->{backend_ip}   foreach @{ $stats->{sessions} };
        delete $_->{backend_port} foreach @{ $stats->{sessions} };

        my $body = {
            description => $desc,
            backends    => $stats->{backends},
            sessions    => $stats->{sessions},
        };

        &httpResponse({ code => 200, body => $body });
    }

    if ($type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Stats;

        my $stats = &getL4FarmBackendsStats($farmname);
        my $body  = {
            description => $desc,
            backends    => $stats,
        };

        &httpResponse({ code => 200, body => $body });
    }

    if ($type eq "gslb" && $eload) {
        if (defined $servicename) {
            my @services = &eload(
                module => 'Relianoid::Farm::GSLB::Service',
                func   => 'getGSLBFarmServices',
                args   => [$farmname],
            );

            # check if the SERVICE exists
            unless (grep { $servicename eq $_ } @services) {
                my $msg = "Could not find the requested service.";
                return &httpErrorResponse(
                    code => 404,
                    desc => $desc,
                    msg  => $msg
                );
            }
        }

        my $gslb_stats = &eload(
            module => 'Relianoid::Farm::GSLB::Stats',
            func   => 'getGSLBFarmBackendsStats',
            args   => [ $farmname, $servicename ],
            decode => 'true'
        );

        my $body = {
            description => $desc,
            backends    => $gslb_stats->{'backends'},
            client      => $gslb_stats->{'udp'},
            server      => $gslb_stats->{'tcp'},
            extended    => $gslb_stats->{'stats'},
        };

        &httpResponse({ code => 200, body => $body });
    }
}

#Get Farm Stats
sub all_farms_stats    # ()
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my $farms = &getAllFarmStats();
    my $body  = {
        description => "List all farms stats",
        farms       => $farms,
    };

    &httpResponse({ code => 200, body => $body });
}

#GET /stats
sub stats    # ()
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    require Relianoid::Stats;
    require Relianoid::SystemInfo;

    my @data_mem  = &getMemStats();
    my @data_load = &getLoadStats();
    my @data_net  = &getNetworkStats();
    my @data_cpu  = &getCPU();

    my $out = {
        'hostname' => &getHostname(),
        'date'     => &getDate(),
    };

    foreach my $x (0 .. @data_mem - 1) {
        my $name  = $data_mem[$x][0];
        my $value = $data_mem[$x][1] + 0;
        $out->{memory}->{$name} = $value;
    }

    foreach my $x (0 .. @data_load - 1) {
        my $name  = $data_load[$x][0];
        my $value = $data_load[$x][1] + 0;

        $name =~ s/ /_/;
        $name = 'Last_1' if $name eq 'Last';
        $out->{load}->{$name} = $value;
    }

    foreach my $x (0 .. @data_cpu - 1) {
        my $name  = $data_cpu[$x][0];
        my $value = $data_cpu[$x][1] + 0;

        $name =~ s/CPU//;
        $out->{cpu}->{$name} = $value;
    }

    $out->{cpu}->{cores} = &getCpuCores();

    foreach my $x (0 .. @data_net - 1) {
        my $name;
        if ($x % 2 == 0) {
            $name = $data_net[$x][0] . ' in';
        }
        else {
            $name = $data_net[$x][0] . ' out';
        }
        my $value = $data_net[$x][1] + 0;
        $out->{network}->{$name} = $value;
    }

    my $body = {
        description => "System stats",
        params      => $out
    };

    &httpResponse({ code => 200, body => $body });
}

#GET /stats/network
sub stats_network    # ()
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    require Relianoid::Stats;
    require Relianoid::SystemInfo;

    my @interfaces = &getNetworkStats('hash');
    my $output;
    $output->{'hostname'}   = &getHostname();
    $output->{'date'}       = &getDate();
    $output->{'interfaces'} = \@interfaces;

    my $body = {
        description => "Network interefaces usage",
        params      => $output
    };

    &httpResponse({ code => 200, body => $body });
}

1;
