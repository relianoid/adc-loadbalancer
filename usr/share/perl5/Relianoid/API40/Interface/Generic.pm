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

Relianoid::API40::Interface::Generic

=cut

my $eload = eval { require Relianoid::ELoad };

# GET /interfaces Get params of the interfaces
sub get_interfaces () {
    require Relianoid::Net::Interface;

    my $desc = "List interfaces";
    my $if_list_ref;

    if ($eload) {
        $if_list_ref = &eload(
            module => 'Relianoid::Net::Interface',
            func   => 'get_interface_list_struct',    # 100
        );
    }
    else {
        $if_list_ref = &get_interface_list_struct();
    }

    my $body = {
        description => $desc,
        interfaces  => $if_list_ref,
    };

    &httpResponse({ code => 200, body => $body });
    return;
}

1;
