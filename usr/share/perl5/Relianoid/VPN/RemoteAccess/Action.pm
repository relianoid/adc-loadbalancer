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

Relianoid::VPN::RemoteAccess::Action

=cut

require Relianoid::VPN::IPSec::Runtime;
require Relianoid::VPN::L2TP::Runtime;

=pod

=head1 _runVpnRemoteAccessStart

Run a Remote Access VPN

Parameters:

	vpn_name - VPN name

Returns: integer - error code

0  - success
!0 - error

=cut

sub _runVpnRemoteAccessStart ($vpn_name) {
    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    require Relianoid::VPN::IPSec::Runtime;
    my $status = &checkVPNIPSecSvcRunning();

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

    require Relianoid::VPN::IPSec::Core;
    $status = &getVpnIPSecStatus($vpn_name);
    if (    $status ne $vpn_config->{STATUS_DOWN}
        and $status ne $vpn_config->{STATUS_UP})
    {
        require Relianoid::VPN::IPSec::Action;

        $status = &runVPNIPSecCommand("reload");
        if ($status > 0) {
        }
        $status = &getVpnIPSecStatus($vpn_name);
        if (    $status ne $vpn_config->{STATUS_DOWN}
            and $status ne $vpn_config->{STATUS_UP})
        {
            &log_error("VPN Remote Access Ipsec Connection $vpn_name start failed", "VPN");
            return 2;
        }
    }

    require Relianoid::VPN::L2TP::Action;
    my $error = &runVPNL2TPDaemonStart($vpn_name);
    if ($error > 0) {
        &log_error("VPN Remote Access L2TP Connection $vpn_name start failed", "VPN");
        return 3;
    }

    &log_info("VPN Remote Access $vpn_name start successfully", "VPN");
    return 0;
}

=pod

=head1 runVpnRemoteAccessStart

Start a Remote Access VPN connection, create routes, create rules

Parameters:

	vpn_name - VPN name
	write_conf - Optional. String to save bootstatus. "false" no save, "true" save.

Returns: integer - error code

0  - success
!0 - error

=cut

sub runVpnRemoteAccessStart ($vpn_name, $write_conf = undef) {
    my $rc = -1;

    require Relianoid::VPN::Core;
    my $vpn_ref = &getVpnConfObject($vpn_name);

    if (!$vpn_ref) {
        &log_info("VPN Remote Access $vpn_name conf not valid", "VPN");
        return $rc;
    }

    $write_conf = undef if $write_conf && $write_conf eq "false";

    my $vpn_config = &getVpnModuleConfig();

    # check if localnet is in use
    my $params = {
        $vpn_config->{LOCALIP}   => $vpn_ref->{ $vpn_config->{LOCALIP} },
        $vpn_config->{LOCALMASK} => $vpn_ref->{ $vpn_config->{LOCALMASK} },
    };

    my $vpn_name_found = &getVpnParamExists("remote_access", $params, $vpn_name);

    if ($vpn_name_found !~ /^\d+$/) {
        my $status = &getVpnStatus($vpn_name_found);
        if (   ($status eq $vpn_config->{STATUS_UP})
            or ($status eq $vpn_config->{STATUS_CONNECTING}))
        {
            my $msg = "Local network $vpn_ref->{$vpn_config->{LOCALIP}} / $vpn_ref->{$vpn_config->{LOCALMASK}} ";
            $msg .= "is in use by VPN $vpn_name_found";
            &log_warn($msg, "VPN");
            return 1;
        }
    }

    require Relianoid::VPN::RemoteAccess::Core;
    my $status = &getVpnRemoteAccessStatus($vpn_name);

    if ($status eq $vpn_config->{STATUS_UNLOADED}) {
        &log_warn("VPN Remote Access $vpn_name is only configured : Reloading config", "VPN");
        &runVpnRemoteAccessReload();
        $status = &getVpnRemoteAccessStatus($vpn_name);
    }
    if (   $status eq $vpn_config->{STATUS_UP}
        or $status eq $vpn_config->{STATUS_CONNECTING})
    {
        &log_warn("VPN Remote Access $vpn_name is already running", "VPN");
        require Relianoid::VPN::Config;
        &setVPNBootstatus($vpn_name, $vpn_config->{STATUS_UP}) if $write_conf;
        return 0;
    }
    elsif ($status eq $vpn_config->{STATUS_IPSEC_DOWN}) {
        &log_warn("Warning: VPN Remote Access L2TP Connection $vpn_name is UP, setting down", "VPN");
        require Relianoid::VPN::L2TP::Action;
        my $rc = &runVPNL2TPDaemonStop($vpn_name);
        if ($rc) {
            &log_error("VPN Remote Access L2TP Connection $vpn_name down action failed", "VPN");
            return 4;
        }
    }
    elsif ($status eq $vpn_config->{STATUS_L2TP_DOWN}) {
        &log_warn("Warning: VPN Remote Access IPSec Connection $vpn_name is UP, setting down", "VPN");
        require Relianoid::VPN::IPSec::Runtime;
        my $error_ref = &runVPNIPSecIKEDaemonCommand("delete", $vpn_name);

        if ($error_ref->{code}) {
            &log_error("VPN Remote Access IPSec $vpn_name down action failed", "VPN");
            return 5;
        }
    }

    if ($status ne $vpn_config->{STATUS_ROUTE_DOWN}) {
        # start vpn
        $rc = &_runVpnRemoteAccessStart($vpn_name);
        if ($rc) {
            &log_error("VPN Remote Access $vpn_name start failed", "VPN");
            return 2;
        }
    }

    require Relianoid::VPN::RemoteAccess::Config;
    $rc = &createVpnRemoteAccessRoute($vpn_name);

    if ($rc) {
        &log_error("VPN Remote Access $vpn_name route create failed", "VPN");
        return 3;
    }

    require Relianoid::Net::Util;
    &setIpForward('true');

    require Relianoid::VPN::Config;
    &setVPNBootstatus($vpn_name, $vpn_config->{STATUS_UP}) if $write_conf;
    &setVPNRestartStatus($vpn_name, "false");

    return 0;
}

=pod

=head1 _runVpnRemoteAccessStop

Stop a Remote Access VPN

Parameters:

    vpn_name - VPN name

Returns: integer - error code

0  - success
!0 - error

=cut

sub _runVpnRemoteAccessStop ($vpn_name) {
    require Relianoid::VPN::IPSec::Runtime;
    my $error_ref = &runVPNIPSecIKEDaemonCommand("delete", $vpn_name);
    if ($error_ref->{code} != 0) {
        &log_error("VPN Remote Access Ipsec Connection $vpn_name stop failed: $error_ref->{err}", "VPN");
        return 1;
    }

    require Relianoid::VPN::L2TP::Action;
    my $error = &runVPNL2TPDaemonStop($vpn_name);
    if ($error > 0) {
        &log_error("VPN Remote Access L2TP Connection $vpn_name stop failed.","VPN");
        return 2;
    }

    return 0;
}

=pod

=head1 runVpnRemoteAccessStop

Stop a Remote Access VPN connection, delete route, delete rule

Parameters:

    vpn_name   - VPN name
    write_conf - Optional. String to save bootstatus. "false" no save, "true" save.

Returns: integer - error code

0  - success
!0 - error

=cut

sub runVpnRemoteAccessStop ($vpn_name, $write_conf = undef) {
    my $rc = -1;

    require Relianoid::VPN::Core;
    my $vpn_ref = &getVpnConfObject($vpn_name);

    if (!$vpn_ref) {
        &log_info("VPN Remote Access $vpn_name conf not valid", "VPN");
        return 1;
    }

    $write_conf = undef if $write_conf && $write_conf eq "false";

    my $vpn_config = &getVpnModuleConfig();

    require Relianoid::VPN::RemoteAccess::Core;
    my $status = &getVpnRemoteAccessStatus($vpn_name);

    require Relianoid::VPN::Config;
    if ($status eq $vpn_config->{STATUS_DOWN}) {
        &log_warn("VPN Remote Access $vpn_name is already stopped", "VPN");
        &setVPNBootstatus($vpn_name, $vpn_config->{STATUS_DOWN}) if $write_conf;
        &setVPNRestartStatus($vpn_name, "false");
        return 0;
    }

    require Relianoid::VPN::RemoteAccess::Config;
    $rc = &delVpnRemoteAccessRoute($vpn_name);
    if ($rc) {
        &log_error("VPN Remote Access $vpn_name route delete failed", "VPN");
        return 2;
    }

    if (&checkVPNIPSecSvcRunning() == 0) {
        $rc = &_runVpnRemoteAccessStop($vpn_name);
        if ($rc) {
            &log_error("VPN Remote Access $vpn_name stop failed", "VPN");
            return 2;
        }
    }

    &setVPNBootstatus($vpn_name, $vpn_config->{STATUS_DOWN}) if $write_conf;
    &setVPNRestartStatus($vpn_name, "false");

    return $rc;
}

=pod

=head1 runVpnRemoteAccessReload

Reload a Remote Access VPN Configuration

Parameters: None

Returns: integer - error code

0  - success
!0 - error

=cut

sub runVpnRemoteAccessReload () {
    require Relianoid::VPN::IPSec::Runtime;
    my $error = &checkVPNIPSecSvcRunning();

    if ($error == 0) {
        $error = &runVPNIPSecCommand("rereadsecrets");
        $error += &runVPNIPSecCommand("reload");
    }

    return $error;
}

1;
