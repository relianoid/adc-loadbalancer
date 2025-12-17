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

Relianoid::VPN::IPSec::Core

=cut

=pod

=head1 getVpnIPSecInitConfig

	Gets the default values of a IPSec object.

Parameters:
	None.

Returns:
	Hash ref - Object with default values.

=cut

sub getVpnIPSecInitConfig () {
    return {
        # ike => "aes256gcm16-aes256gcm12-aes128gcm16-aes128gcm12-sha256-sha1-modp2048-modp4096-modp1024,aes256-aes128-sha256-sha1-modp2048-modp4096-modp1024,3des-sha1-modp1024!",
        ike => join(
            ',',
            qw(
              aes256gcm16-aes256gcm12-aes128gcm16-aes128gcm12-sha256-sha1-modp2048-modp4096-modp1024
              aes256-aes128-sha256-sha1-modp2048-modp4096-modp1024
              3des-sha1-modp1024!
            )
        ),

        # esp => "aes128gcm12-aes128gcm16-aes256gcm12-aes256gcm16-modp2048-modp4096-modp1024,aes128-aes256-sha1-sha256-modp2048-modp4096-modp1024,aes128-sha1-modp2048,aes128-sha1-modp1024,3des-sha1-modp1024,aes128-aes256-sha1-sha256,aes128-sha1,3des-sha1!",
        esp => join(
            ',',
            qw(
              aes128gcm12-aes128gcm16-aes256gcm12-aes256gcm16-modp2048-modp4096-modp1024
              aes128-aes256-sha1-sha256-modp2048-modp4096-modp1024
              aes128-sha1-modp2048
              aes128-sha1-modp1024
              3des-sha1-modp1024
              aes128-aes256-sha1-sha256
              aes128-sha1
              3des-sha1!
            )
        ),
        keyingtries => "1",
        ikelifetime => "1h",
        lifetime    => "8h",
        dpddelay    => "30",
        dpdtimeout  => "120",
        dpdaction   => "restart",
        auto        => "add",
    };
}

=pod

=head1 getVpnIPSecParamName

	Translate Config Param Name to IPSec Param Name and viceversa.

Parameters:
	param - String : Param to translate.
	mode - String :  Indicates the format to translate.

Returns:
	String - IPSec Param or undef if param not found.

=cut

sub getVpnIPSecParamName ($param, $mode) {
    my $params;

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    if ($mode eq "ipsec") {
        $params = {
            $vpn_config->{LOCAL}     => "left",
            $vpn_config->{LOCALNET}  => "leftsubnet",
            $vpn_config->{REMOTE}    => "right",
            $vpn_config->{REMOTENET} => "rightsubnet",
        };
    }
    elsif ($mode eq "config") {
        $params = {
            left        => $vpn_config->{LOCAL},
            leftsubnet  => $vpn_config->{LOCALNET},
            right       => $vpn_config->{REMOTE},
            rightsubnet => $vpn_config->{REMOTENET},
        };
    }

    return $params->{$param};
}

=pod

=head1 getVpnIPSecSecretType

Gets the secret type for a secret mode.

Parameters:

    secret_mode - string - Secret type definition.

Returns: string - Cipher

Value for the secret type: The Values can be RSA|ECDSA|BLISS|P12|PSK|EAP|NTLM|XAUTH|PIN.

The default is RSA.

=cut

sub getVpnIPSecSecretType ($secret) {
    my $type = "RSA";

    my $secret_types = {
        pubkey      => "P12",
        rsasig      => "RSA",
        ecdsasig    => "ECDSA",
        psk         => "PSK",
        secret      => "PSK",
        xauthrsasig => "XAUTH",
        xauthpsk    => "XAUTH",
        never       => "PSK",
    };

    if (defined $secret && defined $secret_types->{$secret}) {
        $type = $secret_types->{$secret};
    }

    return $type;
}

=pod

=head1 getVpnIPSecConnFilePath

	Gets the Connection filepath of a IPSec connection.

Parameters:
	vpn_name - vpn connection name.

Returns:
	String - Filepath.

=cut

sub getVpnIPSecConnFilePath ($vpn_name) {
    return (&getVpnConfigPath() . "/" . $vpn_name . "_conn.conf");
}

=pod

=head1 getVpnIPSecKeyFilePath

	Gets the Secret filepath of a Site-to-Site VPN connection.

Parameters:
	vpn_name - vpn connection name.

Returns:
	String - Filepath.

=cut

sub getVpnIPSecKeyFilePath ($vpn_name) {
    return (&getVpnConfigPath() . "/" . $vpn_name . "_secret.conf");
}

=pod

=head1 getVpnIPSecStatus

	Gets the status of a IPSec connection.

Parameters:
	conn_name - connection name.

Returns:
	String - IPSec conn status . empty|unloaded|connecting|up|down

=cut

sub getVpnIPSecStatus ($conn_name) {
    require Relianoid::VPN::IPSec::Runtime;

    my $status        = &runVPNIPSecIKEDaemonStatus();
    my $remote_access = "";

    if ($status ne "") {
        require Relianoid::VPN::Core;
        my $vpn_config = &getVpnModuleConfig();

        if (defined $status->{sa}{$conn_name}{child}) {
            my $child_status = $status->{sa}{$conn_name}{child}{status};

            my $parent = $conn_name;

            $parent = $status->{conns}{$conn_name}{parent}
              if defined $status->{conns}{$conn_name}{parent};

            my $ike_status = $status->{sa}{$parent}{ike}{status};

            $remote_access = $vpn_config->{STATUS_CONNECTING}
              if ($ike_status eq "CONNECTING");

            $remote_access = $vpn_config->{STATUS_UP}
              if ($ike_status eq "ESTABLISHED" and $child_status eq "INSTALLED");
        }
        else {
            if (defined $status->{conns}{$conn_name}) {
                $remote_access = $vpn_config->{STATUS_DOWN};
            }
            else {
                $remote_access = $vpn_config->{STATUS_UNLOADED};
            }
        }
    }

    return $remote_access;
}

=pod

=head1 getVpnIPSecInfo

	Gets the Ike Daemon info of a IPSec connection.

Parameters:
	conn_name - connection name.

Returns:
	Hash ref - Undef on error.

=cut

sub getVpnIPSecInfo ($conn_name) {
    require Relianoid::VPN::IPSec::Runtime;

    my $remote_access;
    my $info = &runVPNIPSecIKEDaemonStatus();

    if (!defined $info || $info ne "") {
        if (defined $info->{conns}{$conn_name}) {
            $remote_access->{conns} = $info->{conns}{$conn_name};
            $remote_access->{sa}    = $info->{sa}{$conn_name};
        }
    }
    return $remote_access;
}

=pod

=head1 getVpnIPSecStats

	Gets the Network stats of a IPSec connection.

Parameters:
	conn_name - connection name.

Returns:
	Hash ref - Undef on error.

=cut

sub getVpnIPSecStats ($conn_name) {
    my $stats_ref;
    my $info = &getVpnIPSecInfo($conn_name);

    if (!defined $info || $info ne "") {
        if (defined $info->{sa}{child}) {
            $stats_ref->{in}  = $info->{sa}{child}{bytes_in};
            $stats_ref->{out} = $info->{sa}{child}{bytes_out};
        }
    }
    return $stats_ref;
}

1;
