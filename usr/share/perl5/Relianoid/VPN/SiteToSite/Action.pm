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

Relianoid::VPN::SiteToSite::Action

=cut

require Relianoid::VPN::IPSec::Runtime;

=pod

=head1 _runVpnSiteToSiteStart

Run a Site-to-Site VPN

Parameters:

	vpn_name - VPN name

Returns: integer - error code

0  - success
!0 - error

=cut

sub _runVpnSiteToSiteStart ($vpn_name) {
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

    require Relianoid::VPN::IPSec::Runtime;
    my $error_ref = &runVPNIPSecIKEDaemonCommand("up", $vpn_name);
    if ($error_ref->{code} == 0) {
        &log_info("VPN Site-to-Site $vpn_name start successfully", "VPN");
    }
    else {
        &log_error("VPN Site-to-Site $vpn_name start failed: $error_ref->{err}", "VPN");
        return $error_ref->{code};
    }

    return 0;
}

=pod

=head1 runVpnSiteToSiteStart

Start a Site-to-Site VPN connection, create routes, create rules

Parameters:

	vpn_name - VPN name
	write_conf - Optional. String to save bootstatus. "false" no save, "true" save.

Returns: integer - error code

0  - success
!0 - error

=cut

sub runVpnSiteToSiteStart ($vpn_name, $write_conf = undef) {
    my $rc = -1;

    require Relianoid::VPN::Core;
    my $vpn_ref = &getVpnConfObject($vpn_name);

    if (!$vpn_ref) {
        &log_info("VPN Site-to-Site $vpn_name conf not valid", "VPN");
        return $rc;
    }

    $write_conf = undef if $write_conf && $write_conf eq "false";

    my $vpn_config = &getVpnModuleConfig();

    # check if localnet and remote net are in use
    my $params = {
        $vpn_config->{LOCALNET}  => $vpn_ref->{ $vpn_config->{LOCALNET} },
        $vpn_config->{REMOTENET} => $vpn_ref->{ $vpn_config->{REMOTENET} }
    };

    my $vpn_name_found = &getVpnParamExists("site_to_site", $params, $vpn_name);

    if ($vpn_name_found !~ /^\d+$/) {
        my $status = &getVpnStatus($vpn_name_found);
        if (   ($status eq $vpn_config->{STATUS_UP})
            or ($status eq $vpn_config->{STATUS_CONNECTING}))
        {
            my $msg = "Local network $vpn_ref->{$vpn_config->{LOCALNET}} ";
            $msg .= "and Remote network $vpn_ref->{$vpn_config->{REMOTENET}} ";
            $msg .= "are in use by VPN $vpn_name_found";
            &log_warn($msg, "VPN");
            return 1;
        }
    }

    require Relianoid::VPN::SiteToSite::Core;
    my $status = &getVpnSiteToSiteStatus($vpn_name);

    if (   $status eq $vpn_config->{STATUS_UP}
        or $status eq $vpn_config->{STATUS_CONNECTING})
    {
        &log_warn("VPN Site-to-Site $vpn_name is already running", "VPN");
        require Relianoid::VPN::Config;
        &setVPNBootstatus($vpn_name, $vpn_config->{STATUS_UP}) if $write_conf;
        return 0;
    }
    elsif ($status eq $vpn_config->{STATUS_UNLOADED}) {
        &log_warn("VPN Site-to-Site $vpn_name is only configured : Reloading config", "VPN");
        &runVpnSiteToSiteReload();
        $status = &getVpnSiteToSiteStatus($vpn_name);
    }

    if (    ($status ne $vpn_config->{STATUS_DOWN})
        and ($status ne $vpn_config->{STATUS_ROUTE_DOWN}))
    {
        &log_error("VPN Site-to-Site $vpn_name config can not be loaded", "VPN");
        return $rc;
    }

    # start vpn
    $rc = &_runVpnSiteToSiteStart($vpn_name);
    if ($rc) {
        &log_error("VPN Site-to-Site $vpn_name start failed", "VPN");
        return 2;
    }

    require Relianoid::VPN::Config;
    $rc = &createVPNRoute($vpn_name);
    if ($rc) {
        &log_error("VPN Site-to-Site $vpn_name route create failed", "VPN");
        return 3;
    }

    require Relianoid::Net::Util;
    &setIpForward('true');

    &setVPNBootstatus($vpn_name, $vpn_config->{STATUS_UP}) if $write_conf;
    &setVPNRestartStatus($vpn_name, "false");

    return 0;
}

=pod

=head1 _runVpnSiteToSiteStop

Stop a Site-to-Site VPN

Parameters:

	vpn_name - VPN name

Returns: integer - error code

0  - success
!0 - error

=cut

sub _runVpnSiteToSiteStop ($vpn_name) {
    require Relianoid::VPN::IPSec::Runtime;
    my $error_ref = &runVPNIPSecIKEDaemonCommand("down", $vpn_name);
    if ($error_ref->{code} == 0) {
        &log_info("VPN Site-to-Site $vpn_name stopping", "VPN");
    }
    else {
        &log_error("VPN Site-to-Site $vpn_name stop failed: $error_ref->{err}", "VPN");
    }

    return $error_ref->{code};
}

=pod

=head1 runVpnSiteToSiteStop

Stop a Site-to-Site VPN connection, delete route, delete rule

Parameters:

	vpn_name - VPN name
	write_conf - Optional. String to save bootstatus. "false" no save, "true" save.

Returns: integer - error code

0  - success
!0 - error

=cut

sub runVpnSiteToSiteStop ($vpn_name, $write_conf = undef) {
    my $rc = -1;

    require Relianoid::VPN::Core;
    my $vpn_ref = &getVpnConfObject($vpn_name);

    if (!$vpn_ref) {
        &log_info("VPN Site-to-Site $vpn_name conf not valid", "VPN");
        return 1;
    }

    $write_conf = undef if $write_conf && $write_conf eq "false";

    my $vpn_config = &getVpnModuleConfig();

    require Relianoid::VPN::SiteToSite::Core;
    my $status = &getVpnSiteToSiteStatus($vpn_name);

    require Relianoid::VPN::Config;
    if ($status eq $vpn_config->{STATUS_DOWN}) {
        &log_warn("VPN Site-to-Site $vpn_name is already stopped", "VPN");
        &setVPNBootstatus($vpn_name, $vpn_config->{STATUS_DOWN}) if $write_conf;
        return 0;
    }

    $rc = &delVPNRoute($vpn_name);
    if ($rc) {
        &log_error("VPN Site-to-Site $vpn_name route delete failed", "VPN");
        return 2;
    }

    if (&checkVPNIPSecSvcRunning() == 0) {
        $rc = &_runVpnSiteToSiteStop($vpn_name);
        if ($rc) {
            &log_error("VPN Site-to-Site $vpn_name stop failed", "VPN");
            return 2;
        }
    }

    &setVPNBootstatus($vpn_name, $vpn_config->{STATUS_DOWN}) if $write_conf;
    &setVPNRestartStatus($vpn_name, "false");

    return $rc;
}

=pod

=head1 runVpnSiteToSiteReload

Reload a Site-to-Site VPN Configuration

Parameters: None

Returns: integer - error code

0  - success
!0 - error

=cut

sub runVpnSiteToSiteReload () {
    require Relianoid::VPN::IPSec::Runtime;

    my $error = &checkVPNIPSecSvcRunning();

    if ($error == 0) {
        $error = &runVPNIPSecCommand("rereadsecrets");
        $error += &runVPNIPSecCommand("reload");
    }
    else {
        &log_info("Starting VPN IPSec Daemon.", "VPN");
        require Relianoid::VPN::IPSec::Action;
        my $status = runVPNIPSecSvcStart();
        sleep 1;

        if ($status > 0) {
            &log_error("VPN IPSec Daemon start failed", "VPN");
            return 1;
        }

        return 0;
    }

    return $error;
}

1;
