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

use Relianoid::System::Proxy;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::System::Service::Proxy

=cut

# GET /system/proxy
sub get_proxy_controller () {
    my $desc = "Get proxy configuration";

    return &httpResponse({
        code => 200,
        body => { description => $desc, params => &getProxyResponse() }
    });
}

#  POST /system/proxy
sub set_proxy_controller ($json_obj) {
    my $desc   = "Configuring proxy";
    my $params = &getAPIModel("system_proxy-modify.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    if (&setProxy($json_obj)) {
        my $msg = "There was a error modifying the proxy configuration.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # Proxy needs to be updated in apt module
    require Relianoid::Apt;
    &setAPTProxy();

    return &httpResponse({
        code => 200,
        body => {
            description => $desc,
            params      => &getProxyResponse(),
            message     => "The Proxy service has been updated successfully."
        }
    });
}

sub getProxyResponse () {
    my $proxy = &getProxy();

    return {
        http_proxy  => $proxy->{http_proxy},
        https_proxy => $proxy->{https_proxy}
    };
}

1;

