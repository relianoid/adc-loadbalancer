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

use Relianoid::Farm::Core;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::Farm::Put

=cut

my $eload = eval { require Relianoid::ELoad };

sub modify_farm_controller ($json_obj, $farmname) {
    my $desc = "Modify farm";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);

    if ($type eq "http" || $type eq "https") {
        require Relianoid::HTTP::Controllers::API::Farm::Put::HTTP;
        &modify_http_farm($json_obj, $farmname);
    }

    elsif ($type eq "l4xnat") {
        require Relianoid::HTTP::Controllers::API::Farm::Put::L4xNAT;
        &modify_l4xnat_farm($json_obj, $farmname);
    }

    elsif ($type eq "datalink") {
        require Relianoid::EE::HTTP::Controllers::API::Farm::Put::Datalink;
        &modify_datalink_farm($json_obj, $farmname);
    }

    elsif ($type eq "gslb" && $eload) {
        &eload(
            module => 'Relianoid::EE::HTTP::Controllers::API::Farm::Put::GSLB',
            func   => 'modify_gslb_farm',
            args   => [ $json_obj, $farmname ],
        );
    }

    elsif ($type eq "eproxy" && $eload) {
        &eload(
            module => 'Relianoid::EE::HTTP::Controllers::API::Farm::Put::Eproxy',
            func   => 'modify_eproxy_farm',
            args   => [ $json_obj, $farmname ],
        );
    }

    return;
}

1;

