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

use Relianoid::Core;
use Relianoid::SystemInfo;

=pod

=head1 Module

Relianoid::Apt

=cut

=pod

=head1 setAPTProxy

Sets http_proxy and https_proxy variables in the APT conf

Parameters: None

Returns: Nothing

=cut

sub setAPTProxy () {
    require Relianoid::Lock;

    my $http_proxy    = &getGlobalConfiguration('http_proxy');
    my $https_proxy   = &getGlobalConfiguration('https_proxy');
    my $apt_conf_file = &getGlobalConfiguration('apt_conf_file');

    &ztielock(\my @apt_conf, $apt_conf_file);

    for my $line (@apt_conf) {
        if ($line =~ /^Acquire::http::proxy/) {
            $line = "Acquire::http::proxy \"$http_proxy\/\";\n";
        }
        if ($line =~ /Acquire::https::proxy/) {
            $line = "Acquire::https::proxy \"$https_proxy\/\";\n";
        }
    }

    untie @apt_conf;

    return;
}

1;
