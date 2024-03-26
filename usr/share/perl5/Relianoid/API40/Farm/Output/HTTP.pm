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

use Relianoid::Farm::HTTP::Config;

=pod

=head1 Module

Relianoid::API40::Farm::Output::HTTP

=cut

# farm parameters
sub getHTTPOutFarm ($farmname) {
    require Relianoid::Farm::Config;
    my $farm_ref = &getFarmStruct($farmname);

    # Remove useless fields
    delete($farm_ref->{name});
    return $farm_ref;
}

sub getHTTPOutService ($farmname) {
    require Relianoid::Farm::HTTP::Service;
    my @services_list = ();

    foreach my $service (&getHTTPFarmServices($farmname)) {
        my $service_ref = &getHTTPServiceStruct($farmname, $service);
        push @services_list, $service_ref;
    }

    return \@services_list;
}

1;

