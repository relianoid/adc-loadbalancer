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

use Relianoid::System;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::Stats

=cut

my $eload = eval { require Relianoid::ELoad };

# Get all farm stats
sub _get_all_farm_stats_controller () {
    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    my @files = &getFarmList();
    my @farms;

    for my $file (@files) {
        my $name = &getFarmName($file);
        my $type = &getFarmType($name);

        if ($type eq 'eproxy' && $eload) {
            my $farm_stats = &eload(
                module => 'Relianoid::EE::Farm::Eproxy::Stats',
                func   => 'getEproxyFarmStats',
                args   => [ { 'farm_name' => $name } ],
            );
            push(@farms, $farm_stats);
        }
        else {
            my $status      = &getFarmVipStatus($name);
            my $vip         = &getFarmVip('vip',  $name);
            my $port        = &getFarmVip('vipp', $name);
            my $established = 0;
            my $pending     = 0;

            # datalink has no stats
            if ($type eq 'datalink') {
                $established = undef;
                $pending     = undef;
            }
            elsif ($status ne "down") {
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
    }

    if ($eload) {
        @farms = @{
            &eload(
                module => 'Relianoid::EE::RBAC::Group::Core',
                func   => 'getRBACUserSet',
                args   => [ 'farms', \@farms ],
            )
        };
    }

    return \@farms;
}

#Get Farm Stats
sub get_farm_stats_controller ($farmname, $servicename = undef) {
    if ($farmname eq 'modules') { return; }
    if ($farmname eq 'total')   { return; }

    require Relianoid::Farm::Core;

    my $desc = "Get farm stats";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);

    if (defined $servicename
        && ($type ne 'http' && $type ne 'https' && $type ne 'gslb'))
    {
        my $msg = "The $type farm profile does not support services.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
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
                return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
            }
        }

        my $stats = &getHTTPFarmBackendsStats($farmname, $servicename);

        my $body;
        if ($stats eq -1) {
            $body = {
                warning        => "It was not possible to extract the sessions.",
                description    => $desc,
                backends       => [],
                sessions       => [],
                total_sessions => 0,
            };
        }
        else {
            $body = {
                description    => $desc,
                backends       => $stats->{backends},
                sessions       => $stats->{sessions},
                total_sessions => $#{ $stats->{sessions} } + 1,
            };
        }
        return &httpResponse({ code => 200, body => $body });
    }

    if ($type eq "l4xnat") {
        my $backends = [];
        my $sessions = [];

        require Relianoid::Farm::L4xNAT::Config;

        if (&getL4FarmStatus($farmname) ne "down") {
            require Relianoid::Farm::L4xNAT::Stats;
            $backends = &getL4FarmBackendsStats($farmname);

            require Relianoid::HTTP::Adapters::Backend;
            &getBackendsResponse($backends, $type, [ 'established', 'pending' ]);

            require Relianoid::Farm::L4xNAT::Sessions;
            $sessions = &listL4FarmSessions($farmname);
        }

        my $body = {
            description    => $desc,
            backends       => $backends,
            sessions       => $sessions,
            total_sessions => $#{$sessions} + 1,
        };

        return &httpResponse({ code => 200, body => $body });
    }

    if ($type eq "gslb" && $eload) {
        my $gslb_stats;

        my $gslbStatus = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Config',
            func   => 'getGSLBFarmStatus',
            args   => [$farmname],
        );
        if ($gslbStatus ne "down") {
            if (defined $servicename) {
                my @services = &eload(
                    module => 'Relianoid::EE::Farm::GSLB::Service',
                    func   => 'getGSLBFarmServices',
                    args   => [$farmname],
                );

                # check if the SERVICE exists
                unless (grep { $servicename eq $_ } @services) {
                    my $msg = "Could not find the requested service.";
                    return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
                }
            }
            $gslb_stats = &eload(
                module => 'Relianoid::EE::Farm::GSLB::Stats',
                func   => 'getGSLBFarmBackendsStats',
                args   => [ $farmname, $servicename ],
                decode => 'true'
            );
        }

        my $body = {
            description => $desc,
            backends    => $gslb_stats->{backends} // [],
            client      => $gslb_stats->{udp}      // [],
            server      => $gslb_stats->{tcp}      // [],
            extended    => $gslb_stats->{stats}    // [],
        };

        return &httpResponse({ code => 200, body => $body });
    }

    if ($type eq "eproxy" && $eload) {
        my $backend_stats = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Stats',
            func   => 'getEproxyFarmBackendsStats',
            args   => [{ farm_name => $farmname, service_name => $servicename}],
        );

        my $body = {
            description    => $desc,
            backends       => $backend_stats,
#            sessions       => $stats->{sessions},
#            total_sessions => $#{ $stats->{sessions} } + 1,
        };
        return &httpResponse({ code => 200, body => $body });
    }

}

#Get Farm Stats
sub list_farms_stats_controller () {
    my $farms = &_get_all_farm_stats_controller();

    my $body = {
        description => "List all farms stats",
        farms       => $farms,
    };

    return &httpResponse({ code => 200, body => $body });
}

#GET /stats
sub get_stats_controller () {
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

    for my $x (0 .. @data_mem - 1) {
        my $name  = $data_mem[$x][0];
        my $value = $data_mem[$x][1] + 0;
        $out->{memory}{$name} = $value;
    }

    for my $x (0 .. @data_load - 1) {
        my $name  = $data_load[$x][0];
        my $value = $data_load[$x][1] + 0;

        $name =~ s/ /_/;
        $name = 'Last_1' if $name eq 'Last';
        $out->{load}{$name} = $value;
    }

    for my $x (0 .. @data_cpu - 1) {
        my $name  = $data_cpu[$x][0];
        my $value = $data_cpu[$x][1] + 0;

        $name =~ s/CPU//;
        $out->{cpu}{$name} = $value;
    }

    $out->{cpu}{cores} = &getCpuCores();

    for my $x (0 .. @data_net - 1) {
        my $name;
        if ($x % 2 == 0) {
            $name = $data_net[$x][0] . ' in';
        }
        else {
            $name = $data_net[$x][0] . ' out';
        }
        my $value = $data_net[$x][1] + 0;
        $out->{network}{$name} = $value;
    }

    my $body = {
        description => "System stats",
        params      => $out
    };

    return &httpResponse({ code => 200, body => $body });
}

#GET /stats/system/network
sub get_stats_network_controller () {
    require Relianoid::Stats;
    require Relianoid::SystemInfo;

    my @interfaces = &getNetworkStats('hash');
    my $output;
    $output->{hostname}   = &getHostname();
    $output->{date}       = &getDate();
    $output->{interfaces} = \@interfaces;

    my $body = {
        description => "Network interefaces usage",
        params      => $output
    };

    return &httpResponse({ code => 200, body => $body });
}

1;
