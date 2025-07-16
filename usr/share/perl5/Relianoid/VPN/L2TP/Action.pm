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

Relianoid::VPN::L2TP::Action

=cut

use strict;
use warnings;
use feature qw(signatures);

=pod

=head1 runVPNL2TPDaemonStart
	Start the Connection L2TP Daemon.

Parameters:
	$vpn_name - String . Vpn Name

Returns:
	Integer -  Error code: 0 on success, -1 service already started,
		               1 error on start L2TP Daemon

=cut

sub runVPNL2TPDaemonStart ($vpn_name) {
    require Relianoid::VPN::L2TP::Runtime;

    my $ret   = -1;
    my $error = &checkVPNL2TPDaemonRunning($vpn_name);

    if ($error == 0) {
        &log_info("The $vpn_name L2TP Daemon is already running", "VPN");
        return $ret;
    }

    require Relianoid::VPN::L2TP::Core;
    my $l2tp_pid_file  = &getVpnL2TPPidFilePath($vpn_name);
    my $l2tp_ctl_file  = &getVpnL2TPCtlFilePath($vpn_name);
    my $l2tp_conf_file = &getVpnL2TPConfFilePath($vpn_name);
    my $l2tp_bin       = &getGlobalConfiguration("l2tp_bin");

    my $cmd    = "$l2tp_bin -c $l2tp_conf_file -C $l2tp_ctl_file -p $l2tp_pid_file";
    my $status = &run_with_env("$cmd");

    if ($status == 0) {
        &log_info("The $vpn_name L2TP Daemon is started successfuly", "VPN");
        $ret = 0;
    }
    else {
        &log_error("The $vpn_name L2TP Daemon can not be started successfuly", "VPN");
        $ret = 1;
    }

    return $ret;
}

=pod

=head1 runVPNL2TPDaemonStop
	Stop the Connection L2TP Daemon.

Parameters:
	$vpn_name - String . Vpn Name

Returns:
	Integer -  Error code: 0 on success, -1 service already stopped,
		               1 error on stop L2TP Daemon

=cut

sub runVPNL2TPDaemonStop ($vpn_name) {
    require Relianoid::VPN::L2TP::Runtime;

    my $ret      = -1;
    my $error = &checkVPNL2TPDaemonRunning($vpn_name);

    if ($error == 1) {
        &log_info("The $vpn_name L2TP Daemon is already stopped", "VPN");
        return $ret;
    }

    require Relianoid::VPN::L2TP::Core;
    my $l2tp_pid_file = &getVpnL2TPPidFilePath($vpn_name);
    my $l2tp_ctl_file = &getVpnL2TPCtlFilePath($vpn_name);
    my $l2tp_pid      = &getVpnL2TPPid($vpn_name);

    if ($l2tp_pid ne "-1") {
        kill 9, $l2tp_pid;
        sleep 1;
    }

    $error = &checkVPNL2TPDaemonRunning($vpn_name);
    if ($error == 1) {
        &log_warn("The $vpn_name L2TP Daemon can not be stopped ( $error )", "VPN");
        $ret = 2;
    }
    else {
        unlink $l2tp_pid_file if -e $l2tp_pid_file;
        unlink $l2tp_ctl_file if -e $l2tp_ctl_file;

        # TODO : Stop Pppd connections running for this L2TP daemon.
        # They will stop, but why wait for it?
        # send kill -HUP
        &log_info("The $vpn_name L2TP Daemon is stopped successfuly", "VPN");
        $ret = 0;
    }

    return $ret;
}

1;
