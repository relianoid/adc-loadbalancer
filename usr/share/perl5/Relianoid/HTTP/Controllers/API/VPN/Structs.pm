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

Relianoid::HTTP::Controllers::API::VPN::Structs

=cut

=pod

=head1 getVpnResponse 

Translate the VPN Config params to API params.

Parameters:

    config_ref  - Array of vpn config params.
    api_version - Version of the API

Returns: hash reference - Translated params.

=cut

sub getVpnResponse ($config_ref, $api_version) {
    require Relianoid::VPN::Core;

    my $vpn_config = &getVpnModuleConfig();
    my $out;

    my $params = {
        "4.0" => {
            $vpn_config->{NAME}           => 'name',
            $vpn_config->{PROFILE}        => 'profile',
            $vpn_config->{STATUS}         => 'status',
            $vpn_config->{LOCAL}          => 'local',
            $vpn_config->{LOCALNET}       => 'localnet',
            $vpn_config->{LOCALIP}        => 'localip',
            $vpn_config->{LOCALMASK}      => 'localmask',
            $vpn_config->{LOCALTUNIP}     => 'localtunip',
            $vpn_config->{LOCALTUNMASK}   => 'localtunmask',
            $vpn_config->{REMOTE}         => 'remote',
            $vpn_config->{REMOTENET}      => 'remotenet',
            $vpn_config->{REMOTEIP}       => 'remoteip',
            $vpn_config->{REMOTEMASK}     => 'remotemask',
            $vpn_config->{REMOTETUNIP}    => 'remotetunip',
            $vpn_config->{REMOTETUNRANGE} => 'remotetunrange',
            $vpn_config->{AUTH}           => 'auth',
            $vpn_config->{PASS}           => 'password',
            $vpn_config->{P1ENCRYPT}      => 'p1encrypt',
            $vpn_config->{P1AUTHEN}       => 'p1authen',
            $vpn_config->{P1DHGROUP}      => 'p1dhgroup',
            $vpn_config->{P2PROTO}        => 'p2protocol',
            $vpn_config->{P2ENCRYPT}      => 'p2encrypt',
            $vpn_config->{P2AUTHEN}       => 'p2authen',
            $vpn_config->{P2DHGROUP}      => 'p2dhgroup',
            $vpn_config->{P2PRF}          => 'p2prfunc',
            $vpn_config->{VPN_USER}       => 'vpnuser',
            $vpn_config->{VPN_PASSWORD}   => 'vpnpass'
        }
    };

    if ($config_ref) {
        for my $param (@{$config_ref}) {
            push @{$out}, $params->{$api_version}{$param};
        }
    }

    return $out;
}

=pod

=head1 parseVPNRequest

Translate the API Params into Config params.

Parameters:

    api_ref     - Array of params to translate.
    api_version - Version of the API

Returns: arrary reference - Translated array.

=cut

sub parseVPNRequest ($api_ref, $api_version) {
    require Relianoid::VPN::Core;

    my $vpn_config = &getVpnModuleConfig();

    my $params = {
        "4.0" => {
            name           => $vpn_config->{NAME},
            profile        => $vpn_config->{PROFILE},
            status         => $vpn_config->{STATUS},
            local          => $vpn_config->{LOCAL},
            localnet       => $vpn_config->{LOCALNET},
            localip        => $vpn_config->{LOCALIP},
            localmask      => $vpn_config->{LOCALMASK},
            localtunip     => $vpn_config->{LOCALTUNIP},
            localtunmask   => $vpn_config->{LOCALTUNMASK},
            remote         => $vpn_config->{REMOTE},
            remotenet      => $vpn_config->{REMOTENET},
            remoteip       => $vpn_config->{REMOTEIP},
            remotemask     => $vpn_config->{REMOTEMASK},
            remotetunip    => $vpn_config->{REMOTETUNIP},
            remotetunrange => $vpn_config->{REMOTETUNRANGE},
            auth           => $vpn_config->{AUTH},
            password       => $vpn_config->{PASS},
            p1encrypt      => $vpn_config->{P1ENCRYPT},
            p1authen       => $vpn_config->{P1AUTHEN},
            p1dhgroup      => $vpn_config->{P1DHGROUP},
            p2protocol     => $vpn_config->{P2PROTO},
            p2encrypt      => $vpn_config->{P2ENCRYPT},
            p2authen       => $vpn_config->{P2AUTHEN},
            p2dhgroup      => $vpn_config->{P2DHGROUP},
            p2prfunc       => $vpn_config->{P2PRF},
            vpnuser        => $vpn_config->{VPN_USER},
            vpnpass        => $vpn_config->{VPN_PASSWORD}
        }
    };

    my $out;

    if ($api_ref) {
        for my $param (@{$api_ref}) {
            push @{$out}, $params->{$api_version}{$param};
        }
    }

    return $out;
}

=pod

=head1 getVpnObjectResponse

Returns the VPN object params or the API object params translated.

Parameters:

    obj_ref      - VPN object or API object to translate.
    api_version  - Version of the API
    translate_to - Optional. Translation : values "config" or "api".

Returns: hash reference - Translated object.

=cut

sub getVpnObjectResponse ($obj_ref, $api_version, $translated_to = undef) {
    my $out;

    my $params_translated;
    my @params = keys %{$obj_ref};

    if ($translated_to && $translated_to eq "config") {
        $params_translated = &parseVPNRequest(\@params, $api_version);
    }
    else {
        $params_translated = &getVpnResponse(\@params, $api_version);
    }

    for my $idx (0 .. $#params) {
        $out->{ @{$params_translated}[$idx] } = $obj_ref->{ $params[$idx] }
          if defined @{$params_translated}[$idx];
    }

    return $out;
}

1;
