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

Relianoid::VPN::L2TP::Config

=cut

use strict;
use warnings;
use feature qw(signatures);

use Config::Tiny;

=pod

=head1 createVPNL2TPConf

	Create L2TP Configuration file

Parameters:
	conn_name - L2TP Connection name
	conn_ref - L2TP Connection object

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub createVPNL2TPConf ($conn_name, $conn_ref) {
    require Relianoid::VPN::L2TP::Core;

    my $object = &getVpnL2TPInitConfig();
    if (!$object) {
        &log_error("Error, no L2TP Initial config", "VPN");
        return -3;
    }

    my $conf_file = &getVpnL2TPConfFilePath($conn_name);
    if (-f $conf_file) {
        &log_warn("VPN L2TP Configuration file $conf_file already exits.", "VPN");
        return -2;
    }

    # create pppdfile
    my $ppp_file = &getVpnL2TPPppFilePath($conn_name);
    my $error    = &createVPNL2TPPppFile($conn_name);
    if ($error) {
        &log_warn("Create L2TP PPP Configuration file $ppp_file Failed.", "VPN");
        return -3;
    }

    $object->{"lns default"}{pppoptfile} = $ppp_file;

    # merge template object with l2tp object values
    my @sections = ("global", "lns default");

    for my $section (@sections) {
        my %object_tmp = %{ $object->{$section} };
        require Relianoid::VPN::Config;
        &replaceHashValues(\%object_tmp, $conn_ref->{$section}, "add");
        &setTinyObj($conf_file, $section, \%object_tmp, "new");
    }

    return 0;
}

=pod

=head1 delVPNL2TPConf

	Delete a L2TP Configuration File

Parameters:
	$conn_name - Connection name

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub delVPNL2TPConf ($conn_name) {
    my $rc = -1;

    require Relianoid::VPN::L2TP::Core;
    my $l2tp_conf_file = &getVpnL2TPConfFilePath($conn_name);

    if (-e $l2tp_conf_file) {
        $rc = 0 if (unlink $l2tp_conf_file);
    }
    else {
        &log_warn("VPN L2TP Configuration file $l2tp_conf_file doesn't exists", "VPN");
        $rc = 1;
    }

    return $rc;
}

=pod

=head1 setVPNL2TPConf

	Update a L2TP Configuration

Parameters:
	$conn_name - String. Connection name
	$params_ref - Hash ref with params to update.

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub setVPNL2TPConf ($conn_name, $params_ref) {
    my $l2tp_conf_file = &getVpnL2TPConfFilePath($conn_name);

    if (!-f $l2tp_conf_file) {
        &log_warn("VPN L2TP Configuration File $l2tp_conf_file doesn't exist.", "VPN");
        return 1;
    }

    my $rc = 0;
    for my $section (keys %{$params_ref}) {
        $rc += &setTinyObj($l2tp_conf_file, $section, $params_ref->{$section}, "update");
    }

    return $rc;
}

=pod

=head1 createVPNL2TPPppFile

	Create a L2TP PPP options File

Parameters:
	$conn_name - String. Connection name

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub createVPNL2TPPppFile ($conn_name) {
    require Relianoid::VPN::L2TP::Core;

    my $object = &getVpnL2TPPppInitConfig();
    if (!$object) {
        &log_error("Error, no L2TP PPP Initial config", "VPN");
        return -3;
    }

    my $ppp_file = &getVpnL2TPPppFilePath($conn_name);
    if (-f $ppp_file) {
        &log_warn("VPN L2TP PPP Options file $ppp_file already exits.", "VPN");
        return -2;
    }

    require Relianoid::Lock;
    &ztielock(\my @contents, $ppp_file);

    for my $param (sort keys %{$object}) {
        my $line = $param;
        $line .= " " . $object->{$param} if defined $object->{$param};
        push @contents, $line;
    }

    untie @contents;

    return 0;
}

=pod

=head1 delVPNL2TPPppFile

	Delete a L2TP PPP Options File

Parameters:
	$conn_name - Connection name

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub delVPNL2TPPppFile ($conn_name) {
    require Relianoid::VPN::L2TP::Core;

    my $ppp_file = &getVpnL2TPPppFilePath($conn_name);
    my $rc       = -1;

    if (-e $ppp_file) {
        $rc = 0 if (unlink $ppp_file);
    }
    else {
        &log_warn("VPN L2TP PPP Options file $ppp_file doesn't exists", "VPN");
        $rc = 1;
    }

    return $rc;
}

=pod

=head1 setVPNL2TPPppSecret

Create or update a key in the L2TP key file

Parameters:

	$vpn_name - VPN name
	$user_name - User name
	$user_pass - User password

Returns: integer - Error code. 0 on success or other value on error

=cut

sub setVPNL2TPPppSecret ($vpn_name, $user_name, $user_pass) {
    require Relianoid::VPN::L2TP::Core;

    my $key_file = &getVpnL2TPPppSecretFilePath();
    my $rc       = -1;

    if (!-f $key_file) {
        &log_warn("L2TP PPP $key_file doesn't exist.", "VPN");
        return 1;
    }

    require Relianoid::Lock;
    &ztielock(\my @contents, $key_file);

    my $new_line     = "${user_name} * ${user_pass} *";
    my $size         = @contents;
    my @contents_tmp = @contents;
    my $config_found = 0;
    my $found        = 0;
    my $idx;

    for ($idx = 0 ; $idx < $size ; $idx++) {
        if ($contents_tmp[$idx] =~ /^#RELIANOID VPN Users for ([a-zA-Z][a-zA-Z0-9\-]*)$/) {
            if ($1 eq $vpn_name) {
                $config_found = 1;
            }
            else {
                $config_found = 0;
            }

            next;
        }

        next if not $config_found == 1;

        if ($contents_tmp[$idx] =~ /^#END$/ && $found == 0) {
            splice @contents_tmp, $idx, 0, $new_line;
            $found = 1;
            last;
        }

        if ($contents_tmp[$idx] =~ /^(\w+)\s+(.+)\s+(\w+)\s+(.+)\s*$/) {
            my $user     = $1;
            my $server   = $2;
            my $password = $3;
            my $ip       = $4;

            if ($user eq $user_name) {
                my $new_line = "${user_name} ${server} ${user_pass} ${ip}";
                @contents_tmp[$idx] = $new_line;
                $found = 1;
                last;
            }
        }
    }

    if ($found == 0) {
        @contents_tmp[ $idx++ ] = "#RELIANOID VPN Users for $vpn_name";
        @contents_tmp[ $idx++ ] = $new_line;
        @contents_tmp[$idx]     = "#END";
        $found = 1;
    }

    if ($found == 1) {
        @contents = @contents_tmp;
        $rc       = 0;
    }
    else {
        $rc = 2;
    }

    untie @contents;

    return $rc;
}

=pod

=head1 unsetVPNL2TPPppSecret

Remove a key in the L2TP key file

Parameters:

	vpn_user - User to remove

Returns: integer - Error code. 0 on success.

=cut

sub unsetVPNL2TPPppSecret ($vpn_name, $vpn_user) {
    my $rc = -1;

    require Relianoid::VPN::L2TP::Core;
    my $key_file = &getVpnL2TPPppSecretFilePath();

    if (!-f $key_file) {
        &log_warn("L2TP PPP $key_file doesn't exist.", "VPN");
        return 1;
    }

    require Relianoid::Lock;
    &ztielock(\my @contents, $key_file);

    my $found;
    my $vpn_found = 0;
    my $size      = @contents;

    for (my $idx = 0 ; $idx < $size ; $idx++) {
        if ($contents[$idx] =~ /^#RELIANOID VPN Users for \Q$vpn_name\E$/) {
            $vpn_found = 1;
            next;
        }

        if ($vpn_found == 1) {
            if ($contents[$idx] =~ /^\Q$vpn_user\E\s+(.+)\s+(\w+)\s+(.+)\s*$/) {
                splice(@contents, $idx, 1);
                $found = 1;
                $rc    = 0;
                last;
            }
            elsif ($contents[$idx] =~ /^#END$/) {
                last;
            }
        }
    }

    $rc = 2 if (!$found);
    untie @contents;

    return $rc;
}

1;
