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

my $eload = eval { require Relianoid::ELoad; };

=pod

=head1 Module

Relianoid::API

=cut

=pod

=head1 getAPI

Get zapi status

Parameters:

    name - 'status' to get if the user 'zapi' is enabled, or 'zapikey' to get the 'zapikey'.

Returns:

    For 'status': Boolean. 'true' if the zapi user is enabled, or 'false' if it is disabled.

    For 'zapikey': Returns the current zapikey.

=cut

sub getAPI ($name) {
    require Relianoid::File;

    my $result = "false";

    #return if zapi user is enabled or not true = enable, false = disabled
    if ($name eq "status") {
        if (grep { /^zapi/ } readFileAsArray(&getGlobalConfiguration('htpass'))) {
            $result = "true";
        }
    }
    elsif ($name eq "zapikey") {
        $result = &getGlobalConfiguration('zapikey');
    }

    return $result;
}

=pod

=head1 setAPI

Set zapi values

Parameters:

    name - Actions to be taken: 'enable', 'disable', 'randomkey' to set a random key, or 'key' to set the key specified in value.

        enable - Enables the user 'zapi'.
        disable - Disables the user 'zapi'.
        randomkey - Generates a random key.
        key - Sets $value a the zapikey.

    value - New key to be used. Only apply when the action 'key' is used.

Returns:

    none

Bugs:

    -setGlobalConfig should be used to set the zapikey.
    -Randomkey is not used.

=cut

sub setAPI ($name, $value = undef) {
    my $globalcfg = &getGlobalConfiguration('globalcfg');

    #Enable ZAPI
    if ($name eq "enable") {
        my $cmd = "adduser --system --shell /bin/false --no-create-home zapi";
        return &logAndRun($cmd);
    }

    #Disable ZAPI
    if ($name eq "disable") {
        my $deluser_bin = &getGlobalConfiguration('deluser_bin');
        my $cmd         = "$deluser_bin zapi";

        # delete zapikey
        require Tie::File;
        tie my @contents, 'Tie::File', "$globalcfg";

        for my $line (@contents) {
            if ($line =~ /^\$zapikey/) {
                $line =~ s/^\$zapikey.*/\$zapikey=""\;/g;
            }
        }
        untie @contents;

        # Update zapikey global configuration
        &getGlobalConfiguration('zapikey', 1);
        return &logAndRun($cmd);
    }

    #Set Random key for zapi
    if ($name eq "randomkey") {
        require Tie::File;
        my $random = &getAPIRandomKey(64);

        tie my @contents, 'Tie::File', "$globalcfg";
        for my $line (@contents) {
            if ($line =~ /zapi/) {
                $line =~ s/^\$zapikey.*/\$zapikey="$random"\;/g;
            }
        }
        untie @contents;
    }

    #Set ZAPI KEY
    if ($name eq "key") {
        if ($eload) {
            $value = &eload(
                module => 'Relianoid::EE::Code',
                func   => 'setCryptString',
                args   => [$value],
            );
        }

        require Tie::File;
        tie my @contents, 'Tie::File', "$globalcfg";

        for my $line (@contents) {
            if ($line =~ /zapi/) {
                $line =~ s/^\$zapikey.*/\$zapikey="$value"\;/g;
            }
        }
        untie @contents;

        # Update zapikey global configuration
        &getGlobalConfiguration('zapikey', 1);
    }

    return;
}

=pod

=head1 getAPIRandomKey

Generate random key for ZAPI user.

Parameters:

    length - Number of characters in the new key.

Returns:

    string - Random key.

See Also:

    <setAPI>

=cut

sub getAPIRandomKey ($length) {
    my @alphanumeric = ('a' .. 'z', 'A' .. 'Z', 0 .. 9);
    my $randpassword = join '', map { $alphanumeric[ rand @alphanumeric ] } 0 .. $length;

    return $randpassword;
}

=pod

=head1 isApiKeyValid

Parameters:

    Read the enviroment variable $ENV{HTTP_ZAPI_KEY}

Returns:

    integer

    0 - If the API key was invalid
    1 - If the API key was valid

=cut

sub isApiKeyValid () {
    my $validKey = 0;                 # output
    my $key      = "HTTP_ZAPI_KEY";

    require Relianoid::User;
    if (exists $ENV{$key}) {
        # zapi user is enabled and matches key
        if (&getAPI("status") eq "true" && &getAPI("zapikey") eq $ENV{$key}) {
            &setUser('root');
            $validKey = 1;
        }
        elsif ($eload) {
            # get a RBAC user
            my $user = &eload(
                module => 'Relianoid::EE::RBAC::User::Core',
                func   => 'validateRBACUserZapi',
                args   => [ $ENV{$key} ],
            );
            if ($user) {
                &setUser($user);
                $validKey = 1;
            }
        }
    }

    return $validKey;
}

=pod

=head1 getApiVersionsList

Parameters:

    none

Returns:

    list of API versions (as strings)

=cut

sub getApiVersionsList () {
    my $version_st     = &getGlobalConfiguration("zapi_versions");
    my @versions       = split(' ', $version_st);
    my @versions_array = sort @versions;
    return @versions_array;
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

1;

