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

=pod

=head1 Module

Relianoid::Farm::HTTP::Stats

=cut

=pod

=head1 getHTTPFarmEstConns

Get all ESTABLISHED connections for a farm

Parameters:

    farm_name - Farm name

Returns:

    array - Return all ESTABLISHED conntrack lines for a farm

=cut

sub getHTTPFarmEstConns ($farm_name) {
    my $count = 0;

    my $vip      = &getFarmVip("vip",  $farm_name);
    my $vip_port = &getFarmVip("vipp", $farm_name);

    my $filter = {
        proto         => 'tcp',
        orig_dst      => $vip,
        orig_port_dst => $vip_port,
        state         => 'ESTABLISHED',
    };

    my $ct_params = &getConntrackParams($filter);
    $count = &getConntrackCount($ct_params);

    #~ &log_info( "getHTTPFarmEstConns: $farm_name farm -> $count connections." );

    return $count + 0;
}

=pod

=head1 getHTTPFarmSYNConns

Get all SYN connections for a farm

Parameters:

    farm_name - Farm name

Returns:

    array - Return all SYN conntrack lines for a farm

=cut

sub getHTTPFarmSYNConns ($farm_name) {
    my $vip      = &getFarmVip("vip",  $farm_name);
    my $vip_port = &getFarmVip("vipp", $farm_name);

    my $filter = {
        proto         => 'tcp',
        orig_dst      => $vip,
        orig_port_dst => $vip_port,
        state         => 'SYN_SENT',
    };

    my $ct_params = &getConntrackParams($filter);
    my $count     = &getConntrackCount($ct_params);

    $filter->{state} = 'SYN_RECV';

    $ct_params = &getConntrackParams($filter);
    $count += &getConntrackCount($ct_params);

    #~ &log_info( "getHTTPFarmSYNConns: $farm_name farm -> $count connections." );

    return $count + 0;
}

=pod

=head1 getHTTPBackendEstConns

Get all ESTABLISHED connections for a backend

Parameters:

    farm_name    - Farm name
    backend_ip   - IP backend
    backend_port - backend port
    mark

Returns:

    array - Return all ESTABLISHED conntrack lines for the backend

BUG:

    If a backend is used on more than one farm, here it appears all them

=cut

sub getHTTPBackendEstConns ($farm_name, $backend_ip, $backend_port, $mark = undef) {
    my $filter = {
        proto         => 'tcp',
        orig_dst      => $backend_ip,
        orig_port_dst => $backend_port,
        state         => 'ESTABLISHED',
    };

    if ($mark) {
        $filter->{mark} = $mark;
    }

    require Relianoid::Net::ConnStats;
    my $ct_params = &getConntrackParams($filter);
    my $count     = &getConntrackCount($ct_params);

    return $count + 0;
}

=pod

=head1 getHTTPBackendSYNConns

Get all SYN connections for a backend

Parameters:

    farm_name    - Farm name
    backend_ip   - IP backend
    backend_port - backend port
    mark

Returns:

    unsigned integer - connections count

BUG:

    If a backend is used on more than one farm, here it appears all them.

=cut

sub getHTTPBackendSYNConns ($farm_name, $backend_ip, $backend_port, $mark = undef) {
    my $filter = {
        proto         => 'tcp',
        orig_dst      => $backend_ip,
        orig_port_dst => $backend_port,
        state         => 'SYN_SENT',
    };

    if ($mark) {
        $filter->{mark} = $mark;
    }

    my $ct_params = &getConntrackParams($filter);
    my $count     = &getConntrackCount($ct_params);

    $filter->{state} = 'SYN_RECV';

    $ct_params = &getConntrackParams($filter);
    $count += &getConntrackCount($ct_params);

    return $count + 0;
}

=pod

=head1 getHTTPFarmBackendsStats

This function take data from pounctl and it gives hash format

Parameters:

    farm_name    - Farm name
    service_name - Service name

Returns:

    hash ref - hash with backend farm stats

    backends => [
        {
            "id" = $backend_id      # it is the index in the backend array too
            "ip" = $backend_ip
            "port" = $backend_port
            "status" = $backend_status
            "established" = $established_connections
        }
    ]

    sessions => [
        {
            "client"       = $client_id         # it is the index in the session array too
            "id"           = $session_id        # id associated to a backend, it can change depend of session type
            "backend_ip"   = $backend ip        # it is the backend ip
            "backend_port" = $backend port      # it is the backend port
            "service"      = $service name
            "session"      = $session identifier    # it depends on the persistence mode
        }
    ]

FIXME:

    Put output format same format than "GET /stats/farms/BasekitHTTP"

=cut

sub getHTTPFarmBackendsStats ($farm_name, $service_name = undef) {
    require Relianoid::Farm::Base;
    require Relianoid::Farm::HTTP::Config;
    require Relianoid::Validate;

    my $serviceName;
    my $service_re = &getValidFormat('service');
    my $stats      = {
        sessions => [],
        backends => []
    };

    unless ($eload) {
        require Relianoid::Net::ConnStats;
    }

    # Get L7 proxy info
    #i.e. of poundctl:

    #Requests in queue: 0
    #0. http Listener 185.76.64.223:80 a
    #0. Service "HTTP" active (4)
    #0. Backend 172.16.110.13:80 active (1 0.780 sec) alive (61)
    #1. Backend 172.16.110.14:80 active (1 0.878 sec) alive (90)
    #2. Backend 172.16.110.11:80 active (1 0.852 sec) alive (99)
    #3. Backend 172.16.110.12:80 active (1 0.826 sec) alive (75)
    my @poundctl = &getHTTPFarmGlobalStatus($farm_name);

    my $alias;
    $alias = &eload(
        module => 'Relianoid::EE::Alias',
        func   => 'getAlias',
        args   => ['backend']
    ) if $eload;

    my $backend_info;

    # Parse L7 proxy info
    for my $line (@poundctl) {
        # i.e.
        #     0. Service "HTTP" active (10)
        if ($line =~ /(\d+)\. Service "($service_re)"/) {
            $serviceName  = $2;
            $backend_info = undef;
        }

        next if (defined $service_name && $service_name ne $serviceName);

        # Parse backend connections
        # i.e.
        #      0. Backend 192.168.100.254:80 active (5 0.000 sec) alive (0)
        if ($line =~ /(\d+)\. Backend (\d+\.\d+\.\d+\.\d+|[a-fA-F0-9:]+):(\d+) (\w+) .+ (\w+)(?: \((\d+)\))?/) {
            my $backendHash = {
                id      => $1 + 0,
                ip      => $2,
                port    => $3 + 0,
                status  => $5,
                pending => 0,
                service => $serviceName,
            };

            $backendHash->{alias}                       = $alias->{$2} if $eload;
            $backend_info->{ $backendHash->{id} }{ip}   = $backendHash->{ip};
            $backend_info->{ $backendHash->{id} }{port} = $backendHash->{port};

            # The established connections should be always defined with >= 0
            # If there is any case where it is not defined, we can use the IP based filtering in conntrack
            # $backendHash->{established} = &getHTTPBackendEstConns($farm_name, $backendHash->{ip}, $backendHash->{port});
            $backendHash->{established} = $6 + 0;

            # Getting real status
            my $backend_disabled = $4;

            if ($backend_disabled eq "DISABLED") {
                require Relianoid::Farm::HTTP::Backend;

                #Checkstatusfile
                $backendHash->{status} =
                  &getHTTPBackendStatusFromFile($farm_name, $backendHash->{id}, $serviceName);

                # not show fgDOWN status
                $backendHash->{status} = "down"
                  if ($backendHash->{status} ne "maintenance");
            }
            elsif ($backendHash->{status} eq "alive") {
                $backendHash->{status} = "up";
            }
            elsif ($backendHash->{status} eq "DEAD") {
                $backendHash->{status} = "down";
            }

            # Getting pending connections
            require Relianoid::Net::ConnStats;
            require Relianoid::Farm::Stats;

            # The port passed to getBackendSYNConns will be converted to string,
            # port + 0 will pass a copy of the port, so the original port will not be converted
            $backendHash->{pending} = &getBackendSYNConns($farm_name, $backendHash->{ip}, $backendHash->{port} + 0);

            # Workaround: getBackendSYNConns changes the port to string
            $backendHash->{port} += 0;

            push(@{ $stats->{backends} }, $backendHash);
        }

        # Parse sessions
        # i.e.
        #      1. Session 107.178.194.117 -> 1
        if ($line =~ /(\d+)\. Session (.+) \-\> (\d+)/) {
            push @{ $stats->{sessions} },
              {
                client       => $1 + 0,
                session      => $2,
                id           => $3 + 0,
                backend_ip   => $backend_info->{$3}{ip},
                backend_port => $backend_info->{$3}{port},
                service      => $serviceName,
              };
        }
    }

    return $stats;
}

1;
