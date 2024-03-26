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

use Relianoid::System;

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::API40::System::Info

=cut

# show license
sub get_license ($format) {
    my $desc = "Get license";
    my $licenseFile;

    if ($format eq 'txt') {
        $licenseFile = &getGlobalConfiguration('licenseFileTxt');
    }
    elsif ($format eq 'html') {
        $licenseFile = &getGlobalConfiguration('licenseFileHtml');
    }
    else {
        my $msg = "Not found license.";
        &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $file = &slurpFile($licenseFile);

    &httpResponse({ code => 200, body => $file, type => 'text/plain' });
    return;
}

sub get_supportsave () {
    my $desc = "Get supportsave file";

    my $req_size = &checkSupportSaveSpace();
    if ($req_size) {
        my $space = &getSpaceFormatHuman($req_size);
        my $msg   = "Supportsave cannot be generated because '/tmp' needs '$space' Bytes of free space";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $ss_filename = &getSupportSave();

    &httpDownloadResponse(desc => $desc, dir => '/tmp', file => $ss_filename);
    return;
}

# GET /system/version
sub get_version () {
    require Relianoid::SystemInfo;

    my $desc = "Get version";

    my $params = {
        'kernel_version'    => &getKernelVersion(),
        'relianoid_version' => &getGlobalConfiguration('version'),
        'hostname'          => &getHostname(),
        'system_date'       => &getDate(),
        'appliance_version' => &getApplianceVersion(),
    };

    # For compatibility with previous versions
    $params->{'zevenet_version'} = $params->{'relianoid_version'};

    my $body = { description => $desc, params => $params };

    &httpResponse({ code => 200, body => $body });
    return;
}

# GET /system/info
sub get_system_info () {
    require Relianoid::SystemInfo;
    require Relianoid::User;
    require Relianoid::API;

    my $desc = "Get the system information";

    my @api_versions = &getApiVersionsList();

    my $params = {
        'system_date'             => &getDate(),
        'appliance_version'       => &getApplianceVersion(),
        'kernel_version'          => &getKernelVersion(),
        'relianoid_version'       => &getGlobalConfiguration('version'),
        'hostname'                => &getHostname(),
        'user'                    => &getUser(),
        'supported_zapi_versions' => \@api_versions,
        'last_zapi_version'       => $api_versions[-1],
        'edition'                 => $eload ? "enterprise" : "community",
        'language'                => &getGlobalConfiguration('lang'),
        'platform'                => &getGlobalConfiguration('cloud_provider'),
    };

    # For compatibility with previous versions
    $params->{'zevenet_version'} = $params->{'relianoid_version'};

    if ($eload) {
        $params = &eload(
            module => 'Relianoid::System::Ext',
            func   => 'setSystemExtendZapi',
            args   => [$params],
        );
    }

    my $body = { description => $desc, params => $params };
    &httpResponse({ code => 200, body => $body });
    return;
}

#  POST /system/language
sub set_language ($json_obj) {
    my $desc   = "Modify the WebGUI language";
    my $params = &getAPIModel("system_language-modify.json");

    # Check allowed parameters
    my $error_msg = &checkApiParams($json_obj, $params, $desc);
    if ($error_msg) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # Check allowed parameters
    &setGlobalConfiguration('lang', $json_obj->{language});

    &httpResponse({
        code => 200,
        body => {
            description => $desc,
            params      => { language => &getGlobalConfiguration('lang') },
            message     => "The WebGui language has been configured successfully"
        }
    });
    return;
}

#  GET /system/language
sub get_language () {
    my $desc = "List the WebGUI language";
    my $lang = &getGlobalConfiguration('lang') // 'en';

    &httpResponse({
        code => 200,
        body => {
            description => $desc,
            params      => { lang => $lang },
        }
    });
    return;
}

# GET /system/packages
sub get_packages_info () {
    require Relianoid::System::Packages;

    my $desc   = "Relianoid packages list info";
    my $output = &getSystemPackagesUpdatesList();

    if (defined $output->{number}) {
        $output->{number} += 0;
    }

    &httpResponse({ code => 200, body => { description => $desc, params => $output } });
    return;
}

1;
