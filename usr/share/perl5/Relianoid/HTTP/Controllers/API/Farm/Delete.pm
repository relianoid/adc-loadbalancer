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
use Relianoid::Farm::Base;
use Relianoid::Farm::Action;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::Farm::Delete

=cut

my $eload = eval { require Relianoid::ELoad };

# DELETE /farms/FARMNAME
sub delete_farm_controller ($farmname) {
    my $desc = "Delete farm $farmname";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm $farmname doesn't exist, try another name.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmStatus($farmname) eq 'up') {
        if (&runFarmStop($farmname, "true")) {
            my $msg = "The farm $farmname could not be stopped.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        &eload(
            module => 'Relianoid::EE::Cluster',
            func   => 'runClusterRemoteManager',
            args   => [ 'farm', 'stop', $farmname ],
        ) if ($eload);
    }

    my $error = &runFarmDelete($farmname);

    if ($error) {
        my $msg = "The Farm $farmname hasn't been deleted";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    &log_info("Success, the farm $farmname has been deleted.", "FARMS");

    &eload(
        module => 'Relianoid::EE::Cluster',
        func   => 'runClusterRemoteManager',
        args   => [ 'farm', 'delete', $farmname ],
    ) if ($eload);

    my $msg  = "The Farm $farmname has been deleted.";
    my $body = {
        description => $desc,
        success     => "true",
        message     => $msg
    };

    return &httpResponse({ code => 200, body => $body });
}

1;

