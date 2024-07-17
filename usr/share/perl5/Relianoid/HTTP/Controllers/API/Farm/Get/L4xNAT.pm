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

use Relianoid::FarmGuardian;
use Relianoid::Farm::Config;
use Relianoid::Farm::Backend;
use Relianoid::Farm::L4xNAT::Config;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::Farm::Get::L4xNAT

=cut

my $eload = eval { require Relianoid::ELoad };

# GET /farms/<farmname> Request info of a l4xnat Farm
sub farms_name_l4 ($farmname) {
    require Relianoid::Farm::L4xNAT::Sessions;

    my $farm   = &getL4FarmStruct($farmname);
    my $status = &getFarmVipStatus($farmname);
    my $fields = {
        status      => $status,
        vip         => $farm->{vip},
        vport       => $farm->{vport},
        algorithm   => $farm->{lbalg},
        nattype     => $farm->{nattype},
        persistence => $farm->{persist},
        ttl         => $farm->{ttl} + 0,
        protocol    => $farm->{vproto},

        farmguardian => &getFGFarm($farmname),
        listener     => 'l4xnat',
        sessions     => &listL4FarmSessions($farmname)
    };

    require Relianoid::HTTP::Adapters::Backend;

    my $backends = &getL4FarmServers($farmname);
    &getBackendsResponse($backends, 'l4xnat');

    my $body = {
        description => "List farm $farmname",
        params      => $fields,
        backends    => $backends,
    };

    if ($eload) {
        $fields->{logs} = $farm->{logs};

        $body->{ipds} = &eload(
            module => 'Relianoid::EE::IPDS::Core',
            func   => 'getIPDSfarmsRules',
            args   => [$farmname],
        );
    }

    return &httpResponse({ code => 200, body => $body });
}

1;

