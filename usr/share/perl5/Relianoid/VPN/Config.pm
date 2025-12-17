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

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::VPN::Config

=cut

require Relianoid::VPN::Core;

my $vpn_config = &getVpnModuleConfig();

=pod

=head1 createVPNConf

Create a VPN conf file

Parameters:

    vpn_ref - vpn object

    site_to_site_sobject = (
        name =>  vpnname,
        profile => vpntype,
        leftauth => vpnauth,
        secret => vpnsecret,
        left => ip,
        leftsubnet => subnet,
        right => ip,
        rightsubnet => subnet,
        p1encrypt =>  p1encrypt,  algorithm
        p2protocol =>
        p2encrypt =>
    )

Returns: integer - error code

0  - success
!0 - error
-1 - VPN Object not valid
-2 - VPN already exits
-3 - No VPN Initial config

=cut

sub createVPNConf ($vpn_ref) {
    require Relianoid::VPN::Validate;

    # validate object
    if (my $error = &checkVPNObject($vpn_ref)) {
        &log_warn("VPN Object not valid.", "VPN");
        return -1;
    }

    require Relianoid::VPN::Core;

    my $vpn_config = &getVpnModuleConfig();
    my $vpn_name   = $vpn_ref->{ $vpn_config->{NAME} };

    # check config exists
    unless (&getVpnExists($vpn_name)) {
        &log_warn("VPN $vpn_name already exits.", "VPN");
        return -2;
    }

    my $conf_init = &getVpnInitConfig();

    if (!$conf_init) {
        &log_error("Error, no VPN Initial config", "VPN");
        return -3;
    }

    # Use $conf_init as default values, and replace defaults with $vpn_ref values.
    my %vpn_conf = (%$conf_init, %$vpn_ref);

    my $conf_file = &getVpnConfFilePath($vpn_name);
    return (&setTinyObj($conf_file, $vpn_name, \%vpn_conf, "new"));
}

=pod

=head1 setVPNConfObject

Set a VPN Configuration file with all or selected params.

Parameters:

    vpn_name   - vpn connection name.
    params_ref - Hash of params to set.

Returns: integer - error code

0  - success
!0 - error

=cut

sub setVPNConfObject ($vpn_name, $params_ref) {
    my $conf_file = &getVpnConfFilePath($vpn_name);
    return -1 if (!-f $conf_file);

    my $error = &setTinyObj($conf_file, $vpn_name, $params_ref, "update");

    return $error;
}

=pod

=head1 delVPNConf

Remove a VPN conf file

Parameters:

    vpn_name - Site-to-Site VPN object

Returns: integer - error code

0  - success
!0 - error

=cut

sub delVPNConf ($vpn_name) {
    my $rc = -1;

    my $conf_file = &getVpnConfFilePath($vpn_name);
    if (-e $conf_file) {
        $rc = 0 if (unlink $conf_file);
    }
    else {
        &log_warn("VPN $vpn_name conf file doesn't exists", "VPN");
        $rc = 1;
    }

    return $rc;
}

=pod

=head1 setVPNBootstatus

Set VPN Configuration Boot Status value.

Parameters:

    vpn_name   - string - Vpn connection name.
    bootstatus - string - BootStatus value.

Returns: integer - error code

0  - success
!0 - error

=cut

sub setVPNBootstatus ($vpn_name, $bootstatus) {
    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    my $param = { $vpn_config->{BOOTSTATUS} => $bootstatus };
    my $error = &setVPNConfObject($vpn_name, $param);

    return $error;
}

=pod

=head1 setVPNRestartStatus

Set VPN Configuration Restart Status value.

Parameters:

    vpn_name - string - Vpn connection name.
    restart  - string - Restart value.

Returns: integer - error code

0  - success
!0 - error

=cut

sub setVPNRestartStatus ($vpn_name, $restart) {
    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();
    $restart = $restart eq "true" ? "true" : "false";

    my $param = { $vpn_config->{RESTART} => $restart };
    my $error = &setVPNConfObject($vpn_name, $param);

    return $error;
}

=pod

=head1 setVPNLocalGateway

Set VPN Local Gateway.

Parameters:

    vpn_name - string - Vpn connection name.
    ip       - string - IP to use as Local Gateway.

Returns: integer - error code

0  - success
!0 - error

=cut

sub setVPNLocalGateway ($vpn_name, $ip) {
    my $error_ref;
    return if (!defined $ip);

    my $type = &getVpnType($vpn_name);
    if ($type eq "site_to_site") {
        my $param = { $vpn_config->{LOCAL} => $ip };

        require Relianoid::VPN::SiteToSite::Config;
        $error_ref = &setVpnSiteToSiteParams($vpn_name, $param);
    }

    #elsif ( $type eq "tunnel" )
    #elsif ( $type eq "remote_access" )

    return $error_ref;
}

=pod

=head1 setAllVPNLocalGateway

Set VPN Local Gateway for a set of Vpns. If some vpn is up, this function will restart it.

Parameters:

    ip       - String : IP to use as Local Gateway.
    vpn_list - Array ref : List of vpns to update.

Returns: integer - error code

0  - success
!0 - error

=cut

sub setAllVPNLocalGateway ($ip, $vpn_list) {
    my $error;
    my @error_objects;
    my @error_desc;

    require Relianoid::VPN::Action;
    for my $vpn_name (@{$vpn_list}) {
        # get status
        my $status  = &getVpnStatus($vpn_name);
        my $bstatus = &getVpnBootstatus($vpn_name);

        my $error = &setVPNLocalGateway($vpn_name, $ip);
        if ($error->{code}) {
            push @error_objects, $vpn_name;
            push @error_desc,    $error->{desc};
            next;
        }

        if (   $status eq $vpn_config->{STATUS_UP}
            or $bstatus eq $vpn_config->{STATUS_UP})
        {
            my $error = &runVPNRestart($vpn_name);
            if ($error) {
                push @error_objects, $vpn_name;
                push @error_desc,    "$vpn_name cannot be restarted";
            }
        }
    }

    if (@error_objects) {
        $error->{code} = 1;
        $error->{err}  = join(', ', @error_objects);
        $error->{desc} = join('. ', @error_desc);
    }

    return $error;
}

=pod

=head1 setVPNLocalNetwork

Set VPN Local Network.

Parameters:
    vpn_name - string - Vpn connection name.
    net      - string - Network in CIDR format IP/Bits to use as Local Network

Returns: integer - error code

0  - success
!0 - error

=cut

sub setVPNLocalNetwork ($vpn_name, $net) {
    my $error_ref = 1;

    return $error_ref if (!defined $net);

    my $type = &getVpnType($vpn_name);
    if ($type eq "site_to_site") {
        my $param = { $vpn_config->{LOCALNET} => $net };
        require Relianoid::VPN::SiteToSite::Config;
        $error_ref = &setVpnSiteToSiteParams($vpn_name, $param);
    }

    #elsif ( $type eq "tunnel" )
    #elsif ( $type eq "remote_access" )

    return $error_ref;
}

=pod

=head1 setAllVPNLocalNetwork

Set VPN Local Network for a set of Vpns. If some vpn is up, this function will restart it.

Parameters:

    net      - String - Net to use as Local Network.
    vpn_list - Array ref - List of vpns to update.

Returns: integer - error code

0  - success
!0 - error

=cut

sub setAllVPNLocalNetwork ($net, $vpn_list) {
    require Relianoid::VPN::Action;

    my $error;
    my @error_objects;
    my @error_desc;

    for my $vpn_name (@{$vpn_list}) {
        # get status
        my $status  = &getVpnStatus($vpn_name);
        my $bstatus = &getVpnBootstatus($vpn_name);

        my $error = &setVPNLocalNetwork($vpn_name, $net);
        if ($error->{code}) {
            push @error_objects, $vpn_name;
            push @error_desc,    $error->{desc};
            next;
        }

        if (   $status eq $vpn_config->{STATUS_UP}
            or $bstatus eq $vpn_config->{STATUS_UP})
        {
            my $error = &runVPNRestart($vpn_name);
            if ($error) {
                push @error_objects, $vpn_name;
                push @error_desc,    "$vpn_name cannot be restarted";
            }
        }
    }

    if (@error_objects) {
        $error->{code} = 1;
        $error->{err}  = join(', ', @error_objects);
        $error->{desc} = join('. ', @error_desc);
    }

    return $error;
}

=pod

=head1 createVPNRoute

Create a route based on VPN.

Parameters:

    vpn_name - string - vpn name.

Returns: integer - error code

0  - success
!0 - error

=cut

sub createVPNRoute ($vpn_name) {
    my $rc = 0;

    my $type = &getVpnType($vpn_name);
    if ($type eq "site_to_site") {
        require Relianoid::VPN::SiteToSite::Config;
        $rc = &createVpnSiteToSiteRoute($vpn_name);
    }
    elsif ($type eq "tunnel") {
        require Relianoid::VPN::Tunnel::Config;
        $rc = &createVpnTunnelRoute($vpn_name);
    }

    return $rc;
}

=pod

=head1 delVPNRoute

Remove a route based on VPN.

Parameters:

    vpn_name - string - vpn name.

Returns: integer - error code

0  - success
!0 - error

=cut

sub delVPNRoute ($vpn_name) {
    my $rc = 0;

    my $type = &getVpnType($vpn_name);
    if ($type eq "site_to_site") {
        require Relianoid::VPN::SiteToSite::Config;
        $rc = &delVpnSiteToSiteRoute($vpn_name);
    }
    elsif ($type eq "tunnel") {
        require Relianoid::VPN::Tunnel::Config;
        $rc = &delVpnTunnelRoute($vpn_name);
    }

    return $rc;
}

=pod

=head1 CreateVPNTunnelIf

Create a VPN Interface

Parameters:

    if_name   - string - Dev Name
    mode      - string - Type of Virtual Interface. gre, ip6gre
    local_ip  - string - Local End Point of the tunnel.
    remote_ip - string - Remote End Point of the tunnel.
    ip        - string - Virtual Interface Ip address
    mask      - string - Virtual Interface Netmask

Returns: integer - error code

0  - success
!0 - error

=cut

sub createVPNTunnelIf ($if_name, $mode, $local_ip, $remote_ip, $ip, $mask) {
    my $ip_bin = &getGlobalConfiguration("ip_bin");
    my $ip_cmd = "$ip_bin tunnel add $if_name local $local_ip remote $remote_ip mode $mode";

    # Log udev debug events
    # logAndRun("udevadm control --log-priority=debug");

    my $status = &logAndRun($ip_cmd);

    if ($status) {
        return 1;
    }

    my $tunnel_ref = &getSystemInterface($if_name);
    $tunnel_ref->{addr} = $ip;
    $tunnel_ref->{mask} = $mask;

    $status = &setInterfaceConfig($tunnel_ref);
    if ($status == 0) {
        return 2;
    }

    require Relianoid::Net::Route;

    if (!&getRoutingTableExists("table_$if_name")) {
        &writeRoutes($if_name);

        if (debug() > 1) {
            &getRoutingTableExists("table_$if_name");
        }

        # No routes are expected on a newly created table.
        # Workaround: On Community we find routes on a new table.
        if (my $routes = logAndGet("/bin/ip route list table table_$if_name")) {
            log_debug2($routes);
            log_warn("Found unexpected routes in new routing table table_$if_name. Flushing table.");

            logAndRun("ip route flush table table_$if_name");
        }
    }

    return 0;
}

=pod

=head1 delVPNtunnelIf

Delete a VPN Interface

Parameters:

    if_name - string - Dev Name
    mode    - string - Type of Virtual Interface. gre, ip6gre

Returns: integer - error code

0  - success
!0 - error

=cut

sub delVPNTunnelIf ($if_name, $mode) {
    my $status;

    require Relianoid::Net::Interface;
    my $tunnel_ref = &getInterfaceConfig($if_name);

    if (!$tunnel_ref->{type}) {
        require Relianoid::Net::Interface;
        $status = &cleanInterfaceConfig($tunnel_ref);

        if ($status) {
            return $status;
        }

        require Relianoid::RRD;
        &delGraph($if_name, "iface");
    }
    elsif ($tunnel_ref->{type} eq $mode) {
        require Relianoid::Net::Core;
        $status = &delIf($tunnel_ref);

        if ($status) {
            return $status;
        }

        require Relianoid::Net::Route;

        if (&getRoutingTableExists("table_$if_name")) {
            &deleteRoutesTable($if_name);
        }
    }

    return 0;
}

=pod

=head1 setVPNTunnelIf

Modify a VPN Interface

Parameters:

    if_name   - string - Dev Name
    local_ip  - string - Local End Point of the tunnel.
    remote_ip - string - Remote End Point of the tunnel.

    # mode - String : Type of Virtual Interface. gre, ip6gre

Returns: integer - error code

0  - success
!0 - error

=cut

sub setVPNTunnelIf ($if_name, $local_ip, $remote_ip) {
    my $ip_bin = &getGlobalConfiguration("ip_bin");

    my $ip_cmd = "$ip_bin tunnel change $if_name local $local_ip remote $remote_ip";
    my $status = &logAndRun($ip_cmd);

    if ($status) {
        return 1;
    }

    return 0;
}

=pod

=head1 createVPNUser

Create a VPN Credentials configuration

Parameters:

    vpn_name - Remote Access VPN name
    user_ref - VPN Credentials object

Returns: integer - error code

0  - success
!0 - error

=cut

sub createVPNUser ($vpn_name, $user_ref) {
    require Relianoid::VPN::Core;

    my $conf_file = &getVpnConfFilePath($vpn_name);
    return &setTinyObj($conf_file, $vpn_name, $vpn_config->{VPN_USER}, $user_ref->{ $vpn_config->{VPN_USER} }, "add");
}

=pod

=head1 deleteVPNUser

    Delete a VPN Credentials configuration

Parameters:

    vpn_name  - Remote Access VPN name
    user_name - VPN User name

Returns: integer - error code

0  - success
!0 - error

=cut

sub deleteVPNUser ($vpn_name, $user_name) {
    require Relianoid::VPN::Core;

    my $conf_file = &getVpnConfFilePath($vpn_name);
    return (&setTinyObj($conf_file, $vpn_name, $vpn_config->{VPN_USER}, $user_name, "del"));
}

1;
