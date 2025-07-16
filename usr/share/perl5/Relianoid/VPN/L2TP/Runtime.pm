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

Relianoid::VPN::L2TP::Runtime

=cut

sub checkVPNL2TPDaemonRunning ($vpn_name) {
    my $ret = -1;

    require Relianoid::VPN::L2TP::Core;
    my $l2tp_PID_file = &getVpnL2TPPidFilePath($vpn_name);

    if (-f $l2tp_PID_file) {
        use Relianoid::System;

        if (not &checkPidFileRunning($l2tp_PID_file)) {
            $ret = 0;
        }
        else {
            &log_warn("VPN $vpn_name L2TP Daemon not running but PID file $l2tp_PID_file exists!", "VPN");
            $ret = 2;
        }
    }
    else {
        my $pgrep          = &getGlobalConfiguration("pgrep");
        my $l2tp_conf_file = &getVpnL2TPConfFilePath($vpn_name);
        my $l2tp_bin       = &getGlobalConfiguration("l2tp_bin");

        if (&logAndRunCheck("$pgrep -f \"$l2tp_bin.*$l2tp_conf_file\"")) {
            &log_warn("VPN $vpn_name L2TP Daemon is running but no PID file $l2tp_PID_file exists!", "VPN");
            $ret = 0;
        }
        else {
            $ret = 1;
        }
    }

    return $ret;
}

=pod

=head1 runVPNL2TPDaemonStatus

	Gets all information of Daemon.

Parameters:

	conn_name .- String. Connection name
	type - String. L2TP type. Possible values "lns" or "lac".

Returns:

	Hash ref - Empty on error.

Variable: $status_ref.

	A hashref that maps Daemon Status

	$status_ref->{vpn}{lns} - Connections Info for vpns.

=cut

sub runVPNL2TPDaemonStatus ($type, $conn_name) {
    my $status_ref;

    require Relianoid::VPN::L2TP::Core;
    my $l2tp_ctl_file = &getVpnL2TPCtlFilePath($conn_name);

    if (!-p $l2tp_ctl_file) {
        return $status_ref;
    }

    my $connection   = $type eq "lns" ? "default" : $conn_name;
    my $l2tp_ctl_bin = &getGlobalConfiguration('l2tp_ctl_bin');
    my $command      = &logRunAndGet("$l2tp_ctl_bin -d -c $l2tp_ctl_file status-$type $connection", "array");

    if (!$command->{stderr}) {
        my $n_tunnel;
        my $param_tmp;
        my $value;
        my $n_call;
        my $param;

        for my $line (@{ $command->{stdout} }) {
            if ($line =~ /STATUS tunnels\.(\d+)\.(.+)=(.+)$/) {
                $n_tunnel  = $1;
                $param_tmp = $2;
                $value     = $3;

                if ($param_tmp =~ /calls\.(\d+)\.(.*)$/) {
                    $n_call                                                      = $1;
                    $param                                                       = $2;
                    $status_ref->{$conn_name}{$n_tunnel}{calls}{$n_call}{$param} = $value;
                }
                else {
                    $status_ref->{$conn_name}{$n_tunnel}{$param_tmp} =
                      $value;
                }
            }
            elsif ($line =~ /STATUS tunnels\.(.+)=(.+)$/) {
                $status_ref->{$conn_name}{$1} = $2;
            }
        }
    }

    return $status_ref;
}

1;

