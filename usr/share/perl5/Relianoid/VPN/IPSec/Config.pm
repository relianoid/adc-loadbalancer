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

use Config::Tiny;

=pod

=head1 Module

Relianoid::VPN::IPSec::Config

=cut

=pod

=head1 createVPNIPSecConn

	Create IPSec connection file

Parameters:
	conn_name - IPSec Connection name
	conn_ref - IPSec Connection object

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub createVPNIPSecConn ($conn_name, $conn_ref) {
    # validate object
    #my $error = &checkVPNObject( $conn_ref );
    #if ( $error ) {
    #	&log_warn( "VPN Object not valid.", "VPN" );
    #	return -1;
    #}

    # get template object
    my $object = &getVpnIPSecInitConfig();
    if (!$object) {
        &log_error("Error, no IPSec Initial config", "VPN");
        return -3;
    }

    # merge template object with Site-to-Site object values
    &replaceHashValues($object, $conn_ref, "add");

    require Relianoid::Lock;

    my $conn_file = &getVpnIPSecConnFilePath($conn_name);

    if (-f $conn_file) {
        &log_warn("VPN IPSec $conn_file already exits.", "VPN");
        return -2;
    }

    &ztielock(\my @contents, $conn_file);
    push @contents, "conn " . $conn_name;

    for my $param (sort keys %{$object}) {
        push @contents, "\t" . $param . "=" . $object->{$param};
    }

    untie @contents;

    return 0;
}

=pod

=head1 delVPNIPsecConn

	Delete a IPSec connection

Parameters:
	$vpn_name - vpn name

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub delVPNIPSecConn ($vpn_name) {
    my $rc = -1;

    my $conn_file = &getVpnIPSecConnFilePath($vpn_name);

    if (-e $conn_file) {
        $rc = 0 if (unlink $conn_file);
    }
    else {
        &log_warn("VPN $vpn_name conn file doesn't exists", "VPN");
        $rc = 1;
    }

    return $rc;
}

=pod

=head1 setVPNIPsecConn

	Update a IPSec connection

Parameters:
	$vpn_name - vpn name
	$params_ref - Hash ref with params to update.

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub setVPNIPSecConn ($vpn_name, $params_ref) {
    my $rc = -1;

    my $conn_file = &getVpnIPSecConnFilePath($vpn_name);

    if (!-f $conn_file) {
        &log_warn("VPN IPSec $conn_file doesn't exist.", "VPN");
        $rc = 1;
        return $rc;
    }

    my $idx = 1;

    require Relianoid::Lock;
    &ztielock(\my @contents, $conn_file);

    my $size         = @contents;
    my $nparams      = keys %{$params_ref};
    my @contents_tmp = @contents;

    for (my $idx = 1 ; $idx < $size ; $idx++) {
        if ($contents_tmp[$idx] =~ /^\s+(.*)=(.*)/) {
            my $param = $1;
            my $value = $2;

            if (defined $params_ref->{$param}) {
                @contents_tmp[$idx] = "\t" . $param . "=" . $params_ref->{$param};
                $nparams--;
            }
        }
    }

    if (!$nparams) {
        @contents = @contents_tmp;
        $rc       = 0;
    }
    else {
        $rc = 2;
    }

    untie @contents;

    return $rc;
}

=pod

=head1 createVPNIPsecKey

	Create a IPSec key file

Parameters:
	vpn_ref - vpn object

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub createVPNIPSecKey ($vpn_ref) {
    # validate object
    if (my $error = &checkVPNObject($vpn_ref)) {
        &log_warn("VPN Object not valid.", "VPN");
        return -1;
    }

    require Relianoid::VPN::Core;

    my $vpn_config = &getVpnModuleConfig();

    # check config exists
    my $key_file = &getVpnIPSecKeyFilePath($vpn_ref->{ $vpn_config->{NAME} });
    if (-f $key_file) {
        &log_warn("IPSec $key_file already exits.", "VPN");
        return -2;
    }

    # get secret type
    my $auth       = "PSK";
    my $left_auth  = &getVpnIPSecSecretType($vpn_ref->{ $vpn_config->{LOCALAUTH} });
    my $right_auth = &getVpnIPSecSecretType($vpn_ref->{ $vpn_config->{REMOTEAUTH} });

    # any remote
    my $remote = $vpn_ref->{ $vpn_config->{REMOTE} } // "any";
    my $string = sprintf "%s $remote : $auth \"%s\"", $vpn_ref->{ $vpn_config->{LOCAL} }, $vpn_ref->{ $vpn_config->{PASS} };

    require Relianoid::Lock;

    &ztielock(\my @contents, $key_file);
    push @contents, $string;
    untie @contents;

    return 0;
}

=pod

=head1 delVPNIPSecKey

	Delete a IPSec key file

Parameters:
	$vpn_name - vpn name

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub delVPNIPSecKey ($vpn_name) {
    my $rc = -1;

    my $key_file = &getVpnIPSecKeyFilePath($vpn_name);
    if (-f $key_file) {
        $rc = 0 if (unlink $key_file);
    }
    else {
        &log_warn("IPSec $vpn_name key file doesn't exists", "VPN");
        $rc = 1;
    }

    return $rc;
}

=pod

=head1 setVPNIPsecKey

	Update a IPSec key file

Parameters:
	vpn_name - vpn name
	$params_ref - Hash ref with params to update.

Returns:
	Integer - Error code. 0 on success or other value on failure

=cut

sub setVPNIPSecKey ($vpn_name, $params_ref) {
    my $rc       = -1;
    my $key_file = &getVpnIPSecKeyFilePath($vpn_name);
    if (!-f $key_file) {
        &log_warn("IPSec $key_file doesn't exist.", "VPN");
        return 1;
    }

    require Relianoid::VPN::Core;
    my $vpn_config = &getVpnModuleConfig();

    my $auth;
    if (defined $params_ref->{ $vpn_config->{AUTH} }) {
        #$auth = &getVpnIPSecAuthType ( $params_ref->{ $vpn_config->{AUTH} } );
        $auth = "PSK";
        $params_ref->{ $vpn_config->{AUTH} } = $auth;
    }

    require Relianoid::Lock;
    &ztielock(\my @contents, $key_file);

    my $size    = @contents;
    my $nparams = keys %{$params_ref};
    my $key_ref;
    my @contents_tmp = @contents;

    for (my $idx = 0 ; $idx < $size ; $idx++) {
        if ($contents_tmp[$idx] =~ /^(.*) (.*) : (.*) "(.*)"$/) {
            $key_ref->{ $vpn_config->{LOCAL} }  = $1;
            $key_ref->{ $vpn_config->{REMOTE} } = $2;
            $key_ref->{ $vpn_config->{AUTH} }   = $3;
            $key_ref->{ $vpn_config->{PASS} }   = $4;

            for my $param (keys %{$params_ref}) {
                if (defined $key_ref->{$param}) {
                    $key_ref->{$param} = $params_ref->{$param};
                    $nparams--;
                }
            }

            @contents_tmp[$idx] =
                $key_ref->{ $vpn_config->{LOCAL} } . " "
              . $key_ref->{ $vpn_config->{REMOTE} } . " : "
              . $key_ref->{ $vpn_config->{AUTH} } . " \""
              . $key_ref->{ $vpn_config->{PASS} } . "\"";
        }
    }

    if (!$nparams) {
        @contents = @contents_tmp;
        $rc       = 0;
    }
    else {
        $rc = 2;
    }

    untie @contents;

    return $rc;
}

=pod

=head1 getVpnIPsecCipherConvert

	Converts cipher suite to struct or string.

Parameters:
	cipher_suite - String or Hash with cipher suite
	ike_version - Integer version of ike

Returns:
	Hash ref or string - $cipher_ref on success, undef on ike or algorithm not supported.

Variable: $$cipher_ref.
	A hash ref that maps the proposals of the connection.

	$$cipher_ref->{proposal} - Array of $cipher_suit.

Variable: $$cipher_suit.
	A hash ref that maps the ciphers used in a suite.

	$$cipher_suit->{encrytion}      - Array of encryption algorithms.
	$$cipher_suit->{authentication} - Array of authentication algorithms.
	$$cipher_suit->{dhgroups}       - Array of Diffie-Hellman groups.
	$$cipher_suit->{functions}      - Array of Pseudo-Random functions.

=cut

sub getVpnIPSecCipherConvert ($cipher_suite, $ike_version) {
    # supported proposals
    #ikev1
    # encryption algorithms :
    #  	aes [ 128,192,256 ] [ ctr, ccm [ 64,96,128 ], gcm [ 8,12,16,64,96,128 ], gmac ]
    #	3des
    #	blowfish [ 128,192,256 ]
    #	camellia [ 128,192,256 ]
    #	serpent [ 128,192,256 ]
    #	twofish [ 128,192,256 ]
    # integrity algorithms :
    #	md5
    #	sha [ 1,256,384,512 ]
    #	aes [ xcbc, [ 128,192,256 ] gmac ]
    # DH groups
    #	modp [ 768,1024,1536,2048,3072,4096,6144,8192 ]
    #ikev2
    # encryption algorithms :
    #  	aes [ 128,192,256 ] [ ctr, ccm [ 64,96,128 ], gcm [ 8,12,16,64,96,128 ], gmac ]
    #	blowfish [ 128,192,256 ]
    #	3des
    #	cast128
    #	camellia [ 128,192,256 ] [ ctr, ccm [ 64,96,128 ] ]
    #	chacha20poly1305
    # integrity algorithms :
    #	md5 [ _128 ]
    #	sha [ 1,1_160,256,256_96,384,512 ]
    #	aes [ xcbc, cmac, [ 128,192,256 ] gmac ]
    # Pseudo-random Functions :
    #	prf [ md5, sha [ 1,256,384,512 ], aes [ xcbc, cmac ] ]
    # DH groups
    #	modp [ 768,1024,1536,2048,3072,4096,6144,8192 ]

    my %ike = (
        v1 => {
            encryption => [
                "aes128",       "aes192",       "aes256",       "aes128ctr",   "aes192ctr",   "aes256ctr",
                "aes128ccm64",  "aes192ccm64",  "aes256ccm64",  "aes128ccm96", "aes192ccm96", "aes256ccm96",
                "aes128ccm128", "aes192ccm128", "aes256ccm128", "aes128gcm8",  "aes192gcm8",  "aes256gcm8",
                "aes128gcm64",  "aes192gcm64",  "aes256gcm64",  "aes128gcm12", "aes192gcm12", "aes256gcm12",
                "aes128gcm96",  "aes192gcm96",  "aes256gcm96",  "aes128gcm16", "aes192gcm16", "aes256gcm16",
                "aes128gcm128", "aes192gcm128", "aes256gcm128", "aes128gmac",  "aes192gmac",  "aes256gmac",
                "3des",         "blowfish128",  "blowfish192",  "blowfish256", "camellia128", "camellia192",
                "camellia256",  "serpent128",   "serpent192",   "serpent256",  "twofish128",  "twofish192",
                "twofish256"
            ],
            authentication => [ "md5", "sha1", "sha256", "sha384", "sha512", "aesxcbc", "aes128gmac", "aes192gmac", "aes256gmac" ],
            dhgroup        => [ "modp768", "modp1024", "modp1536", "modp2048", "modp3072", "modp4096", "modp6144", "modp8192" ],
        },
        v2 => {
            encryption => [
                "aes128",           "aes192",            "aes256",            "aes128ctr",
                "aes192ctr",        "aes256ctr",         "aes128ccm64",       "aes192ccm64",
                "aes256ccm64",      "aes128ccm96",       "aes192ccm96",       "aes256ccm96",
                "aes128ccm128",     "aes192ccm128",      "aes256ccm128",      "aes128gcm8",
                "aes192gcm8",       "aes256gcm8",        "aes128gcm64",       "aes192gcm64",
                "aes256gcm64",      "aes128gcm12",       "aes192gcm12",       "aes256gcm12",
                "aes128gcm96",      "aes192gcm96",       "aes256gcm96",       "aes128gcm16",
                "aes192gcm16",      "aes256gcm16",       "aes128gcm128",      "aes192gcm128",
                "aes256gcm128",     "aes128gmac",        "aes192gmac",        "aes256gmac",
                "3des",             "cast128",           "blowfish128",       "blowfish192",
                "blowfish256",      "camellia128",       "camellia192",       "camellia256",
                "camellia128ctr",   "camellia192ctr",    "camellia256ctr",    "camellia128ccm64",
                "camellia192ccm64", "camellia256ccm64",  "camellia128ccm96",  "camellia192ccm96",
                "camellia256ccm96", "camellia128ccm128", "camellia192ccm128", "camellia256ccm128",
                "chacha20poly1305"
            ],
            authentication => [
                "md5",    "md5_128", "sha1",    "sha1_160",   "sha256",     "sha256_96",
                "sha384", "sha512",  "aesxcbc", "aes128gmac", "aes192gmac", "aes256gmac"
            ],
            function => [ "prfmd5",  "prfsha1",  "prfsha256", "prfsha384", "prfsha512", "prfaes",   "prfaesxcbc", "prfaescmac" ],
            dhgroup  => [ "modp768", "modp1024", "modp1536",  "modp2048",  "modp3072",  "modp4096", "modp6144",   "modp8192" ],
        }
    );

    my $cipher_ref;

    if ((!$ike_version) or ($ike_version < 1 and $ike_version > 2)) {
        return;
    }

    $ike_version = "v$ike_version";

    if (ref $cipher_suite eq 'HASH') {
        if (!$cipher_suite->{proposal}) {
            return;
        }

        for my $proposal (@{ $cipher_suite->{proposal} }) {
            my @ciph_suite;

            if ($proposal->{encryption}) {
                for my $alg (@{ $proposal->{encryption} }) {
                    if (grep { /$alg/ } @{ $ike{$ike_version}{encryption} }) {
                        push @ciph_suite, $alg;
                    }
                    else {
                        log_warn("Algorithm $alg not supported", "VPN");
                        return;
                    }
                }
            }

            if ($proposal->{authentication}) {
                for my $alg (@{ $proposal->{authentication} }) {
                    if (grep { /$alg/ } @{ $ike{$ike_version}{authentication} }) {
                        push @ciph_suite, $alg;
                    }
                    else {
                        log_warn("Algorithm $alg not supported", "VPN");
                        return;
                    }
                }
            }

            if ($proposal->{dhgroup}) {
                for my $alg (@{ $proposal->{dhgroup} }) {
                    if (grep { /$alg/ } @{ $ike{$ike_version}{dhgroup} }) {
                        push @ciph_suite, $alg;
                    }
                    else {
                        log_warn("Algorithm $alg not supported", "VPN");
                        return;
                    }
                }
            }

            if ($ike_version eq "v2" and $proposal->{function}) {
                for my $alg (@{ $proposal->{function} }) {
                    if (grep { /$alg/ } @{ $ike{$ike_version}{function} }) {
                        push @ciph_suite, $alg;
                    }
                    else {
                        log_warn("Algorithm $alg not supported", "VPN");
                        return;
                    }
                }
            }

            $cipher_ref .= join '-', @ciph_suite;
            $cipher_ref .= ",";
        }

        chop $cipher_ref;
    }
    elsif ($cipher_suite) {
        my @suites = split(",", $cipher_suite);

        if (scalar @suites == 0) {
            push @suites, $cipher_suite;
        }

        for my $suite (@suites) {
            my @algorithms = split("-", $suite);

            if (scalar @algorithms == 0) {
                push @algorithms, $suite;
            }

            my $cipher_suite;

            for my $alg (@algorithms) {
                if (grep { /$alg/ } @{ $ike{$ike_version}{encryption} }) {
                    push @{ $cipher_suite->{encryption} }, $alg;
                    next;
                }
                elsif (grep { /$alg/ } @{ $ike{$ike_version}{authentication} }) {
                    push @{ $cipher_suite->{authentication} }, $alg;
                    next;
                }
                elsif (grep { /$alg/ } @{ $ike{$ike_version}{dhgroup} }) {
                    push @{ $cipher_suite->{dhgroup} }, $alg;
                    next;
                }
                elsif ($ike_version eq "v2" && grep { /$alg/ } @{ $ike{$ike_version}{function} }) {
                    push @{ $cipher_suite->{function} }, $alg;
                    next;
                }
                else {
                    log_warn("Algorithm $alg not supported", "VPN");
                    return;
                }
            }

            if ($cipher_suite) {
                push @{ $cipher_ref->{proposal} }, $cipher_suite;
            }
        }
    }

    return $cipher_ref;
}

1;
