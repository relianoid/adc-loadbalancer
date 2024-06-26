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

=pod

=head1 Module

Relianoid::Farm::Backend::Maintenance

=cut

=pod

=head1 setFarmBackendMaintenance

Function that enable the maintenance mode for backend

Parameters:

    farm_name -  Farm name
    backend   -  Backend id
    mode      -  Maintenance mode, the options are:
                 - drain: the backend continues working with the established connections
                 - cut:   the backend cuts all the established connections
    service   -  Service name, required for http only

Returns:

    Integer - return 0 on success or -1 on failure

=cut

sub setFarmBackendMaintenance ($farm_name, $backend, $mode, $service = undef) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Backend;
        $output = &setHTTPFarmBackendMaintenance($farm_name, $backend, $mode, $service);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Backend;
        $output = &setL4FarmBackendStatus($farm_name, $backend, 'maintenance', $mode);
    }

    return $output;
}

=pod

=head1 setFarmBackendNoMaintenance

Function that disable the maintenance mode for backend

Parameters:

    farm_name - Farm name
    backend   - Backend id
    service   - Service name

Returns:

    Integer - return 0 on success or -1 on failure

=cut

sub setFarmBackendNoMaintenance ($farm_name, $backend, $service = undef) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Backend;
        $output = &setHTTPFarmBackendNoMaintenance($farm_name, $backend, $service);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Backend;
        $output = &setL4FarmBackendStatus($farm_name, $backend, 'up', "");
    }

    return $output;
}

1;

