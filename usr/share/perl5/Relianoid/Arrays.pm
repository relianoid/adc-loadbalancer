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

Relianoid::Arrays

=cut

=pod

=head1 moveByIndex

This function moves an element of an list to another position using its index.
This funcion uses the original array to apply the changes, so it does not return anything.

Parameters:

    list - Array reference with the list to modify.
    ori_index - Index of the element will be moved.
    dst_index - Position in the list that the element will have.

Returns:

    None

=cut

sub moveByIndex ($list, $ori_index, $dst_index) {
    my $elem = $list->[$ori_index];

    # delete item
    splice(@{$list}, $ori_index, 1);

    # add item
    splice(@{$list}, $dst_index, 0, $elem);

    return;
}

=pod

=head1 getArrayIndex

Retuns the first index matching the value given, evaluated as a string.

Parameters:

    haystack - Array reference with the list to look for.
    needle   - Value to get its index

Returns:

    undef   - When the needle was not found
    integer - index of array with the first match found

=cut

sub getArrayIndex ($haystack, $needle) {
    my $found_index;
    my $current_index = 0;

    for my $element (@{$haystack}) {
        if ($element eq $needle) {
            $found_index = $current_index;
            last;
        }
        $current_index++;
    }

    return $found_index;
}

=pod

=head1 uniqueArray

It gets an array for reference and it removes the items that are repeated.
The original input array is modified. This function does not return anything

Parameters:

    Array ref - It is the array is going to be managed

Returns:

    None

=cut

sub uniqueArray ($arr) {
    my %hold = ();
    my @hold;

    for my $v (@{$arr}) {
        unless (exists $hold{$v}) {
            $hold{$v} = 1;
            push @hold, $v;
        }
    }

    @{$arr} = @hold;

    return;
}

=pod

=head1 getArrayCollision

It checks if two arrays have some value repeted.
The arrays have to contain scalar values.

Parameters:

    Array ref 1 - List of values 1
    Array ref 2 - List of values 2

Returns:

    scalar - It returns the first value which is contained in both arrays

=cut

sub getArrayCollision ($arr1, $arr2) {
    for my $it (sort @{$arr1}) {
        if (grep { $it eq $_ } @{$arr2}) {
            return $it;
        }
    }

    return;
}

1;

