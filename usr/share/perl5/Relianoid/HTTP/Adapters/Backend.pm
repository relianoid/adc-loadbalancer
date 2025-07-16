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

Relianoid::HTTP::Adapters::Backend

=cut

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 getBackendsResponse

Function to standarizate the backend structure on the API.

Parameters:

    out_b    - hash reference  - Required. Input and output
    type     - string          - Required. Farm type
    api_keys - array reference - Optional. Keys in API response. Only used in `get_farm_stats_controller`

Returns: nothing - It modifies the hash referenced by `out_b`.

=cut

sub getBackendsResponse ($backend_ref, $type, $api_keys = []) {
    die "Waiting a hash input" if not ref $backend_ref;

    if ($type eq 'l4xnat') {
        push @{$api_keys}, qw(id weight port ip priority status max_conns);
    }
    elsif ($type eq 'datalink') {
        push @{$api_keys}, qw(id weight ip priority status interface);
    }
    elsif ($type =~ /http/) {
        push @{$api_keys}, qw(id ip port weight status timeout);
    }
    elsif ($type eq 'gslb') {
        push @{$api_keys}, qw(id ip);
    }

    my $translate->{status} = { fgdown => "down", undefined => "up" };

    if (ref $backend_ref eq "ARRAY") {
        for my $backend (@{$backend_ref}) {
            _buildBackendAPIParams($backend, $api_keys, $translate);
        }
    }
    elsif (ref $backend_ref eq "HASH") {
        _buildBackendAPIParams($backend_ref, $api_keys, $translate);
    }

    if ($eload) {
        $backend_ref = &eload(
            module => 'Relianoid::EE::Alias',
            func   => 'addAliasBackendsStruct',
            args   => [$backend_ref],
        );
    }

    return;
}

sub _buildBackendAPIParams ($backend, $api_keys, $translate) {
    my @bk_keys = keys(%{$backend});

    for my $param (keys %{$translate}) {
        for my $opt (keys %{ $translate->{$param} }) {
            if ($opt) {
                # This is a workaround to avoid regex substitution on undefined $out_b->{$param}
                if (defined $backend->{$param}) {
                    if (lc($backend->{$param}) eq $opt) {
                        $backend->{$param} = $translate->{$param}{$opt};
                    }
                    # else {
                    #     $out_b->{$param} =~ s/$opt/$translate->{$param}{$opt}/i;
                    # }
                }
                else {
                    if (not exists $backend->{$param}) {
                        $backend->{$param} = undef;
                    }

                    # if ($opt eq 'undefined') {
                    #     $backend->{$param} = $translate->{$param}{$opt};
                    # }
                }
            }
        }
    }

    for my $param (@bk_keys) {
        if (!grep { $param eq $_ } @{$api_keys}) {
            delete $backend->{$param};
        }
    }

    if (&debug()) {
        for my $param (@{$api_keys}) {
            if (!grep { $param eq $_ } @bk_keys) {
                &log_error("API parameter $param is missing", 'API');
            }
        }
    }

    return;
}

1;

