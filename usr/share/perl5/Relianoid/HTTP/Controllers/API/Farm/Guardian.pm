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

use Relianoid::FarmGuardian;
use Relianoid::Farm::Core;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::Farm::Guardian

=cut

my $eload = eval { require Relianoid::ELoad };

sub get_farmguardian_response ($fg_name) {
    my $fg  = &getFGObject($fg_name);
    my $out = {
        'name'          => $fg_name,
        'backend_alias' => $fg->{backend_alias} // 'false',
        'description'   => $fg->{description},
        'command'       => $fg->{command},
        'farms'         => $fg->{farms},
        'log'           => $fg->{log} // 'false',
        'interval'      => $fg->{interval} + 0,
        'cut_conns'     => $fg->{cut_conns},
        'template'      => $fg->{template},
        'timeout'       => ($fg->{timeout} // $fg->{interval}) + 0,
    };

    return $out;
}

sub list_farmguardian_response () {
    my @out;
    my @list = &getFGList();

    for my $fg_name (@list) {
        my $fg = &get_farmguardian_response($fg_name);
        push @out, $fg;
    }

    return \@out;
}

# first, it checks is exists and later look for in both lists, template and config
#  GET /monitoring/fg/<fg_name>
sub get_farmguardian_controller ($fg_name) {
    my $desc = "Retrive the farm guardian '$fg_name'";

    unless (&getFGExists($fg_name)) {
        my $msg = "The farm guardian '$fg_name' has not been found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $out  = &get_farmguardian_response($fg_name);
    my $body = { description => $desc, params => $out };

    return &httpResponse({ code => 200, body => $body });
}

#  GET /monitoring/fg
sub list_farmguardian_controller () {
    my $fg   = &list_farmguardian_response();
    my $desc = "List farm guardian checks and templates";

    return &httpResponse({ code => 200, body => { description => $desc, params => $fg } });
}

#  POST /monitoring/fg
sub create_farmguardian_controller ($json_obj) {
    my $fg_name = $json_obj->{name};
    my $desc    = "Create a farm guardian '$fg_name'";

    if (&getFGExistsConfig($fg_name)) {
        my $msg = "The farm guardian '$fg_name' already exists.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    if (&getFGExistsTemplate($fg_name)) {
        my $msg = "The farm guardian '$fg_name' is a template, select another name, please";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farmguardian-create.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    if (exists $json_obj->{copy_from}
        and not &getFGExists($json_obj->{copy_from}))
    {
        my $msg = "The parent farm guardian '$json_obj->{copy_from}' does not exist.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    if    (not exists $json_obj->{copy_from}) { &createFGBlank($fg_name); }
    elsif (&getFGExistsTemplate($json_obj->{copy_from})) {
        &createFGTemplate($fg_name, $json_obj->{copy_from});
    }
    else { &createFGConfig($fg_name, $json_obj->{copy_from}); }

    my $out = &get_farmguardian_response($fg_name);
    if ($out) {
        my $msg  = "The farm guardian '$fg_name' has been created successfully.";
        my $body = {
            description => $desc,
            params      => $out,
            message     => $msg,
        };
        return &httpResponse({ code => 200, body => $body });
    }
    else {
        my $msg = "The farm guardian '$fg_name' could not be created";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }
}

#  PUT /monitoring/fg/<fg_name>
sub modify_farmguardian_controller ($json_obj, $fgname) {
    my $desc = "Modify farm guardian '$fgname'";

    unless (&getFGExists($fgname)) {
        my $msg = "The farm guardian '$fgname' does not exist.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farmguardian-modify.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my @run_farms = @{ &getFGRunningFarms($fgname) };
    my $run_farms;
    $run_farms = join(', ', @run_farms) if @run_farms;

    # avoid modifying some parameters of a template
    if (&getFGExistsTemplate($fgname)) {
        if (exists $json_obj->{description} or exists $json_obj->{command}) {
            my $msg = "It is not allow to modify the parameters 'description' or 'command' in a template.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # check if farm guardian is running
    if (    $run_farms
        and not exists $json_obj->{force}
        and $json_obj->{force} ne 'true')
    {
        if (exists $json_obj->{command} or exists $json_obj->{backend_alias}) {
            my $error_msg = "Farm guardian '$fgname' is running in: '$run_farms'. To apply, send parameter 'force'";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
        }
    }

    delete $json_obj->{force};

    if (my $error = &setFGObject($fgname, $json_obj)) {
        my $msg  = "Modifying farm guardian '$fgname'.";
        my $body = { description => $desc, message => $msg, };
        return &httpResponse({ code => 400, body => $body });
    }

    # sync with cluster
    if ($eload) {
        &eload(
            module => 'Relianoid::EE::Cluster',
            func   => 'runClusterRemoteManager',
            args   => [ 'fg', 'restart', $fgname ],
        );
    }

    # no error found, return successful response
    my $msg  = "Success, some parameters have been changed in farm guardian '$fgname'.";
    my $out  = &get_farmguardian_response($fgname);
    my $body = { description => $desc, params => $out, message => $msg, };

    return &httpResponse({ code => 200, body => $body });
}

#  DELETE /monitoring/fg/<fg_name>
sub delete_farmguardian_controller ($fg_name) {
    my $desc = "Delete the farm guardian '$fg_name'";

    unless (&getFGExists($fg_name)) {
        my $msg = "The farm guardian $fg_name does not exist";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my @running_farms = @{ &getFGRunningFarms($fg_name) };
    if (@running_farms) {
        my $farm_str = join(', ', @running_farms);
        my $msg      = "It is not possible delete farm guardian '$fg_name' because it is running in: '$farm_str'";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    &delFGObject($fg_name);

    if (!&getFGExists($fg_name)) {
        # sync with cluster
        if ($eload) {
            &eload(
                module => 'Relianoid::EE::Cluster',
                func   => 'runClusterRemoteManager',
                args   => [ 'fg', 'stop', $fg_name ],
            );
        }

        my $msg  = "$fg_name has been deleted successfully.";
        my $body = {
            description => $desc,
            success     => "true",
            message     => $msg,
        };
        return &httpResponse({ code => 200, body => $body });
    }
    else {
        my $msg = "Deleting the farm guardian '$fg_name'.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }
}

#  POST /farms/<farm>(/services/<service>)?/fg
sub add_fg_to_farm_controller ($json_obj, $farm, $srv = undef) {
    my $srv_message = ($srv) ? "service '$srv' in the farm '$farm'" : "farm '$farm'";

    my $desc = "Add the farm guardian '$json_obj->{name}' to the '$srv_message'";

    require Relianoid::Farm::Service;

    # Check if it exists
    if (!&getFarmExists($farm)) {
        my $msg = "The farm '$farm' does not exist";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farmguardian_to_farm-add.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # Check if it exists
    if (!&getFGExists($json_obj->{name})) {
        my $msg = "The farmguardian '$json_obj->{name}' does not exist";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # Check if it exists
    if ($srv and not grep { $srv eq $_ } &getFarmServices($farm)) {
        my $msg = "The service '$srv' does not exist";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # check if another fg is applied to the farm
    my $fg_old = &getFGFarm($farm, $srv);
    if ($fg_old) {
        my $msg = "The '$srv_message' has already linked a farm guardian";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # link the check with the farm_service
    my $farm_tag = $farm;
    $farm_tag = "${farm}_$srv" if $srv;

    # check if the farm guardian is already applied to the farm
    my $fg_obj = &getFGObject($json_obj->{name});
    if (grep { $farm_tag eq $_ } @{ $fg_obj->{farms} }) {
        my $msg = "'$json_obj->{name}' is already applied in the '$srv_message'";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check farm type
    my $type = &getFarmType($farm);
    if ($type =~ /http|gslb|eproxy/ and not $srv) {
        my $msg = "The farm guardian expects a service";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $output = &linkFGFarm($json_obj->{name}, $farm, $srv);

    # check result and return success or failure
    if (!$output) {
        # sync with cluster
        if ($eload) {
            &eload(
                module => 'Relianoid::EE::Cluster',
                func   => 'runClusterRemoteManager',
                args   => [ 'fg_farm', 'start', $farm, $srv ],
            );
        }

        my $msg  = "Success, The farm guardian '$json_obj->{name}' was added to the '$srv_message'";
        my $body = {
            description => $desc,
            message     => $msg,
            status      => &getFarmVipStatus($farm),
        };
        return &httpResponse({ code => 200, body => $body });
    }
    else {
        my $msg = "There was an error trying to add '$json_obj->{name}' to the '$srv_message'";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }
}

#  DELETE /farms/<farm>(/services/<service>)?/fg/<fg_name>
sub delete_fg_from_farm_controller ($farm, $srv, $fgname = undef) {
    unless (defined $fgname) {
        $fgname = $srv;
        $srv    = undef;
    }

    my $srv_message = ($srv) ? "service '$srv' in the farm '$farm'" : "farm '$farm'";
    my $desc        = "Remove the farm guardian '$fgname' from the '$srv_message'";

    require Relianoid::Farm::Service;

    # Check if it exists
    if (!&getFarmExists($farm)) {
        my $msg = "The farm '$farm' does not exist";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # Check if it exists
    if (!&getFGExists($fgname)) {
        my $msg = "The farmguardian '$fgname' does not exist";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # Check if it exists
    if ($srv and not grep { $srv eq $_ } &getFarmServices($farm)) {
        my $msg = "The service '$srv' does not exist";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # link the check with the farm_service
    my $farm_tag = $farm;
    $farm_tag = "${farm}_$srv" if $srv;

    # check if the farm guardian is already applied to the farm
    my $fg_obj = &getFGObject($fgname);
    if (not grep { $farm_tag eq $_ } @{ $fg_obj->{farms} }) {
        my $msg = "The farm guardian '$fgname' is not applied to the '$srv_message'";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    &unlinkFGFarm($fgname, $farm, $srv);

    # check output
    $fg_obj = &getFGObject($fgname);
    if (grep { $farm_tag eq $_ } @{ $fg_obj->{farms} } or &getFGPidFarm($farm)) {
        my $msg = "Error removing '$fgname' from the '$srv_message'";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }
    else {
        require Relianoid::Farm::Base;

        # sync with cluster
        if ($eload) {
            &eload(
                module => 'Relianoid::EE::Cluster',
                func   => 'runClusterRemoteManager',
                args   => [ 'fg_farm', 'stop', $farm, $srv ],
            );
        }

        my $msg  = "Success, '$fgname' was removed from the '$srv_message'";
        my $body = {
            description => $desc,
            message     => $msg,
            status      => &getFarmVipStatus($farm),
        };
        return &httpResponse({ code => 200, body => $body });
    }
}

1;

