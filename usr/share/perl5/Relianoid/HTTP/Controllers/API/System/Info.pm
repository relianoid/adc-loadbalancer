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

Relianoid::HTTP::Controllers::API::System::Info

=cut

# show license
# GET /system/license/($license_re)
sub get_license_controller ($format) {
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
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $file = &slurpFile($licenseFile);

    return &httpResponse({ code => 200, body => $file, type => 'text/plain' });
}

# GET /system/support
sub get_support_file_controller () {
    my $desc = "Get support file";

    my $req_size = &checkSupportFileSpace();
    if ($req_size) {
        my $space = &getSpaceFormatHuman($req_size);
        my $msg   = "Support file cannot be generated because '/tmp' needs '$space' Bytes of free space";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $ss_filename = &getSupportFile();

    return &httpDownloadResponse(desc => $desc, dir => '/tmp', file => $ss_filename);
}

# GET /system/version
sub get_version_controller () {
    require Relianoid::SystemInfo;

    my $desc = "Get version";

    my $params = {
        kernel_version    => &getKernelVersion(),
        relianoid_version => &getGlobalConfiguration('version'),
        hostname          => &getHostname(),
        system_date       => &getDate(),
        appliance_version => &getApplianceVersion(),
    };

    # For compatibility with previous versions
    $params->{zevenet_version} = $params->{relianoid_version};

    my $body = { description => $desc, params => $params };

    return &httpResponse({ code => 200, body => $body });
}

# GET /system/info
sub get_system_info_controller () {
    require Relianoid::SystemInfo;
    require Relianoid::User;

    my $desc = "Get the system information";

    my @api_versions = &get_api_versions_list();

    my $params = {
        system_date             => &getDate(),
        appliance_version       => &getApplianceVersion(),
        kernel_version          => &getKernelVersion(),
        relianoid_version       => &getGlobalConfiguration('version'),
        hostname                => &getHostname(),
        user                    => &getUser(),
        supported_zapi_versions => \@api_versions,
        supported_api_versions  => \@api_versions,
        last_zapi_version       => $api_versions[-1],
        last_api_version        => $api_versions[-1],
        edition                 => $eload ? "enterprise" : "community",
        language                => &getGlobalConfiguration('lang'),
        platform                => &getGlobalConfiguration('cloud_provider'),
    };

    # For compatibility with previous versions
    $params->{zevenet_version} = $params->{relianoid_version};

    if ($eload) {
        $params = &eload(
            module => 'Relianoid::EE::System::Ext',
            func   => 'getSystemInfoExt',
            args   => [$params],
        );
    }

    my $body = { description => $desc, params => $params };
    return &httpResponse({ code => 200, body => $body });
}

# POST /system/language
sub set_language_controller ($json_obj) {
    my $desc   = "Modify the web GUI language";
    my $params = &getAPIModel("system_language-modify.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # Check allowed parameters
    &setGlobalConfiguration('lang', $json_obj->{language});

    return &httpResponse({
        code => 200,
        body => {
            description => $desc,
            params      => { language => &getGlobalConfiguration('lang') },
            message     => "The WebGui language has been configured successfully"
        }
    });
}

# GET /system/language
sub get_language_controller () {
    my $desc = "Get the web GUI language";
    my $lang = &getGlobalConfiguration('lang') || 'en';

    return &httpResponse({
        code => 200,
        body => {
            description => $desc,
            params      => { lang => $lang },
        }
    });
}

# GET /system/packages
sub get_packages_info_controller () {
    require Relianoid::System::Packages;

    my $desc   = "Relianoid packages list info";
    my $output = &getSystemPackagesUpdatesList();

    if (defined $output->{number}) {
        $output->{number} += 0;
    }

    return &httpResponse({ code => 200, body => { description => $desc, params => $output } });
}

1;
