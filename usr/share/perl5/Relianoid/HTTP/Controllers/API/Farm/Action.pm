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

use Relianoid::Farm::Core;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::Farm::Action

=cut

my $eload = eval { require Relianoid::ELoad };

# PUT /farms/<farmname>/actions Set an action in a Farm
sub actions_farm_controller ($json_obj, $farmname) {
    require Relianoid::Farm::Action;
    require Relianoid::Farm::Base;

    my $desc = "Farm actions";

    # validate FARM NAME
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) =~ /http/) {
        require Relianoid::Farm::HTTP::Config;
        my $err_msg = &getHTTPFarmConfigErrorMessage($farmname);

        if ($err_msg) {
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $err_msg });
        }
    }

    my $params = &getAPIModel("farm-action.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    if ($json_obj->{action} eq "stop") {
        my $status = &runFarmStop($farmname, "true");

        if ($status != 0) {
            my $msg = "Error trying to set the action stop in farm $farmname.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }
    elsif ($json_obj->{action} eq "start") {
        require Relianoid::Net::Interface;

        # check if the ip exists in any interface
        my $ip = &getFarmVip("vip", $farmname);

        if (!&getIpAddressExists($ip)) {
            my $msg = "The virtual ip $ip is not defined in any interface.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        require Relianoid::Farm::Base;
        require Relianoid::Farm::Action;
        if (&getFarmRestartStatus($farmname)) {
            my $msg = "The farm has changes pending of applying, it has to be restarted.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        require Relianoid::Farm::Core;
        my $farm_type = &getFarmType($farmname);
        if ($farm_type ne "datalink") {
            my $if_name = &getInterfaceByIp($ip);
            my $if_ref  = &getInterfaceConfig($if_name);
            if (&getInterfaceSystemStatus($if_ref) ne "up") {
                my $msg = "The virtual IP '$ip' is not UP";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
            if ($farm_type eq "http" or $farm_type eq "https") {
                require Relianoid::Farm::HTTP::Action;
                &checkFarmHTTPSystemStatus($farmname, "down", "true");
            }

            my $port = &getFarmVip("vipp", $farmname);
            if (!&validatePort($ip, $port, undef, $farmname)) {
                my $msg = "There is another farm using the ip '$ip' and the port '$port'";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        my $status = &runFarmStart($farmname, "true");

        if ($status) {
            my $msg = "Error trying to set the action start in farm $farmname.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }
    elsif ($json_obj->{action} eq "restart") {
        my $status = &runFarmStop($farmname, "true");

        if ($status) {
            my $msg = "Error trying to stop the farm in the action restart in farm $farmname.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        require Relianoid::Net::Interface;

        # check if the ip exists in any interface
        my $ip = &getFarmVip("vip", $farmname);

        if (!&getIpAddressExists($ip)) {
            my $msg = "The virtual ip $ip is not defined in any interface.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        require Relianoid::Farm::Core;
        my $farm_type = &getFarmType($farmname);

        if ($farm_type ne "datalink") {
            my $if_name = &getInterfaceByIp($ip);
            my $if_ref  = &getInterfaceConfig($if_name);

            if (&getInterfaceSystemStatus($if_ref) ne "up") {
                my $msg = "The virtual IP '$ip' is not UP";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }

            my $port = &getFarmVip("vipp", $farmname);
            if (!&validatePort($ip, $port, undef, $farmname)) {
                my $msg = "There is another farm using the ip '$ip' and the port '$port'";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        $status = &runFarmStart($farmname, "true");

        if ($status) {
            my $msg = "ZAPI error, trying to start the farm in the action restart in farm $farmname.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    my $msg = "The action $json_obj->{action} has been performed in farm $farmname.";

    &zenlog("Success, $msg", "info", "FARMS");

    &eload(
        module => 'Relianoid::EE::Cluster',
        func   => 'runZClusterRemoteManager',
        args   => [ 'farm', $json_obj->{action}, $farmname ],
    ) if ($eload);

    my $body = {
        description => "Set a new action in $farmname",
        params      => {
            "action" => $json_obj->{action},
            "status" => &getFarmVipStatus($farmname),
        },
        message => $msg
    };

    return &httpResponse({ code => 200, body => $body });
}

# Set an action in a backend of http|https farm
# PUT /farms/<farmname>/services/<service>/backends/<backend>/maintenance
sub set_service_backend_maintenance_controller ($json_obj, $farmname, $service, $backend_id) {
    require Relianoid::Farm::Base;
    require Relianoid::Farm::HTTP::Config;
    require Relianoid::Farm::HTTP::Service;
    require Relianoid::Farm::HTTP::Backend;

    my $desc = "Set service backend status";

    # validate FARM NAME
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # validate FARM TYPE
    if (&getFarmType($farmname) !~ /^https?$/) {
        my $msg = "Only HTTP farm profile supports this feature.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # validate SERVICE
    my @services = &getHTTPFarmServices($farmname);
    my $found_service;

    for my $service_name (@services) {
        if ($service eq $service_name) {
            $found_service = 1;
            last;
        }
    }

    if (!$found_service) {
        my $msg = "Could not find the requested service.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # validate BACKEND
    my $be_aref = &getHTTPFarmBackends($farmname, $service);
    my $be      = $be_aref->[ $backend_id - 1 ];

    if (!$be) {
        my $msg = "Could not find a service backend with such id.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_service_backend-maintenance.json");
    if ($json_obj->{action} ne 'maintenance') {
        delete $params->{mode};
    }

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # Do not allow to modify the maintenance status if the farm needs to be restarted
    require Relianoid::Farm::Action;
    if (&getFarmRestartStatus($farmname)) {
        my $msg = "The farm needs to be restarted before to apply this action.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # validate STATUS
    my $status;
    if ($json_obj->{action} eq "maintenance") {
        my $maintenance_mode = $json_obj->{mode} // "drain";    # default

        $status = &setHTTPFarmBackendMaintenance($farmname, $backend_id, $maintenance_mode, $service);
    }
    elsif ($json_obj->{action} eq "up") {
        $status = &setHTTPFarmBackendNoMaintenance($farmname, $backend_id, $service);
    }

    if ($status->{code} == 1 or $status->{code} == -1) {
        my $msg = "Errors found trying to change status backend to $json_obj->{action}";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $msg = "The action $json_obj->{action} has been performed in farm '$farmname'.";
    my $warning;
    if ($status->{code} != 0) {
        $warning = $status->{desc};
    }

    my $body = {
        description => $desc,
        params      => {
            action => $json_obj->{action},
            farm   => {
                status => &getFarmVipStatus($farmname),
            },
            message => $msg
        },
    };
    $body->{warning} = $warning if $warning;

    &eload(
        module => 'Relianoid::EE::Cluster',
        func   => 'runZClusterRemoteManager',
        args   => [ 'farm', 'restart', $farmname ],
    ) if ($eload && &getFarmStatus($farmname) eq 'up');

    return &httpResponse({ code => 200, body => $body });
}

# PUT backend in maintenance
# PUT /farms/<farmname>/backends/<backend>/maintenance
sub set_backend_maintenance_controller ($json_obj, $farmname, $backend_id) {
    require Relianoid::Farm::Backend::Maintenance;
    require Relianoid::Farm::Backend;
    require Relianoid::Farm::Base;

    my $desc = "Set backend status";

    # validate FARM NAME
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # validate FARM TYPE
    unless (&getFarmType($farmname) eq 'l4xnat') {
        my $msg = "Only L4xNAT farm profile supports this feature.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # validate BACKEND
    require Relianoid::Farm::L4xNAT::Backend;

    my $backends = &getL4FarmServers($farmname);
    my $exists   = &getFarmServer($backends, $backend_id);

    if (!$exists) {
        my $msg = "Could not find a backend with such id.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_l4xnat_service_backend-maintenance.json");

    if ($json_obj->{action} ne 'maintenance') {
        delete $params->{mode};
    }

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # validate STATUS
    my $status;
    if ($json_obj->{action} eq "maintenance") {
        my $maintenance_mode = $json_obj->{mode} // "drain";    # default

        $status = &setFarmBackendMaintenance($farmname, $backend_id, $maintenance_mode);
    }
    elsif ($json_obj->{action} eq "up") {
        $status = &setFarmBackendNoMaintenance($farmname, $backend_id);
    }

    if ($status->{code} == 1 or $status->{code} == -1) {
        my $msg = "Errors found trying to change status backend to $json_obj->{action}";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $msg = "The action $json_obj->{action} has been performed in farm '$farmname'.";
    my $warning;
    if ($status->{code} != 0) {
        $warning = $status->{desc};
    }

    # no error found, send successful response
    my $body = {
        description => $desc,
        params      => {
            action => $json_obj->{action},
            farm   => {
                status => &getFarmVipStatus($farmname),
            },
            message => $msg
        },
    };
    $body->{warning} = $warning if $warning;

    &eload(
        module => 'Relianoid::EE::Cluster',
        func   => 'runZClusterRemoteManager',
        args   => [ 'farm', 'restart', $farmname ],
    ) if ($eload && &getFarmStatus($farmname) eq 'up');

    return &httpResponse({ code => 200, body => $body });
}

1;

