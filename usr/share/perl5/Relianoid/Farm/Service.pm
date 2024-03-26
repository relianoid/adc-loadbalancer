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

Relianoid::Farm::Service

=cut

=pod

=head1 getFarmServices

Get a list of services name for a farm
    
Parameters:

    farm_name - Farm name

Returns:

    Array - list of service names 
    
=cut

sub getFarmServices ($farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my @output    = ();

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Service;
        @output = &getHTTPFarmServices($farm_name);
    }

    if ($farm_type eq "gslb") {
        @output = &eload(
            module => 'Relianoid::Farm::GSLB::Service',
            func   => 'getGSLBFarmServices',
            args   => [$farm_name],
        ) if $eload;
    }

    return @output;
}

1;

