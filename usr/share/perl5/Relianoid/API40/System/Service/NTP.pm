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

Relianoid::API40::System::Service::NTP

=cut

# GET /system/ntp
sub get_ntp () {
    my $desc = "Get ntp";
    my $ntp  = &getGlobalConfiguration('ntp');

    &httpResponse({
        code => 200,
        body => { description => $desc, params => { "server" => $ntp } }
    });
    return;
}

#  POST /system/ntp
sub set_ntp ($json_obj) {
    my $desc = "Post ntp";

    my $params = &getAPIModel("system_ntp-modify.json");

    # Check allowed parameters
    my $error_msg = &checkApiParams($json_obj, $params, $desc);
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg })
      if ($error_msg);

    my $error = &setGlobalConfiguration('ntp', $json_obj->{'server'});

    if ($error) {
        my $msg = "There was a error modifying ntp.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $ntp = &getGlobalConfiguration('ntp');
    &httpResponse({
        code => 200,
        body => {
            description => $desc,
            params      => $ntp,
            message     => "The NTP service has been updated successfully."
        }
    });
    return;
}

1;

