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

Relianoid::VPN::Tunnel::Core

=cut

=pod

=head1 getVpnTunnelExists

	Check if Tunnel VPN exits.

Parameters:
	$vpn_name - vpn connection name.

Returns:
	Integer - Error code: 0 on success or other value on failure.

=cut

sub getVpnTunnelExists ($vpn_name) {
    my $rc    = 1;
    my $found = 0;

    require Relianoid::VPN::Core;
    require Relianoid::VPN::IPSec::Core;

    $found++ if (-f &getVpnConfFilePath($vpn_name));
    $found++ if (-f &getVpnIPSecConnFilePath($vpn_name));
    $found++ if (-f &getVpnIPSecKeyFilePath($vpn_name));
    $rc = 0  if ($found == 3);
    return $rc;
}

=pod

=head1 getVpnTunnelStatus

	Gets the status of a Tunnel VPN connection and its virtual interface.

Parameters:
	vpn_name - vpn connection name.

Returns:
	String - Tunnel VPN status . empty|connecting|up|down|unloaded|tunnel down|ipsec down

=cut

sub getVpnTunnelStatus ($vpn_name) {
    require Relianoid::VPN::Core;

    my $vpn_config  = &getVpnModuleConfig();
    my $status      = $vpn_config->{STATUS_DOWN};
    my $status_comp = 0;

    require Relianoid::VPN::IPSec::Runtime;

    if (&checkVPNIPSecSvcRunning() == 0) {
        require Relianoid::VPN::IPSec::Core;
        my $ipsec_status = &getVpnIPSecStatus($vpn_name);

        return $ipsec_status
          if ($ipsec_status eq $vpn_config->{STATUS_UNLOADED});

        $status_comp += 1 if ($ipsec_status ne $vpn_config->{STATUS_UP});
    }
    else {
        $status_comp += 1;
    }

    require Relianoid::Net::Interface;
    my $tunnel_ref = &getSystemInterface($vpn_name);

    if (!defined $tunnel_ref
        || $tunnel_ref->{status} eq 'down')
    {
        $status_comp += 2;
    }

    if ($status_comp == 0) {
        $status = $vpn_config->{STATUS_UP};

        if (&getVpnTunnelRouteStatus($vpn_name) eq $vpn_config->{STATUS_DOWN}) {
            $status = $vpn_config->{STATUS_ROUTE_DOWN};
        }
    }
    elsif ($status_comp == 1) {
        $status = $vpn_config->{STATUS_IPSEC_DOWN};
    }
    elsif ($status_comp == 2) {
        $status = $vpn_config->{STATUS_TUNN_DOWN};
    }

    return $status;
}

=pod

=head1 getVpnTunnelRouteStatus

	Gets the status of the routing Tunnel VPN connection.

Parameters:
	vpn_name - vpn connection name.

Returns:
	String - Tunnel VPN Routing status . up|down

=cut

sub getVpnTunnelRouteStatus ($vpn_name) {
    require Relianoid::VPN::Core;

    if (&getVpnRestartStatus($vpn_name) eq "true") {
        return &getVpnTunnelRouteSystemStatus($vpn_name);
    }
    else {
        return &getVpnTunnelRouteConfigStatus($vpn_name);
    }
}

=pod

=head1 getVpnTunnelRouteConfigStatus

	Gets the status of the routing Tunnel VPN connection using config values.

Parameters:
	vpn_name - vpn connection name.

Returns:
	String - Tunnel VPN Routing status . up|down

=cut

sub getVpnTunnelRouteConfigStatus ($vpn_name) {
    require Relianoid::VPN::Core;

    my $vpn_config = &getVpnModuleConfig();
    my $status     = $vpn_config->{STATUS_DOWN};
    my $vpn_ref    = &getVpnConfObject($vpn_name);

    require Relianoid::Net::Route;

    if (!&getRoutingTableExists("table_$vpn_name")) {
        return $status;
    }

    my $rule = {
        from  => $vpn_ref->{ $vpn_config->{LOCALNET} },
        to    => $vpn_ref->{ $vpn_config->{REMOTENET} },
        table => "table_$vpn_name",
        type  => 'vpn',
    };

    require Relianoid::Net::Route;

    if (!&isRule($rule)) {
        return $status;
    }

    my $route_cmd =
        $vpn_ref->{ $vpn_config->{REMOTENET} } . " via "
      . $vpn_ref->{ $vpn_config->{REMOTETUNIP} } . " dev "
      . $vpn_name . " "
      . "table table_$vpn_name ";

    if (!isRoute($route_cmd)) {
        return $status;
    }

    return $vpn_config->{STATUS_UP};
}

=pod

=head1 getVpnTunnelRouteSystemStatus

	Gets the status of the routing Tunnel VPN connection using system values.

Parameters:
	vpn_name - vpn connection name.

Returns:
	String - Tunnel VPN Routing status . up|down

=cut

sub getVpnTunnelRouteSystemStatus ($vpn_name) {
    require Relianoid::VPN::Core;

    my $vpn_config = &getVpnModuleConfig();
    my $status     = $vpn_config->{STATUS_DOWN};

    use Relianoid::Net::Route;

    # get rule from system
    my $rule_filter = { table => "table_$vpn_name" };
    my $system_rule = &listRoutingRulesSys($rule_filter);

    if (!@{$system_rule}) {
        return $status;
    }

    # get route from system
    my $system_route = &listRoutingTableSys("table_$vpn_name");

    if (!@{$system_route}) {
        return $status;
    }

    return $vpn_config->{STATUS_UP};
}

1;
