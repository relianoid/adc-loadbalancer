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

use JSON;
use Relianoid::Lock;

my $json = JSON->new->utf8->pretty(1);

# canonical: if true or missing => sort keys
$json->canonical([1]);

=pod

=head1 Module

Relianoid::JSON

=cut

=pod

=head1 decodeJSONFile

=cut

sub decodeJSONFile ($file) {
    my $file_str;
    my $fh = &openlock($file, 'r');
    return if !defined $fh;

    {
        local $/ = undef;
        $file_str = <$fh>;
    }
    close $fh;

    my $f_json;

    eval { $f_json = $json->decode($file_str); };
    if ($@) {
        &log_error("Error decoding the file $file");
        &log_debug("json: $@");
    }

    return $f_json;
}

1;

