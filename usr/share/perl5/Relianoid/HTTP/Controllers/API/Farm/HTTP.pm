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

use Relianoid::HTTP;
use Relianoid::Farm::Base;
use Relianoid::Farm::HTTP::Config;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::Farm::HTTP

=cut

# POST	/farms/<>/addheader
sub add_addheader_controller ($json_obj, $farmname) {
    my $desc = "Add addheader directive.";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) !~ /http/) {
        my $msg = "This feature is only for HTTP profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_request_add-create.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # check if the header is already added
    for my $header (@{ &getHTTPAddReqHeader($farmname) }) {
        if ($header->{header} eq $json_obj->{header}) {
            my $msg = "The header is already added.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    unless (&addHTTPAddheader($farmname, $json_obj->{header})) {
        # success
        my $message = "Added a new item to the addheader list";
        my $body    = {
            description => $desc,
            success     => "true",
            message     => $message,
        };

        if (&getFarmStatus($farmname) ne 'down') {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }

        return &httpResponse({ code => 200, body => $body });
    }

    # error
    my $msg = "Error adding a new addheader";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# PUT	/farms/<>/addheader/<id>
sub modify_addheader_controller ($json_obj, $farmname, $index) {
    my $desc = "Modify an addheader directive.";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) !~ /http/) {
        my $msg = "This feature is only for HTTP profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_request_add-modify.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my @directives = @{ &getHTTPAddReqHeader($farmname) };

    # check if the header exists
    if ((scalar @directives) < $index + 1) {
        my $msg = "The header with index $index not found.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the header is already added
    for my $header (@directives) {
        if ($header->{header} eq $json_obj->{header}) {
            my $msg = "The header is already added.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    unless (&modifyHTTPAddheader($farmname, $json_obj->{header}, $index)) {
        # success
        my $message = "Modified an item from the addheader list";
        my $body    = {
            description => $desc,
            success     => "true",
            message     => $message,
        };

        if (&getFarmStatus($farmname) ne 'down') {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }

        return &httpResponse({ code => 200, body => $body });
    }

    # error
    my $msg = "Error modifying an addheader";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

#  DELETE	/farms/<>/addheader/<>
sub del_addheader_controller ($farmname, $index) {
    my $desc = "Delete addheader directive.";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) !~ /http/) {
        my $msg = "This feature is only for HTTP profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the header is already added
    if ((scalar @{ &getHTTPAddReqHeader($farmname) }) < $index + 1) {
        my $msg = "The index has not been found.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    unless (&delHTTPAddheader($farmname, $index)) {
        # success
        my $message = "The addheader $index was deleted successfully";
        my $body    = {
            description => $desc,
            success     => "true",
            message     => $message,
        };

        if (&getFarmStatus($farmname) ne 'down') {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }

        return &httpResponse({ code => 200, body => $body });
    }

    # error
    my $msg = "Error deleting the addheader $index";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# POST	/farms/<>/headremove
sub add_headremove_controller ($json_obj, $farmname) {
    my $desc = "Add headremove directive.";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) !~ /http/) {
        my $msg = "This feature is only for HTTP profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_request_remove-create.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # check if the header is already added
    for my $header (@{ &getHTTPRemReqHeader($farmname) }) {
        if ($header->{pattern} eq $json_obj->{pattern}) {
            my $msg = "The pattern is already added.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    unless (&addHTTPHeadremove($farmname, $json_obj->{pattern})) {
        # success
        my $message = "Added a new item to the headremove list";
        my $body    = {
            description => $desc,
            success     => "true",
            message     => $message,
        };

        if (&getFarmStatus($farmname) ne 'down') {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }

        return &httpResponse({ code => 200, body => $body });
    }

    # error
    my $msg = "Error adding a new headremove";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# PUT	/farms/<>/headremove/<id>
sub modify_headremove_controller ($json_obj, $farmname, $index) {
    my $desc = "Modify an headremove directive.";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) !~ /http/) {
        my $msg = "This feature is only for HTTP profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_request_remove-modify.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my @directives = @{ &getHTTPRemReqHeader($farmname) };

    # check if the header exists
    if ((scalar @directives) < $index + 1) {
        my $msg = "The header with index $index not found.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the new pattern is already added
    for my $header (@directives) {
        if ($header->{pattern} eq $json_obj->{pattern}) {
            my $msg = "The pattern is already added.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    unless (&modifyHTTPHeadremove($farmname, $json_obj->{pattern}, $index)) {
        # success
        my $message = "Modified an item from the headremove list";
        my $body    = {
            description => $desc,
            success     => "true",
            message     => $message,
        };

        if (&getFarmStatus($farmname) ne 'down') {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }

        return &httpResponse({ code => 200, body => $body });
    }

    # error
    my $msg = "Error modifying an headremove";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

#  DELETE	/farms/<>/addheader/<>
sub del_headremove_controller ($farmname, $index) {
    my $desc = "Delete headremove directive.";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) !~ /http/) {
        my $msg = "This feature is only for HTTP profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the headremove is already added
    if ((scalar @{ &getHTTPRemReqHeader($farmname) }) < $index + 1) {
        my $msg = "The index has not been found.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    unless (&delHTTPHeadremove($farmname, $index)) {
        # success
        my $message = "The headremove $index was deleted successfully";
        my $body    = {
            description => $desc,
            success     => "true",
            message     => $message,
        };

        if (&getFarmStatus($farmname) ne 'down') {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }

        return &httpResponse({ code => 200, body => $body });
    }

    # error
    my $msg = "Error deleting the headremove $index";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# POST	/farms/<>/addheader
sub add_addResHeader_controller ($json_obj, $farmname) {
    my $desc = "Add a header to the backend repsonse.";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) !~ /http/) {
        my $msg = "This feature is only for HTTP profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_response_add-create.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # check if the header is already added
    for my $header (@{ &getHTTPAddRespHeader($farmname) }) {
        if ($header->{header} eq $json_obj->{header}) {
            my $msg = "The header is already added.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    unless (&addHTTPAddRespheader($farmname, $json_obj->{header})) {
        # success
        my $message = "Added a new header to the backend response";
        my $body    = {
            description => $desc,
            success     => "true",
            message     => $message,
        };

        if (&getFarmStatus($farmname) ne 'down') {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }

        return &httpResponse({ code => 200, body => $body });
    }

    # error
    my $msg = "Error adding a new response header";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# PUT	/farms/<>/addresponseheader/<id>
sub modify_addResHeader_controller ($json_obj, $farmname, $index) {
    my $desc = "Modify an addresponseheader directive.";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) !~ /http/) {
        my $msg = "This feature is only for HTTP profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_response_add-modify.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my @directives = @{ &getHTTPAddRespHeader($farmname) };

    # check if the header exists
    if ((scalar @directives) < $index + 1) {
        my $msg = "The header with index $index not found.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the header is already added
    for my $header (@directives) {
        if ($header->{header} eq $json_obj->{header}) {
            my $msg = "The header is already added.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    unless (&modifyHTTPAddRespheader($farmname, $json_obj->{header}, $index)) {
        # success
        my $message = "Modified an item from the addresponseheader list";
        my $body    = {
            description => $desc,
            success     => "true",
            message     => $message,
        };

        if (&getFarmStatus($farmname) ne 'down') {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }

        return &httpResponse({ code => 200, body => $body });
    }

    # error
    my $msg = "Error modifying an addresponseheader";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

#  DELETE	/farms/<>/addresponseheader/<>
sub del_addResHeader_controller ($farmname, $index) {
    my $desc = "Delete a header previously added to the backend response.";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) !~ /http/) {
        my $msg = "This feature is only for HTTP profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the header is already added
    if ((scalar @{ &getHTTPAddRespHeader($farmname) }) < $index + 1) {
        my $msg = "The index has not been found.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    unless (&delHTTPAddRespheader($farmname, $index)) {
        # success
        my $message = "The header $index was deleted successfully";
        my $body    = {
            description => $desc,
            success     => "true",
            message     => $message,
        };

        if (&getFarmStatus($farmname) ne 'down') {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }

        return &httpResponse({ code => 200, body => $body });
    }

    # error
    my $msg = "Error deleting the response header $index";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# POST	/farms/<>/removeresponseheader
sub add_delResHeader_controller ($json_obj, $farmname) {
    my $desc = "Remove a header from the backend response.";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) !~ /http/) {
        my $msg = "This feature is only for HTTP profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_response_remove-create.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # check if the header is already added
    for my $header (@{ &getHTTPRemRespHeader($farmname) }) {
        if ($header->{pattern} eq $json_obj->{pattern}) {
            my $msg = "The pattern is already added.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    unless (&addHTTPRemRespHeader($farmname, $json_obj->{pattern})) {
        # success
        my $message = "Added a patter to remove reponse headers";
        my $body    = {
            description => $desc,
            success     => "true",
            message     => $message,
        };

        if (&getFarmStatus($farmname) ne 'down') {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }

        return &httpResponse({ code => 200, body => $body });
    }

    # error
    my $msg = "Error adding the remove pattern";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# PUT	/farms/<>/removeresponseheader/<id>
sub modify_delResHeader_controller ($json_obj, $farmname, $index) {
    my $desc = "Modify a remove response header directive.";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) !~ /http/) {
        my $msg = "This feature is only for HTTP profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_response_remove-modify.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my @directices = @{ &getHTTPRemRespHeader($farmname) };

    # check if the header exists
    if ((scalar @directices) < $index + 1) {
        my $msg = "The header with index $index not found.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the header is already added
    for my $header (@directices) {
        if ($header->{pattern} eq $json_obj->{pattern}) {
            my $msg = "The pattern is already added.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    unless (&modifyHTTPRemRespHeader($farmname, $json_obj->{header}, $index)) {
        # success
        my $message = "Modified an item from the removeresponseheader list";
        my $body    = {
            description => $desc,
            success     => "true",
            message     => $message,
        };

        if (&getFarmStatus($farmname) ne 'down') {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }

        return &httpResponse({ code => 200, body => $body });
    }

    # error
    my $msg = "Error modifying an removeresponseheader";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

#  DELETE	/farms/<>/addheader/<>
sub del_delResHeader_controller ($farmname, $index) {
    my $desc = "Delete a pattern to remove response headers.";

    # Check that the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (&getFarmType($farmname) !~ /http/) {
        my $msg = "This feature is only for HTTP profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if the headremove is already added
    if ((scalar @{ &getHTTPRemRespHeader($farmname) }) < $index + 1) {
        my $msg = "The index has not been found.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    unless (&delHTTPRemRespHeader($farmname, $index)) {
        # success
        my $message = "The pattern $index was deleted successfully";
        my $body    = {
            description => $desc,
            success     => "true",
            message     => $message,
        };

        if (&getFarmStatus($farmname) ne 'down') {
            require Relianoid::Farm::Action;
            &setFarmRestart($farmname);
            $body->{status} = 'needed restart';
        }

        return &httpResponse({ code => 200, body => $body });
    }

    # error
    my $msg = "Error deleting the pattern $index";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

1;
