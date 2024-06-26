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

use Relianoid::API40::HTTP;
use Relianoid::Farm::Core;
use Relianoid::Farm::Base;
use Relianoid::Net::Validate;
use Relianoid::API40::Farm::Get;

=pod

=head1 Module

Relianoid::API40::Farm::Backend

=cut

my $eload = eval { require Relianoid::ELoad };

# POST

sub new_farm_backend ($json_obj, $farmname) {
    require Relianoid::Farm::Backend;

    # Initial parameters
    my $desc = "New farm backend";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type ne 'datalink' and $type ne 'l4xnat') {
        my $msg = "The $type farm profile has backends only in services.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $params =
      ($type eq 'l4xnat')
      ? &getAPIModel("farm_l4xnat_service_backend-add.json")
      : &getAPIModel("farm_datalink_service_backend-add.json");

    # Check allowed parameters
    my $error_msg = &checkApiParams($json_obj, $params, $desc);
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg })
      if ($error_msg);

    my $id = &getFarmBackendAvailableID($farmname);

    my $info_msg;

    # check of interface for datalink
    if ($type eq 'datalink') {
        my $msg = &validateDatalinkBackendIface($json_obj);
        if ($msg) {
            &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # check of ip version
    if ($type eq 'l4xnat') {
        require Relianoid::Farm::L4xNAT::Config;
        my $farm_vip = &getL4FarmParam("vip", $farmname);

        if (&ipversion($json_obj->{ip}) ne &ipversion($farm_vip)) {
            my $msg = "The IP version of backend IP '$json_obj->{ ip }' does not match with farm VIP '$farm_vip'";

            &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # Create backend
    my $status = &setFarmServer($farmname, undef, $id, $json_obj);
    if ($status == -1) {
        my $msg = "It was not possible to create the backend";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }
    if ($status == -2) {
        my $msg = "The IP $json_obj->{ip} is already set in farm $farmname";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    &zenlog("New backend created in farm $farmname with IP $json_obj->{ip}.", "info", "FARMS");

    # check priority for l4xnat
    if ($type eq 'l4xnat') {
        require Relianoid::Farm::L4xNAT::Backend;
        require Relianoid::Farm::Validate;
        my $priorities = &getL4FarmPriorities($farmname);
        if (my $prio = &priorityAlgorithmIsOK($priorities)) {
            $info_msg = "Backends with high priority value ($prio) will not be used.";
            &zenlog("Warning, backend with high priority value ($prio) in farm $farmname.", "warning", "FARMS");
        }
    }

    # Backend retrieval
    my $serversArray = &getFarmServers($farmname);
    my $out_b        = &getFarmServer($serversArray, $id);

    if (!$out_b) {
        my $msg = "Error when retrieving the backend created";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    &getAPIFarmBackends($out_b, $type);

    my $message = "Backend added.";
    my $body    = {
        description => $desc,
        params      => $out_b,
        message     => $message,
        status      => &getFarmVipStatus($farmname),
    };
    $body->{warning} = $info_msg if defined $info_msg;

    &eload(
        module => 'Relianoid::Cluster',
        func   => 'runZClusterRemoteManager',
        args   => [ 'farm', 'restart', $farmname ],
    ) if ($eload);

    &httpResponse({ code => 201, body => $body });
    return;
}

sub new_service_backend ($json_obj, $farmname, $service) {

    # Initial parameters
    my $desc = "New service backend";

    my $type = &getFarmType($farmname);

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # validate FARM TYPE

    if ($type eq "gslb" && $eload) {
        &eload(
            module => 'Relianoid::API40::Farm::GSLB',
            func   => 'new_gslb_service_backend',
            args   => [ $json_obj, $farmname, $service ]
        );
    }
    elsif ($type !~ /^https?$/) {
        my $msg = "The $type farm profile does not support services.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # HTTP
    require Relianoid::Farm::Config;
    require Relianoid::Farm::Backend;
    require Relianoid::Farm::Validate;
    require Relianoid::Farm::HTTP::Backend;
    require Relianoid::Farm::HTTP::Service;

    # validate SERVICE
    my @services = &getHTTPFarmServices($farmname);

    # Check if the provided service is configured in the farm
    unless (grep { /^$service$/ } @services) {
        my $msg = "Invalid service name, please insert a valid value.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the service has configured a redirect
    if (&getHTTPFarmVS($farmname, $service, 'redirect')) {
        my $msg = "It is not possible to create a backend when the service has a redirect configured.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_service_backend-add.json");
    if (&getGlobalConfiguration('proxy_ng') ne 'true') {
        undef $params->{"connection_limit"};
    }

    # Check allowed parameters
    my $error_msg = &checkApiParams($json_obj, $params, $desc);
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg })
      if ($error_msg);

    # get an ID for the new backend
    my $id = &getHTTPFarmBackendAvailableID($farmname, $service);

    my $prio = 1;
    $prio = $json_obj->{priority} + 0
      if (defined $json_obj->{priority} && $json_obj->{priority} !~ /^$/);
    if ($type =~ /http/ && &getGlobalConfiguration('proxy_ng') ne 'true' && $prio > 1) {
        my $priorities = &getHTTPFarmPriorities($farmname, $service);
        if (scalar(@{$priorities}) >= 1) {
            my $msg = "Only one backend as second priority is allowed.";
            &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # First param ($id) is an empty string to let function autogenerate the id for the new backend
    my $status = &setHTTPFarmServer(
        "",                  $json_obj->{ip},       $json_obj->{port},
        $json_obj->{weight}, $json_obj->{timeout},  $farmname,
        $service,            $json_obj->{priority}, $json_obj->{connection_limit},
    );

    # check if there was an error adding a new backend
    if ($status == -1) {
        my $msg =
            "It's not possible to create the backend with ip $json_obj->{ ip }"
          . " and port $json_obj->{ port } for the $farmname farm";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # no error found, return successful response
    &zenlog("Success, a new backend has been created in farm $farmname in service $service with IP $json_obj->{ip}.",
        "info", "FARMS");

    my $info_msg;
    if ($type =~ /http/ and &getGlobalConfiguration('proxy_ng') eq 'true') {
        my $priorities = &getHTTPFarmPriorities($farmname, $service);
        if (my $prio = &priorityAlgorithmIsOK($priorities)) {
            $info_msg = "Backends with high priority value ($prio) will not be used.";
            &zenlog("Warning, backend with high priority value ($prio) in farm $farmname in service $service.", "warning", "FARMS");
        }
    }

    my $message = "Added backend to service successfully.";

    my $out_b = &getFarmServers($farmname, $service)->[$id];
    &getAPIFarmBackends($out_b, $type);

    my $body = {
        description => $desc,
        params      => $out_b,
        message     => $message,
        status      => &getFarmVipStatus($farmname),
    };
    $body->{warning} = $info_msg if defined $info_msg;

    if (&getFarmStatus($farmname) eq 'up') {
        require Relianoid::Farm::Action;
        if (&getGlobalConfiguration('proxy_ng') ne 'true') {
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }
        else {
            require Relianoid::Farm::HTTP::Config;
            my $config_error = &getHTTPFarmConfigErrorMessage($farmname);
            if ($config_error ne "") {
                $body->{warning} = "Farm '$farmname' config error: $config_error";
            }
            else {
                &runFarmReload($farmname);
                &eload(
                    module => 'Relianoid::Cluster',
                    func   => 'runZClusterRemoteManager',
                    args   => [ 'farm', 'reload', $farmname ],
                ) if ($eload);
            }
        }
    }

    &httpResponse({ code => 201, body => $body });
    return;
}

# GET

#GET /farms/<name>/backends
sub backends ($farmname) {
    my $desc = "List backends";
    require Relianoid::Farm::Backend;

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type ne 'l4xnat' and $type ne 'datalink') {
        my $msg = "The farm $farmname with profile $type does not support this request.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $backends = &getFarmServers($farmname);
    &getAPIFarmBackends($backends, $type);

    my $body = {
        description => $desc,
        params      => $backends,
    };

    &httpResponse({ code => 200, body => $body });
    return;
}

#GET /farms/<name>/services/<service>/backends
sub service_backends ($farmname, $service) {
    my $desc = "List service backends";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);

    if ($type eq 'gslb' && $eload) {
        &eload(
            module => 'Relianoid::API40::Farm::GSLB',
            func   => 'list_gslb_service_backends',
            args   => [ $farmname, $service ]
        );
    }

    if ($type !~ /^https?$/) {
        my $msg = "The farm profile $type does not support this request.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # HTTP
    require Relianoid::Farm::HTTP::Service;

    my $service_ref = &getHTTPServiceStruct($farmname, $service);

    # check if the requested service exists
    if ($service_ref == -1) {
        my $msg = "The service $service does not exist.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $body = {
        description => $desc,
        params      => $service_ref->{backends},
    };

    &httpResponse({ code => 200, body => $body });
    return;
}

# PUT

sub modify_backends ($json_obj, $farmname, $id_server) {
    my $desc = "Modify backend";

    require Relianoid::Farm::Backend;
    require Relianoid::Net::Validate;

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type ne 'datalink' and $type ne 'l4xnat') {
        my $msg = "The $type farm profile has backends only in services.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # get backends
    my $serversArray = &getFarmServers($farmname);

    my $backend = &getFarmServer($serversArray, $id_server);

    if (!$backend || ref($backend) ne "HASH") {
        my $msg = "Could not find a backend with such id.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $params =
      ($type eq 'l4xnat')
      ? &getAPIModel("farm_l4xnat_service_backend-modify.json")
      : &getAPIModel("farm_datalink_service_backend-modify.json");

    # Check allowed parameters
    my %json_params = %{$json_obj};
    my $error_msg   = &checkApiParams(\%json_params, $params, $desc);
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg })
      if ($error_msg);

    # check of ip version
    if ($type eq 'l4xnat') {
        if (exists $json_obj->{ip}) {
            require Relianoid::Farm::L4xNAT::Config;
            my $farm_vip = &getL4FarmParam("vip", $farmname);
            if (&ipversion($json_obj->{ip}) ne &ipversion($farm_vip)) {
                my $msg = "The IP version of backend IP '$json_obj->{ ip }' does not match with farm VIP '$farm_vip'";
                &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }
    }
    $backend->{ip}        = $json_obj->{ip}        if exists $json_obj->{ip};
    $backend->{port}      = $json_obj->{port}      if exists $json_obj->{port};         # l4xnat
    $backend->{weight}    = $json_obj->{weight}    if exists $json_obj->{weight};
    $backend->{priority}  = $json_obj->{priority}  if exists $json_obj->{priority};
    $backend->{max_conns} = $json_obj->{max_conns} if exists $json_obj->{max_conns};    # l4xnat
    $backend->{interface} = $json_obj->{interface} if exists $json_obj->{interface};    # datalink

    if ($type eq 'datalink') {
        my $msg = &validateDatalinkBackendIface($backend);
        if ($msg) {
            &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    my $error = &setFarmServer($farmname, undef, $id_server, $backend);
    if ($error == -2) {
        my $msg = "The IP $json_obj->{ip} is already set in farm $farmname";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }
    if ($error) {
        my $msg = "Error trying to modify the backend $id_server.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $info_msg;
    if (($type ne 'datalink') and (exists $json_obj->{priority})) {
        require Relianoid::Farm::L4xNAT::Backend;
        require Relianoid::Farm::Validate;
        if (my $prio = &priorityAlgorithmIsOK(&getL4FarmPriorities($farmname))) {
            $info_msg = "Backends with high priority value ($prio) will not be used.";
            &zenlog("Warning, backend with high priority value ($prio) in farm $farmname.", "warning", "FARMS");
        }
    }

    &zenlog("Success, some parameters have been changed in the backend $id_server in farm $farmname.", "info", "FARMS");

    my $message = "Backend modified.";
    my $body    = {
        description => $desc,
        params      => $json_obj,
        message     => $message,
        status      => &getFarmVipStatus($farmname),
    };
    $body->{warning} = $info_msg if defined $info_msg;

    &eload(
        module => 'Relianoid::Cluster',
        func   => 'runZClusterRemoteManager',
        args   => [ 'farm', 'restart', $farmname ],
    ) if ($eload && &getFarmStatus($farmname) eq 'up');

    &httpResponse({ code => 200, body => $body });
    return;
}

sub modify_service_backends ($json_obj, $farmname, $service, $id_server) {
    my $desc = "Modify service backend";

    my $type = &getFarmType($farmname);

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if ($type eq "gslb" && $eload) {
        &eload(
            module => 'Relianoid::API40::Farm::GSLB',
            func   => 'modify_gslb_service_backends',
            args   => [ $json_obj, $farmname, $service, $id_server ]
        );
    }
    elsif ($type !~ /^https?$/) {
        my $msg = "The $type farm profile does not support services.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # HTTP
    require Relianoid::Farm::Action;
    require Relianoid::Farm::HTTP::Config;
    require Relianoid::Farm::HTTP::Backend;
    require Relianoid::Farm::HTTP::Service;

    # validate SERVICE
    my @services      = &getHTTPFarmServices($farmname);
    my $found_service = grep { $service eq $_ } @services;

    # check if the service exists
    if (!$found_service) {
        my $msg = "Could not find the requested service.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # validate BACKEND
    my $be;
    {
        my @be_list = @{ &getHTTPFarmBackends($farmname, $service) };
        $be = $be_list[$id_server];
    }

    # check if the backend was found
    if (!$be) {
        my $msg = "Could not find a service backend with such id.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_service_backend-modify.json");
    if (&getGlobalConfiguration('proxy_ng') ne 'true') {
        undef $params->{"connection_limit"};
    }

    # Check allowed parameters
    my $error_msg = &checkApiParams($json_obj, $params, $desc);
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg })
      if ($error_msg);

    # apply BACKEND change

    $be->{ip}               = $json_obj->{ip}               // $be->{ip};
    $be->{port}             = $json_obj->{port}             // $be->{port};
    $be->{weight}           = $json_obj->{weight}           // $be->{weight};
    $be->{priority}         = $json_obj->{priority}         // $be->{priority};
    $be->{timeout}          = $json_obj->{timeout}          // $be->{timeout};
    $be->{connection_limit} = $json_obj->{connection_limit} // $be->{connection_limit};

    my $prio = 1;
    $prio = $be->{priority} + 0 if (defined $be->{priority} && $be->{priority} !~ /^$/);
    if ($type =~ /http/ && &getGlobalConfiguration('proxy_ng') ne 'true' && $prio > 1) {
        my $priorities = &getHTTPFarmPriorities($farmname, $service);
        if (scalar(@{$priorities}) >= 1 && !grep { $_->{id} == $id_server } @{$priorities}) {
            my $msg = "Only one backend as second priority is allowed.";
            &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    my $status = &setHTTPFarmServer(
        $id_server, $be->{ip}, $be->{port},     $be->{weight}, $be->{timeout},
        $farmname,  $service,  $be->{priority}, $be->{connection_limit}
    );

    # check if there was an error modifying the backend
    if ($status == -1) {
        my $msg = "It's not possible to modify the backend with IP $json_obj->{ip} in service $service.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $info_msg;

    if (    (&getGlobalConfiguration('proxy_ng') eq 'true')
        and (exists $json_obj->{priority}))
    {
        require Relianoid::Farm::Validate;
        if (my $prio = &priorityAlgorithmIsOK(&getHTTPFarmPriorities($farmname, $service))) {
            $info_msg = "Backends with high priority value ($prio) will not be used.";
            &zenlog("Warning, backend with high priority value ($prio) in farm $farmname in service $service.", "warning", "FARMS");
        }
    }
    my $msg  = "Backend modified.";
    my $body = {
        description => $desc,
        params      => $json_obj,
        message     => $msg,
        status      => &getFarmVipStatus($farmname),
    };

    $body->{warning} = $info_msg if defined $info_msg;

    if (&getFarmStatus($farmname) eq "up") {
        require Relianoid::Farm::Action;
        if (&getGlobalConfiguration('proxy_ng') ne 'true') {
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }
        else {
            require Relianoid::Farm::HTTP::Config;
            my $config_error = &getHTTPFarmConfigErrorMessage($farmname);
            if ($config_error ne "") {
                $body->{warning} = "Farm '$farmname' config error: $config_error";
            }
            else {
                &runFarmReload($farmname);
                &eload(
                    module => 'Relianoid::Cluster',
                    func   => 'runZClusterRemoteManager',
                    args   => [ 'farm', 'reload', $farmname ],
                ) if ($eload);
            }
        }
    }

    &httpResponse({ code => 200, body => $body });
    return;
}

# DELETE

# DELETE /farms/<farmname>/backends/<backendid> Delete a backend of a Farm
sub delete_backend ($farmname, $id_server) {
    require Relianoid::Farm::Backend;

    my $desc = "Delete backend";

    # validate FARM NAME
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # validate FARM TYPE
    my $type = &getFarmType($farmname);
    unless ($type eq 'l4xnat' || $type eq 'datalink') {
        my $msg = "The $type farm profile has backends only in services.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $backends = &getFarmServers($farmname);
    my $exists   = &getFarmServer($backends, $id_server);

    if (!$exists) {
        my $msg = "Could not find a backend with such id.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $status = &runFarmServerDelete($id_server, $farmname);

    if ($status == -1) {
        my $msg = "It's not possible to delete the backend with ID $id_server of the $farmname farm.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $info_msg;
    if ($type eq 'l4xnat') {
        require Relianoid::Farm::Validate;
        if (my $prio = &priorityAlgorithmIsOK(&getL4FarmPriorities($farmname))) {
            $info_msg = "Backends with high priority value ($prio) will not be used.";
            &zenlog("Warning, backend with high priority value ($prio) in farm $farmname.", "warning", "FARMS");
        }
    }

    &zenlog("Success, the backend $id_server in farm $farmname has been deleted.", "info", "FARMS");

    &eload(
        module => 'Relianoid::Cluster',
        func   => 'runZClusterRemoteManager',
        args   => [ 'farm', 'delete', $farmname, 'backend', $id_server ],
    ) if ($eload && $type eq 'l4xnat');

    &eload(
        module => 'Relianoid::Cluster',
        func   => 'runZClusterRemoteManager',
        args   => [ 'farm', 'restart', $farmname ],
    ) if ($eload && $type eq 'datalink');

    my $message = "Backend removed";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
        status      => &getFarmVipStatus($farmname),
    };
    $body->{warning} = $info_msg if defined $info_msg;

    &httpResponse({ code => 200, body => $body });
    return;
}

#  DELETE /farms/<farmname>/services/<servicename>/backends/<backendid> Delete a backend of a Service
sub delete_service_backend ($farmname, $service, $id_server) {
    my $desc = "Delete service backend";

    # validate FARM NAME
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # validate FARM TYPE
    my $type = &getFarmType($farmname);

    if ($type eq 'gslb' && $eload) {
        &eload(
            module => 'Relianoid::API40::Farm::GSLB',
            func   => 'delete_gslb_service_backend',
            args   => [ $farmname, $service, $id_server ]
        );
    }
    elsif ($type !~ /^https?$/) {
        my $msg = "The $type farm profile does not support services.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # HTTP
    require Relianoid::Farm::Action;
    require Relianoid::Farm::HTTP::Config;
    require Relianoid::Farm::HTTP::Backend;
    require Relianoid::Farm::HTTP::Service;

    # validate SERVICE
    my @services = &getHTTPFarmServices($farmname);

    # check if the SERVICE exists
    unless (grep { $service eq $_ } @services) {
        my $msg = "Could not find the requested service.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # check if the backend id is available
    my $be_found;
    {
        my $be = &getHTTPFarmBackends($farmname, $service);
        $be_found = defined @{$be}[$id_server];
    }

    unless ($be_found) {
        my $msg = "Could not find the requested backend.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $status = &runHTTPFarmServerDelete($id_server, $farmname, $service);

    # check if there was an error deleting the backend
    if ($status == -1) {
        &zenlog("It's not possible to delete the backend.", "info", "FARMS");

        my $msg = "Could not find the backend with ID $id_server of the $farmname farm.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $info_msg;
    if (&getGlobalConfiguration('proxy_ng') eq 'true') {
        require Relianoid::Farm::Validate;
        if (my $prio = &priorityAlgorithmIsOK(&getHTTPFarmPriorities($farmname, $service))) {
            $info_msg = "Backends with high priority value ($prio) will not be used.";
            &zenlog("Warning, backend with high priority value ($prio) in service $service in farm $farmname.", "warning", "FARMS");
        }
    }

    # no error found, return successful response
    &zenlog("Success, the backend $id_server in service $service in farm $farmname has been deleted.", "info", "FARMS");

    my $message = "Backend removed";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
        status      => &getFarmVipStatus($farmname),
    };

    $body->{warning} = $info_msg if defined $info_msg;

    if (&getFarmStatus($farmname) eq 'up') {
        require Relianoid::Farm::Action;
        if (&getGlobalConfiguration('proxy_ng') ne 'true') {
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }
        else {
            require Relianoid::Farm::HTTP::Config;
            my $config_error = &getHTTPFarmConfigErrorMessage($farmname);
            if ($config_error ne "") {
                $body->{warning} = "Farm '$farmname' config error: $config_error";
            }
            else {
                &runFarmReload($farmname);
                &eload(
                    module => 'Relianoid::Cluster',
                    func   => 'runZClusterRemoteManager',
                    args   => [ 'farm', 'reload', $farmname ],
                ) if ($eload);
            }
        }
    }

    &httpResponse({ code => 200, body => $body });
    return;
}

sub validateDatalinkBackendIface ($backend) {
    require Relianoid::Net::Interface;

    my $msg;
    my $iface_ref = &getInterfaceConfig($backend->{interface});

    if (not defined $iface_ref) {
        $msg = "$backend->{interface} has not been found";
    }
    elsif ($iface_ref->{vini}) {
        $msg = "It is not possible to configure vlan interface for datalink backends";
    }
    elsif (!&validateGateway($iface_ref->{addr}, $iface_ref->{mask}, $backend->{ip})) {
        $msg = "The $backend->{ ip } IP must be in the same network than the $iface_ref->{ addr } interface.";
    }

    return $msg;
}

1;

