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

=head1 getAPI

Get API status

Parameters:

    name - 'status' to get if the user 'api' is enabled, or 'api_key' to get the 'api_key'.

Returns:

    For 'status': Boolean. 'true' if the API user is enabled, or 'false' if it is disabled.

    For 'api_key': Returns the current api_key.

=cut

sub getAPI ($name) {
    require Relianoid::File;

    my $result = "false";

    if ($name eq "status") {
        if (grep { /^api:/ } readFileAsArray(&getGlobalConfiguration('htpass'))) {
            $result = "true";
        }
    }
    elsif ($name eq "api_key") {
        $result = &getGlobalConfiguration('api_key');
    }

    return $result;
}

=pod

=head1 setAPI

Set API values

Parameters:

    name - Actions to be taken: 'enable', 'disable', 'randomkey' to set a random key, or 'key' to set the key specified in value.

        enable    - Enables the user 'api'.
        disable   - Disables the user 'api'.
        randomkey - Generates a random key.
        key       - Sets $value a the api_key.

    value - New key to be used. Only apply when the action 'key' is used.

Returns:

    none

=cut

sub setAPI ($action, $value = undef) {
    if ($action eq "enable") {
        my $cmd = "adduser --system --shell /bin/false --no-create-home api";

        return &logAndRun($cmd);
    }
    elsif ($action eq "disable") {
        setGlobalConfiguration('api_key', "");

        # Update api_key global configuration
        &getGlobalConfiguration('api_key', 1);

        my $deluser_bin = &getGlobalConfiguration('deluser_bin');
        my $cmd         = "$deluser_bin api";

        return &logAndRun($cmd);
    }
    elsif ($action eq "randomkey") {
        my $random = &getAPIRandomKey(64);

        setGlobalConfiguration('api_key', $random);
    }
    elsif ($action eq "key") {
        if ($eload) {
            $value = &eload(
                module => 'Relianoid::EE::Code',
                func   => 'setCryptString',
                args   => [$value],
            );
        }

        setGlobalConfiguration('api_key', $value);

        # Update api_key global configuration
        &getGlobalConfiguration('api_key', 1);
    }

    return;
}

=pod

=head1 getAPIRandomKey

Generate random key for API user.

Parameters:

    length - Number of characters in the new key.

Returns: string - Random key.

=cut

sub getAPIRandomKey ($length) {
    my @alphanumeric = ('a' .. 'z', 'A' .. 'Z', 0 .. 9);
    my $randpassword = join '', map { $alphanumeric[ rand @alphanumeric ] } 0 .. $length;

    return $randpassword;
}

=pod

=head1 isApiKeyValid

Validates the API key received with the HTTP header API_KEY

Parameters: None

Returns: integer - integer used as boolean

=cut

sub isApiKeyValid () {
    require Relianoid::User;

    my $is_valid = 0;
    my $key      = get_http_api_key();

    if ($key) {
        if (&getAPI("status") eq "true" && &getAPI("api_key") eq $key) {
            &setUser('root');
            $is_valid = 1;
        }
        elsif ($eload) {
            my $user = &eload(
                module => 'Relianoid::EE::RBAC::User::Core',
                func   => 'validateRBACUserAPIKey',
                args   => [$key],
            );
            if ($user) {
                &setUser($user);
                $is_valid = 1;
            }
        }
    }

    return $is_valid;
}

=pod

=head1 getApiVersionsList

Parameters: None

Returns: string array - list of API versions (as strings)

=cut

sub getApiVersionsList () {
    return (sort split ' ', &getGlobalConfiguration("api_versions"));
}

=pod

=head1 getApiVersion

Parameters:

    none

Returns:

    string - API version or empty string.

=cut

sub getApiVersion () {
    return $ENV{API_VERSION} // "";
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

