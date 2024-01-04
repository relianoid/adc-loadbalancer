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

# GET /system/dns
sub get_dns {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    require Relianoid::System::DNS;

    my $desc = "Get dns";
    my $dns  = &getDns();

    &httpResponse({ code => 200, body => { description => $desc, params => $dns } });
    return;
}

#  POST /system/dns
sub set_dns {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my $json_obj = shift;

    require Relianoid::System::DNS;

    my $desc = "Modify the DNS";

    my $params = &getAPIModel("system_dns-modify.json");

    # Check allowed parameters
    my $error_msg = &checkApiParams($json_obj, $params, $desc);
    return &httpErrorResponse(code => 400, desc => $desc, msg => $error_msg)
      if ($error_msg);

    foreach my $key (keys %{$json_obj}) {
        my $msg = &setDns($key, $json_obj->{$key});
        &httpErrorResponse(code => 400, desc => $desc, msg => $msg) if $msg;
    }

    my $dns = &getDns();
    &httpResponse(
        {
            code => 200,
            body => {
                description => $desc,
                params      => $dns,
                message     => "The DNS service has been updated successfully."
            }
        }
    );
    return;
}

1;

