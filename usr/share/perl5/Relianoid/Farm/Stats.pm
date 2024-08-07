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

Relianoid::Farm::Stats

=cut

=pod

=head1 getFarmEstConns

Get all ESTABLISHED connections for a farm

Parameters:

    farm_name - Farm name
    netstat   - reference to array with Conntrack -L output

Returns:

    unsigned integer - Return number of ESTABLISHED conntrack lines for a farm

=cut

sub getFarmEstConns ($farm_name, $netstat) {
    my $farm_type   = &getFarmType($farm_name);
    my $connections = 0;

    if ($farm_type eq "http" || $farm_type eq "https") {
        my @pid = &getFarmPid($farm_name);
        return $connections if (!@pid);
        require Relianoid::Farm::HTTP::Stats;
        $connections = &getHTTPFarmEstConns($farm_name);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Stats;
        $connections = &getL4FarmEstConns($farm_name, $netstat);
    }
    elsif ($farm_type eq "gslb") {
        my @pid = &getFarmPid($farm_name);
        return $connections if (!@pid);
        $connections = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Stats',
            func   => 'getGSLBFarmEstConns',
            args   => [ $farm_name, $netstat ],
        ) if $eload;
    }

    return $connections;
}

=pod

=head1 getBackendSYNConns

Get all SYN connections for a backend

Parameters:

    farm_name    - Farm name
    ip_backend   - IP backend
    port_backend - backend port
    netstat      - reference to array with Conntrack -L output

Returns:

    integer - Return number of SYN conntrack lines for a backend of a farm or -1 if error

=cut

sub getBackendSYNConns ($farm_name, $ip_backend, $port_backend, $netstat = undef) {
    my $farm_type   = &getFarmType($farm_name);
    my $connections = 0;

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Stats;
        $connections = &getHTTPBackendSYNConns($farm_name, $ip_backend, $port_backend);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Stats;
        $connections = &getL4BackendSYNConns($farm_name, $ip_backend, $port_backend, $netstat);
    }

    return $connections;
}

=pod

=head1 getFarmSYNConns

Get all SYN connections for a farm

Parameters:

    farm_name - Farm name
    netstat   - reference to array with Conntrack -L output

Returns:

    unsigned integer - Return number of SYN conntrack lines for a farm

=cut

sub getFarmSYNConns ($farm_name, $netstat = undef) {
    my $farm_type   = &getFarmType($farm_name);
    my $connections = 0;

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Stats;
        $connections = &getHTTPFarmSYNConns($farm_name);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Stats;
        $connections = &getL4FarmSYNConns($farm_name, $netstat);
    }

    return $connections;
}

1;

