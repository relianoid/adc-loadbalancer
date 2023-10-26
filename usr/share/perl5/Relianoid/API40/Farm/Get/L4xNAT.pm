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
use Relianoid::FarmGuardian;
use Relianoid::Farm::Config;
use Relianoid::Farm::Backend;
use Relianoid::Farm::L4xNAT::Config;

my $eload;
if (eval { require Relianoid::ELoad; }) {
    $eload = 1;
}

# GET /farms/<farmname> Request info of a l4xnat Farm
sub farms_name_l4    # ( $farmname )
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )",
        "debug", "PROFILING");
    my $farmname = shift;

    my $out_p;

    my $farm   = &getL4FarmStruct($farmname);
    my $status = &getFarmVipStatus($farmname);

    require Relianoid::Farm::L4xNAT::Sessions;
    $out_p = {
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

    if ($eload) {
        $out_p->{logs} = $farm->{logs};
    }

    # Backends
    my $out_b = &getFarmServers($farmname);
    &getAPIFarmBackends($out_b, 'l4xnat');

    my $body = {
        description => "List farm $farmname",
        params      => $out_p,
        backends    => $out_b,
    };

    $body->{ipds} = &eload(
        module => 'Relianoid::IPDS::Core',
        func   => 'getIPDSfarmsRules',
        args   => [$farmname],
    ) if ($eload);

    &httpResponse({ code => 200, body => $body });
}

1;

