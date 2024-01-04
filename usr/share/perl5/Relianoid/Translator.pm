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
no warnings 'experimental::args_array_with_signatures';

=pod

=head1 Module

Relianoid::Translator

=cut

=pod

=head1 createTRANSLATE

Expects a hash. The keys are the zapi parameters and the value the lib parameters

=cut

sub createTRANSLATE ($dictionary) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my %translator = { api => $dictionary };

    foreach my $key (keys %{$dictionary}) {
        $translator{lib}->{ $dictionary->{$key} } = $key;
    }

    return \%translator;
}

=pod

=head1 getTRANSLATEInputs

=cut

sub getTRANSLATEInputs ($tr) {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my @values = sort keys(%{ $tr->{api} });
    return \@values;
}

1;

