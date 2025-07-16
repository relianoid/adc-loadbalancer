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

=pod

=head1 Module

Relianoid::System::Proxy

=cut

use strict;
use warnings;
use feature qw(signatures);

=pod

=head1 getProxy

Get a reference to a hash with the proxy configuration

Parameters: None

Returns: hash reference

    {
        http_proxy  => "https://10.10.21.13:8080",
        https_proxy => "https://10.10.21.12:8080",
    }

=cut

sub getProxy () {
    my $http_proxy  = &getGlobalConfiguration('http_proxy')  // '';
    my $https_proxy = &getGlobalConfiguration('https_proxy') // '';

    return {
        http_proxy  => $http_proxy,
        https_proxy => $https_proxy,
    };
}

=pod

=head1 setProxy

Configure a system proxy

Parameters: hash reference

proxy structure

    {
        http_proxy  => "https://10.10.21.13:8080",
        https_proxy => "https://10.10.21.12:8080",
    }

Returns: integer

    0 - succes
    1 - error

=cut

sub setProxy ($proxy_conf) {
    my $error = 0;

    for my $key ('http_proxy', 'https_proxy') {
        next if not exists $proxy_conf->{$key};

        if ($error = &setGlobalConfiguration($key, $proxy_conf->{$key})) {
            &log_error("Error setting '$key' with the value '$proxy_conf->{$key}'", "System");
        }
    }

    if (not $error) {
        require Relianoid::Apt;
        &setAPTProxy();
    }

    return $error;
}

1;

