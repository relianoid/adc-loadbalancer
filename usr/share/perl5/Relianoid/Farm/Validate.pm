#!/usr/bin/perl
###############################################################################
#
#    RELIANOID Software License
#    This file is part of the RELIANOID Load Balancer software package.
#
#    Copyright (C) 2020-today RELIANOID
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

Relianoid::Farm::Validate

=cut

=pod

=head1 priorityAlgorithmIsOK

This funcion receives a list of priority values and it checks if all backends will be started according to priority Algorithm

Parameters:

    Priorities - Array reference to priorities to check

Returns:

    Integer - Return 0 if valid priority settings, unsuitable priority value if not.

=cut

sub priorityAlgorithmIsOK ($priority_ref) {
    use List::Util qw( min max );
    my @backends = sort @{$priority_ref};
    my @backendstmp;

    my $prio_last = 0;
    foreach my $prio_cur (@backends) {
        if ($prio_cur != $prio_last) {
            my $n_backendstmp = @backendstmp;
            return $prio_cur if ($prio_cur > ($n_backendstmp + 1));
            push @backendstmp, $prio_cur;
            $prio_last = $prio_cur;
        }
        else {
            push @backendstmp, $prio_cur;
        }
    }
    return 0;
}

1;

