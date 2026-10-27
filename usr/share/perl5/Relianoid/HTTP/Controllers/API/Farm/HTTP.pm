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

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type !~ /http|eproxy/) {
        my $msg = "This feature is only for HTTP or Eproxy profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_request_add-create.json");

    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my $message = "Added a new item to the addheader list";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    if ($type =~ /http/) {
        for my $header (@{ &getHTTPAddReqHeader($farmname) }) {
            if ($header->{header} eq $json_obj->{header}) {
                my $msg = "The header is already added.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        if (!&addHTTPAddheader($farmname, $json_obj->{header})) {
            if (&getFarmStatus($farmname) ne 'down') {
                require Relianoid::Farm::Action;
                &setFarmRestart($farmname);
                $body->{status} = 'needed restart';
            }

            return &httpResponse({ code => 200, body => $body });
        }
    } elsif ($type eq "eproxy" && $eload) {
        my $headers = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'getEproxyFarmHeaders',
            args   => [ { farm_name => $farmname } ]
        );

        for my $header (@{ $headers->{request_headers_to_add} }) {
            my $pair;
            ($pair->{key}, $pair->{value}) = split(":",$json_obj->{header});
            if ($header->{key} eq $pair->{key}) {
                my $msg = "The header is already added.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        my $inbound_headers = { request_headers_to_add => [ { header => $json_obj->{header} } ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'addEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers } ]
        );

        return &httpResponse({ code => 200, body => $body });
    }

    my $msg = "Error adding a new addheader";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# PUT	/farms/<>/addheader/<id>
sub modify_addheader_controller ($json_obj, $farmname, $index) {
    my $desc = "Modify an addheader directive.";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type !~ /http|eproxy/) {
        my $msg = "This feature is only for HTTP and Eproxy profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_request_add-modify.json");

    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my $message = "Modified an item from the addheader list";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    if ($type =~ /http/) {
        my @directives = @{ &getHTTPAddReqHeader($farmname) };

        if ((scalar @directives) < $index + 1) {
            my $msg = "The header with index $index not found.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        for my $header (@directives) {
            if ($header->{header} eq $json_obj->{header}) {
                my $msg = "The header is already added.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        unless (&modifyHTTPAddheader($farmname, $json_obj->{header}, $index)) {

            if (&getFarmStatus($farmname) ne 'down') {
                require Relianoid::Farm::Action;
                &setFarmRestart($farmname);
                $body->{status} = 'needed restart';
            }

            return &httpResponse({ code => 200, body => $body });
        }
    } elsif ($type eq "eproxy" && $eload) {
        my $inbound_headers_delete = { request_headers_to_add => [ { id => $index } ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'delEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers_delete } ]
        );
        my $inbound_headers_add = { request_headers_to_add => [ { header => $json_obj->{header} } ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'addEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers_add } ]
        );

        return &httpResponse({ code => 200, body => $body });
    }

    my $msg = "Error modifying an addheader";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

#  DELETE	/farms/<>/addheader/<>
sub del_addheader_controller ($farmname, $index) {
    my $desc = "Delete addheader directive.";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type !~ /http|eproxy/) {
        my $msg = "This feature is only for HTTP and Eproxy profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $message = "The addheader was successfully deleted.";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    if ($type =~ /http/) {
        if ((scalar @{ &getHTTPAddReqHeader($farmname) }) < $index + 1) {
            my $msg = "The index has not been found.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        unless (&delHTTPAddheader($farmname, $index)) {
            if (&getFarmStatus($farmname) ne 'down') {
                require Relianoid::Farm::Action;
                &setFarmRestart($farmname);
                $body->{status} = 'needed restart';
            }

            return &httpResponse({ code => 200, body => $body });
        }
    } elsif ($type eq "eproxy" && $eload) {
        my $inbound_headers = { request_headers_to_add => [ { id => $index } ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'delEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers } ]
        );

        return &httpResponse({ code => 200, body => $body });
    }

    my $msg = "Error deleting the addheader $index";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# POST	/farms/<>/headremove
sub add_headremove_controller ($json_obj, $farmname) {
    my $desc = "Add headremove directive.";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type !~ /http|eproxy/) {
        my $msg = "This feature is only for HTTP and Eproxy profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_request_remove-create.json");

    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my $message = "Added a new item to the headremove list";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    if ($type =~ /http/) {
        for my $header (@{ &getHTTPRemReqHeader($farmname) }) {
            if ($header->{pattern} eq $json_obj->{pattern}) {
                my $msg = "The pattern is already added.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        unless (&addHTTPHeadremove($farmname, $json_obj->{pattern})) {
            if (&getFarmStatus($farmname) ne 'down') {
                require Relianoid::Farm::Action;
                &setFarmRestart($farmname);
                $body->{status} = 'needed restart';
            }

            return &httpResponse({ code => 200, body => $body });
        }
    } elsif ($type eq "eproxy" && $eload) {
        my $headers = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'getEproxyFarmHeaders',
            args   => [ { farm_name => $farmname } ]
        );

        for my $header (@{ $headers->{request_headers_to_remove} }) {
            if ($header eq $json_obj->{pattern}) {
                my $msg = "The header is already added.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        my $inbound_headers = { request_headers_to_remove => [ $json_obj->{pattern} ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'addEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers } ]
        );

        return &httpResponse({ code => 200, body => $body });
    }

    my $msg = "Error adding a new headremove";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# PUT	/farms/<>/headremove/<id>
sub modify_headremove_controller ($json_obj, $farmname, $index) {
    my $desc = "Modify an headremove directive.";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type !~ /http|eproxy/) {
        my $msg = "This feature is only for HTTP and Eproxy profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_request_remove-modify.json");

    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my $message = "Modified an item from the headremove list";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    if ($type =~ /http/) {
        my @directives = @{ &getHTTPRemReqHeader($farmname) };

        if ((scalar @directives) < $index + 1) {
            my $msg = "The header with index $index not found.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        for my $header (@directives) {
            if ($header->{pattern} eq $json_obj->{pattern}) {
                my $msg = "The pattern is already added.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        unless (&modifyHTTPHeadremove($farmname, $json_obj->{pattern}, $index)) {
            if (&getFarmStatus($farmname) ne 'down') {
                require Relianoid::Farm::Action;
                &setFarmRestart($farmname);
                $body->{status} = 'needed restart';
            }

            return &httpResponse({ code => 200, body => $body });
        }
    } elsif ($type eq "eproxy" && $eload) {
        my $inbound_headers_delete = { request_headers_to_remove => [ { id => $index } ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'delEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers_delete } ]
        );
        my $inbound_headers_add = { request_headers_to_remove => [ $json_obj->{pattern} ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'addEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers_add } ]
        );

        return &httpResponse({ code => 200, body => $body });
    }

    my $msg = "Error modifying an headremove";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

#  DELETE	/farms/<>/headremove/<>
sub del_headremove_controller ($farmname, $index) {
    my $desc = "Delete headremove directive.";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type !~ /http|eproxy/) {
        my $msg = "This feature is only for HTTP and Eproxy profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $message = "The headremove was successfully deleted";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    if ($type =~ /http/) {
        if ((scalar @{ &getHTTPRemReqHeader($farmname) }) < $index + 1) {
            my $msg = "The index has not been found.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        unless (&delHTTPHeadremove($farmname, $index)) {
            if (&getFarmStatus($farmname) ne 'down') {
                require Relianoid::Farm::Action;
                &setFarmRestart($farmname);
                $body->{status} = 'needed restart';
            }
        }
        return &httpResponse({ code => 200, body => $body });

    } elsif ($type eq "eproxy" && $eload) {
        my $inbound_headers = { request_headers_to_remove => [ { id => $index } ] };

        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'delEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers } ]
        );

        return &httpResponse({ code => 200, body => $body });
    }

    my $msg = "Error deleting the headremove $index";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# POST	/farms/<>/addresponseheader
sub add_addResHeader_controller ($json_obj, $farmname) {
    my $desc = "Add a header to the backend response.";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type !~ /http|eproxy/) {
        my $msg = "This feature is only for HTTP and Eproxy profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_response_add-create.json");

    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my $message = "Added a new header to the backend response";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    if ($type =~ /http/) {
        for my $header (@{ &getHTTPAddRespHeader($farmname) }) {
            if ($header->{header} eq $json_obj->{header}) {
                my $msg = "The header is already added.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        unless (&addHTTPAddRespheader($farmname, $json_obj->{header})) {
            if (&getFarmStatus($farmname) ne 'down') {
                require Relianoid::Farm::Action;
                &setFarmRestart($farmname);
                $body->{status} = 'needed restart';
            }

            return &httpResponse({ code => 200, body => $body });
        }
    } elsif ($type eq "eproxy" && $eload) {
        my $headers = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'getEproxyFarmHeaders',
            args   => [ { farm_name => $farmname } ]
        );

        for my $header (@{ $headers->{response_headers_to_add} }) {
            my $pair;
            ($pair->{key}, $pair->{value}) = split(":",$json_obj->{header});
            if ($header->{key} eq $pair->{key}) {
                my $msg = "The header is already added.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }
        my $inbound_headers = { response_headers_to_add => [ { header => $json_obj->{header} } ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'addEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers } ]
        );

        return &httpResponse({ code => 200, body => $body });
    }

    my $msg = "Error adding a new response header";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# PUT	/farms/<>/addresponseheader/<id>
sub modify_addResHeader_controller ($json_obj, $farmname, $index) {
    my $desc = "Modify an addresponseheader directive.";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type !~ /http|eproxy/) {
        my $msg = "This feature is only for HTTP and Eproxy profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_response_add-modify.json");
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my $message = "Modified an item from the addresponseheader list";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    if ($type =~ /http/) {
        my @directives = @{ &getHTTPAddRespHeader($farmname) };

        if ((scalar @directives) < $index + 1) {
            my $msg = "The header with index $index not found.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        for my $header (@directives) {
            if ($header->{header} eq $json_obj->{header}) {
                my $msg = "The header is already added.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        unless (&modifyHTTPAddRespheader($farmname, $json_obj->{header}, $index)) {
            if (&getFarmStatus($farmname) ne 'down') {
                require Relianoid::Farm::Action;
                &setFarmRestart($farmname);
                $body->{status} = 'needed restart';
            }

            return &httpResponse({ code => 200, body => $body });
        }
    } elsif ($type eq "eproxy" && $eload) {
        my $inbound_headers_delete = { response_headers_to_add => [ { id => $index } ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'delEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers_delete } ]
        );
        my $inbound_headers_add = { response_headers_to_add => [ { header => $json_obj->{header} } ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'addEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers_add } ]
        );

        return &httpResponse({ code => 200, body => $body });
    }

    my $msg = "Error modifying an addresponseheader";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

#  DELETE	/farms/<>/addresponseheader/<>
sub del_addResHeader_controller ($farmname, $index) {
    my $desc = "Delete a header previously added to the backend response.";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type !~ /http|eproxy/) {
        my $msg = "This feature is only for HTTP and Eproxy profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $message = "The header was successfully deleted.";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    if ($type =~ /http/) {
        if ((scalar @{ &getHTTPAddRespHeader($farmname) }) < $index + 1) {
            my $msg = "The index has not been found.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        unless (&delHTTPAddRespheader($farmname, $index)) {
            if (&getFarmStatus($farmname) ne 'down') {
                require Relianoid::Farm::Action;
                &setFarmRestart($farmname);
                $body->{status} = 'needed restart';
            }

            return &httpResponse({ code => 200, body => $body });
        }
    } elsif ($type eq "eproxy" && $eload) {
        my $inbound_headers = { response_headers_to_add => [ { id => $index } ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'delEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers } ]
        );

        return &httpResponse({ code => 200, body => $body });
    }

    my $msg = "Error deleting the response header";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# POST	/farms/<>/removeresponseheader
sub add_delResHeader_controller ($json_obj, $farmname) {
    my $desc = "Remove a header from the backend response.";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type !~ /http|eproxy/) {
        my $msg = "This feature is only for HTTP and Eproxy profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_response_remove-create.json");

    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my $message = "Added a patter to remove reponse headers";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    if ($type =~ "http") {
        for my $header (@{ &getHTTPRemRespHeader($farmname) }) {
            if ($header->{pattern} eq $json_obj->{pattern}) {
                my $msg = "The pattern is already added.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        unless (&addHTTPRemRespHeader($farmname, $json_obj->{pattern})) {
            if (&getFarmStatus($farmname) ne 'down') {
                require Relianoid::Farm::Action;
                &setFarmRestart($farmname);
                $body->{status} = 'needed restart';
            }

            return &httpResponse({ code => 200, body => $body });
        }
    } elsif ($type eq "eproxy" && $eload) {
        my $headers = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'getEproxyFarmHeaders',
            args   => [ { farm_name => $farmname } ]
        );

        for my $header (@{ $headers->{response_headers_to_remove} }) {
            if ($header eq $json_obj->{pattern}) {
                my $msg = "The header is already added.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        my $inbound_headers = { response_headers_to_remove => [ $json_obj->{pattern} ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'addEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers } ]
        );

        return &httpResponse({ code => 200, body => $body });
    }

    my $msg = "Error adding the remove pattern";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

# PUT	/farms/<>/removeresponseheader/<id>
sub modify_delResHeader_controller ($json_obj, $farmname, $index) {
    my $desc = "Modify a remove response header directive.";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type !~ /http|eproxy/) {
        my $msg = "This feature is only for HTTP and Eproxy profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_http_header_response_remove-modify.json");
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my $message = "Modified an item from the removeresponseheader list";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    if ($type =~ /http/) {
        my @directices = @{ &getHTTPRemRespHeader($farmname) };

        if ((scalar @directices) < $index + 1) {
            my $msg = "The header with index $index not found.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        for my $header (@directices) {
            if ($header->{pattern} eq $json_obj->{pattern}) {
                my $msg = "The pattern is already added.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        unless (&modifyHTTPRemRespHeader($farmname, $json_obj->{header}, $index)) {
            if (&getFarmStatus($farmname) ne 'down') {
                require Relianoid::Farm::Action;
                &setFarmRestart($farmname);
                $body->{status} = 'needed restart';
            }

            return &httpResponse({ code => 200, body => $body });
        }
    } elsif ($type eq "eproxy" && $eload) {
        my $inbound_headers_delete = { response_headers_to_remove => [ { id => $index } ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'delEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers_delete } ]
        );
        my $inbound_headers_add = { response_headers_to_remove => [ $json_obj->{pattern} ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'addEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers_add } ]
        );

        return &httpResponse({ code => 200, body => $body });
    }

    my $msg = "Error modifying an removeresponseheader";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

#  DELETE	/farms/<>/removeresponseheader/<>
sub del_delResHeader_controller ($farmname, $index) {
    my $desc = "Delete a pattern to remove response headers.";

    if (!&getFarmExists($farmname)) {
        my $msg = "The farm '$farmname' does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type !~ /http|eproxy/) {
        my $msg = "This feature is only for HTTP and Eproxy profiles.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $message = "The pattern was successfully deleted.";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    if ($type =~ /http/) {
        if ((scalar @{ &getHTTPRemRespHeader($farmname) }) < $index + 1) {
            my $msg = "The index has not been found.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        unless (&delHTTPRemRespHeader($farmname, $index)) {

            if (&getFarmStatus($farmname) ne 'down') {
                require Relianoid::Farm::Action;
                &setFarmRestart($farmname);
                $body->{status} = 'needed restart';
            }

            return &httpResponse({ code => 200, body => $body });
        }
    } elsif ($type eq "eproxy" && $eload) {
        my $inbound_headers = { response_headers_to_remove => [ { id => $index } ] };
        &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Headers',
            func   => 'delEproxyFarmHeaders',
            args   => [ { farm_name => $farmname, headers => $inbound_headers } ]
        );

        return &httpResponse({ code => 200, body => $body });
    }

    my $msg = "Error deleting the pattern $index";
    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
}

1;
