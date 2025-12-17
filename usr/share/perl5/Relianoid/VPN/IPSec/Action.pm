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

Relianoid::VPN::IPSec::Action

=cut

=pod

=head1 runVPNIPSecSvcStart

Start the Ipsec Service : starterdaemon and ikedaemon

Parameters:

Returns: integer - Error code

0 on success
-1 service already started
1 error on VPNIPSec command
2 error on start service

=cut

sub runVPNIPSecSvcStart () {
    my $ret   = -1;
    my $error = &checkVPNIPSecSvcRunning();

    if ($error == 0) {
        &log_info("The IPSec Service is already running", "VPN");
        return $ret;
    }

    # starter pidfile exits, daemon not running
    elsif (int($error / 10) == 2) {
        &log_info("Deleting starter Pidfile");
        my $ike_daemon       = basename(&getGlobalConfiguration("ipsec_ike_svc"));
        my $starter_PID_file = &getGlobalConfiguration("piddir") . "/starter." . $ike_daemon . ".pid";
        unlink $starter_PID_file;
    }

    # starter pidfile doesnt exits, daemon running
    elsif (int($error / 10) == 3) {
        &log_info("stopping starter Daemon");
        my $pgrep = &getGlobalConfiguration("pgrep");
        my $pid   = &logAndGet("$pgrep starter");
        kill 15, $pid;
    }

    # ikedaemon pidfile exits, daemon not running
    elsif (int($error % 10) == 2) {
        &log_info("Deleting ikedaemon Pidfile");
        my $ike_daemon   = basename(&getGlobalConfiguration("ipsec_ike_svc"));
        my $ike_PID_file = &getGlobalConfiguration("piddir") . "/" . $ike_daemon . ".pid";
        unlink $ike_PID_file;
    }

    # ikedaemon pidfile doesnt exits, daemon running
    elsif (int($error % 10) == 3) {
        &log_info("stopping ikedaemon Daemon");
        my $ike_daemon = basename(&getGlobalConfiguration("ipsec_ike_svc"));
        my $pgrep      = &getGlobalConfiguration("pgrep");
        my $pid        = &logAndGet("$pgrep $ike_daemon");
        kill 15, $pid;
    }

    $error = &runVPNIPSecCommand("start");

    if ($error) {
        &log_warn("The IPSec Service can not be started ( $error )", "VPN");
        $ret = 2;
    }
    else {
        sleep 1;
        $error = &checkVPNIPSecSvcRunning();

        if ($error) {
            &log_error("The IPSec Service can not be started ( $error )", "VPN");
            $ret = 1;
        }
        else {

            # delete extra rule created by kernel-netlink plugin
            my $table_route      = &getGlobalConfiguration("ipsec_ike_table_route");
            my $table_route_prio = &getGlobalConfiguration("ipsec_ike_table_route_prio");
            my $rule             = {
                priority => $table_route_prio,
                from     => 'all',
                table    => $table_route
            };

            require Relianoid::Net::Route;

            if (&isRule($rule)) {
                &applyRule('del', $rule);
            }

            &log_info("The IPSec Service is started successfuly", "VPN");
            $ret = 0;
        }
    }

    return $ret;
}

1;
