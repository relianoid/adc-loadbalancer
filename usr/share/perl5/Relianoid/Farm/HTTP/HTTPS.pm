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

my $eload     = eval { require Relianoid::ELoad };
my $configdir = &getGlobalConfiguration('configdir');

=pod

=head1 Module

Relianoid::Farm::HTTP::HTTPS

=cut

=pod

=head1 getFarmCertificate

Return the certificate applied to the farm

Parameters:

    farm_name - Farm name

Returns:

    scalar - Return the certificate file, or -1 on failure.

FIXME:

    If are there more than one certificate, only return the last one

=cut

sub getFarmCertificate ($farm_name) {
    my $output = -1;

    my $farm_filename = &getFarmFile($farm_name);
    open my $fh, '<', "${configdir}/${farm_filename}";
    my @content = <$fh>;
    close $fh;

    for my $line (@content) {
        if ($line =~ /Cert/ && $line !~ /\#.*Cert/) {
            my @partline = split('\"', $line);
            @partline = split("\/", $partline[1]);
            my $lfile = @partline;
            $output = $partline[ $lfile - 1 ];
        }
    }

    return $output;
}

=pod

=head1 setFarmCertificate

Configure a certificate for a HTTP farm

Parameters:

    cert_file - certificate file name
    farm_name - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

FIXME:

    There is other function for this action: setFarmCertificateSNI

=cut

sub setFarmCertificate ($cert_file, $farm_name) {
    require Tie::File;
    require Relianoid::Lock;
    require Relianoid::Farm::HTTP::Config;

    my $farm_filename = &getFarmFile($farm_name);
    my $lock_file     = &getLockFile($farm_name);
    my $lock_fh       = &openlock($lock_file, 'w');
    my $output        = -1;

    my $cert_dir  = &getGlobalConfiguration('certdir');
    my $cert_path = "${cert_dir}/${cert_file}";

    &log_info("Setting 'Certificate ${cert_file}' for ${farm_name} farm https", "LSLB");

    require Relianoid::Certificate;
    my $error = &checkCertPEMValid($cert_path);

    if ($error->{code}) {
        &log_error("'Certificate ${cert_file}' for ${farm_name} farm https is not valid", "LSLB");
        return $output;
    }

    tie my @array, 'Tie::File', "${configdir}/${farm_filename}";

    for my $line (@array) {
        if ($line =~ /Cert "/) {
            $line =~ s!.*Cert .*!\tCert "${cert_path}"!g;
            $output = 0;
        }
    }

    untie @array;
    close $lock_fh;
    unlink $lock_file;

    return $output;
}

=pod

=head1 setFarmCipherList

Set Farm Ciphers value

Parameters:

    farmname - Farm name

    ciphers - The options are: cipherglobal, cipherpci, cipherssloffloading or ciphercustom

    cipherc - Cipher custom, this field is used when ciphers is ciphercustom

Returns:

    Integer - return 0 on success or -1 on failure

=cut

sub setFarmCipherList ($farm_name, $ciphers, $cipherc) {
    require Tie::File;
    require Relianoid::Lock;
    require Relianoid::Farm::HTTP::Config;

    my $farm_filename = &getFarmFile($farm_name);
    my $lock_file     = &getLockFile($farm_name);
    my $lock_fh       = &openlock($lock_file, 'w');
    my $output        = -1;

    tie my @array, 'Tie::File', "$configdir/$farm_filename";

    for my $line (@array) {
        # takes the first Ciphers line only
        next if ($line !~ /Ciphers/);

        if ($ciphers eq "cipherglobal") {
            $line =~ s/#//g;
            $line   = "\tCiphers \"ALL\"";
            $output = 0;
        }
        elsif ($ciphers eq "cipherpci") {
            my $cipher_pci = &getGlobalConfiguration('cipher_pci');
            $line =~ s/#//g;
            $line   = "\tCiphers \"$cipher_pci\"";
            $output = 0;
        }
        elsif ($ciphers eq "ciphercustom") {
            $cipherc = 'DEFAULT' if not defined $cipherc;
            $line =~ s/#//g;
            $line   = "\tCiphers \"$cipherc\"";
            $output = 0;
        }
        elsif ($ciphers eq "cipherssloffloading") {
            my $cipher = &getGlobalConfiguration('cipher_ssloffloading');
            $line   = "\tCiphers \"$cipher\"";
            $output = 0;
        }

        # default cipher
        else {
            $line =~ s/#//g;
            $line   = "\tCiphers \"ALL\"";
            $output = 0;
        }

        last;
    }

    untie @array;
    close $lock_fh;
    unlink $lock_file;

    return $output;
}

=pod

=head1 getFarmCipherList

Get Cipher value defined in l7 proxy configuration file

Parameters:

    farmname - Farm name

Returns:

    scalar - return a string with cipher value or -1 on failure
=cut

sub getFarmCipherList ($farm_name) {
    my $output = -1;

    my $farm_filename = &getFarmFile($farm_name);

    open my $fh, '<', "${configdir}/${farm_filename}";
    my @content = <$fh>;
    close $fh;

    for my $line (@content) {
        next if ($line !~ /Ciphers/);

        $output = (split('\"', $line))[1];

        last;
    }

    return $output;
}

=pod

=head1 getFarmCipherSet

Get Ciphers value defined in l7 proxy configuration file.

Parameters:

    farmname - Farm name

Returns:

    scalar - return a string with cipher set (ciphers) or -1 on failure

    Possible values are:

        cipherglobal
        cipherpci
        cipherssloffloading
        ciphercustom

=cut

sub getFarmCipherSet ($farm_name) {
    my $output = -1;

    my $cipher_list = &getFarmCipherList($farm_name);

    if ($cipher_list eq 'ALL') {
        $output = "cipherglobal";
    }
    elsif ($cipher_list eq &getGlobalConfiguration('cipher_pci')) {
        $output = "cipherpci";
    }
    elsif ($eload
        && $cipher_list eq &getGlobalConfiguration('cipher_ssloffloading'))
    {
        $output = "cipherssloffloading";
    }
    else {
        $output = "ciphercustom";
    }

    return $output;
}

=pod

=head1 getHTTPFarmDisableSSL

Get if a security protocol version is enabled or disabled in a HTTPS farm

Parameters:

    farm_name - Farm name
    protocol - SSL or TLS protocol get status (disabled or enabled)

Returns:

    Integer - 1 on disabled, 0 on enabled or -1 on failure

=cut

sub getHTTPFarmDisableSSL ($farm_name, $protocol) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    open my $fh, '<', "${configdir}/${farm_filename}" or return $output;
    $output = 0;    # if the directive is not in config file, it is disabled
    my @file = <$fh>;
    close $fh;

    for my $line (@file) {
        if ($line =~ /^\tDisable $protocol$/) {
            $output = 1;
            last;
        }
    }

    return $output;
}

=pod

=head1 setHTTPFarmDisableSSL

Enable or disable a security protocol for a HTTPS farm

Parameters:

    farm_name - Farm name
    protocol - SSL or TLS protocol to disable/enable: SSLv2|SSLv3|TLSv1|TLSv1_1|TLSv1_2
    action   - The available actions are: 1 to disable or 0 to enable

Returns:

    Integer - Error code: 0 on success or -1 on failure

=cut

sub setHTTPFarmDisableSSL ($farm_name, $protocol, $action) {
    require Tie::File;
    require Relianoid::Lock;
    require Relianoid::Farm::HTTP::Config;

    my $farm_filename = &getFarmFile($farm_name);
    my $lock_file     = &getLockFile($farm_name);
    my $lock_fh       = &openlock($lock_file, 'w');
    my $output        = -1;

    tie my @file, 'Tie::File', "$configdir/$farm_filename";

    if ($action == 1) {
        for my $line (@file) {
            if ($line =~ /Ciphers\ .*/) {
                $line = "$line\n\tDisable $protocol";
                last;
            }
        }
        $output = 0;
    }
    else {
        my $it = -1;
        for my $line (@file) {
            $it = $it + 1;
            last if ($line =~ /Disable $protocol$/);
        }

        # Remove line only if it is found (we haven't arrive at last line).
        splice(@file, $it, 1) if (($it + 1) != scalar @file);
        $output = 0;
    }

    untie @file;
    close $lock_fh;
    unlink $lock_file;

    return $output;
}

1;

