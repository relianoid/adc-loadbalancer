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

Relianoid::VPN::Tunnel::Action

=cut

use strict;
use warnings;
use feature qw(signatures);

require Relianoid::VPN::IPSec::Runtime;

=pod

=head1 _runVpnTunnelStart

Run a Tunnel VPN

Parameters:

    vpn_name - string - VPN name

Returns: integer - error code

0  - success
!0 - error

=cut

sub _runVpnTunnelStart ($vpn_name) {
    require Relianoid::VPN::Core;
    require Relianoid::VPN::IPSec::Runtime;

    my $vpn_config = &getVpnModuleConfig();
    my $status     = &checkVPNIPSecSvcRunning();

    if ($status > 0) {
        &log_info("Starting VPN IPSec Daemon.", "VPN");
        require Relianoid::VPN::IPSec::Action;

        $status = runVPNIPSecSvcStart();
        sleep 1;

        if ($status > 0) {
            &log_error("VPN IPSec Daemon start failed", "VPN");
            return 1;
        }
    }

    require Relianoid::VPN::IPSec::Runtime;

    my $error_ref = &runVPNIPSecIKEDaemonCommand("up", $vpn_name);

    if ($error_ref->{code} != 0) {
        &log_error("VPN Tunnel $vpn_name start failed: $error_ref->{err}", "VPN");
        return $error_ref->{code};
    }

    require Relianoid::Net::Validate;
    require Relianoid::VPN::Config;

    my $tunnel_ref;
    my $tunnel = &getVpnConfObject($vpn_name);

    if (&ifexist($vpn_name) eq 'false') {
        my $error = &createVPNTunnelIf(
            $tunnel->{ $vpn_config->{NAME} },
            "gre",
            $tunnel->{ $vpn_config->{LOCALIP} },
            $tunnel->{ $vpn_config->{REMOTEIP} },
            $tunnel->{ $vpn_config->{LOCALTUNIP} },
            $tunnel->{ $vpn_config->{LOCALTUNMASK} }
        );

        if ($error > 0) {
            &log_error("VPN Tunnel Tunnel Interface $vpn_name create failed ( $error )", "VPN");
            my $error_ref = &runVPNIPSecIKEDaemonCommand("down", $vpn_name);
            return 2 if ($error_ref->{code} == 0);
            return $error_ref->{code};
        }
    }
    else {
        require Relianoid::Net::Core;
        require Relianoid::Net::Interface;
        require Relianoid::Net::Route;
        require Relianoid::Net::Util;

        $tunnel_ref = &getSystemInterface($tunnel->{ $vpn_config->{NAME} });

        # ip , mask , net and ip_v  are not filled by getSystemInterface
        $tunnel_ref->{addr} = IO::Socket::INET->new(Proto => 'udp')->if_addr($tunnel->{ $vpn_config->{NAME} });
        $tunnel_ref->{mask} = IO::Socket::INET->new(Proto => 'udp')->if_netmask($tunnel->{ $vpn_config->{NAME} });
        $tunnel_ref->{net}  = NetAddr::IP->new($tunnel_ref->{addr}, $tunnel_ref->{mask})->network()->addr();
        $tunnel_ref->{ip_v} = &ipversion($tunnel_ref->{addr});

        if ($tunnel_ref->{addr}) {
            &delIp($tunnel->{ $vpn_config->{NAME} }, $tunnel_ref->{addr}, $tunnel_ref->{mask});
            &delRoutes("local", $tunnel_ref);
        }

        &downIf($tunnel_ref);

        my $error = &setVPNTunnelIf(
            $tunnel->{ $vpn_config->{NAME} },
            $tunnel->{ $vpn_config->{LOCALIP} },
            $tunnel->{ $vpn_config->{REMOTEIP} },
        );

        if ($error > 0) {
            &log_error("VPN Tunnel Tunnel Interface $vpn_name modified failed ( $error )", "VPN");
            my $error_ref = &runVPNIPSecIKEDaemonCommand("down", $vpn_name);
            return 2 if ($error_ref->{code} == 0);
            return $error_ref->{code};
        }
    }

    if (!defined $tunnel_ref) {
        require Relianoid::Net::Interface;
        require Relianoid::Net::Core;
    }

    $tunnel_ref = &getInterfaceConfig($vpn_name);
    &addIp($tunnel_ref);
    $status = &upIf($tunnel_ref, "writeconf");

    if ($status) {
        &log_error("VPN Tunnel Tunnel Interface $vpn_name UP failed", "VPN");
        my $error_ref = &runVPNIPSecIKEDaemonCommand("down", $vpn_name);
        return 3 if ($error_ref->{code} == 0);
        return $error_ref->{code};
    }

    &log_info("VPN Tunnel $vpn_name start successfully", "VPN");
    return 0;
}

=pod

=head1 runVpnTunnelStart

Start a Tunnel VPN connection, create routes, create rules

Parameters:

	vpn_name - VPN name
	write_conf - Optional. String to save bootstatus. "false" no save, "true" save.

Returns: integer - error code

0  - success
!0 - error

=cut

sub runVpnTunnelStart ($vpn_name, $write_conf = undef) {
    my $rc = -1;

    require Relianoid::VPN::Core;

    my $vpn_ref = &getVpnConfObject($vpn_name);

    if (!$vpn_ref) {
        &log_info("VPN Tunnel $vpn_name conf not valid", "VPN");
        return $rc;
    }

    if ($write_conf && $write_conf eq "false") {
        $write_conf = undef;
    }

    my $vpn_config = &getVpnModuleConfig();

    # check if localnet and remote net are in use
    my $params = {
        $vpn_config->{LOCALIP}    => $vpn_ref->{ $vpn_config->{LOCALIP} },
        $vpn_config->{LOCALMASK}  => $vpn_ref->{ $vpn_config->{LOCALMASK} },
        $vpn_config->{REMOTEIP}   => $vpn_ref->{ $vpn_config->{REMOTEIP} },
        $vpn_config->{REMOTEMASK} => $vpn_ref->{ $vpn_config->{REMOTEMASK} }
    };

    my $vpn_name_found = &getVpnParamExists("tunnel", $params, $vpn_name);

    if ($vpn_name_found !~ /^\d+$/) {
        my $status = &getVpnStatus($vpn_name_found);

        if (   ($status eq $vpn_config->{STATUS_UP})
            or ($status eq $vpn_config->{STATUS_CONNECTING}))
        {
            my $msg = "Local network $vpn_ref->{ $vpn_config->{LOCALIP} } / $vpn_ref->{ $vpn_config->{LOCALMASK} } ";
            $msg .= "and Remote network $vpn_ref->{ $vpn_config->{REMOTEIP} } / $vpn_ref->{ $vpn_config->{LOCALMASK} } ";
            $msg .= "are in use by VPN $vpn_name_found";
            &log_warn($msg, "VPN");

            return 1;
        }
    }

    require Relianoid::VPN::Tunnel::Core;
    my $status = &getVpnTunnelStatus($vpn_name);

    if ($status eq $vpn_config->{STATUS_UNLOADED}) {
        &log_warn("VPN Tunnel $vpn_name is only configured : Reloading config", "VPN");

        &runVpnTunnelReload();
        $status = &getVpnTunnelStatus($vpn_name);
    }

    if (   $status eq $vpn_config->{STATUS_UP}
        or $status eq $vpn_config->{STATUS_CONNECTING})
    {
        &log_warn("VPN Tunnel $vpn_name is already running", "VPN");

        require Relianoid::VPN::Config;

        if ($write_conf) {
            &setVPNBootstatus($vpn_name, $vpn_config->{STATUS_UP});
        }

        return 0;
    }
    elsif ($status eq $vpn_config->{STATUS_TUNN_DOWN}
        or $status eq $vpn_config->{STATUS_IPSEC_DOWN})
    {
        &log_warn("Warning: IPSec or Tunnel VPN Tunnel $vpn_name is UP, setting down", "VPN");

        # ipsec down
        $rc = &_runVpnTunnelStop($vpn_name);

        if ($rc) {
            &log_error("Ipsec or Tunnel VPN Tunnel $vpn_name down action failed", "VPN");

            return 4;
        }
    }

    if ($status ne $vpn_config->{STATUS_ROUTE_DOWN}) {
        # start vpn
        $rc = &_runVpnTunnelStart($vpn_name);

        if ($rc) {
            &log_error("VPN Tunnel $vpn_name start failed", "VPN");

            return 2;
        }
    }

    require Relianoid::Net::Interface;

    my $tunnel_ref = &getInterfaceConfig($vpn_name);
    &applyRoutes('local', $tunnel_ref);

    require Relianoid::VPN::Config;
    require Relianoid::VPN::Tunnel::Config;

    $rc = &createVpnTunnelRoute($vpn_name);

    if ($rc) {
        &log_error("VPN Tunnel $vpn_name route create failed", "VPN");
        return 3;
    }

    require Relianoid::Net::Util;
    &setIpForward('true');

    if ($write_conf) {
        &setVPNBootstatus($vpn_name, $vpn_config->{STATUS_UP});
    }

    &setVPNRestartStatus($vpn_name, "false");

    return 0;
}

=pod

=head1 _runVpnTunnelStop

Stop a Tunnel VPN

Parameters:

    vpn_name - VPN name

Returns: integer - error code

0  - success
!0 - error

=cut

sub _runVpnTunnelStop ($vpn_name) {
    require Relianoid::Net::Validate;

    if (&ifexist($vpn_name) eq 'true') {
        require Relianoid::Net::Interface;

        my $tunnel_ref = &getSystemInterface($vpn_name);

        # ip , mask , net and ip_v are not filled by getSystemInterface
        $tunnel_ref->{addr} = IO::Socket::INET->new(Proto => 'udp')->if_addr($vpn_name);
        $tunnel_ref->{mask} = IO::Socket::INET->new(Proto => 'udp')->if_netmask($vpn_name);
        $tunnel_ref->{net}  = NetAddr::IP->new($tunnel_ref->{addr}, $tunnel_ref->{mask})->network()->addr();

        my $status;

        if ($tunnel_ref->{addr}) {
            require Relianoid::Net::Util;
            $tunnel_ref->{ip_v} = &ipversion($tunnel_ref->{addr});

            require Relianoid::Net::Route;
            $status = &delRoutes("local", $tunnel_ref);
        }

        require Relianoid::Net::Core;
        $status += &downIf($tunnel_ref);
        if ($status) {
            &log_error("VPN Tunnel Tunnel Interface $vpn_name DOWN failed", "VPN");
            return 1;
        }
    }

    require Relianoid::VPN::IPSec::Runtime;
    my $error_ref = &runVPNIPSecIKEDaemonCommand("down", $vpn_name);

    if ($error_ref->{code} == 0) {
        &log_info("VPN Tunnel $vpn_name stopping", "VPN");
    }
    else {
        &log_error("VPN Tunnel $vpn_name stop failed: $error_ref->{err}", "VPN");
    }

    return $error_ref->{code};
}

=pod

=head1 runVpnTunnelStop

Stop a Tunnel VPN connection, delete route, delete rule

Parameters:

	vpn_name - VPN name
	write_conf - Optional. String to save bootstatus. "false" no save, "true" save.

Returns: integer - error code

0  - success
!0 - error

=cut

sub runVpnTunnelStop ($vpn_name, $write_conf = undef) {
    my $rc = -1;

    require Relianoid::VPN::Core;
    my $vpn_ref = &getVpnConfObject($vpn_name);

    if (!$vpn_ref) {
        &log_info("VPN Tunnel $vpn_name conf not valid", "VPN");
        return 1;
    }

    $write_conf = undef if $write_conf && $write_conf eq "false";

    my $vpn_config = &getVpnModuleConfig();

    require Relianoid::VPN::Tunnel::Core;
    my $status = &getVpnTunnelStatus($vpn_name);

    require Relianoid::VPN::Config;
    if (($status eq $vpn_config->{STATUS_DOWN} or $status eq $vpn_config->{STATUS_UNLOADED})) {
        &log_warn("VPN Tunnel $vpn_name is already stopped", "VPN");
        &setVPNBootstatus($vpn_name, $vpn_config->{STATUS_DOWN}) if $write_conf;
        &setVPNRestartStatus($vpn_name, "false");
        return 0;
    }

    $rc = &delVPNRoute($vpn_name);
    if ($rc) {
        &log_error("VPN Tunnel $vpn_name route delete failed", "VPN");
        return 2;
    }

    if (&checkVPNIPSecSvcRunning() == 0) {
        $rc = &_runVpnTunnelStop($vpn_name);
        if ($rc) {
            &log_error("VPN Tunnel $vpn_name stop failed", "VPN");
            return 2;
        }
    }

    &setVPNBootstatus($vpn_name, $vpn_config->{STATUS_DOWN}) if $write_conf;
    &setVPNRestartStatus($vpn_name, "false");

    return $rc;
}

=pod

=head1 runVpnTunnelReload

Reload a Tunnel VPN Configuration

Parameters: None

Returns: integer - error code

0  - success
!0 - error

=cut

sub runVpnTunnelReload () {
    require Relianoid::VPN::IPSec::Runtime;

    my $error = &checkVPNIPSecSvcRunning();

    if ($error == 0) {
        $error = &runVPNIPSecCommand("rereadsecrets");
        $error += &runVPNIPSecCommand("reload");
    }

    return $error;
}

1;
