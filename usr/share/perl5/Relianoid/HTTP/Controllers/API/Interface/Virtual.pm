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

Relianoid::HTTP::Controllers::API::Interface::Virtual

=cut

my $eload = eval { require Relianoid::ELoad };

# POST /interfaces/virtual Create a new virtual network interface
sub add_virtual_controller ($json_obj) {
    my $desc = "Add a virtual interface";

    my $nic_re         = &getValidFormat('nic_interface');
    my $vlan_re        = &getValidFormat('vlan_interface');
    my $virtual_tag_re = &getValidFormat('virtual_tag');

    my $params = &getAPIModel("virtual-create.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # virtual_name = pather_name + . + virtual_tag
    # size < 16: size = pather_name:virtual_name
    if (length $json_obj->{name} > 15) {
        my $msg = "Virtual interface name has a maximum length of 15 characters";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    unless ($json_obj->{name} =~ /^($nic_re|$vlan_re):($virtual_tag_re)$/) {
        my $msg = "Interface name is not valid";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    $json_obj->{parent} = $1;
    $json_obj->{vini}   = $2;

    my $vlan_tag_re = &getValidFormat('vlan_tag');
    $json_obj->{parent} =~ /^($nic_re)(?:\.($vlan_tag_re))?$/;
    $json_obj->{dev}  = $1;
    $json_obj->{vlan} = $2;

    require Relianoid::Net::Validate;
    $json_obj->{ip_v} = ipversion($json_obj->{ip});

    # validate PARENT
    # virtual interfaces require a configured parent interface
    my $parent_exist = &ifexist($json_obj->{parent});
    my $if_parent    = &getInterfaceConfig($json_obj->{parent}, $json_obj->{ip_v});

    unless ($parent_exist eq "true" && $if_parent) {
        my $msg = "The parent interface $json_obj->{parent} doesn't exist.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    if ($if_parent->{type} eq 'nic' and not $if_parent->{addr}) {
        my $msg = "The parent interface $json_obj->{parent} must be configured.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # Check network interface errors
    # A virtual interface cannnot exist in two stacks
    my $if_ref = &getInterfaceConfig($json_obj->{name}, $json_obj->{ip_v});

    if ($if_ref) {
        my $msg = "Network interface $json_obj->{name} already exists.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # Check new IP address is not in use
    require Relianoid::Net::Util;

    my @activeips = &listallips();

    for my $ip (@activeips) {
        if ($ip eq $json_obj->{ip}) {
            my $msg = "IP address $json_obj->{ip} already in use.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # setup parameters of virtual interface
    $if_ref = &getInterfaceConfig($json_obj->{parent}, $json_obj->{ip_v});

    # $json_obj->{addr} must exist in getInterfaceSystemStatus()
    $json_obj->{addr}  = $json_obj->{ip};
    $if_ref->{status}  = &getInterfaceSystemStatus($json_obj);
    $if_ref->{name}    = $json_obj->{name};
    $if_ref->{vini}    = $json_obj->{vini};
    $if_ref->{addr}    = $json_obj->{ip};
    $if_ref->{gateway} = "" if !$if_ref->{gateway};
    $if_ref->{type}    = 'virtual';
    $if_ref->{dhcp}    = 'false';

    # GCP and other services will create /32 parent and virtual interfaces
    # so do not limit this if the system allows it
    # unless (&validateGateway($if_parent->{addr}, $if_ref->{mask}, $if_ref->{addr})) {
    #     my $msg = "IP Address $json_obj->{ip} must be same net than the parent interface.";
    #     return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    # }

    require Relianoid::Net::Core;
    require Relianoid::Net::Route;

    eval {
        die if &addIp($if_ref);

        my $state = &upIf($if_ref, 'writeconf');

        if ($state == 0) {
            $if_ref->{status} = "up";
            &applyRoutes("local", $if_ref);
        }

        &setInterfaceConfig($if_ref) or die;
        if ($eload) {
            &eload(
                module => 'Relianoid::EE::RBAC::Group::Config',
                func   => 'addRBACUserResource',
                args   => [ $if_ref->{name}, 'interfaces' ],
            );
        }
    };

    if ($@) {
        &log_error("Module failed: $@", "net");
        my $msg = "The $json_obj->{name} virtual network interface can't be created";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    &eload(
        module => 'Relianoid::EE::Cluster',
        func   => 'runClusterRemoteManager',
        args   => [ 'interface', 'start', $if_ref->{name} ],
    ) if ($eload);

    my $body = {
        description => $desc,
        params      => {
            name    => $if_ref->{name},
            ip      => $if_ref->{addr},
            netmask => $if_ref->{mask},
            gateway => $if_ref->{gateway},
            mac     => $if_ref->{mac},
        },
        message => "The $if_ref->{name} Virtual interface has been created successfully"
    };

    return &httpResponse({ code => 201, body => $body });
}

sub delete_virtual_controller ($virtual) {
    require Relianoid::Net::Interface;

    my $desc   = "Delete virtual interface";
    my $ip_v   = 4;
    my $if_ref = &getInterfaceConfig($virtual, $ip_v);

    if (!$if_ref) {
        my $msg = "The virtual interface $virtual doesn't exist.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if some farm is using this ip
    require Relianoid::Farm::Base;

    my @farms = &getFarmListByVip($if_ref->{addr});

    if (@farms) {
        my $str = join(', ', @farms);
        my $msg = "This interface is being used as farm vip in the farm(s): $str.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my @child = &getInterfaceChild($virtual);

    if (@child) {
        my $child_string = join(', ', @child);
        my $msg          = "Before removing $virtual interface, disable the floating IPs: $child_string.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    require Relianoid::Net::Route;
    require Relianoid::Net::Core;

    eval {
        if ($eload) {
            &eload(
                module => 'Relianoid::EE::Cluster',
                func   => 'runClusterRemoteManager',
                args   => [ 'interface', 'stop', $if_ref->{name} ],
            );

            &eload(
                module => 'Relianoid::EE::Net::Routing',
                func   => 'delRoutingDependIfaceVirt',
                args   => [$if_ref],
            );
        }

        if ($if_ref->{status} eq 'up') {
            # removing before in the remote node
            die if &delRoutes("local", $if_ref);
            die if &downIf($if_ref, 'writeconf');
        }
        die if &delIf($if_ref);
    };

    if ($@) {
        &log_error("Module failed: $@", "net");
        my $msg = "The virtual interface $virtual can't be deleted";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    if ($eload) {
        &eload(
            module => 'Relianoid::EE::Cluster',
            func   => 'runClusterRemoteManager',
            args   => [ 'interface', 'delete', $if_ref->{name} ],
        );
    }

    my $message = "The virtual interface $virtual has been deleted.";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    return &httpResponse({ code => 200, body => $body });
}

sub list_virtual_controller () {
    require Relianoid::Net::Interface;

    my $desc        = "List virtual interfaces";
    my $output_list = &get_virtual_list_struct();

    if ($eload) {
        $output_list = &eload(
            module => 'Relianoid::EE::RBAC::Group::Core',
            func   => 'getRBACUserSet',
            args   => [ 'interfaces', $output_list ],
        );
    }

    my $body = {
        description => $desc,
        interfaces  => $output_list,
    };

    return &httpResponse({ code => 200, body => $body });
}

sub get_virtual_controller ($virtual) {
    require Relianoid::Net::Interface;

    my $desc      = "Show virtual interface $virtual";
    my $interface = &get_virtual_struct($virtual);

    unless ($interface) {
        my $msg = "Virtual interface not found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $body = {
        description => $desc,
        interface   => $interface,
    };

    return &httpResponse({ code => 200, body => $body });
}

sub actions_virtual_controller ($json_obj, $virtual) {
    require Relianoid::Net::Interface;

    my $desc = "Action on virtual interface";
    my $ip_v = 4;

    my $params = &getAPIModel("virtual-action.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # validate VLAN
    unless (grep { $virtual eq $_->{name} } &getInterfaceTypeList('virtual')) {
        my $msg = "Virtual interface not found";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $if_ref = &getInterfaceConfig($virtual, $ip_v);

    if ($json_obj->{action} eq "up") {
        require Relianoid::Net::Core;

        &addIp($if_ref);

        # Check the parent's status before up the interface
        my $parent_if_name   = &getParentInterfaceName($if_ref->{name});
        my $parent_if_status = 'up';

        if ($parent_if_name) {
            my $parent_if_ref = &getSystemInterface($parent_if_name);
            $parent_if_status = &getInterfaceSystemStatus($parent_if_ref);
        }

        unless ($parent_if_status eq 'up') {
            my $msg = "The interface $if_ref->{name} has a parent interface DOWN, check the interfaces status";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        my $state = &upIf($if_ref, 'writeconf');

        if (!$state) {
            require Relianoid::Net::Route;
            &applyRoutes("local", $if_ref);

            if ($eload) {
                &eload(
                    module => 'Relianoid::EE::Net::Routing',
                    func   => 'applyRoutingDependIfaceVirt',
                    args   => [ 'add', $if_ref ]
                );
            }
        }
        else {
            my $msg = "The interface could not be set UP";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        if ($eload) {
            &eload(
                module => 'Relianoid::EE::Cluster',
                func   => 'runClusterRemoteManager',
                args   => [ 'interface', 'start', $if_ref->{name} ],
            );
        }
    }
    elsif ($json_obj->{action} eq "down") {
        require Relianoid::Net::Core;

        my $state = &downIf($if_ref, 'writeconf');

        if ($state) {
            my $msg = "The interface could not be set DOWN";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        if ($eload) {
            &eload(
                module => 'Relianoid::EE::Cluster',
                func   => 'runClusterRemoteManager',
                args   => [ 'interface', 'stop', $if_ref->{name} ],
            );
        }
    }

    my $body = {
        description => $desc,
        params      => { action => $json_obj->{action} },
        message     => "The $if_ref->{name} Virtual interface is $json_obj->{action}"
    };

    return &httpResponse({ code => 200, body => $body });
}

sub modify_virtual_controller ($json_obj, $virtual) {
    require Relianoid::Net::Interface;
    require Net::Netmask;

    my $desc   = "Modify virtual interface";
    my $if_ref = &getInterfaceConfig($virtual);
    my $old_ip = $if_ref->{addr};

    my $params = &getAPIModel("virtual-modify.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    unless ($if_ref) {
        my $msg = "Virtual interface not found";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (my @child = &getInterfaceChild($virtual)) {
        my $child_string = join(', ', @child);
        my $msg          = "Before modifying $virtual interface, disable the floating IPs: $child_string.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    require Relianoid::Farm::Base;

    my @farms = &getFarmListByVip($if_ref->{addr});

    # check if ip exists in other interface
    if ($json_obj->{ip}) {
        if ($json_obj->{ip} ne $if_ref->{addr}) {
            require Relianoid::Net::Util;

            if (grep { $json_obj->{ip} eq $_ } &listallips()) {
                my $msg = "The IP address is already in use for other interface.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        if (@farms and $json_obj->{force} ne 'true') {
            my $str = join(', ', @farms);
            my $msg = "The IP is being used as farm vip in the farm(s): $str."    #
              . " If you are sure, repeat with parameter 'force'. All farms using this interface will be restarted.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    require Relianoid::Net::Validate;
    my $if_ref_parent = &getInterfaceConfig($if_ref->{parent});

    unless (&validateGateway($if_ref_parent->{addr}, $if_ref_parent->{mask}, $json_obj->{ip})) {
        my $msg = "IP address $json_obj->{ip} must be on the same network than the parent interface.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    require Relianoid::Net::Core;

    my $state = $if_ref->{status};
    &downIf($if_ref) if $state eq 'up';

    if ($eload) {
        &eload(
            module => 'Relianoid::EE::Cluster',
            func   => 'runClusterRemoteManager',
            args   => [ 'interface', 'stop', $if_ref->{name} ],
        );
    }

    eval {
        # Set the new params
        $if_ref->{addr} = $json_obj->{ip};

        if ($state eq 'up') {
            require Relianoid::Net::Route;
            die if &addIp($if_ref);
            &upIf($if_ref);
            &applyRoutes("local", $if_ref);
        }

        # Add new IP, netmask and gateway
        &setInterfaceConfig($if_ref) or die;

        if ($eload and $old_ip) {
            &eload(
                module => 'Relianoid::EE::Net::Routing',
                func   => 'updateRoutingVirtualIfaces',
                args   => [ $if_ref->{parent}, $old_ip, $json_obj->{ip} ],
            );
        }

        # change farm vip,
        if (@farms) {
            require Relianoid::Farm::Config;

            &setAllFarmByVip($json_obj->{ip}, \@farms);
        }
    };

    if ($@) {
        &log_error("Module failed: $@", "net");
        my $msg = "Errors found trying to modify interface $virtual";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    if ($eload) {
        &eload(
            module => 'Relianoid::EE::Cluster',
            func   => 'runClusterRemoteManager',
            args   => [ 'interface', 'start', $if_ref->{name} ],
        );
        &eload(
            module => 'Relianoid::EE::Cluster',
            func   => 'runClusterRemoteManager',
            args   => [ 'farm', 'restart_farms', @farms ],
        );
    }

    my $body = {
        description => $desc,
        params      => $json_obj,
        message     => "The $if_ref->{name} Virtual interface has been updated successfully"
    };

    return &httpResponse({ code => 200, body => $body });
}

1;
