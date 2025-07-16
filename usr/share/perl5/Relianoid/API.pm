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
use feature qw(signatures state);

my $eload = eval { require Relianoid::ELoad; };

=pod

=head1 Module

Relianoid::API

=cut

=pod

=head1 is_api_enabled

Get if the API is enabled.

Parameters: none

Returns: boolean

=cut

sub is_api_enabled() {
    require Relianoid::File;

    my $filename = &getGlobalConfiguration('htpass');
    my @lines    = readFileAsArray($filename);
    my $result   = scalar(grep { /^api:/ } @lines) > 0;

    return $result;
}

=pod

=head1 get_api_key

Returns a string with the API key.

Parameters: none

Returns: string

=cut

sub get_api_key() {
    return &getGlobalConfiguration('api_key');
}

=pod

=head1 enable_api

Enable API.

Parameters: none

Returns: integer - errno

=cut

sub enable_api () {
    my $cmd = "adduser --system --shell /bin/false --no-create-home api";

    return &logAndRun($cmd);
}

=pod

=head1 disable_api

Disable API.

Parameters: none

Returns: integer - errno

=cut

sub disable_api() {
    setGlobalConfiguration('api_key', "");

    # Update api_key global configuration
    &getGlobalConfiguration('api_key', 1);

    my $deluser_bin = &getGlobalConfiguration('deluser_bin');
    my $cmd         = "$deluser_bin api";

    return &logAndRun($cmd);
}

=pod

=head1 set_api_key

Set API key.

Parameters:

    key - string - API key.

Returns: nothing

=cut

sub set_api_key ($key) {
    if ($eload) {
        $key = &eload(
            module => 'Relianoid::EE::Code',
            func   => 'setCryptString',
            args   => [$key],
        );
    }

    setGlobalConfiguration('api_key', $key);

    # Update api_key global configuration
    &getGlobalConfiguration('api_key', 1);

    return;
}

=pod

=head1 is_api_key_valid

Validates the API key received with the HTTP header API_KEY

Parameters: None

Returns: integer - integer used as boolean

=cut

sub is_api_key_valid () {
    my $key = get_http_api_key();

    if (!$key) {
        return 0;
    }

    require Relianoid::User;
    my $is_valid = 0;

    if (&is_api_enabled() && &get_api_key() eq $key) {
        &setUser('root');
        $is_valid = 1;
    }
    elsif ($eload) {
        my $user = &eload(
            module => 'Relianoid::EE::RBAC::User::Core',
            func   => 'validateRBACUserAPIKey',
            args   => [$key],
        );

        if (my $user = &validateRBACUserAPIKey($key)) {
            &setUser($user);
            $is_valid = 1;
        }
    }

    return $is_valid;
}

sub get_http_api_key () {
    return $ENV{HTTP_API_KEY} if $ENV{HTTP_API_KEY};

    state $warned_deprecation = 0;

    if (exists $ENV{HTTP_ZAPI_KEY}) {
        if (not $warned_deprecation) {
            log_warn("The HTTP header 'ZAPI_KEY' is deprecated and its use will be removed, use 'API_KEY' instead.");
            $warned_deprecation = 1;
        }

        return $ENV{HTTP_ZAPI_KEY};
    }

    return;
}

1;

