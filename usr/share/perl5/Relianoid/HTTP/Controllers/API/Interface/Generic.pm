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

Relianoid::HTTP::Controllers::API::Interface::Generic

=cut

# GET /interfaces Get params of the interfaces
sub list_interfaces_controller () {
    require Relianoid::Net::Interface;

    my $desc = "List interfaces";
    my $if_list_ref;

    $if_list_ref = &get_interface_list_struct();

    my $body = {
        description => $desc,
        interfaces  => $if_list_ref,
    };

    return &httpResponse({ code => 200, body => $body });
}

1;
