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

Relianoid::HTTP::Controllers::API::Certificate

=cut

my $eload = eval { require Relianoid::ELoad };

my $CSR_KEY_SIZE = 2048;

# GET /certificates
sub list_certificates_controller () {
    require Relianoid::Certificate;

    my $desc         = "List certificates";
    my @certificates = &getCertFiles();
    my $configdir    = &getGlobalConfiguration('certdir');
    my @out;

    for my $cert (sort @certificates) {
        push @out, &getCertInfo("$configdir/$cert");
    }

    my $body = {
        description => $desc,
        params      => \@out,
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET /certificates/CERTIFICATE/info
sub get_certificate_info_controller ($cert_filename) {
    require Relianoid::Certificate;

    my $desc     = "Show certificate details";
    my $cert_dir = &getGlobalConfiguration('certdir');

    # check is the certificate file exists
    if (!-f "$cert_dir\/$cert_filename") {
        my $msg = "Certificate file not found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    if (not &getValidFormat('certificate', $cert_filename)) {
        my $msg = "Could not get such certificate information";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $cert = &getCertData("$cert_dir\/$cert_filename", "true");
    return &httpResponse({ code => 200, body => $cert, type => 'text/plain' });
}

# GET /certificates/CERTIFICATE
sub download_certificate_controller ($cert_filename) {
    my $desc      = "Download certificate";
    my $cert_dir  = &getGlobalConfiguration('certdir');
    my $cert_path = "$cert_dir/$cert_filename";

    unless ($cert_filename =~ /\.(pem|csr)$/ && -f $cert_path) {
        my $msg = "Could not find such certificate";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    return &httpDownloadResponse(desc => $desc, dir => $cert_dir, file => $cert_filename);
}

# DELETE /certificates/CERTIFICATE
sub delete_certificate_controller ($cert_filename) {
    require Relianoid::Certificate;
    require Relianoid::Letsencrypt;

    my $desc     = "Delete certificate";
    my $cert_dir = &getGlobalConfiguration('certdir');

    # check is the certificate file exists
    if (!-f "$cert_dir\/$cert_filename") {
        my $msg = "Certificate file not found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $status = &getFarmCertUsed($cert_filename);

    # check is the certificate is being used
    if ($status == 0) {
        my $msg = "File can't be deleted because it's in use by a farm.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    if ($eload) {
        $status = &eload(
            module => 'Relianoid::EE::System::HTTP',
            func   => 'getHttpsCertUsed',
            args   => [$cert_filename]
        );

        if ($status == 0) {
            my $msg = "File can't be deleted because it's in use by HTTPS server";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # check if it is a LE certificate
    my $le_cert_name = $cert_filename;
    $le_cert_name =~ s/.pem//g;
    $le_cert_name =~ s/\_/\./g;
    my $error;
    if (@{ &getLetsencryptCertificates($le_cert_name) }) {
        $error = &runLetsencryptDestroy($le_cert_name);
    }

    if ($eload) {
        my $wildcard = &eload(
            module => 'Relianoid::EE::Letsencrypt::Wildcard',
            func   => 'getLetsencryptWildcardCertificates',
            args   => [$le_cert_name]
        );

        if (@{$wildcard}) {
            $error = &eload(
                module => 'Relianoid::EE::Letsencrypt::Wildcard',
                func   => 'runLetsencryptWildcardDestroy',
                args   => [$le_cert_name]
            );
        }
    }

    if ($error) {
        my $msg = "LE Certificate can not be removed";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    &delCert($cert_filename);

    # check if the certificate exists
    if (-f "$cert_dir\/$cert_filename") {
        my $msg = "Error deleting certificate $cert_filename.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # no errors found, make a succesful response
    my $msg  = "The Certificate $cert_filename has been deleted.";
    my $body = {
        description => $desc,
        success     => "true",
        message     => $msg,
    };

    return &httpResponse({ code => 200, body => $body });
}

# POST /certificates (Create CSR)
sub create_csr_controller ($json_obj) {
    require Relianoid::Certificate;

    my $desc      = 'Create CSR';
    my $configdir = &getGlobalConfiguration('certdir');

    if (-f "$configdir/$json_obj->{name}.csr") {
        my $msg = "$json_obj->{name} already exists.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("certificate_csr-create.json");
    $params->{fqdn}{function} = \&checkFQDN;

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my $error = &createCSR(
        $json_obj->{name},     $json_obj->{fqdn},         $json_obj->{country},  $json_obj->{state},
        $json_obj->{locality}, $json_obj->{organization}, $json_obj->{division}, $json_obj->{mail},
        $CSR_KEY_SIZE,         ""
    );

    if ($error) {
        my $msg = "Error, creating certificate $json_obj->{name}.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $message = "Certificate $json_obj->{name} created";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    return &httpResponse({ code => 200, body => $body });
}

# POST /certificates/CERTIFICATE (Upload PEM)
sub upload_certificate_controller ($upload_data, $filename) {
    require Relianoid::File;

    my $desc      = "Upload PEM certificate";
    my $configdir = &getGlobalConfiguration('certdir');

    # add extension if it does not exist
    $filename .= ".pem" if $filename !~ /\.pem$/;

    # check if the certificate filename already exists
    $filename =~ s/[\(\)\@ ]//g;
    if (-f "$configdir/$filename") {
        my $msg = "Certificate file name already exists";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    unless (&setFile("$configdir/$filename", $upload_data)) {
        my $msg = "Could not save the certificate file";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # no errors found, return sucessful response
    my $message = "Certificate uploaded";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET /ciphers
sub get_ciphers_controller () {
    my $desc = "Get the ciphers available";

    my @out = (
        { 'ciphers' => "all",            "description" => "All" },
        { 'ciphers' => "highsecurity",   "description" => "High security" },
        { 'ciphers' => "customsecurity", "description" => "Custom security" }
    );

    if ($eload) {
        push(@out, &eload(module => 'Relianoid::EE::Farm::HTTP::HTTPS::Ext', func => 'getExtraCipherProfiles',));
    }

    my $body = {
        description => $desc,
        params      => \@out,
    };

    return &httpResponse({ code => 200, body => $body });
}

# POST /farms/FARM/certificates (Add certificate to farm)
sub add_farm_certificate_controller ($json_obj, $farmname) {
    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;
    unless ($eload) { require Relianoid::Farm::HTTP::HTTPS; }

    my $desc = "Add certificate to farm '$farmname'";

    # Check if the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "Farm not found";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # Check if the farm exists
    if (&getFarmType($farmname) ne 'https') {
        my $msg = "This feature is only available for 'https' farms";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("farm_certificate-add.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    my $configdir = &getGlobalConfiguration('certdir');

    # validate certificate filename and format
    unless (-f $configdir . "/" . $json_obj->{file}) {
        my $msg = "The certificate does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $cert_in_use;
    if ($eload) {
        $cert_in_use = grep { $json_obj->{file} eq $_ } &eload(
            module => 'Relianoid::EE::Farm::HTTP::HTTPS::Ext',
            func   => 'getFarmCertificatesSNI',
            args   => [$farmname]
        );
    }
    else {
        $cert_in_use = &getFarmCertificate($farmname) eq $json_obj->{file};
    }

    if ($cert_in_use) {
        my $msg = "The certificate already exists in the farm.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $status;
    if ($eload) {
        $status = &eload(
            module => 'Relianoid::EE::Farm::HTTP::HTTPS::Ext',
            func   => 'setFarmCertificateSNI',
            args   => [ $json_obj->{file}, $farmname ],
        );
    }
    else {
        $status = &setFarmCertificate($json_obj->{file}, $farmname);
    }

    if ($status) {
        my $msg = "It's not possible to add the certificate with name $json_obj->{file} for the $farmname farm";

        &log_error("It's not possible to add the certificate.", "LSLB");
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # no errors found, return succesful response
    &log_info("Success trying to add a certificate to the farm.", "LSLB");

    my $message =
      "The certificate $json_obj->{file} has been added to the farm $farmname, you need restart the farm to apply";

    my $body = {
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

# DELETE /farms/FARM/certificates/CERTIFICATE
sub delete_farm_certificate_controller ($farmname, $certfilename) {
    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    my $desc = "Delete farm certificate";

    unless ($eload) {
        my $msg = "HTTPS farm without certificate is not allowed.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # Check if the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "The farmname $farmname does not exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # validate certificate
    unless ($certfilename && &getValidFormat('cert_pem', $certfilename)) {
        my $msg = "Invalid certificate id, please insert a valid value.";
        &log_error("Invalid certificate id.", "LSLB");
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my @certSNI = &eload(
        module => 'Relianoid::EE::Farm::HTTP::HTTPS::Ext',
        func   => 'getFarmCertificatesSNI',
        args   => [$farmname],
    );

    my $number = scalar grep ({ $_ eq $certfilename } @certSNI);
    if (!$number) {
        my $msg = "Certificate is not used by the farm.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    if (@certSNI == 1 or ($number == @certSNI)) {
        my $msg = "The certificate '$certfilename' could not be deleted, the farm needs one certificate at least.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $status;

    # This is a BUGFIX: delete the certificate all times that it appears in config file
    for (my $it = 0 ; $it < $number ; $it++) {
        $status = &eload(
            module => 'Relianoid::EE::Farm::HTTP::HTTPS::Ext',
            func   => 'setFarmDeleteCertNameSNI',
            args   => [ $certfilename, $farmname ],
        );
        last if ($status == -1);
    }

    # check if the certificate could not be removed
    if ($status == -1) {
        &log_error("It's not possible to delete the certificate.", "LSLB");

        my $msg = "It isn't possible to delete the selected certificate $certfilename from the SNI list";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # check if removing the certificate would leave the SNI list empty, not supported
    if ($status == 1) {
        &log_error("It's not possible to delete all certificates, at least one is required for HTTPS.", "LSLB");

        my $msg = "It isn't possible to delete all certificates, at least one is required for HTTPS profiles";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # no errors found, return succesful response
    my $msg  = "The Certificate $certfilename has been deleted";
    my $body = {
        description => $desc,
        success     => "true",
        message     => $msg
    };

    if (&getFarmStatus($farmname) ne 'down') {
        require Relianoid::Farm::Action;
        &setFarmRestart($farmname);
        $body->{status} = 'needed restart';
    }

    &log_info("Success trying to delete a certificate to the SNI list.", "LSLB");

    return &httpResponse({ code => 200, body => $body });
}

# POST /certificates/pem (Create PEM)
sub create_certificate_controller ($json_obj) {
    my $desc = "Create certificate";

    my $configdir = &getGlobalConfiguration('certdir');

    if (-f "$configdir/$json_obj->{name}.pem") {
        my $msg = "$json_obj->{name} already exists.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("certificate_pem-create.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    require Relianoid::Certificate;
    my $error = &createPEM($json_obj->{name}, $json_obj->{key}, $json_obj->{ca}, $json_obj->{intermediates});

    if ($error->{code}) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error->{desc} });
    }

    # no errors found, return sucessful response
    my $message = "Certificate $json_obj->{name} created";
    my $body    = {
        description => $desc,
        success     => "true",
        message     => $message,
    };

    return &httpResponse({ code => 200, body => $body });
}

1;
