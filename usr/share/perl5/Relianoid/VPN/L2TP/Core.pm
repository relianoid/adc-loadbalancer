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

Relianoid::VPN::L2TP::Core

=cut

use strict;
use warnings;
use feature qw(signatures);

=pod

=head1 getVpnL2TPInitConfig

	Gets the default values of a L2TP object.

Parameters:
	None.

Returns:
	Hash ref - Object with default values.

=cut

sub getVpnL2TPInitConfig () {
    return {
        global => {
            "access control" => "no",
        },
        "lns default" => {
            "require authentication" => "yes",
            "require chap"           => "yes",
            "refuse pap"             => "yes",
            "length bit"             => "yes",
        }
    };
}

=pod

=head1 getVpnL2TPPppInitConfig

	Gets the default values of L2TP PPP options.

Parameters:
	None.

Returns:
	Hash ref - Object with default values.

=cut

sub getVpnL2TPPppInitConfig () {
    return {
        "ipcp-accept-local"     => undef,
        "ipcp-accept-remote"    => undef,
        "connect-delay"         => 500,
        "noccp"                 => undef,
        "auth"                  => undef,
        "idle"                  => 1800,
        "mtu"                   => 1410,
        "mru"                   => 1410,
        "nodefaultroute"        => undef,
        "noreplacedefaultroute" => undef,
        "noktune"               => undef,
        "noipdefault"           => undef,
        "noproxyarp"            => undef,
    };
}

=pod

=head1 getVpnL2TPParamName

	Translate Config Param Name to L2TP Param Name and viceversa.

Parameters:
	param - String : Param to translate.
	mode - String :  Indicates the format to translate.

Returns:
	String - IPSec Param or undef if param not found.

=cut

sub getVpnL2TPParamName ($param, $mode) {
    my $params;

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    if ($mode eq "l2tp") {
        $params = {
            $vpn_config->{LOCAL}          => "listen-addr",
            $vpn_config->{REMOTETUNRANGE} => "ip range",
            $vpn_config->{LOCALTUNIP}     => "local ip",
        };
    }
    elsif ($mode eq "config") {
        $params = {
            "ip range"    => $vpn_config->{REMOTETUNRANGE},
            "local ip"    => $vpn_config->{LOCALTUNIP},
            "listen-addr" => $vpn_config->{LOCAL},
        };
    }

    return $params->{$param};
}

=pod

=head1 getVpnL2TPParams

	Translate Config Params to L2TP Params and viceversa.

Parameters:
	params_ref  - Hash : Params to translate.
	mode - String :  Indicates the format to translate.

Returns:
	Hash - L2TP Params or undef if no params found.

=cut

sub getVpnL2TPParams ($params_ref, $mode) {
    my $params_ref_tmp;

    if ($mode eq "l2tp") {
        for my $param (keys %{$params_ref}) {
            my $param_translate = &getVpnL2TPParamName($param, "l2tp");

            if ($param_translate) {
                if ($param_translate eq "listen-addr") {
                    $params_ref_tmp->{global}{$param_translate} = $params_ref->{$param};
                }
                else {
                    $params_ref_tmp->{"lns default"}{$param_translate} = $params_ref->{$param};
                }
            }
        }
    }

    return $params_ref_tmp;
}

=pod

=head1 getVpnL2TPConfFilePath

	Gets the Configuration filepath of a L2TP connection.

Parameters:
	vpn_name - vpn connection name.

Returns:
	String - Filepath.

=cut

sub getVpnL2TPConfFilePath ($vpn_name) {
    require Relianoid::VPN::Core;
    return (&getVpnConfigPath() . "/" . $vpn_name . "_l2tp.conf");
}

=pod

=head1 getVpnL2TPPppFilePath

	Gets the PPP Configuration filepath of a L2TP connection.

Parameters:
	vpn_name - vpn connection name.

Returns:
	String - Filepath.

=cut

sub getVpnL2TPPppFilePath ($vpn_name) {
    require Relianoid::VPN::Core;
    return (&getVpnConfigPath() . "/" . $vpn_name . "_ppp.conf");
}

=pod

=head1 getVpnL2TPPppSecretFilePath

	Gets the PPP Secrets Configuration filepath.

Parameters:

Returns:
	String - Filepath.

=cut

sub getVpnL2TPPppSecretFilePath () {
    return (&getGlobalConfiguration("l2tp_ppp_secret"));
}

=pod

=head1 getVpnL2TPPidFilePath

	Gets the Pid filepath of a L2TP connection.

Parameters:
	vpn_name - vpn connection name.

Returns:
	String - Filepath.

=cut

sub getVpnL2TPPidFilePath ($vpn_name) {
    return (&getGlobalConfiguration("piddir") . "/" . $vpn_name . "_l2tp.pid");
}

=pod

=head1 getVpnL2TPCtlFilePath

	Gets the Control filepath of a L2TP connection.

Parameters:
	vpn_name - vpn connection name.

Returns:
	String - Filepath.

=cut

sub getVpnL2TPCtlFilePath ($vpn_name) {
    return (&getGlobalConfiguration("l2tp_ctl_dir") . "/" . $vpn_name . "_l2tp.ctl");
}

=pod

=head1 getVpnL2TPPid

	Gets the Pid of a L2TP connection.

Parameters:
	vpn_name - vpn connection name.

Returns:
	Integer - PID if successful or -1 on failure

=cut

sub getVpnL2TPPid ($vpn_name) {
    my $l2tp_pid_file = &getVpnL2TPPidFilePath($vpn_name);
    my $rc            = -1;

    if (!-f "$l2tp_pid_file") {
        my $pgrep          = &getGlobalConfiguration("pgrep");
        my $l2tp_bin       = &getGlobalConfiguration("l2tp_bin");
        my $l2tp_conf_file = &getVpnL2TPConfFilePath($vpn_name);
        $rc = &logAndRunCheck("$pgrep -f \"$l2tp_bin.*$l2tp_conf_file\"");
    }
    else {
        open my $fh, '<', "$l2tp_pid_file";
        $rc = <$fh>;
        close $fh;
    }

    $rc = -1 if ($rc eq "");
    return $rc;
}

=pod

=head1 getVpnL2TPLnsStatus

	Gets the status of a L2TP L2tp Network Server connection.

Parameters:
	conn_name - connection name.

Returns:
	String - L2TP conn status . empty|unloaded|connecting|up|down

=cut

sub getVpnL2TPLnsStatus ($conn_name) {
    require Relianoid::VPN::L2TP::Runtime;
    require Relianoid::VPN::Core;

    my $remote_access = "";
    my $status        = &runVPNL2TPDaemonStatus("lns", $conn_name);
    my $vpn_config    = &getVpnModuleConfig();

    if (defined $status->{$conn_name}) {
        $remote_access = $vpn_config->{STATUS_UP};
    }
    else {
        $remote_access = $vpn_config->{STATUS_DOWN};
    }

    return $remote_access;
}

=pod

=head1 getVpnL2TPPppUsers

	Gets a User list from the L2TP key file

Parameters:
	$vpn_name - VPN Name. Empty means all vpns and system.

Returns:
	Hash -  Users ref

=cut

sub getVpnL2TPPppUsers ($vpn_name) {
    my $user_ref = {};

    require Relianoid::VPN::L2TP::Core;
    my $key_file = &getVpnL2TPPppSecretFilePath();

    if (!-f $key_file) {
        &log_warn("L2TP PPP $key_file doesn't exist.", "VPN");
        return;
    }

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    require Relianoid::Lock;
    &ztielock(\my @contents, $key_file);

    my $vpn_found = 0;
    my $key_ref;
    my $size = @contents;

    for (my $idx = 0 ; $idx < $size ; $idx++) {
        if ($contents[$idx] =~ /^#RELIANOID VPN Users for ([a-zA-Z][a-zA-Z0-9\-]*)$/) {
            $vpn_found = $1;
        }
        elsif ($contents[$idx] =~ /^(\w+)\s+(.+)\s+(\w+)\s+(.+)\s*$/) {
            $key_ref->{ $vpn_config->{VPN_USER} }     = $1;
            $key_ref->{server}                        = $2;
            $key_ref->{ $vpn_config->{VPN_PASSWORD} } = $3;
            $key_ref->{ip}                            = $4;

            next                  if (defined $vpn_name and $vpn_found ne $vpn_name);
            $vpn_found = "SYSTEM" if ($vpn_found eq "0");
            push @{ $user_ref->{$vpn_found} }, $key_ref;
            $key_ref = undef;
        }
        elsif ($contents[$idx] =~ /^#END$/) {
            last if ((defined $vpn_name) and ($vpn_found eq $vpn_name));
            $vpn_found = 0;
        }
    }

    untie @contents;

    return $user_ref;
}

1;
