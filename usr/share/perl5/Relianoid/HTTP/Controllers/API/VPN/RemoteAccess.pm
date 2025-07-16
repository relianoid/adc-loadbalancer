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

use Relianoid::HTTP;
use Relianoid::Config;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::VPN::RemoteAccess

=cut

# GET /vpns/modules/remote_access
sub list_vpn_remote_access_controller () {
    my $out  = [];
    my $desc = "List Remote Access VPNs";

    my $type   = "remote_access";
    my $params = [ "name", "status", "local", "localnet", "remote", "remotenet" ];

    require Relianoid::VPN::Core;
    require Relianoid::HTTP::Controllers::API::VPN::Structs;
    my $params_translated = &parseVPNRequest($params, "4.0");

    my $vpns = &getVpnList($type);
    for my $vpn_name (@{$vpns}) {
        my $vpn_obj = &getVpnObject($vpn_name, $params_translated);
        my $api_obj = &getVpnObjectResponse($vpn_obj, "4.0");
        push @{$out}, $api_obj;
    }

    my $body = {
        description => $desc,
        params      => $out,
    };

    return &httpResponse({ code => 200, body => $body });
}

# POST /vpns Create a new Remote Access VPN
sub _add_vpn_remote_access_controller ($json_obj) {
    my $desc = "Create Remote Access VPN $json_obj->{name}";

    # create api params already done
    # check api params already done
    # integrity checks

    require Relianoid::HTTP::Controllers::API::VPN::Structs;
    my $remote_access = &getVpnObjectResponse($json_obj, "4.0", "config");

    require Relianoid::VPN::RemoteAccess::Validate;
    my $error = &validateVpnRemoteAccessObject($remote_access);

    if ($error->{code}) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error->{desc} });
    }

    require Relianoid::VPN::RemoteAccess::Config;
    $error = &createVpnRemoteAccess($remote_access);

    if ($error->{code}) {
        my $error_msg = "Some errors happened trying to create VPN. " . $error->{desc} . ".";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    require Relianoid::VPN::Config;
    my $out_obj = &getVpnObject($json_obj->{name});
    my $api_obj = &getVpnObjectResponse($out_obj, "4.0", "api");

    my $msg  = "The VPN $json_obj->{name} has been created successfully.";
    my $body = {
        description => $desc,
        params      => $api_obj,
        message     => $msg,
    };

    return &httpResponse({ code => 201, body => $body });
}

# PUT /vpns/<vpn_name> Modify a Remote access VPN
sub _modify_vpn_remote_access_controller ($json_obj, $vpn_name) {
    my $desc = "Modify Remote Access VPN $vpn_name";

    my $params = {
        local          => { valid_format => 'ip_addr',       non_blank => 'true', },
        localip        => { valid_format => 'ip_addr',       non_blank => 'true', },
        localmask      => { valid_format => 'ip_mask',       non_blank => 'true', },
        localtunip     => { valid_format => 'ip_addr',       non_blank => 'true', },
        localtunmask   => { valid_format => 'ip_mask',       non_blank => 'true', },
        remotetunrange => { valid_format => 'ip_addr_range', non_blank => 'true', },
        password       => { non_blank    => 'true', },
        p1encrypt      => {
            ref       => 'ARRAY',
            non_blank => 'true',
            values    => [
                'aes128', 'aes192',      'aes256',      'aes128gmac',  'aes192gmac',  'aes256gmac',
                '3des',   'blowfish128', 'blowfish192', 'blowfish256', 'camellia128', 'camellia192',
                'camellia256'
            ],
        },
        p1authen => {
            ref       => 'ARRAY',
            non_blank => 'true',
            values    => [ 'md5', 'sha1', 'sha256', 'sha384', 'sha512', 'aesxcbc', 'aes128gmac', 'aes192gmac', 'aes256gmac' ],
        },
        p1dhgroup => {
            ref       => 'ARRAY',
            non_blank => 'true',
            values    => [ 'modp768', 'modp1024', 'modp1536', 'modp2048', 'modp3072', 'modp4096', 'modp6144', 'modp8192' ],
        },
        p2encrypt => {
            ref       => 'ARRAY',
            non_blank => 'true',
            values    => [
                'aes128', 'aes192',      'aes256',      'aes128gmac',  'aes192gmac',  'aes256gmac',
                '3des',   'blowfish128', 'blowfish192', 'blowfish256', 'camellia128', 'camellia192',
                'camellia256'
            ],
        },
        p2authen => {
            ref       => 'ARRAY',
            non_blank => 'true',
            values    => [ 'md5', 'sha1', 'sha256', 'sha384', 'sha512', 'aesxcbc', 'aes128gmac', 'aes192gmac', 'aes256gmac' ],
        },
    };

    # check api params
    require Relianoid::Validate;

    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # integrity checks
    require Relianoid::VPN::Core;
    my $vpn_ref = getVpnConfObject($vpn_name);

    require Relianoid::HTTP::Controllers::API::VPN::Structs;
    my $remote_access = &getVpnObjectResponse($json_obj, "4.0", "config");

    require Relianoid::VPN::RemoteAccess::Validate;
    my $error = &validateVpnRemoteAccessObject($vpn_ref, $remote_access);

    if ($error->{code}) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error->{desc} });
    }

    # set params
    require Relianoid::VPN::RemoteAccess::Config;
    $error = &setVpnRemoteAccessParams($vpn_name, $remote_access);

    if ($error->{code}) {
        my $error_msg = "Some errors happened trying to modify the " . $error->{err} . "." . $error->{desc};
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # get api obj response
    my $out_obj = &getVpnObject($vpn_name);
    my $api_obj = &getVpnObjectResponse($out_obj, "4.0", "api");

    my $msg  = "Some parameters have been changed in VPN $vpn_name.";
    my $body = {
        description => $desc,
        params      => $api_obj,
        message     => $msg,
    };

    return &httpResponse({ code => 200, body => $body });
}

1;
