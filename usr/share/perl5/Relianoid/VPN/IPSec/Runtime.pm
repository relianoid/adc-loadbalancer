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

Relianoid::VPN::IPSec::Runtime

=cut

sub checkVPNIPSecSvcRunning () {
    my $ike_status     = &checkVPNIPSecIKEDaemonRunning();
    my $starter_status = &checkVPNIPSecIKEStarterRunning() * 10;
    my $ret            = $ike_status + $starter_status;
    return $ret;
}

sub checkVPNIPSecIKEDaemonRunning () {
    use File::Basename;

    my $ike_daemon   = basename(&getGlobalConfiguration("ipsec_ike_svc"));
    my $ike_PID_file = &getGlobalConfiguration("piddir") . "/" . $ike_daemon . ".pid";
    my $ret          = -1;

    if (-f $ike_PID_file) {
        use Relianoid::System;
        unless (&checkPidFileRunning($ike_PID_file)) {
            $ret = 0;
        }
        else {
            &log_warn("VPNIPSec $ike_daemon not running but PID file $ike_PID_file exists!", "VPN");
            $ret = 2;
        }
    }
    else {
        my $pgrep = &getGlobalConfiguration("pgrep");
        if (!&logAndRunCheck("$pgrep $ike_daemon")) {
            &log_warn("VPNIPSec $ike_daemon running but no PID file $ike_PID_file exists!", "VPN");
            $ret = 3;
        }
        else {
            $ret = 1;
        }
    }
    return $ret;
}

sub checkVPNIPSecIKEStarterRunning () {
    my $ret              = -1;
    my $ike_daemon       = basename(&getGlobalConfiguration("ipsec_ike_svc"));
    my $starter_PID_file = &getGlobalConfiguration("piddir") . "/starter." . $ike_daemon . ".pid";

    if (-f $starter_PID_file) {
        unless (&checkPidFileRunning($starter_PID_file)) {
            $ret = 0;
        }
        else {
            &log_warn("VPNIPSec Starter not running but PID file $starter_PID_file exists!", "VPN");
            $ret = 2;
        }
    }
    else {
        my $pgrep = &getGlobalConfiguration("pgrep");
        if (!&logAndRunCheck("$pgrep starter")) {
            &log_warn("VPNIPSec Starter running but no PID file $starter_PID_file exists!", "VPN");
            $ret = 3;
        }
        else {
            $ret = 1;
        }
    }
    return $ret;
}

=pod

=head1 runVPNIPSecIKEDaemonCommand
	It runs an action regarding the vpn connection name.

Parameters:
	action -  Action to be executed.
	vpnname - Name of the vpn connection.

Returns:
	Integer -  Error code: 0 on success or other value on failure.

=cut

sub runVPNIPSecIKEDaemonCommand ($action, $vpnname) {
    my $error_ref->{code} = 1;
    my $ipsec_ctl         = &getGlobalConfiguration('ipsec_ike_ctl');
    my $command           = &logRunAndGet("$ipsec_ctl $action $vpnname", "array");

    my %match = (
        up   => "connection '([a-zA-Z][a-zA-Z0-9\-]*)' established successfully",
        down => "IKE_SA \\[(\\d+)\\] closed successfully"
    );

    if (!$command->{stderr}) {
        if (scalar @{ $command->{stdout} } == 0) {
            $error_ref->{code} = 0;
        }

        for my $line (@{ $command->{stdout} }) {
            if ($line =~ /$match{$action}/) {
                $error_ref->{code} = 0;
                last;
            }
        }

        if ($error_ref->{code} == 1) {
            if (@{ $command->{stdout} } > 2) {
                my $error_str = @{ $command->{stdout} }[-2];

                $error_ref->{code} = 2 if ($error_str =~ /AUTHENTICATION_FAILED/);
                $error_ref->{code} = 3 if ($error_str =~ /NO_PROPOSAL_CHOSEN/);
                $error_ref->{code} = 4 if ($error_str =~ /INVALID_PAYLOAD_TYPE/);
                $error_ref->{code} = 5 if ($error_str =~ /INVALID_KEY_INFORMATION/);
                $error_ref->{code} = 6 if ($error_str =~ /INVALID_ID_INFORMATION/);
                $error_ref->{err}  = $error_str;
            }
            else {
                $error_ref->{err} = @{ $command->{stdout} }[0];
            }
        }
    }
    else {
        $error_ref->{code} = $command->{stderr};
    }

    return $error_ref;
}

=pod

=head1 runVPNIPSecCommand
	It runs an ipsec action.

Parameters:
	Action -  Action to be executed.

Returns:
	Integer -  0 on success or other value on failure.

=cut

sub runVPNIPSecCommand ($action) {
    my $ipsec_bin = &getGlobalConfiguration('ipsec_bin');
    my $command   = &logRunAndGet("$ipsec_bin $action", "array");

    my %match = (
        start         => "Starting strongSwan",
        stop          => "Stopping strongSwan IPsec",
        reload        => "Reloading strongSwan IPsec configuration",
        rereadsecrets => "",
    );

    my $status = -1;
    if (!$command->{stderr}) {
        for my $line (@{ $command->{stdout} }) {
            if ($line =~ /$match{$action}/) {
                $status = 0;
                last;
            }
        }

        if ($action eq "rereadsecrets") {
            $status = 0;
        }
    }
    else {
        $status = $command->{stderr};
    }

    return $status;
}

=pod

=head1 runVPNIPSecIKEDaemonStatus

Gets all information of Daemon.

Parameters:

    None.

Returns: hash reference

A hash reference with the daemon status

    daemon       - Daemon Info
    up           - Total vpn established.
    connecting   - Total vpn connecting.
    listen       - IP Listening.
    conns => vpn - Connections Info for vpns.
    sa => vpn    - Security Associations Info for vpns.

=cut

sub runVPNIPSecIKEDaemonStatus () {
    my $ipsec_ctl = &getGlobalConfiguration('ipsec_ike_ctl');
    my $command   = &logRunAndGet("$ipsec_ctl statusall", "array");
    my $status_ref;

    if (!$command->{stderr}) {
        my $block = "";
        my $parent;

        for my $line (@{ $command->{stdout} }) {
            if ($line =~ /^Status of IKE (\w+) daemon \(.*\):$/) {
                $block = "daemon";
                next;
            }

            if ($line =~ /^Listening IP addresses:$/) {
                $block = "listen";
                next;
            }

            if ($line =~ /^Connections:$/) {
                $block = "conns";
                next;
            }

            if ($line =~ /^Security Associations \((\d+) up, (\d+) connecting\):$/) {
                $status_ref->{up}         = $1;
                $status_ref->{connecting} = $2;
                $block                    = "sa";
                next;
            }

            if ($block eq "daemon") {
                my ($info, $data);

                if ($line =~ /^\s+(\w+\s*\w*):\s+(.*)$/) {
                    $info = $1;
                    $data = $2;

                    if ($info eq "uptime") {
                        if ($data =~ /(.*), since (.*)/) {
                            $status_ref->{$block}{$info} = $1;
                            $status_ref->{$block}{running} = $2;
                        }
                        next;
                    }

                    if ($info eq "malloc") {
                        $status_ref->{$block}{$info} = $data;
                        next;
                    }

                    if ($info eq "worker threads") {
                        $status_ref->{$block}{threads} = $data;
                        next;
                    }

                    if ($info eq "loaded plugins") {
                        $status_ref->{$block}{plugins} = $data;
                        next;
                    }
                }
            }

            if ($block eq "listen") {
                if ($line =~ /^\s+(.*)$/) {
                    push @{ $status_ref->{$block} }, $1;
                    next;
                }
            }

            if ($block eq "conns") {
                my ($conn, $data, $local, $remote, $child);

                if ($line =~ /^\s*([a-zA-Z][a-zA-Z0-9\-]*):\s+(.*)$/) {
                    $conn = $1;
                    $data = $2;

                    if ($data =~ /local:\s+(.*)/) {
                        $local = $1;
                        $status_ref->{$block}{$conn}{local} = $local;
                        next;
                    }

                    if ($data =~ /remote:\s+(.*)/) {
                        $remote = $1;
                        $status_ref->{$block}{$conn}{remote} = $remote;
                        next;
                    }

                    if ($data =~ /child:\s+(.*)/) {
                        $child = $1;
                        push @{ $status_ref->{$block}{$conn}{child} }, $child;
                        if (    defined $status_ref->{$block}{$conn}{local}
                            and defined $status_ref->{$block}{$conn}{remote})
                        {
                            $parent = $conn;
                        }
                        else {
                            $status_ref->{$block}{$conn}{parent} = $parent;
                        }
                        next;
                    }

                    $status_ref->{$block}{$conn}{connection} = $data;
                    next;
                }
            }

            if ($block eq "sa") {
                my ($conn, $data);

                if ($line =~ /^\s*([a-zA-Z][a-zA-Z0-9\-]*)\[\d+\]:\s+(.*)$/) {
                    $conn = $1;
                    $data = $2;

                    if ($data =~ /IKE\w+ SPIs:\s+(.*)/) {
                        $status_ref->{$block}{$conn}{ike}{spi} = $data;
                        next;
                    }

                    if ($data =~ /IKE\w* proposal:\s+(.*)/) {
                        $status_ref->{$block}{$conn}{ike}{proposal} = $data;
                        next;
                    }

                    if ($data =~ /(ESTABLISHED|CONNECTING)( ((\d+) (\w+)) ago)?, (.*)/) {
                        $status_ref->{$block}{$conn}{ike}{status} = $1;
                        $status_ref->{$block}{$conn}{ike}{uptime} = $3;
                        $status_ref->{$block}{$conn}{ike}{desc}   = $6;
                        next;
                    }
                }

                if ($line =~ /^\s*([a-zA-Z][a-zA-Z0-9\-]*)\{\d+\}:\s+(.*)$/) {
                    $conn = $1;
                    $data = $2;

                    if ($data =~ /^ (.*) === (.*)/) {
                        $status_ref->{$block}{$conn}{child}{local}  = $1;
                        $status_ref->{$block}{$conn}{child}{remote} = $2;
                        next;
                    }

                    if ($data =~ /^(.*), (.*), reqid (\d+), (.*) SPIs: (.*)_i (.*)_o/) {
                        $status_ref->{$block}{$conn}{child}{status}  = $1;
                        $status_ref->{$block}{$conn}{child}{mode}    = $2;
                        $status_ref->{$block}{$conn}{child}{reqid}   = $3;
                        $status_ref->{$block}{$conn}{child}{enc}     = $4;
                        $status_ref->{$block}{$conn}{child}{spi_in}  = $5;
                        $status_ref->{$block}{$conn}{child}{spi_out} = $6;
                        next;
                    }

                    if ($data =~ /^(.*), (\d+) bytes_i( \((\d+) pkts, (\w+) ago\))?, (\d+) bytes_o( \((\d+) pkts, (\w+) ago\))?, (.*)/) {
                        $status_ref->{$block}{$conn}{child}{cipher}      = $1;
                        $status_ref->{$block}{$conn}{child}{bytes_in}    = $2;
                        $status_ref->{$block}{$conn}{child}{packets_in}  = $4;
                        $status_ref->{$block}{$conn}{child}{last_in}     = $5;
                        $status_ref->{$block}{$conn}{child}{bytes_out}   = $6;
                        $status_ref->{$block}{$conn}{child}{packets_out} = $8;
                        $status_ref->{$block}{$conn}{child}{last_out}    = $9;
                        next;
                    }
                }
            }
        }
    }

    return $status_ref;
}

1;

