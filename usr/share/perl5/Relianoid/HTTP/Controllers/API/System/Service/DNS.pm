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

Relianoid::HTTP::Controllers::API::System::Service::DNS

=cut

# GET /system/dns
sub get_dns_controller () {
    require Relianoid::System::DNS;

    my $desc = "Get dns";
    my $dns  = &getDns();

    return &httpResponse({ code => 200, body => { description => $desc, params => $dns } });
}

#  POST /system/dns
sub set_dns_controller ($json_obj) {
    require Relianoid::System::DNS;

    my $desc = "Modify the DNS";

    my $params = &getAPIModel("system_dns-modify.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # the order is important to avoid to be the secondary
    # overriden if the primary is set afterwards
    if (exists $json_obj->{primary}) {
        my $msg = &setDns('primary', $json_obj->{primary});
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg }) if $msg;
    }
    if (exists $json_obj->{secondary}) {
        my $msg = &setDns('secondary', $json_obj->{secondary});
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg }) if $msg;
    }

    my $dns = &getDns();

    return &httpResponse({
        code => 200,
        body => {
            description => $desc,
            params      => $dns,
            message     => "The DNS service has been updated successfully."
        }
    });
}

1;

