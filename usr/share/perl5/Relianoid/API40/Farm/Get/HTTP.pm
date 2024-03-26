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

use Relianoid::Farm::HTTP::Config;

=pod

=head1 Module

Relianoid::API40::Farm::Get::HTTP

=cut

my $eload = eval { require Relianoid::ELoad };

# GET /farms/<farmname> Request info of a http|https Farm
sub farms_name_http ($farmname) {

    # Get farm reference
    require Relianoid::API40::Farm::Output::HTTP;
    my $farm_ref = &getHTTPOutFarm($farmname);

    # Get farm services reference
    require Relianoid::Farm::HTTP::Service;
    my $services_ref = &getHTTPOutService($farmname);

    # Output
    my $body = {
        description => "List farm $farmname",
        params      => $farm_ref,
        services    => $services_ref,
    };

    if ($eload) {
        $body->{ipds} = &eload(
            module => 'Relianoid::IPDS::Core',
            func   => 'getIPDSfarmsRules',
            args   => [$farmname],
        );
    }

    &httpResponse({ code => 200, body => $body });
    return;
}

# GET /farms/<farmname>/summary
sub farms_name_http_summary ($farmname) {

    # Get farm reference
    require Relianoid::API40::Farm::Output::HTTP;
    my $farm_ref = &getHTTPOutFarm($farmname);

    # Services
    require Relianoid::Farm::HTTP::Service;

    my $services_ref = &get_http_all_services_summary_struct($farmname);

    my $body = {
        description => "List farm $farmname",
        params      => $farm_ref,
        services    => $services_ref,
    };

    if ($eload) {
        $body->{ipds} = &eload(
            module => 'Relianoid::IPDS::Core',
            func   => 'getIPDSfarmsRules',
            args   => [$farmname],
        );
    }

    &httpResponse({ code => 200, body => $body });
    return;
}

1;

