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

use File::stat;

use Relianoid::Core;
use Relianoid::Config;

my $openssl = &getGlobalConfiguration('openssl');

=pod

=head1 Module

Relianoid::Certificate

- Privacy-Enhanced Mail (PEM)
- Certificate Signing Request (CSR)

=cut

=pod

=head1 getCertFiles

Returns a list of all .pem and .csr certificate files in the config directory.

Parameters:

    none

Returns:

    list - certificate files in config/ directory.

=cut

sub getCertFiles () {
    my $configdir = &getGlobalConfiguration('certdir');
    my $dir;

    opendir($dir, $configdir);
    my @files = grep { /.*\.pem$/ } readdir($dir);
    @files = grep { !/_dh\d+\.pem$/ } @files;
    closedir($dir);

    opendir($dir, $configdir);
    push(@files, grep { /.*\.csr$/ } readdir($dir));
    closedir($dir);

    return @files;
}

=pod

=head1 getPemCertFiles

Returns a list of only .pem certificate files in the config directory.

Parameters:

    none

Returns:

    list - certificate files in config/ directory.

=cut

sub getPemCertFiles () {
    my $configdir = &getGlobalConfiguration('certdir');

    opendir(my $dir, $configdir);
    my @files = grep { /.*\.pem$/ } readdir($dir);
    @files = grep { !/_dh\d+\.pem$/ } @files;
    closedir($dir);

    return @files;
}

=pod

=head1 getCertType

Return the type of a certificate filename.

The certificate types are:

    Certificate - For .pem or .crt certificates
    CSR         - For .csr certificates
    none        - for any other file or certificate

Parameters:

    String - Certificate filename.

Returns:

    String - Certificate type.

=cut

sub getCertType ($certfile) {
    my $certtype = "none";

    if ($certfile =~ /\.pem/ || $certfile =~ /\.crt/) {
        $certtype = "Certificate";
    }
    elsif ($certfile =~ /\.csr/) {
        $certtype = "CSR";
    }

    return $certtype;
}

=pod

=head1 getCertExpiration

Return the expiration date of a certificate file

Parameters:

    String - Certificate filename.

Returns:

    String - Expiration date.

=cut

sub getCertExpiration ($certfile) {
    my $expiration_date = "";

    if (&getCertType($certfile) eq "Certificate") {
        my @eject  = `$openssl x509 -noout -in $certfile -dates`;
        my @dateto = split(/=/, $eject[1]);
        $expiration_date = $dateto[1];
    }
    else {
        $expiration_date = "NA";
    }

    return $expiration_date;
}

=pod

=head1 getFarmCertUsed

Get if a certificate file is being used by an HTTP farm

Parameters:

    String - Certificate filename.

Returns:

    Integer - 0 if the certificate is being used, or -1 if it is not.

=cut

sub getFarmCertUsed ($cfile) {
    require Relianoid::File;
    require Relianoid::Farm::Core;

    my $certdir   = &getGlobalConfiguration('certdir');
    my $configdir = &getGlobalConfiguration('configdir');
    my @farms     = &getFarmsByType("https");
    my $output    = -1;

    for my $fname (@farms) {
        my $farm_filename = &getFarmFile($fname);

        if (grep { /Cert \"$certdir\/\Q$cfile\E\"/ } readFileAsArray("$configdir/$farm_filename")) {
            $output = 0;
        }
    }

    return $output;
}

=pod

=head1 getCertFarmsUsed

Get HTTPS Farms list using the certificate file. 

Parameters:

    String - Certificate filename.

Returns:

    Array ref - Farm list using the certificate.

=cut

sub getCertFarmsUsed ($cfile) {
    require Relianoid::File;
    require Relianoid::Farm::Core;

    my $certdir   = &getGlobalConfiguration('certdir');
    my $configdir = &getGlobalConfiguration('configdir');
    my @farms     = &getFarmsByType("https");
    my $farms_ref = [];

    for my $farm_name (@farms) {
        my $farm_filename = &getFarmFile($farm_name);

        if (grep { /Cert \"$certdir\/\Q$cfile\E\"/ } readFileAsArray("$configdir/$farm_filename")) {
            push @{$farms_ref}, $farm_name;
        }
    }

    return $farms_ref;
}

=pod

=head1 checkFQDN

Check if a FQDN is valid

Parameters:

    certfqdn - FQDN.

Returns:

    String - Boolean 'true' or 'false'.

=cut

sub checkFQDN ($certfqdn) {
    my $valid = "true";

    if ($certfqdn =~ /^http:/) {
        $valid = "false";
    }
    if ($certfqdn =~ /^\./) {
        $valid = "false";
    }
    if ($certfqdn =~ /\.$/) {
        $valid = "false";
    }
    if ($certfqdn =~ /\//) {
        $valid = "false";
    }

    return $valid;
}

=pod

=head1 delCert

Removes a certificate file

Parameters:

    String - Certificate filename.

Returns:

    Integer - Number of files removed.

Bugs:

    Removes the _first_ file found _starting_ with the given certificate name.

=cut

sub delCert ($certname) {
    my $certdir = &getGlobalConfiguration('certdir');

    # escaping special caracters
    $certname =~ s/ /\ /g;

    my $files_removed;

    # verify existance in config directory for security reasons
    if (-f "$certdir/$certname") {
        $files_removed = unlink("$certdir/$certname");

        my $key_file = $certname;
        $key_file =~ s/\.pem$/\.key/;

        if (-f "$certdir/$key_file") {
            unlink("$certdir/$key_file");
        }

        # remove key file for CSR
        if ($certname =~ /.csr$/) {
            my $key_file = $certname;
            $key_file =~ s/\.csr$/\.key/;

            if (-f "$certdir/$key_file") {
                unlink "$certdir/$key_file";
            }
            else {
                &log_error("Key file was not found '$certdir/$key_file'", "LSLB");
            }
        }
    }

    &log_error("Error removing certificate '$certdir/$certname'", "LSLB")
      if !$files_removed;

    return $files_removed;
}

=pod

=head1 createCSR

Create a CSR file.

If the function run correctly two files will appear in the config/ directory:

certname.key and certname.csr.

Parameters:

    certname     - Certificate name, part of the certificate filename without the extension.
    certfqdn     - FQDN.
    certcountry  - Country.
    certstate    - State.
    certlocality - Locality.
    certorganization - Organization.
    certdivision - Division.
    certmail     - E-Mail.
    certkey      - Key. ?
    certpassword - Password. Optional.

Returns:

    Integer - Return code of openssl generating the CSR file..

=cut

sub createCSR ($name, $fqdn, $country, $state, $locality, $organization, $division, $mail, $key, $password) {
    my $configdir = &getGlobalConfiguration('certdir');
    my $output;

    my $subdomains = '';

    my @alternatives = split(/,/, $fqdn);
    my $cn_found     = 0;

    for my $dns (@alternatives) {
        next if $dns =~ /^\s*$/;
        if (not $cn_found) {
            $fqdn     = $dns;
            $cn_found = 1;
        }
        $subdomains .= "DNS:$dns,";
    }

    chop($subdomains);
    $subdomains = "-addext \"subjectAltName = $subdomains\"";

    return 1 if not $cn_found;

    ##sustituir los espacios por guiones bajos en el nombre de archivo###
    if ($password eq "") {
        $output =
          &logAndRun(
            "$openssl req -nodes -newkey rsa:$key -keyout $configdir/$name.key $subdomains -out $configdir/$name.csr -batch -subj \"/C=$country\/ST=$state/L=$locality/O=$organization/OU=$division/CN=$fqdn/emailAddress=$mail\"  2> /dev/null"
          );
        &log_info(
            "Creating CSR: $openssl req -nodes -newkey rsa:$key -keyout $configdir/$name.key $subdomains -out $configdir/$name.csr -batch -subj \"/C=$country\/ST=$state/L=$locality/O=$organization/OU=$division/CN=$fqdn/emailAddress=$mail\"",
            "LSLB"
        ) if (not $output);
    }
    else {
        $output =
          &logAndRun(
            "$openssl req -passout pass:$password -newkey rsa:$key -keyout $configdir/$name.key $subdomains -out $configdir/$name.csr $configdir/openssl.cnf -batch -subj \"/C=$country/ST=$state/L=$locality/O=$organization/OU=$division/CN=$fqdn/emailAddress=$mail\""
          );
        &log_info(
            "Creating CSR: $openssl req -passout pass:$password -newkey rsa:$key -keyout $configdir/$name.key $subdomains -out $configdir/$name.csr $configdir/openssl.cnf -batch -subj \"/C=$country\/ST=$state/L=$locality/O=$organization/OU=$division/CN=$fqdn/emailAddress=$mail\"",
            "LSLB"
        ) if (not $output);
    }
    return $output;
}

=pod

=head1 getCertData

Returns the information stored in a certificate.

Parameters:

    String - Certificate path.
    String - "true" for checking the Certificate.

Returns:

    string - It returns a string with the certificate content. It contains new line characters.

=cut

sub getCertData ($filepath, $check = undef) {
    my $cmd;
    my $filepath_orig = $filepath;
    $filepath = quotemeta($filepath);

    if (&getCertType($filepath) eq "Certificate") {
        $cmd = "$openssl x509 -in $filepath -text";
    }
    else {
        $cmd = "$openssl req -in $filepath -text";

        # request Certs do not need to be checked
        $check = 0;
    }

    my $cert = &logAndGet($cmd);
    $cert = $cert eq "" ? "This certificate is not valid." : $cert;
    if ($check) {
        my $status = checkCertPEMValid($filepath_orig);
        if ($status and $status->{code}) {
            $cert = $status->{desc};
        }
    }

    return $cert;
}

=pod

=head1 getCertInfo

It returns an object with the certificate information parsed

Parameters:

    certificate path - path to the certificate

Returns:

    hash ref - The hash contains the following keys:

    file:       name of the certificate with extension and without path. "zert.pem"
    type:       type of file. CSR or Certificate
    CN:         common name
    issuer:     name of the certificate authority
    creation:   date of certificate creation. "019-08-13 09:31:33 UTC"
    expiration: date of certificate expiration. "2020-07-11 09:31:33 UTC"
    status:     status of the certificate. 'unknown' if the file is not recognized as a certificate, 'expired' if the certificate is expired, 'about to expire' if the expiration date is in less than 15 days, 'valid' the expiration date is greater than 15 days, 'invalid' if the file is a not valid certificate

=cut

sub getCertInfo ($filepath) {
    my %response;

    my $certfile = "";
    if ($filepath =~ /([^\/]+)$/) {
        $certfile = $1;
    }

    # PEM
    if ($certfile =~ /\.pem$/) {
        require Crypt::OpenSSL::X509;
        my $status = "unknown";
        my $CN     = "no CN";
        my $ISSUER = "no issuer";
        my $x509;
        eval {
            $x509 = Crypt::OpenSSL::X509->new_from_file($filepath);

            my $time_offset = 60 * 60 * 24 * 15;    # 15 days
            if ($x509->checkend(0)) { $status = 'expired' }
            else {
                $status = ($x509->checkend($time_offset)) ? 'about to expire' : 'valid';
            }

            if (defined $x509->subject_name()->get_entry_by_type('CN')) {
                $CN = $x509->subject_name()->get_entry_by_type('CN')->value;
            }
            if (defined $x509->issuer_name()->get_entry_by_type('CN')) {
                $ISSUER = $x509->issuer_name()->get_entry_by_type('CN')->value;
            }
        };
        if ($@) {
            %response = (
                file       => $certfile,
                type       => 'Certificate',
                CN         => '-',
                issuer     => '-',
                creation   => '-',
                expiration => '-',
                status     => $status,
            );
        }
        else {
            $status   = "invalid" if (&checkCertPEMValid($filepath)->{code});
            %response = (
                file       => $certfile,
                type       => 'Certificate',
                CN         => $CN,
                issuer     => $ISSUER,
                creation   => $x509->notBefore(),
                expiration => $x509->notAfter(),
                status     => $status,
            );
        }
    }

    # CSR
    else {
        require Relianoid::File;

        my @cert_data = @{ &logAndGet("$openssl req -in $filepath -text -noout", "array") };

        my $cn = "";
        my ($string) = grep { /\sSubject: / } @cert_data;
        if ($string =~ /CN ?= ?([^,]+)/) {
            $cn = $1;
        }

        %response = (
            file       => $certfile,
            type       => 'CSR',
            CN         => $cn,
            issuer     => "NA",
            creation   => &getFileDateGmt($filepath),
            expiration => "NA",
            status     => 'valid',
        );
    }

    return \%response;
}

=pod

=head1 getDateEpoc

It converts a human date (2018-05-17 15:04:52 UTC) in a epoc date (1594459893)

Parameters:

    date - string with the date. The string has to be as "2018-05-17 15:04:52"

Returns:

    Integer - Time in epoc time. "1594459893"

=cut

sub getDateEpoc ($date_string) {
    # my @months      = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    my ($year, $month, $day, $hours, $min, $sec) = split /[ :-]+/, $date_string;

    return 0 if (! defined $year || ! defined $month || ! defined $day || ! defined $hours || ! defined $min || !defined $sec);

    # the range of the month is from 0 to 11
    $month-- if ($month > 0);

    require Time::Local;
    return Time::Local::timegm($sec, $min, $hours, $day, $month, $year);
}

=pod

=head1 getCertDaysToExpire

It calculates the number of days to expire the certificate.

Parameters:

    ending date - String with the ending date with the following format "2018-05-17 15:04:52 UTC"

Returns:

    Integer - Number of days to expire the certificate

=cut

sub getCertDaysToExpire ($cert_ends) {
    my $end       = &getDateEpoc($cert_ends);
    return 0 if ($end == 0);
    my $days_left = ($end - time()) / 86400;

    # leave only two decimals
    if ($days_left < 1) {
        $days_left *= 100;
        $days_left =~ s/\..*//g;
        $days_left /= 100;
    }
    else {
        $days_left =~ s/\..*//g;
    }

    return $days_left;
}

=pod

=head1 getCertPEM

It returns an object with all certificates: key, fullchain

Parameters:

    cert_path - path to the certificate

Returns:

    hash ref - List of certificates : key, fullchain

=cut

sub getCertPEM ($cert_path) {
    my $pem_config;

    if (-T $cert_path) {
        require Tie::File;
        use Fcntl 'O_RDONLY';

        tie my @cert_file, 'Tie::File', "$cert_path", mode => O_RDONLY;

        my $key_boundary         = 0;
        my $certificate_boundary = 0;
        my $cert;

        for (@cert_file) {
            if ($_ =~ /^-+BEGIN.*KEY-+/) {
                $key_boundary = 1;
            }
            if ($_ =~ /^-+BEGIN.*CERTIFICATE-+/) {
                $certificate_boundary = 1;
            }
            if ($key_boundary) {
                push @{ $pem_config->{key} }, $_;
            }
            if ($certificate_boundary) {
                push @{$cert}, $_;
            }
            if (($_ =~ /^-+END.*KEY-+/) and ($key_boundary)) {
                $key_boundary = 0;
                next;
            }
            if (($_ =~ /^-+END.*CERTIFICATE-+/) and ($certificate_boundary)) {
                push @{ $pem_config->{fullchain} }, $cert;
                $certificate_boundary = 0;
                $cert                 = undef;
                next;
            }
        }
    }

    return $pem_config;
}

=pod

=head1 checkCertPEMKeyEncrypted

Checks if a certificate private key in PEM format is encrypted.

Parameters:

    cert_path - path to the certificate

Returns:

    Integer - 0 if it is not encrypted, 1 if encrypted, -1 on error.

=cut

sub checkCertPEMKeyEncrypted ($cert_path) {
    my $rc         = -1;
    my $pem_config = &getCertPEM($cert_path);

    if (($pem_config) and ($pem_config->{key})) {
        use Net::SSLeay;
        $Net::SSLeay::trace = 1;

        $rc = 0;
        my $bio_key = Net::SSLeay::BIO_new_file($cert_path, 'r');

        # Loads PEM formatted private key via given BIO structure using empty password
        unless (Net::SSLeay::PEM_read_bio_PrivateKey($bio_key, undef, "")) {
            my $error     = Net::SSLeay::ERR_error_string(Net::SSLeay::ERR_get_error());
            my @strerr    = split(/:/, $error);
            my $error_str = $strerr[4];
            if ($error_str eq "bad decrypt") {
                &log_debug("Private Key Encrypted was found in '$cert_path': " . $strerr[4], "LSLB");
                $rc = 1;
            }
            else {
                &log_debug("Error checking Private Key Encrypted in '$cert_path': " . $strerr[4], "LSLB");
                $rc = -1;
            }
        }
        Net::SSLeay::BIO_free($bio_key);
    }

    return $rc;
}

=pod

=head1 checkCertPEMValid

Checks if a certificate is in PEM format and has a valid structure.
The certificates must be in PEM format and must be sorted starting with the subject's certificate (actual client or server certificate), followed by intermediate CA certificates if applicable, and ending at the highest level (root) CA. The Private key has to be unencrypted.

Parameters:

    cert_path - path to the certificate

Returns: hash reference

Error object.

    code - integer - Error code. 0 if the PEM file is valid.
    desc - string - Description of the error.

=cut

sub checkCertPEMValid ($cert_path) {
    use Net::SSLeay;
    $Net::SSLeay::trace = 1;

    my $error_ref->{code} = 0;
    my $ctx = Net::SSLeay::CTX_new_with_method(Net::SSLeay::SSLv23_method());

    if (!$ctx) {
        my $error_msg = "Error check PEM certificate";
        $error_ref->{code} = -1;
        $error_ref->{desc} = $error_msg;
        my $error     = Net::SSLeay::ERR_error_string(Net::SSLeay::ERR_get_error());
        my @strerr    = split(/:/, $error);
        my $error_str = $strerr[4];
        &log_debug("$error_msg in '$cert_path': " . $error_str, "LSLB");
        return $error_ref;
    }

    if (&checkCertPEMKeyEncrypted($cert_path) == 1) {
        Net::SSLeay::CTX_free($ctx);
        my $error_msg = "PEM file private key is encrypted";
        $error_ref->{code} = 1;
        $error_ref->{desc} = $error_msg;
        &log_debug("$error_msg in '$cert_path'", "LSLB");
        return $error_ref;
    }

    unless (Net::SSLeay::CTX_use_certificate_chain_file($ctx, "$cert_path")) {
        my $error  = Net::SSLeay::ERR_error_string(Net::SSLeay::ERR_get_error());
        my @strerr = split(/:/, $error);
        Net::SSLeay::CTX_free($ctx);
        my $error_str = $strerr[4];
        if ($error_str eq "no start line") {
            my $error_msg = "No Certificate found";
            $error_ref->{code} = 2;
            $error_ref->{desc} = $error_msg;
            &log_debug("$error_msg in '$cert_path': " . $error_str, "LSLB");
            return $error_ref;
        }
        elsif ($error_str eq "ca md too weak") {
            my $error_msg = "Cipher weak found";
            $error_ref->{code} = 3;
            $error_ref->{desc} = $error_msg;
            &log_debug("$error_msg in '$cert_path': " . $error_str, "LSLB");
            return $error_ref;
        }
        else {
            my $error_msg = "Error using Certificate";
            $error_ref->{code} = 4;
            $error_ref->{desc} = $error_msg;
            &log_debug("$error_msg in '$cert_path': " . $error_str, "LSLB");
            return $error_ref;
        }
    }

    unless (Net::SSLeay::CTX_use_PrivateKey_file($ctx, "$cert_path", Net::SSLeay::FILETYPE_PEM())) {
        my $error  = Net::SSLeay::ERR_error_string(Net::SSLeay::ERR_get_error());
        my @strerr = split(/:/, $error);
        Net::SSLeay::CTX_free($ctx);
        my $error_str = $strerr[4];
        if ($error_str eq "no start line") {
            my $error_msg = "No Private Key found";
            $error_ref->{code} = 5;
            $error_ref->{desc} = $error_msg;
            &log_debug("$error_msg in '$cert_path': " . $error_str, "LSLB");
            return $error_ref;
        }
        elsif ($error_str eq "key values mismatch") {
            my $error_msg = "Private Key is not valid for the first Certificate found";
            $error_ref->{code} = 6;
            $error_ref->{desc} = $error_msg;
            &log_debug("$error_msg in '$cert_path': " . $error_str, "LSLB");
            return $error_ref;
        }
        else {
            my $error_msg = "Error using Private Key";
            $error_ref->{code} = 7;
            $error_ref->{desc} = $error_msg;
            &log_debug("$error_msg in '$cert_path': " . $error_str, "LSLB");
            return $error_ref;
        }
    }

    unless (Net::SSLeay::CTX_check_private_key($ctx)) {
        my $error = Net::SSLeay::ERR_error_string(Net::SSLeay::ERR_get_error());
        Net::SSLeay::CTX_free($ctx);
        my @strerr    = split(/:/, $error);
        my $error_str = $strerr[4];
        my $error_msg = "Error checking Private Key";
        $error_ref->{code} = 8;
        $error_ref->{desc} = $error_msg;
        &log_debug("$error_msg in '$cert_path': " . $error_str, "LSLB");
        return $error_ref;
    }

    Net::SSLeay::CTX_free($ctx);
    return $error_ref;
}

=pod

=head1 createPEM

Create a valid PEM file.

Parameters:

    certname - Certificate name, part of the certificate filename without the extension.
    key      - String. Private Key.
    ca       - String. CA Certificate or fullchain certificates.
    intermediates - CA Intermediates Certificates.

Returns: hash reference

Error object.

    code - integer - Error code. 0 if the PEM file is created.
    desc - string - Description of the error.

=cut

sub createPEM ($cert_name, $cert_key, $cert_ca, $cert_intermediates) {
    my $error_ref->{code} = 0;

    if (not $cert_name or not $cert_key or not $cert_ca) {
        my $error_msg = "A required parameter is missing";
        $error_ref->{code} = 1;
        $error_ref->{desc} = $error_msg;
        return $error_ref;
    }

    # check certificate exists
    my $configdir = &getGlobalConfiguration('certdir');
    my $cert_file = $configdir . "/" . $cert_name . ".pem";

    if (-T $cert_file) {
        my $error_msg = "Certificate already exists";
        $error_ref->{code} = 2;
        $error_ref->{desc} = $error_msg;
        return $error_ref;
    }

    # create temp certificate
    my $tmp_cert  = "/tmp/cert_$cert_name.tmp";
    my $lock_file = &getLockFile($tmp_cert);
    my $lock_fh   = &openlock($lock_file, 'w');
    my $fh        = &openlock($tmp_cert,  'w');
    print $fh $cert_key . "\n";
    print $fh $cert_ca . "\n";
    print $fh $cert_intermediates . "\n" if (defined $cert_intermediates);
    close $fh;

    unless (-T $tmp_cert) {
        close $lock_fh;
        my $error_msg = "Error creating Temp Certificate File";
        $error_ref->{code} = 3;
        $error_ref->{desc} = $error_msg;
        return $error_ref;
    }

    # check temp certificate
    my $cert_conf = &getCertPEM($tmp_cert);
    if (!$cert_conf->{key}) {
        unlink $tmp_cert;
        close $lock_fh;
        my $error_msg = "No Private Key in PEM format found";
        $error_ref->{code} = 4;
        $error_ref->{desc} = $error_msg;
        return $error_ref;
    }
    if (!$cert_conf->{fullchain}) {
        unlink $tmp_cert;
        close $lock_fh;
        my $error_msg = "No Certificate in PEM format found";
        $error_ref->{code} = 4;
        $error_ref->{desc} = $error_msg;
        return $error_ref;
    }

    my $error = &checkCertPEMValid($tmp_cert);
    if ($error->{code}) {
        unlink $tmp_cert;
        close $lock_fh;
        $error_ref->{code} = 5;
        $error_ref->{desc} = $error->{desc} . " in generated PEM";
        return $error_ref;
    }

    # copy temp certificate
    if (&copyLock($tmp_cert, $cert_file)) {
        unlink $tmp_cert;
        close $lock_fh;
        my $error_msg = "Error creating Certificate File";
        $error_ref->{code} = 5;
        $error_ref->{desc} = $error_msg;
        return $error_ref;
    }

    unlink $tmp_cert;
    close $lock_fh;
    return $error_ref;
}

1;
