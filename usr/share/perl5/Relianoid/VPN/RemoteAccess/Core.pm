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

use Config::Tiny;

=pod

=head1 Module

Relianoid::VPN::RemoteAccess::Core

=cut

=pod

=head1 getVpnRemoteAccessExists

	Check if Remote Access VPN exits. 

Parameters:
	$vpn_name - vpn connection name.

Returns:
	Integer - Error code: 0 on success or other value on failure.

=cut

sub getVpnRemoteAccessExists ($vpn_name) {
    my $rc    = 1;
    my $found = 0;

    require Relianoid::VPN::Core;
    $found++ if (-f &getVpnConfFilePath($vpn_name));

    require Relianoid::VPN::IPSec::Core;
    $found++ if (-f &getVpnIPSecConnFilePath($vpn_name));
    $found++ if (-f &getVpnIPSecKeyFilePath($vpn_name));

    require Relianoid::VPN::L2TP::Core;
    $found++ if (-f &getVpnL2TPConfFilePath($vpn_name));
    $found++ if (-f &getVpnL2TPPppFilePath($vpn_name));
    $found++ if (-f &getVpnL2TPPppSecretFilePath());
    $rc = 0  if ($found == 6);

    return $rc;
}

=pod

=head1 getVpnRemoteAccessStatus

	Gets the status of a Remote Access VPN connection , and its L2TP daemon.

Parameters:
	vpn_name - vpn connection name.

Returns:
	String - Remote Access VPN status . empty|connecting|up|down|l2tp down|ipsec down

=cut 

sub getVpnRemoteAccessStatus ($vpn_name) {
    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    my $status      = $vpn_config->{STATUS_DOWN};
    my $status_comp = 0;

    require Relianoid::VPN::IPSec::Runtime;
    if (&checkVPNIPSecSvcRunning() == 0) {
        # Ipsec is waiting for a connection.
        require Relianoid::VPN::IPSec::Core;
        my $status = &getVpnIPSecStatus($vpn_name);
        if (    $status ne $vpn_config->{STATUS_DOWN}
            and $status ne $vpn_config->{STATUS_UP})
        {
            $status_comp += 1;
        }
    }
    else {
        $status_comp += 1;
    }

    require Relianoid::VPN::L2TP::Runtime;
    if (&checkVPNL2TPDaemonRunning($vpn_name) == 0) {
        require Relianoid::VPN::L2TP::Core;
        if (&getVpnL2TPLnsStatus($vpn_name) ne $vpn_config->{STATUS_UP}) {
            $status_comp += 2;
        }
    }
    else {
        $status_comp += 2;
    }

    if ($status_comp == 0) {
        $status = $vpn_config->{STATUS_UP};
        if (&getVpnRemoteAccessRouteStatus($vpn_name) eq $vpn_config->{STATUS_DOWN}) {
            $status = $vpn_config->{STATUS_ROUTE_DOWN};
        }
    }
    elsif ($status_comp == 1) {
        $status = $vpn_config->{STATUS_IPSEC_DOWN};
    }
    elsif ($status_comp == 2) {
        $status = $vpn_config->{STATUS_L2TP_DOWN};
    }

    return $status;
}

=pod

=head1 getVpnRemoteAccessRouteStatus

	Gets the status of the routing Remote Access VPN connection.

Parameters:
	vpn_name - vpn connection name.

Returns:
	String - Remote Access VPN Routing status . up|down

=cut

sub getVpnRemoteAccessRouteStatus ($vpn_name) {
    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();
    my $status     = $vpn_config->{STATUS_DOWN};
    my $vpn_ref    = &getVpnConfObject($vpn_name);

    require Relianoid::Net::Route;

    if (!&getRoutingTableExists("table_$vpn_name")) {
        return $status;
    }

    my $local_net =
      NetAddr::IP->new($vpn_ref->{ $vpn_config->{LOCALIP} }, $vpn_ref->{ $vpn_config->{LOCALMASK} })->network();
    my $remote_net =
      NetAddr::IP->new($vpn_ref->{ $vpn_config->{LOCALTUNIP} }, $vpn_ref->{ $vpn_config->{LOCALTUNMASK} })->network();

    my $rule = {
        from  => $local_net,
        to    => $remote_net,
        table => "table_$vpn_name",
        type  => 'vpn',
    };

    if (!&isRule($rule)) {
        return $status;
    }

    my $route_cmd = $remote_net . " via " . $vpn_ref->{ $vpn_config->{LOCALIP} } . " table table_$vpn_name ";

    if (!isRoute($route_cmd)) {
        return $status;
    }

    return $vpn_config->{STATUS_UP};
}

1;
