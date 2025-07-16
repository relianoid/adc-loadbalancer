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

Relianoid::VPN::Action

=cut

require Relianoid::VPN::Core;

=pod

=head1 initVPNModule

Create configuration files regarding to VPN module

Parameters: None

Returns: Nothing

=cut

sub initVPNModule () {
    my $systemctl_bin = &getGlobalConfiguration('systemctl');

    if (-f $systemctl_bin) {
        my $status = &logRunAndGet("$systemctl_bin is-enabled ipsec");

        if (!$status->{stderr}) {
            &log_info("Disabling Service ipsec", "VPN");

            # disable ipsec service
            &logAndRun("$systemctl_bin disable ipsec");

            $status = &logRunAndGet("$systemctl_bin is-enabled ipsec");
            if ($status->{stderr}) {
                &log_info("Service ipsec has been disabled succesfully", "VPN");

                # stop ipsec service
                &logAndRun("$systemctl_bin stop ipsec");
                $status = &logRunAndGet("$systemctl_bin is-active ipsec");

                &log_info("Service ipsec has been stopped succesfully", "VPN")
                  if (!$status->{stderr});
            }
        }

        # disable xltpd service
        $status = &logRunAndGet("$systemctl_bin is-enabled xl2tpd");

        if (!$status->{stderr}) {
            &log_info("Disabling Service xl2tpd", "VPN");

            &logAndRun("$systemctl_bin disable xl2tpd");

            $status = &logRunAndGet("$systemctl_bin is-enabled xl2tpd");
            if ($status->{stderr}) {
                &log_info("Service xl2tpd has been disabled succesfully", "VPN");

                # stop xl2tpd service
                &logAndRun("$systemctl_bin stop xl2tpd");
                $status = &logRunAndGet("$systemctl_bin is-active xl2tpd");

                &log_info("Service xl2tpd has been stopped succesfully", "VPN")
                  if (!$status->{stderr});
            }
        }
    }

    my $vpn_config_path = &getVpnConfigPath();

    mkdir $vpn_config_path if (!-d $vpn_config_path);

    my $ipsec_base = &getGlobalConfiguration("ipsec_base");

    mkdir $ipsec_base       if (!-d $ipsec_base);
    mkdir "$ipsec_base/etc" if (!-d "$ipsec_base/etc");

    my $conn_filepath   = $ipsec_base . "/etc/ipsec.conns";
    my $secret_filepath = $ipsec_base . "/etc/ipsec.secrets";

    # create ipsec.conns
    if (!-f $conn_filepath) {
        open(my $fh, '>', $conn_filepath);
        print $fh "include " . $vpn_config_path . "/*_conn.conf";
        close $fh;
    }

    # create ipsec.secrets
    if (!-f $secret_filepath) {
        open(my $fh, '>', $secret_filepath);
        print $fh "include " . $vpn_config_path . "/*_secret.conf";
        close $fh;
    }

    my $ipsec_conf     = &getGlobalConfiguration("ipsec_conf");
    my $ipsec_conf_tpl = &getGlobalConfiguration("ipsec_conf_tpl");

    if (!-f $ipsec_conf) {
        my $table_route      = &getGlobalConfiguration("ipsec_ike_table_route");
        my $table_route_prio = &getGlobalConfiguration("ipsec_ike_table_route_prio");

        require Relianoid::Lock;

        &ztielock(\my @file, $ipsec_conf);

        if(open(my $fh, '<', $ipsec_conf_tpl)) {
            while (<$fh>) {
                $_ = $1 . $conn_filepath    if ($_ =~ /(.*)__CONN_FILE__$/);
                $_ = $1 . $secret_filepath  if ($_ =~ /(.*)__SECRET_FILE__$/);
                $_ = $1 . $table_route      if ($_ =~ /(.*)__TABLE_ROUTE__$/);
                $_ = $1 . $table_route_prio if ($_ =~ /(.*)__TABLE_ROUTE_PRIO__$/);
                push @file, $_;
            }
            close $fh;
        }
        else {
            log_error("Could not open file '$ipsec_conf_tpl': $!");
        }

        untie @file;
    }

    # Package strongswan not from RELIANOID
    if (-f "/etc/strongswan.conf") {
        open(my $fh, '<', "/etc/strongswan.conf");
        my $include = 0;
        while (<$fh>) {
            $include = 1 if ($_ =~ /^include \Q$ipsec_conf\E/);
        }
        close $fh;
        if (!$include) {
            open(my $fh, '>>', "/etc/strongswan.conf");
            print $fh "include " . $ipsec_conf . "\n" if (!$include);
            close $fh;
        }
    }

    # Workdir for xl2tpd
    mkdir "/var/run/xl2tpd" if (!-d "/var/run/xl2tpd");

    return;
}

=pod

=head1 runVPNStart

Start a Vpn

Parameters:

    vpn_name   - VPN name
    write_conf - Optional. String to save bootstatus. "true" save, otherwise no save.

Returns: integer - Error code

0  - success
!0 - error

=cut

sub runVPNStart ($vpn_name, $write_conf = undef) {
    my $type = &getVpnType($vpn_name);
    my $rc   = 1;

    $write_conf = "false" if (!$write_conf || $write_conf ne "true");

    if ($type eq "site_to_site") {
        require Relianoid::VPN::SiteToSite::Action;
        $rc = &runVpnSiteToSiteStart($vpn_name, $write_conf);
    }
    elsif ($type eq "tunnel") {
        require Relianoid::VPN::Tunnel::Action;
        $rc = &runVpnTunnelStart($vpn_name, $write_conf);
    }
    elsif ($type eq "remote_access") {
        require Relianoid::VPN::RemoteAccess::Action;
        $rc = &runVpnRemoteAccessStart($vpn_name, $write_conf);
    }

    return $rc;
}

=pod

=head1 runVPNStop

Stop a Vpn

Parameters:

    vpn_name   - VPN name
    write_conf - Optional. String to save bootstatus. "true" save, otherwise no save.

Returns: integer - Error code

0  - success
!0 - error

=cut

sub runVPNStop ($vpn_name, $write_conf = undef) {
    my $type = &getVpnType($vpn_name);
    my $rc   = 1;

    $write_conf = "false" if (!$write_conf || $write_conf ne "true");

    if ($type eq "site_to_site") {
        require Relianoid::VPN::SiteToSite::Action;
        $rc = &runVpnSiteToSiteStop($vpn_name, $write_conf);
    }

    elsif ($type eq "tunnel") {
        require Relianoid::VPN::Tunnel::Action;
        $rc = &runVpnTunnelStop($vpn_name, $write_conf);
    }

    elsif ($type eq "remote_access") {
        require Relianoid::VPN::RemoteAccess::Action;
        $rc = &runVpnRemoteAccessStop($vpn_name, $write_conf);
    }

    return $rc;
}

=pod

=head1 runVPNRestart

Restart a Vpn

Parameters:

    vpn_name   - VPN name
    write_conf - Optional. String to save bootstatus. "true" save, otherwise no save.

Returns: integer - Error code

0  - success
!0 - error

=cut

sub runVPNRestart ($vpn_name, $write_conf = undef) {
    $write_conf = "false" if (!$write_conf || $write_conf ne "true");

    my $rc = &runVPNStop($vpn_name, $write_conf);

    if (!$rc) {
        $rc = &runVPNStart($vpn_name, $write_conf);
    }

    return $rc;
}

=pod

=head1 runVPNDelete

Delete a Vpn

Parameters:

    vpn_name - VPN name
    type     - Optional. VPN Type for delete without checking existing config files.

Returns: integer - Error code

0  - success
!0 - error

=cut

sub runVPNDelete ($vpn_name, $type = undef) {
    my $force;

    if (!defined $type) {
        $type = &getVpnType($vpn_name);
    }
    else {
        $force = "true";
    }

    my $rc = 1;

    if ($type eq "site_to_site") {
        require Relianoid::VPN::SiteToSite::Config;

        $rc = &delVpnSiteToSite($vpn_name);
    }
    elsif ($type eq "tunnel") {
        require Relianoid::VPN::Tunnel::Config;

        $rc = &delVpnTunnel($vpn_name);
        $rc = &cleanVpnTunnel($vpn_name) if ($force eq "true");
    }
    elsif ($type eq "remote_access") {
        require Relianoid::VPN::RemoteAccess::Config;

        $rc = &delVpnRemoteAccess($vpn_name);
        $rc = &cleanVpnRemoteAccess($vpn_name) if ($force eq "true");
    }

    return $rc;
}

sub start_vpn_service() {
    log_info("Starting VPNs...");

    my $vpns = &getVpnList();

    log_info("Setting up VPNs...");

    for my $vpn_name (@{$vpns}) {
        my $bstatus = &getVpnBootstatus($vpn_name);

        if ($bstatus and $bstatus eq "up") {

            my $status = &runVPNStart("$vpn_name", "false");

            if ($status == 0) {
                log_info("Starting VPN: $vpn_name");
            }
            else {
                log_error("Starting VPN: $vpn_name");
            }
        }
        else {
            log_info("VPN: $vpn_name configured DOWN");
        }
    }

    return;
}

sub stop_vpn_service() {
    log_info("Stopping VPNs...");

    my $vpns = &getVpnList();

    for my $vpn_name (@{$vpns}) {
        my $status = &getVpnStatus($vpn_name);

        if ($status and $status eq "up") {
            my $status = &runVPNStop($vpn_name, "false");

            if ($status == 0) {
                log_info("Stopping VPN: $vpn_name");
            }
            else {
                log_error("Stopping VPN: $vpn_name");
            }
        }
    }

    return;
}

1;
