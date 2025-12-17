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

Relianoid::HTTP::Controllers::API::Farm::Service

=cut

my $eload = eval { require Relianoid::ELoad };

# POST
sub add_farm_service_controller ($json_obj, $farmname) {
    require Relianoid::Farm::Service;

    my $desc = "New service";

    # Check if the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # check if the service exists
    if (grep { $json_obj->{id} eq $_ } &getFarmServices($farmname)) {
        my $msg = "Error, the service $json_obj->{id} already exist.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);

    my $result = 0;
    # validate farm profile
    if ($type eq "eproxy") {
        $result = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Service',
            func   => 'setEproxyServiceStruct',
            args   => [ {farm_name => $farmname, service_name => $json_obj->{id}} ]
        );
    }
    elsif ($type eq "gslb") {
        &eload(
            module => 'Relianoid::EE::HTTP::Controllers::API::Farm::GSLB',
            func   => 'new_gslb_farm_service',
            args   => [ $json_obj, $farmname ]
        );
    }
    elsif ($type =~ /^https?$/) {
        my $params = &getAPIModel("farm_http_service-create.json");
        if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
        }

        require Relianoid::HTTP::Controllers::API::Farm::Get::HTTP;
        require Relianoid::Farm::HTTP::Service;

        $result = &setFarmHTTPNewService($farmname, $json_obj->{id});
    }
    else {
        my $msg = "The farm profile $type does not support services actions.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if a service with such name already exists
    if ($result == 1) {
        my $msg = "Service name " . $json_obj->{id} . " already exists.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the service name has invalid characters
    if ($result == 3) {
        my $msg = "Service name is not valid, only allowed numbers, letters and hyphens.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # Return 0 on success
    if ($result) {
        my $msg = "Error creating the service $json_obj->{id}.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # no error found, return successful response
    &log_info("Success, a new service has been created in farm $farmname with id $json_obj->{id}.", "FARMS");

    my $body = {
        description => $desc,
        params      => { id => $json_obj->{id} },
        message     => "A new service has been created in farm $farmname with id $json_obj->{id}."
    };

    require Relianoid::Farm::Base;
    if (&getFarmStatus($farmname) ne 'down') {
        if ($type eq "eproxy" && $eload) {
            $body->{status} = &eload(
                module => 'Relianoid::EE::Farm::Eproxy::Action',
                func   => 'runEproxyFarmReload',
                args   => [ { farm_name => $farmname } ],
            );
            require Relianoid::EE::Cluster;
            &runClusterRemoteManager('farm', 'reload', $farmname);
        }
        else {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }
    }

    return &httpResponse({ code => 201, body => $body });
}

# GET

#GET /farms/<name>/services/<service>
sub get_farm_service_controller ($farmname, $servicename) {
    require Relianoid::HTTP::Controllers::API::Farm::Get::HTTP;
    require Relianoid::Farm::Config;
    require Relianoid::Farm::HTTP::Service;

    my $desc = "Get services of a farm";

    # Check if the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);

    my @services;
    if ($type =~ /http/i) {
        @services = &getHTTPFarmServices($farmname);
    }
    elsif ($type eq "eproxy" && $eload) {
        @services = @ { &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Service',
            func   => 'getEproxyFarmServices',
            args   => [ { farm_name => $farmname } ]
        ) };
    }
    else {
        my $msg = "This functionality only is available for HTTP or eproxy farms.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the service is available
    if (!grep { $servicename eq $_ } @services) {
        my $msg = "The required service does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $service;
    if ($type =~ /http/i) {
        $service = &getHTTPServiceStruct($farmname, $servicename);
    }
    elsif ($type eq "eproxy" && $eload) {
        $service = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Service',
            func   => 'getEproxyServiceStruct',
            args   => [ { farm_name => $farmname, service_name => $servicename } ]
        );
    }

    my $body    = {
        description => $desc,
        params      => $service,
    };

    return &httpResponse({ code => 200, body => $body });
}

# PUT

sub modify_farm_service_controller ($json_obj, $farmname, $service) {
    require Relianoid::Farm::Base;
    require Relianoid::Farm::Service;

    my $desc = "Modify service";
    my $output_params;
    my $bk_msg = "";

    # validate FARM NAME
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # validate FARM TYPE
    my $type = &getFarmType($farmname);

    unless ($type eq 'gslb' || $type eq 'http' || $type eq 'https' || $type eq 'eproxy') {
        my $msg = "The $type farm profile does not support services settings.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the farm profile gslb is supported
    if ($type eq "gslb") {
        unless (my $found_service = grep { $service eq $_ } &getFarmServices($farmname)) {
            my $msg = "Could not find the requested service.";
            return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
        }

        &eload(
            module => 'Relianoid::EE::HTTP::Controllers::API::Farm::GSLB',
            func   => 'modify_gslb_service',
            args   => [ $json_obj, $farmname, $service ]
        );
    }
    elsif ($type eq "eproxy" && $eload) {
        my $args = $json_obj;
        $args->{ farm_name } = $farmname;
        $args->{ service_name } = $service;
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Service',
            func   => 'setEproxyServiceStruct',
            args   => [ $args ]
        );
        $output_params = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Service',
            func   => 'getEproxyServiceStruct',
            args   => [ { farm_name => $farmname, service_name => $service } ]
        );
        delete $output_params->{ farm_filename };
    }
    else {
        unless (my $found_service = grep { $service eq $_ } &getFarmServices($farmname)) {
            my $msg = "Could not find the requested service.";
            return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
        }

        # From here everything is about HTTP farms
        require Relianoid::Farm::HTTP::Config;
        require Relianoid::Farm::HTTP::Service;

        my $params = &getAPIModel("farm_http_service-modify.json");

        # Check allowed parameters
        if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
        }

        # translate params
        if (exists $json_obj->{persistence} and $json_obj->{persistence} eq 'NONE') {
            $json_obj->{persistence} = "";
        }

        # modifying params
        if (exists $json_obj->{vhost}) {
            &setHTTPFarmVS($farmname, $service, "vs", $json_obj->{vhost});
        }

        if (exists $json_obj->{urlp}) {
            &setHTTPFarmVS($farmname, $service, "urlp", $json_obj->{urlp});
        }

        if (exists $json_obj->{redirect}) {
            my $redirect = $json_obj->{redirect};

            &setHTTPFarmVS($farmname, $service, "redirect", $redirect);

            # delete service's backends if redirect has been configured
            if ($redirect) {
                require Relianoid::Farm::HTTP::Backend;
                my $backends = scalar @{ &getHTTPFarmBackends($farmname, $service) };

                if ($backends) {
                    $bk_msg = "The backends of $service have been deleted.";

                    for (my $id = $backends - 1 ; $id >= 0 ; $id--) {
                        &runHTTPFarmServerDelete($id, $farmname, $service);
                    }
                }
            }
        }

        if (exists $json_obj->{redirecttype}) {
            my $redirecttype = $json_obj->{redirecttype};
            &setHTTPFarmVS($farmname, $service, "redirecttype", $redirecttype);
        }

        if (exists $json_obj->{leastresp}) {
            if ($json_obj->{leastresp} eq "true") {
                &setHTTPFarmVS($farmname, $service, "dynscale", $json_obj->{leastresp});
            }
            elsif ($json_obj->{leastresp} eq "false") {
                &setHTTPFarmVS($farmname, $service, "dynscale", "");
            }
        }

        if (exists $json_obj->{persistence}) {
            my $session = $json_obj->{persistence} || 'nothing';
            my $old_persistence;

            if ($eload) {
                require Relianoid::Farm::Config;
                $old_persistence = &getPersistence($farmname);
            }

            if (my $error = &setHTTPFarmVS($farmname, $service, "session", $session)) {
                my $msg = "It's not possible to change the persistence parameter.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }

            if ($eload) {
                my $new_persistence = &getPersistence($farmname);
                if (($new_persistence == 1) and ($old_persistence == 0)) {
                    &eload(
                        module => 'Relianoid::EE::Ssyncd',
                        func   => 'setSsyncdFarmDown',
                        args   => [$farmname],
                    );
                }
                elsif (($new_persistence == 0) and ($old_persistence == 1)) {
                    &eload(
                        module => 'Relianoid::EE::Ssyncd',
                        func   => 'setSsyncdFarmUp',
                        args   => [$farmname],
                    );
                }
            }
        }

        my $session = &getHTTPFarmVS($farmname, $service, "sesstype");

        # It is necessary evaluate first session, next ttl and later persistence
        if (exists $json_obj->{sessionid}) {
            if ($session =~ /^(URL|COOKIE|HEADER)$/) {
                &setHTTPFarmVS($farmname, $service, "sessionid", $json_obj->{sessionid});
            }
        }

        if (exists $json_obj->{ttl}) {
            if ($session =~ /^(IP|BASIC|URL|PARM|COOKIE|HEADER)$/) {
                my $error = &setHTTPFarmVS($farmname, $service, "ttl", "$json_obj->{ttl}");
                if ($error) {
                    my $msg = "Could not change the ttl parameter.";
                    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
                }
            }
        }

        # Cookie insertion
        if (scalar grep { /^cookie/ } keys %{$json_obj}) {
            my $msg;
            if ($eload) {
                $msg = &eload(
                    module   => 'Relianoid::EE::HTTP::Controllers::API::Farm::Service::Ext',
                    func     => 'modify_service_cookie_insertion',
                    args     => [ $farmname, $service, $json_obj ],
                    just_ret => 1,
                );

                if (defined $msg && length $msg) {
                    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
                }
            }
            else {
                $msg = "Cookie insertion feature not available.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        if (exists $json_obj->{httpsb}) {
            if ($json_obj->{httpsb} ne &getHTTPFarmVS($farmname, $service, 'httpsbackend')) {
                if ($json_obj->{httpsb} eq "true") {
                    &setHTTPFarmVS($farmname, $service, "httpsbackend", $json_obj->{httpsb});
                }
                elsif ($json_obj->{httpsb} eq "false") {
                    &setHTTPFarmVS($farmname, $service, "httpsbackend", "");
                }
            }
        }

        # Redirect code
        if (exists $json_obj->{redirect_code}) {
            if ($eload) {
                my $err = &eload(
                    module => 'Relianoid::EE::Farm::HTTP::Service::Ext',
                    func   => 'setHTTPServiceRedirectCode',
                    args   => [ $farmname, $service, $json_obj->{redirect_code} ],
                );

                if ($err) {
                    my $msg = "Error modifying redirect code.";
                    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
                }
            }
            else {
                my $msg = "Redirect code feature not available.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        if ($eload) {
            # sts options
            if (exists $json_obj->{sts_status}) {
                # status
                if ($type ne 'https') {
                    my $msg = "The farms have to be HTTPS to modify STS";
                    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
                }
                my $err = &eload(
                    module => 'Relianoid::EE::Farm::HTTP::Service::Ext',
                    func   => 'setHTTPServiceSTSStatus',
                    args   => [ $farmname, $service, $json_obj->{sts_status} ],
                );

                if ($err) {
                    my $msg = "Error modifying STS status.";
                    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
                }
            }

            if (exists $json_obj->{sts_timeout}) {
                if ($type ne 'https') {
                    my $msg = "The farms have to be HTTPS to modify STS";
                    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
                }

                my $err = &eload(
                    module => 'Relianoid::EE::Farm::HTTP::Service::Ext',
                    func   => 'setHTTPServiceSTSTimeout',
                    args   => [ $farmname, $service, $json_obj->{sts_timeout} ],
                );

                if ($err) {
                    my $msg = "Error modifying STS status.";
                    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
                }
            }
        }

        # no error found, return succesful response
        require Relianoid::HTTP::Controllers::API::Farm::Get::HTTP;
        $output_params = &getHTTPServiceStruct($farmname, $service);
    }

    &log_info("Success, some parameters have been changed in service $service in farm $farmname.", "FARMS");

    my $body = {
        description => "Modify service $service in farm $farmname",
        params      => $output_params,
    };

    $body->{message} = $bk_msg ? $bk_msg : "The service $service has been updated successfully.";

    require Relianoid::Farm::Base;
    if (&getFarmStatus($farmname) ne 'down') {
        if ($type eq "eproxy" && $eload) {
            $body->{status} = &eload(
                module => 'Relianoid::EE::Farm::Eproxy::Action',
                func   => 'runEproxyFarmReload',
                args   => [ { farm_name => $farmname } ],
            );
            require Relianoid::EE::Cluster;
            &runClusterRemoteManager('farm', 'reload', $farmname);
        }
        else {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }
    }

    return &httpResponse({ code => 200, body => $body });
}

# DELETE

# DELETE /farms/<farmname>/services/<servicename> Delete a service of a Farm
sub delete_farm_service_controller ($farmname, $service) {
    my $desc = "Delete service";

    # Check if the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # check the farm type is supported
    my $type = &getFarmType($farmname);

    my $error = 0;
    if ($type eq "eproxy" && $eload) {
        $error = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Service',
            func   => 'delEproxyServiceStruct',
            args   => [ {farm_name => $farmname, service_name => $service} ]
        );
    }
    elsif ($type eq "gslb" && $eload) {
        &eload(
            module => 'Relianoid::EE::HTTP::Controllers::API::Farm::GSLB',
            func   => 'delete_gslb_service',
            args   => [ $farmname, $service ]
        );
    }
    elsif ($type =~ /^https?$/) {
        require Relianoid::Farm::HTTP::Service;

        # Check that the provided service is configured in the farm
        my @services = &getHTTPFarmServices($farmname);
        my $found    = 0;

        for my $farmservice (@services) {
            if ($service eq $farmservice) {
                $found = 1;
                last;
            }
        }

        unless ($found) {
            my $msg = "Invalid service name, please insert a valid value.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        $error = &delHTTPFarmService($farmname, $service);
    } else {
        my $msg = "The farm profile $type does not support services actions.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the service is in use
    if ($error == -2) {
        my $msg = "The service is used by a zone.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the service could not be deleted
    if ($error) {
        my $msg = "Service $service in farm $farmname hasn't been deleted.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # no errors found, returning successful response
    &log_info("Success, the service $service has been deleted in farm $farmname.", "FARMS");

    my $message = "The service $service has been deleted in farm $farmname.";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    require Relianoid::Farm::Base;
    if (&getFarmStatus($farmname) ne 'down') {
        if ($type eq "eproxy" && $eload) {
            $body->{status} = &eload(
                module => 'Relianoid::EE::Farm::Eproxy::Action',
                func   => 'runEproxyFarmReload',
                args   => [ { farm_name => $farmname } ],
            );
            require Relianoid::EE::Cluster;
            &runClusterRemoteManager('farm', 'reload', $farmname);
        }
        else {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }
    }

    return &httpResponse({ code => 200, body => $body });
}

1;

