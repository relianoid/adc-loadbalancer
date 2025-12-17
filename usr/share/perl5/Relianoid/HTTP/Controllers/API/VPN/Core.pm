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

use Relianoid::Config;
use Relianoid::HTTP;

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::VPN::Core

=cut

#GET /vpns
sub list_vpn_controller () {
    my @out;
    my $desc = "List VPNs";

    require Relianoid::VPN::Core;

    my $vpns   = &getVpnList();
    my $params = [ "name", "profile", "status", "local", "localnet", "remote", "remotenet" ];

    require Relianoid::HTTP::Controllers::API::VPN::Structs;
    my $params_translated = &parseVPNRequest($params, "4.0");

    for my $vpn_name (@{$vpns}) {
        my $vpn_obj = &getVpnObject($vpn_name, $params_translated);
        my $api_obj = &getVpnObjectResponse($vpn_obj, "4.0");

        push @out, $api_obj;
    }

    if ($eload) {
        my $output = eload(module => 'Relianoid::EE::RBAC::Group::Core', func => 'getRBACUserSet', args => [ 'vpns', \@out ]);
        @out = @{$output};
    }

    my $body = {
        description => $desc,
        params      => \@out,
    };

    return &httpResponse({ code => 200, body => $body });
}

#GET /vpns/(vpn_re)
sub get_vpn_controller ($vpn_name) {
    my $desc = "Get VPN $vpn_name";

    require Relianoid::VPN::Core;

    my $error = &getVpnExists($vpn_name);
    if ($error) {
        my $msg = "The VPN $vpn_name does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    require Relianoid::HTTP::Controllers::API::VPN::Structs;

    my $vpn_obj = &getVpnObject($vpn_name);
    my $api_obj = &getVpnObjectResponse($vpn_obj, "4.0");

    my $body = {
        description => $desc,
        params      => $api_obj,
    };

    return &httpResponse({ code => 200, body => $body });
}

#GET /vpns/modules/summary
sub list_vpn_bymodule_controller () {
    my $out;
    my $desc = "VPN summary";

    my $types  = [ "site_to_site", "tunnel", "remote_access" ];
    my $params = [ "name", "profile", "local", "remote" ];

    for my $type (@{$types}) {
        $out->{$type} = [];
    }

    require Relianoid::VPN::Core;
    require Relianoid::HTTP::Controllers::API::VPN::Structs;

    my $params_translated = &parseVPNRequest($params, "4.0");

    my $vpns = &getVpnList();
    for my $vpn_name (@{$vpns}) {
        my $vpn_obj = &getVpnObject($vpn_name, $params_translated);
        my $api_obj = &getVpnObjectResponse($vpn_obj, "4.0");
        push @{ $out->{ &getVpnType($vpn_name) } }, $api_obj;
    }

    if ($eload) {
        for my $vpn_type (keys %{$out}) {
            my $vpn_list = $vpn_type;

            $vpn_type = eload(
                module => 'Relianoid::EE::RBAC::Group::Core',
                func   => 'getRBACUserSet',
                args   => [ 'vpns', $vpn_list ]
            );
        }
    }

    my $body = {
        description => $desc,
        params      => $out,
    };

    return &httpResponse({ code => 200, body => $body });
}

# POST /vpns/(vpn_re)/actions
sub actions_vpn_controller ($json_obj, $vpn_name) {
    my $desc = "VPN actions";

    require Relianoid::VPN::Core;

    my $vpn_config = &getVpnModuleConfig();

    my $error = &getVpnExists($vpn_name);
    if ($error) {
        my $msg = "The VPN $vpn_name does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $params = {
        action => {
            values    => [ 'stop', 'start', 'restart' ],
            non_blank => 'true',
            required  => 'true',
        },
    };

    require Relianoid::Validate;

    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    use Relianoid::VPN::Action;

    if ($json_obj->{action} eq "start") {
        require Relianoid::Net::Interface;

        # check if Local Gateway is UP
        my $localgw = &getVpnLocalGateway($vpn_name);
        my $if_name = &getInterfaceByIp($localgw);
        my $if_ref  = &getInterfaceConfig($if_name);

        if (&getInterfaceSystemStatus($if_ref) ne "up") {
            my $msg = "The Local Gateway '$localgw' is not UP";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        # check if Local Network is UP
        my $localnet = &getVpnLocalNetwork($vpn_name);
        my ($local_ip, $local_mask) = split(/\//, $localnet);
        $if_name = &checkNetworkExists($local_ip, $local_mask, undef, 0);
        $if_ref  = &getInterfaceConfig($if_name);

        if (&getInterfaceSystemStatus($if_ref) ne "up") {
            my $msg = "The Local Network Interface '$if_name' is not UP";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        # check if another VPN Remote Access is running
        my $type = &getVpnType($vpn_name);

        if ($type eq "remote_access") {
            my $vpn_running = &getVpnRunning($type);

            if (@{$vpn_running} > 0 and ($vpn_name ne @{$vpn_running}[0])) {
                my $msg = "There is a Remote Access VPN running: '@{$vpn_running}[0]'.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        $error = &runVPNStart($vpn_name, "true");
        if ($error) {
            my $msg = "Error trying to set the action start in VPN $vpn_name.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }
    elsif ($json_obj->{action} eq "stop") {
        $error = &runVPNStop($vpn_name, "true");
        if ($error) {
            my $msg = "Error trying to set the action stop in VPN $vpn_name.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }
    elsif ($json_obj->{action} eq "restart") {
        # Stop VPN
        $error = &runVPNStop($vpn_name);

        if ($error) {
            my $msg = "Error trying to stop the VPN in the action restart in VPN $vpn_name.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        require Relianoid::Net::Interface;

        # check if Local Gateway is UP
        my $localgw = &getVpnLocalGateway($vpn_name);
        my $if_name = &getInterfaceByIp($localgw);
        my $if_ref  = &getInterfaceConfig($if_name);

        if (&getInterfaceSystemStatus($if_ref) ne "up") {
            my $msg = "The Local Gateway '$localgw' is not UP";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        # check if Local Network is UP
        my $localnet = &getVpnLocalNetwork($vpn_name);
        my ($local_ip, $local_mask) = split(/\//, $localnet);
        $if_name = &checkNetworkExists($local_ip, $local_mask, undef, 0);
        $if_ref  = &getInterfaceConfig($if_name);

        if (&getInterfaceSystemStatus($if_ref) ne "up") {
            my $msg = "The Local Network Interface '$if_name' is not UP";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        # check if another VPN Remote Access is running
        my $type = &getVpnType($vpn_name);

        if ($type eq "remote_access") {
            my $vpn_running = &getVpnRunning($type);

            if (@{$vpn_running} > 0 and ($vpn_name ne @{$vpn_running}[0])) {
                my $msg = "There is a Remote Access VPN running : '@{$vpn_running}[0]'.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        # Start VPN
        $error = &runVPNStart($vpn_name, "true");

        if ($error) {
            my $msg = "Error trying to start the VPN in the action restart in VPN $vpn_name.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    my $msg = "The action $json_obj->{action} has been performed in VPN $vpn_name.";
    &log_info("Success, $msg", "VPN");

    my $body = {
        description => "Set a new action in $vpn_name",
        params      => {
            action => $json_obj->{action},
            status => &getVpnStatus($vpn_name),
        },
        message => $msg
    };

    if (&getVpnRestartStatus($vpn_name) eq "true") {
        $body->{params}{status} = $vpn_config->{STATUS_NEEDRESTART};
    }

    return &httpResponse({ code => 200, body => $body });
}

# PUT /vpns/(vpn_re)
sub modify_vpn_controller ($json_obj, $vpn_name) {
    my $desc = "Modify VPN";

    require Relianoid::VPN::Core;

    my $error = &getVpnExists($vpn_name);
    if ($error) {
        my $msg = "The VPN $vpn_name does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getVpnType($vpn_name);
    if ($type eq "site_to_site") {
        require Relianoid::HTTP::Controllers::API::VPN::SiteToSite;
        &_modify_vpn_site_to_site_controller($json_obj, $vpn_name);
    }
    if ($type eq "tunnel") {
        require Relianoid::HTTP::Controllers::API::VPN::Tunnel;
        &_modify_vpn_tunnel_controller($json_obj, $vpn_name);
    }
    if ($type eq "remote_access") {
        require Relianoid::HTTP::Controllers::API::VPN::RemoteAccess;
        &_modify_vpn_remote_access_controller($json_obj, $vpn_name);
    }

    my $msg = "Error trying to modify VPN $vpn_name.";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# DELETE /vpns/(vpn_re)
sub delete_vpn_controller ($vpn_name) {
    my $desc = "Delete VPN";

    require Relianoid::VPN::Core;

    if (my $error = &getVpnExists($vpn_name)) {
        my $msg = "The VPN $vpn_name does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $vpn_config = &getVpnModuleConfig();

    if (&getVpnStatus($vpn_name) eq $vpn_config->{STATUS_UP}) {
        require Relianoid::VPN::Action;

        if (my $error = &runVPNStop($vpn_name, "true")) {
            my $msg = "The VPN $vpn_name could not be stopped.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    my $type = &getVpnType($vpn_name);

    if ($type eq "site_to_site") {
        require Relianoid::VPN::SiteToSite::Config;

        if (my $error = &delVpnSiteToSite($vpn_name)) {
            my $msg = "The VPN $vpn_name hasn't been deleted";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }
    elsif ($type eq "tunnel") {
        require Relianoid::VPN::Tunnel::Config;

        if (my $error = &delVpnTunnel($vpn_name)) {
            my $msg = "The VPN $vpn_name hasn't been deleted";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }
    elsif ($type eq "remote_access") {
        require Relianoid::VPN::RemoteAccess::Config;

        if (my $error = &delVpnRemoteAccess($vpn_name)) {
            my $msg = "The VPN $vpn_name hasn't been deleted";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    &log_info("Success, the VPN $vpn_name has been deleted.", "VPN");

    if ($eload) {
        my @args = ('vpn', 'delete', $vpn_name, $type);
        eload(module => 'Relianoid::EE::Cluster', func => 'runClusterRemoteManager', args => \@args);
    }

    my $msg  = "The VPN $vpn_name has been deleted.";
    my $body = { description => $desc, success => 'true', message => $msg };

    return &httpResponse({ code => 200, body => $body });
}

# POST /vpns
sub add_vpn_controller ($json_obj) {
    my $desc = "Creating a VPN";

    require Relianoid::VPN::Core;

    unless (&getVpnExists($json_obj->{name})) {
        my $msg = "Error trying to create a new VPN, the VPN name already exists.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = {
        profile => {
            required  => 'true',
            non_blank => 'true',
            values    => [ 'site_to_site', 'remote_access', 'tunnel' ],
        },
        name => {
            required     => 'true',
            non_blank    => 'true',
            valid_format => 'vpn_name',
            format_msg   =>
              "The vpn name is required to start with an alphabet letter, and contains alphabet letters, numbers or hypens (-) only.",
        },
    };

    require Relianoid::Net::Validate;

    # commom params
    $params->{local} = {
        required     => 'true',
        non_blank    => 'true',
        valid_format => 'ip_addr',
    };
    $params->{auth} = {
        required  => 'true',
        non_blank => 'true',
        values    => ['secret'],
    };
    $params->{password} = {
        required  => 'true',
        non_blank => 'true',
    };
    $params->{p2protocol} = {
        required  => 'true',
        non_blank => 'true',
        values    => [ 'esp', 'ah' ],
    };
    $params->{p1encrypt} = {
        ref       => 'ARRAY',
        required  => 'true',
        non_blank => 'true',
        values    => [
            'aes128', 'aes192',      'aes256',      'aes128gmac',  'aes192gmac',  'aes256gmac',
            '3des',   'blowfish128', 'blowfish192', 'blowfish256', 'camellia128', 'camellia192',
            'camellia256'
        ],
    };
    $params->{p1authen} = {
        ref       => 'ARRAY',
        required  => 'true',
        non_blank => 'true',
        values    => [ 'md5', 'sha1', 'sha256', 'sha384', 'sha512', 'aesxcbc', 'aes128gmac', 'aes192gmac', 'aes256gmac' ],
    };
    $params->{p1dhgroup} = {
        ref       => 'ARRAY',
        required  => 'true',
        non_blank => 'true',
        values    => [ 'modp768', 'modp1024', 'modp1536', 'modp2048', 'modp3072', 'modp4096', 'modp6144', 'modp8192' ],
    };

    $params->{p2encrypt} = {
        ref       => 'ARRAY',
        required  => 'true',
        non_blank => 'true',
        values    => [
            'aes128', 'aes192',      'aes256',      'aes128gmac',  'aes192gmac',  'aes256gmac',
            '3des',   'blowfish128', 'blowfish192', 'blowfish256', 'camellia128', 'camellia192',
            'camellia256'
        ],
    };
    $params->{p2authen} = {
        ref       => 'ARRAY',
        required  => 'true',
        non_blank => 'true',
        values    => [ 'md5', 'sha1', 'sha256', 'sha384', 'sha512', 'aesxcbc', 'aes128gmac', 'aes192gmac', 'aes256gmac' ],
    };

    if ($json_obj->{profile} eq 'site_to_site' or $json_obj->{profile} eq 'tunnel') {
        $params->{remote} = {
            required     => 'true',
            non_blank    => 'true',
            valid_format => 'ip_addr',
        };

        $params->{p2dhgroup} = {
            ref       => 'ARRAY',
            required  => 'true',
            non_blank => 'true',
            values    => [ 'modp768', 'modp1024', 'modp1536', 'modp2048', 'modp3072', 'modp4096', 'modp6144', 'modp8192' ],
        };
        $params->{p2prfunc} = {
            ref       => 'ARRAY',
            required  => 'true',
            non_blank => 'true',
            values    => [ 'prfmd5', 'prfsha1', 'prfsha256', 'prfsha384', 'prfsha512', 'prfaes', 'prfaesxcbc', 'prfaescmac' ],
        };
    }
    if ($json_obj->{profile} eq 'site_to_site') {
        $params->{localnet} = {
            function  => \&validIpAndNet,
            required  => 'true',
            non_blank => 'true',
        };
        $params->{remotenet} = {
            function  => \&validIpAndNet,
            required  => 'true',
            non_blank => 'true',
        };
    }

    if ($json_obj->{profile} eq 'tunnel' or $json_obj->{profile} eq 'remote_access') {
        $params->{localip} = {
            required     => 'true',
            non_blank    => 'true',
            valid_format => 'ip_addr',
        };
        $params->{localmask} = {
            required     => 'true',
            non_blank    => 'true',
            valid_format => 'ip_mask',
        };
        $params->{localtunip} = {
            required     => 'true',
            non_blank    => 'true',
            valid_format => 'ip_addr',
        };
        $params->{localtunmask} = {
            required     => 'true',
            non_blank    => 'true',
            valid_format => 'ip_mask',
        };
    }
    if ($json_obj->{profile} eq 'tunnel') {
        $params->{remoteip} = {
            required     => 'true',
            non_blank    => 'true',
            valid_format => 'ip_addr',
        };
        $params->{remotetunip} = {
            required     => 'true',
            non_blank    => 'true',
            valid_format => 'ip_addr',
        };
        $params->{remotemask} = {
            required     => 'true',
            non_blank    => 'true',
            valid_format => 'ip_mask',
        };
    }
    if ($json_obj->{profile} eq 'remote_access') {
        $params->{remotetunrange} = {
            required     => 'true',
            non_blank    => 'true',
            valid_format => 'ip_addr_range',
        };
    }

    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    if ($json_obj->{profile} eq "site_to_site") {
        require Relianoid::HTTP::Controllers::API::VPN::SiteToSite;
        &_add_vpn_site_to_site_controller($json_obj);
    }

    if ($json_obj->{profile} eq "tunnel") {
        require Relianoid::HTTP::Controllers::API::VPN::Tunnel;
        &_add_vpn_tunnel_controller($json_obj);
    }

    if ($json_obj->{profile} eq "remote_access") {
        require Relianoid::HTTP::Controllers::API::VPN::RemoteAccess;
        &_add_vpn_remote_access_controller($json_obj);
    }

    my $msg = "Error trying to create new VPN.";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

1;
