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
use Relianoid::Farm::Datalink::Backend;

my $eload;
if (eval { require Relianoid::ELoad; }) {
    $eload = 1;
}

sub farms_name_datalink    # ( $farmname )
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )",
        "debug", "PROFILING");
    my $farmname = shift;

    require Relianoid::Farm::Config;
    my $vip    = &getFarmVip("vip", $farmname);
    my $status = &getFarmVipStatus($farmname);

    my $out_p = {
        vip       => $vip,
        algorithm => &getFarmAlgorithm($farmname),
        status    => $status,
    };

    ### backends
    my $out_b = &getDatalinkFarmBackends($farmname);

    my $body = {
        description => "List farm $farmname",
        params      => $out_p,
        backends    => $out_b,
    };

    if ($eload) {
        $body->{ipds} = &eload(
            module => 'Relianoid::IPDS::Core',
            func   => 'getIPDSfarmsRules',
            args   => [$farmname],
        );
        delete $body->{ipds}->{rbl};
        delete $body->{ipds}->{dos};
        for my $blacklist (@{ $body->{ipds}->{blacklists} }) {
            delete $blacklist->{id};
        }
    }

    &httpResponse({ code => 200, body => $body });
}

1;
