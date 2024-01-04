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
use feature 'state';

=pod

=head1 Module

Relianoid::Debug

=cut

=pod

=head1 debug

Get debugging level.

Parameters:

    none - .

Returns:

    integer - Debugging level, from 0 to 5.

Bugs:

    The debugging level should be stored as a variable.

See Also:

    Widely used.

=cut

sub debug {
    require Relianoid::Config;
    state $debug = &getGlobalConfiguration('debug') // 0;
    return $debug;
}

=pod

=head1 getMemoryUsage

Get the resident memory usage of the current perl process.

Parameters:

    none

Returns:

    scalar - String with the memory usage.

See Also:

    Used in zapi.cgi

=cut

sub getMemoryUsage {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my $mem_string = `grep RSS /proc/$$/status`;

    chomp($mem_string);
    $mem_string =~ s/:.\s+/: /;

    return $mem_string;
}

1;

