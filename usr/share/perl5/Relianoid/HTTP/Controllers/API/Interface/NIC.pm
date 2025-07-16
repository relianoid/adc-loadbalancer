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

Relianoid::HTTP::Controllers::API::Interface::NIC

=cut

sub delete_nic_controller ($nic) {
    require Relianoid::Net::Core;
    require Relianoid::Net::Route;
    require Relianoid::Net::Interface;

    my $desc   = "Delete nic interface";
    my $ip_v   = 4;
    my $if_ref = &getInterfaceConfig($nic, $ip_v);

    if (!$if_ref) {
        my $msg = "There is no configuration for the network interface.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    if ($eload) {
        if ($if_ref->{addr}) {
            my $msg = &eload(
                module => 'Relianoid::EE::Net::Ext',
                func   => 'isManagementIP',
                args   => [ $if_ref->{addr} ],
            );
            if ($msg) {
                $msg = "The interface cannot be modified. $msg";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        my $zcl_conf = &eload(
            module => 'Relianoid::EE::Cluster',
            func   => 'getClusterConfig',
        );

        if (defined $zcl_conf->{_}{interface}
            and $zcl_conf->{_}{interface} eq $if_ref->{name})
        {
            my $msg = "The cluster interface $if_ref->{name} cannot be modified.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        if (defined $if_ref->{is_slave} and $if_ref->{is_slave} eq "true") {
            my $msg = "The slave interface $if_ref->{name} cannot be modified.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        if (defined $zcl_conf->{_}{track_interface}) {
            my @track_interface =
              split(/\s/, $zcl_conf->{_}{track_interface});
            if (grep { $_ eq $if_ref->{name} } @track_interface) {
                my $msg = "The interface $if_ref->{name} cannot be modified because it is been tracked by the cluster.
						If you still want to modify it, remove it from the cluster track interface list.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }
    }

    # not delete the interface if it has some vlan configured
    my @child = &getInterfaceChild($nic);
    if (@child) {
        my $child_string = join(', ', @child);
        my $msg          = "It is not possible to delete $nic because there are virtual interfaces using it: $child_string.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if some farm is using this ip
    if ($if_ref->{addr}) {
        require Relianoid::Farm::Base;
        my @farms = &getFarmListByVip($if_ref->{addr});
        if (@farms) {
            my $str = join(', ', @farms);
            my $msg = "This interface is being used as vip in the farm(s): $str.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    if ($eload && $if_ref->{addr}) {
        # check if some VPN is using this ip
        require Relianoid::VPN::Util;
        my $vpns = getVpnByIp($if_ref->{addr});

        if (@{$vpns}) {
            my $str = join(', ', @{$vpns});
            my $msg = "The interface is being used as Local Gateway in VPN(s): $str";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        $vpns = getVpnByNet($if_ref->{net});

        if (@{$vpns}) {
            my $str = join(', ', @{$vpns});
            my $msg = "The interface is being used as Local Network in VPN(s): $str";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    eval {
        die if &delRoutes("local", $if_ref);
        die if &delIf($if_ref);
    };

    if ($@) {
        &log_error("Module failed: $@", 'net');
        my $msg = "The configuration for the network interface $nic can't be deleted.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $message = "The configuration for the network interface $nic has been deleted.";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET /interfaces Get params of the interfaces
sub list_nic_controller () {
    require Relianoid::Net::Interface;

    my $desc         = "List NIC interfaces";
    my $nic_list_ref = &get_nic_list_struct();

    my $body = {
        description => $desc,
        interfaces  => $nic_list_ref,
    };

    return &httpResponse({ code => 200, body => $body });
}

sub get_nic_controller ($nic) {
    require Relianoid::Net::Interface;

    my $desc      = "Show NIC interface";
    my $interface = &get_nic_struct($nic);

    unless ($interface) {
        my $msg = "Nic interface not found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $body = {
        description => $desc,
        interface   => $interface,
    };

    return &httpResponse({ code => 200, body => $body });
}

sub actions_nic_controller ($json_obj, $nic) {
    require Relianoid::Net::Interface;

    my $desc = "Action on nic interface";
    my $ip_v = 4;

    # validate NIC
    unless (grep { $nic eq $_->{name} } &getInterfaceTypeList('nic')) {
        my $msg = "Nic interface not found";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # Check allowed parameters
    my $params = &getAPIModel("nic-action.json");
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    if ($eload) {
        my $zcl_conf = &eload(
            module => 'Relianoid::EE::Cluster',
            func   => 'getClusterConfig',
        );

        if (defined $zcl_conf->{_}{track_interface}) {
            my @track_interface = split(/\s/, $zcl_conf->{_}{track_interface});

            if (grep { $_ eq $nic } @track_interface) {
                my $msg = "The interface $nic cannot be modified because it is been tracked by the cluster. "
                  . "If you still want to modify it, remove it from the cluster track interface list.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }
    }

    my $if_ref = &getInterfaceConfig($nic, $ip_v);

    # validate action parameter
    if ($json_obj->{action} eq "up") {
        require Relianoid::Net::Core;
        require Relianoid::Net::Route;

        # Delete routes in case that it is not a vini
        if ($if_ref->{addr}) {
            &delRoutes("local", $if_ref);
            &addIp($if_ref);
        }

        my $state = &upIf($if_ref, 'writeconf');

        if (!$state) {
            require Relianoid::Net::Util;
            &applyRoutes("local", $if_ref) if $if_ref->{addr};

            # put all dependant interfaces up
            &setIfacesUp($nic, "vlan");
            &setIfacesUp($nic, "vini") if $if_ref;
        }
        else {
            my $msg = "The interface $nic could not be set UP";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }
    elsif ($json_obj->{action} eq "down") {
        if ($eload && $if_ref->{addr}) {
            my $msg = &eload(
                module => 'Relianoid::EE::Net::Ext',
                func   => 'isManagementIP',
                args   => [ $if_ref->{addr} ],
            );
            if ($msg) {
                $msg = "The interface cannot be stopped. $msg";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        require Relianoid::Net::Core;
        my $state = &downIf($if_ref, 'writeconf');

        if ($state) {
            my $msg = "The interface $nic could not be set DOWN";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    my $msg  = "The $nic NIC is $json_obj->{action}";
    my $body = {
        description => $desc,
        params      => { action => $json_obj->{action} },
        message     => $msg
    };

    return &httpResponse({ code => 200, body => $body });
}

sub modify_nic_controller ($json_obj, $nic) {
    require Relianoid::Net::Interface;
    require Relianoid::Net::Core;
    require Relianoid::Net::Route;
    require Relianoid::Net::Validate;

    my $desc = "Configure NIC interface";

    # validate NIC NAME
    my $type = &getInterfaceType($nic);

    unless ($type eq 'nic') {
        my $msg = "NIC interface not found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }
    my $params = &getAPIModel("nic-modify.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # Delete old interface configuration
    my $if_ref = &getInterfaceConfig($nic) // &getSystemInterface($nic);

    # Ignore the dhcp parameter if it is equal to the configured one
    delete $json_obj->{dhcp}
      if (exists $json_obj->{dhcp} && $json_obj->{dhcp} eq $if_ref->{dhcp});

    my @child = &getInterfaceChild($nic);

    if (exists $json_obj->{dhcp}) {
        # only allow dhcp when no other parameter was sent
        if ($json_obj->{dhcp} eq 'true') {
            if (   exists $json_obj->{ip}
                or exists $json_obj->{netmask}
                or exists $json_obj->{gateway})
            {
                my $msg = "It is not possible set 'ip', 'netmask' or 'gateway' while 'dhcp' is going to be set up.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }
        elsif (!exists $json_obj->{ip}) {
            if (@child) {
                my $msg =
                  "This interface has appending some virtual interfaces, please, set up a new 'ip' in the current networking range.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }
    }

    # check if network is correct

    my $new_if;
    if ($if_ref) {
        $new_if = {
            addr    => $json_obj->{ip}      // $if_ref->{addr},
            mask    => $json_obj->{netmask} // $if_ref->{mask},
            gateway => $json_obj->{gateway} // $if_ref->{gateway},
        };
    }
    else {
        $new_if = {
            addr    => $json_obj->{ip},
            mask    => $json_obj->{netmask},
            gateway => $json_obj->{gateway} // undef,
        };
    }

    # Make sure the address, mask and gateway belong to the same stack
    if ($new_if->{addr}) {
        my $ip_v = &ipversion($new_if->{addr});
        my $gw_v = &ipversion($new_if->{gateway});

        if (!&validateNetmask($new_if->{mask}, $ip_v)) {
            my $msg = "The netmask is not valid";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        if ($new_if->{gateway} && $ip_v ne $gw_v) {
            my $msg = "Invalid IP stack version match.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    if (exists $json_obj->{ip} or exists $json_obj->{netmask}) {
        # check ip and netmask are configured
        unless ($new_if->{addr} ne "" and $new_if->{mask} ne "") {
            my $msg =
              "The networking configuration is not valid. It needs an IP ('$new_if->{addr}') and a netmask ('$new_if->{mask}')";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        # Do not modify gateway or netmask if exists a virtual interface using this interface
        my @wrong_conf;
        for my $child_name (@child) {
            my $child_if = &getInterfaceConfig($child_name);
            unless (&validateGateway($child_if->{addr}, $new_if->{mask}, $new_if->{addr})) {
                push @wrong_conf, $child_name;
            }
        }

        if (@wrong_conf) {
            my $child_string = join(', ', @wrong_conf);
            my $msg          = "The virtual interface(s): '$child_string' will not be compatible with the new configuration.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # check the gateway is in network
    if ($new_if->{gateway}) {
        unless (&validateGateway($new_if->{addr}, $new_if->{mask}, $new_if->{gateway})) {
            my $msg = "The gateway is not valid for the network.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # check if network exists in other interface
    if ($json_obj->{ip} or $json_obj->{netmask}) {
        my $if_used =
          &checkNetworkExists($new_if->{addr}, $new_if->{mask}, $nic);
        if ($if_used) {
            my $msg = "The network already exists in the interface $if_used.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # Check new IP address is not in use
    my $different_ip = ((not $if_ref->{addr}) or ($new_if->{addr} ne $if_ref->{addr}));
    if ($json_obj->{ip} and $different_ip) {
        require Relianoid::Net::Util;
        my @activeips = &listallips();
        for my $ip (@activeips) {
            if ($ip eq $json_obj->{ip}) {
                my $msg = "IP address $json_obj->{ip} already in use.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }
    }

    my @farms;
    my $vpns_localgw  = [];
    my $vpns_localnet = [];
    my $warning_msg;

    if (   exists $json_obj->{ip}
        or (exists $json_obj->{dhcp})
        or (exists $json_obj->{netmask}))
    {
        if (exists $json_obj->{ip}
            or (exists $json_obj->{dhcp}))
        {
            if ($eload) {
                if ($if_ref->{addr}) {
                    my $msg = &eload(
                        module => 'Relianoid::EE::Net::Ext',
                        func   => 'isManagementIP',
                        args   => [ $if_ref->{addr} ],
                    );
                    if ($msg) {
                        $msg = "The interface cannot be modified. $msg";
                        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
                    }
                }

                my $zcl_conf = &eload(
                    module => 'Relianoid::EE::Cluster',
                    func   => 'getClusterConfig',
                );

                if (defined $zcl_conf->{_}{interface}
                    and $zcl_conf->{_}{interface} eq $if_ref->{name})
                {
                    my $msg = "The cluster interface $if_ref->{name} cannot be modified.";
                    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
                }

                if (defined $if_ref->{is_slave}
                    and $if_ref->{is_slave} eq "true")
                {
                    my $msg = "The slave interface $if_ref->{name} cannot be modified.";
                    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
                }
            }

            # check if some farm is using this ip
            if ($if_ref->{addr}) {
                require Relianoid::Farm::Base;
                @farms = &getFarmListByVip($if_ref->{addr});
            }

            require Relianoid::VPN::Util;
            $vpns_localgw = getVpnByIp($if_ref->{addr});
        }

        # check if its a new network and a vpn using old network
        if (exists $json_obj->{ip} or exists $json_obj->{netmask}) {
            # check if network is changed
            my $mask = $json_obj->{netmask} // $if_ref->{mask};

            if (not &validateGateway($if_ref->{addr}, $if_ref->{mask}, $json_obj->{ip})
                or $if_ref->{mask} ne $mask)
            {
                my $net = NetAddr::IP->new($if_ref->{addr}, $if_ref->{mask})->cidr();

                require Relianoid::VPN::Util;
                $vpns_localnet = getVpnByNet($net);
            }
        }

        if (@farms or @{$vpns_localgw} or @{$vpns_localnet}) {
            if (    not exists $json_obj->{ip}
                and exists $json_obj->{dhcp}
                and $json_obj->{dhcp} eq 'false')
            {
                my $str_objects;
                my $str_function;
                if (@farms) {
                    $str_objects  = " and farms";
                    $str_function = " and farm VIP";
                }
                if (@{$vpns_localgw} or @{$vpns_localnet}) {
                    $str_objects .= " and vpns";
                }
                if (@{$vpns_localgw}) {
                    $str_function .= " and Local Gateway";
                }
                if (@{$vpns_localnet}) {
                    $str_function .= " and Local Network";
                }
                $str_objects  = substr($str_objects,  5);
                $str_function = substr($str_function, 5);

                my $msg =
                  "This interface is been used by some $str_objects, please, set up a new 'ip' in order to be used as $str_function.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }

            if (!$json_obj->{force} || $json_obj->{force} ne 'true') {
                my $str_objects;
                my $str_function;
                if (@farms) {
                    $str_objects  = " and farms";
                    $str_function = " and as farm VIP in the farm(s): " . join(', ', @farms);
                }
                if (@{$vpns_localgw} or @{$vpns_localnet}) {
                    $str_objects .= " and vpns";
                }
                if (@{$vpns_localgw}) {
                    $str_function .= " and as Local Gateway in the VPN(s): " . join(', ', @{$vpns_localgw});
                }
                if (@{$vpns_localnet}) {
                    $str_function .= " and as Local Network in the VPN(s): " . join(', ', @{$vpns_localnet});
                }
                $str_objects  = substr($str_objects,  5);
                $str_function = substr($str_function, 5);

                my $msg =
                  "The IP is being used $str_function. If you are sure, repeat with parameter 'force'. All $str_objects using this interface will be restarted.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }
    }

    # END CHECKS

    if ($if_ref->{addr}) {
        # remove custom routes
        if ($eload) {
            &eload(
                module => 'Relianoid::EE::Net::Routing',
                func   => 'updateRoutingVirtualIfaces',
                args   => [ $if_ref->{parent}, $json_obj->{ip} // $if_ref->{addr} ],
            );
        }

        # Delete old IP and Netmask from system to replace it
        &delIp($if_ref->{name}, $if_ref->{addr}, $if_ref->{mask});

        # Remove routes if the interface has its own route table: nic and vlan
        &delRoutes("local", $if_ref);

        $if_ref = undef;
    }

    # Setup new interface configuration structure
    $if_ref            = &getInterfaceConfig($nic) // &getSystemInterface($nic);
    $if_ref->{addr}    = $json_obj->{ip}      if exists $json_obj->{ip};
    $if_ref->{mask}    = $json_obj->{netmask} if exists $json_obj->{netmask};
    $if_ref->{gateway} = $json_obj->{gateway} if exists $json_obj->{gateway};
    $if_ref->{ip_v}    = &ipversion($if_ref->{addr});
    $if_ref->{net}     = &getAddressNetwork($if_ref->{addr}, $if_ref->{mask}, $if_ref->{ip_v});
    $if_ref->{dhcp}    = $json_obj->{dhcp} if exists $json_obj->{dhcp};

    # set DHCP
    my $set_flag        = 1;
    my $nic_config_file = "";
    if (exists $json_obj->{dhcp}) {
        if ($json_obj->{dhcp} eq "true") {
            require Relianoid::Lock;
            $nic_config_file = &getGlobalConfiguration('configdir') . "/if_$if_ref->{name}_conf";
            &lockResource($nic_config_file, "l");
        }

        my $func = ($json_obj->{dhcp} eq 'true') ? "enableDHCP" : "disableDHCP";
        &eload(
            module => 'Relianoid::EE::Net::DHCP',
            func   => $func,
            args   => [$if_ref],
        );

        if (   $json_obj->{dhcp} eq 'false' and not exists $json_obj->{ip}
            or $json_obj->{dhcp} eq 'true')
        {
            $set_flag = 0;
        }
    }
    if (!&setInterfaceConfig($if_ref)) {
        if ($json_obj->{dhcp} eq "true") {
            require Relianoid::Lock;
            &lockResource($nic_config_file, "ud");
        }
        my $msg = "Errors found trying to modify interface $nic";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # Free the resource
    if ($json_obj->{dhcp} and $json_obj->{dhcp} eq "true") {
        require Relianoid::Lock;
        &lockResource($nic_config_file, "ud");
    }

    # set up
    if ($if_ref->{addr} and $if_ref->{mask} and $set_flag) {
        eval {
            # Add new IP, netmask and gateway
            # sometimes there are expected errors pending to be controlled
            &addIp($if_ref);

            # Writing new parameters in configuration file
            &writeRoutes($if_ref->{name});

            # Put the interface up
            my $previous_status = $if_ref->{status};

            if ($previous_status eq "up") {
                if (&upIf($if_ref, 'writeconf') == 0) {
                    $if_ref->{status} = "up";
                    &applyRoutes("local", $if_ref);
                    if ($if_ref->{ip_v} eq "4") {
                        my $if_gw = &getGlobalConfiguration('defaultgwif');
                        if ($if_ref->{name} eq $if_gw) {
                            my $defaultgw = &getGlobalConfiguration('defaultgw');
                            &applyRoutes("global", $if_ref, $defaultgw);
                        }
                    }
                    elsif ($if_ref->{ip_v} eq "6") {
                        my $if_gw = &getGlobalConfiguration('defaultgwif6');
                        if ($if_ref->{name} eq $if_gw) {
                            my $defaultgw = &getGlobalConfiguration('defaultgw6');
                            &applyRoutes("global", $if_ref, $defaultgw);
                        }
                    }
                }
                else {
                    $if_ref->{status} = $previous_status;
                }
            }

            # if the GW is changed, change it in all appending virtual interfaces
            if (exists $json_obj->{gateway}) {
                for my $appending (&getInterfaceChild($nic)) {
                    my $app_config = &getInterfaceConfig($appending);
                    $app_config->{gateway} = $json_obj->{gateway};
                    &setInterfaceConfig($app_config);
                }
            }

            # modify netmask on all dependent interfaces
            if (exists $json_obj->{netmask}) {
                for my $appending (&getInterfaceChild($nic)) {
                    my $app_config = &getInterfaceConfig($appending);
                    &delRoutes("local", $app_config);
                    &downIf($app_config);
                    $app_config->{mask} = $json_obj->{netmask};
                    &setInterfaceConfig($app_config);
                }
            }

            # put all dependent interfaces up
            require Relianoid::Net::Util;
            &setIfacesUp($nic, "vini");

            # change farm vip,
            if (@farms) {
                require Relianoid::Farm::Config;
                &setAllFarmByVip($json_obj->{ip}, \@farms);
                &reloadFarmsSourceAddress();
            }

            if (@{$vpns_localgw}) {
                require Relianoid::VPN::Config;
                my $error = setAllVPNLocalGateway($if_ref->{addr}, $vpns_localgw);

                $warning_msg .= $error->{desc}
                  if $error->{code};
            }

            if (@{$vpns_localnet}) {
                my $net = NetAddr::IP->new($if_ref->{net}, $if_ref->{mask})->cidr();

                require Relianoid::VPN::Config;
                my $error = setAllVPNLocalNetwork($net, $vpns_localnet);

                $warning_msg .= $error->{desc}
                  if $error->{code};
            }
        };

        if ($@) {
            &log_error("Module failed: $@", "net");
            my $msg = "Errors found trying to modify interface $nic";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    my $iface_out = &get_nic_struct($nic);
    my $body      = {
        description => $desc,
        params      => $iface_out,
        message     => "The $nic NIC has been updated successfully."
    };
    $body->{warning} = $warning_msg if ($warning_msg);

    return &httpResponse({ code => 200, body => $body });
}

1;
