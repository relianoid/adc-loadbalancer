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

use Relianoid::Farm::Base;
use Relianoid::Farm::HTTP::Config;
use Relianoid::Farm::Action;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::Farm::Put::HTTP

=cut

my $eload = eval { require Relianoid::ELoad };

# PUT /farms/<farmname> Modify a http|https Farm
sub modify_http_farm ($json_obj, $farmname) {
    my $desc = "Modify HTTP farm $farmname";

    require Relianoid::Net::Interface;
    my $ip_list = &getIpAddressList();

    my $params = &getAPIModel("farm_http-modify.json");
    $params->{vip}{values}               = $ip_list;
    $params->{ciphers}{listener}         = "https";
    $params->{cipherc}{listener}         = "https";
    $params->{certname}{listener}        = "https";
    $params->{disable_sslv2}{listener}   = "https";
    $params->{disable_sslv3}{listener}   = "https";
    $params->{disable_tlsv1}{listener}   = "https";
    $params->{disable_tlsv1_1}{listener} = "https";
    $params->{disable_tlsv1_2}{listener} = "https";

    if (!$eload) {
        $params->{ciphers}{values} = [ "all", "highsecurity", "customsecurity" ];
    }

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # Get current conf
    my $farm_st = &getHTTPFarmStruct($farmname);

    my $vip   = $json_obj->{vip}   // $farm_st->{vip};
    my $vport = $json_obj->{vport} // $farm_st->{vport};

    if (exists($json_obj->{vip}) or exists($json_obj->{vport})) {
        require Relianoid::Net::Validate;
        if ($farm_st->{status} ne 'down' and not &validatePort($vip, $vport, 'http', $farmname)) {
            my $msg =
              "The '$vip' ip and '$vport' port are being used for another farm. This farm should be stopped before modifying it";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    if (exists($json_obj->{vip})) {
        if ($farm_st->{status} ne 'down') {
            require Relianoid::Net::Interface;

            my $if_name = &getInterfaceByIp($json_obj->{vip});
            my $if_ref  = &getInterfaceConfig($if_name);

            if (&getInterfaceSystemStatus($if_ref) ne "up") {
                my $msg = "The '$json_obj->{vip}' ip is not UP. This farm should be stopped before modifying it";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }
    }

    # Flags
    my $reload_ipds = 0;

    if (   exists $json_obj->{vport}
        || exists $json_obj->{vip}
        || exists $json_obj->{newfarmname})
    {
        if ($eload) {
            $reload_ipds = 1;

            &eload(
                module => 'Relianoid::EE::IPDS::Base',
                func   => 'runIPDSStopByFarm',
                args   => [$farmname],
            );

            &eload(
                module => 'Relianoid::EE::Cluster',
                func   => 'runClusterRemoteManager',
                args   => [ 'ipds', 'stop', $farmname ],
            );
        }
    }

    ######## Functions
    # Modify Farm's Name
    if (exists($json_obj->{newfarmname})) {
        unless ($farm_st->{status} eq 'down') {
            my $msg = 'Cannot change the farm name while the farm is running';
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        #Check if the new farm's name alredy exists
        if (&getFarmExists($json_obj->{newfarmname})) {
            my $msg = "The farm $json_obj->{newfarmname} already exists, try another name.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        # Change farm name
        if (&setNewFarmName($farmname, $json_obj->{newfarmname})) {
            my $msg = "Error modifying the farm name.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        $farmname = $json_obj->{newfarmname};
    }

    # Modify Backend Connection Timeout
    if (exists $json_obj->{contimeout}) {
        if (&setHTTPFarmConnTO($json_obj->{contimeout}, $farmname) == -1) {
            my $msg = "Some errors happened trying to modify the contimeout.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # Modify Backend Respone Timeout
    if (exists($json_obj->{restimeout})) {
        if (&setFarmTimeout($json_obj->{restimeout}, $farmname) == -1) {
            my $msg = "Some errors happened trying to modify the restimeout.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # Modify Frequency To Check Resurrected Backends
    if (exists($json_obj->{resurrectime})) {
        if (&setFarmBlacklistTime($json_obj->{resurrectime}, $farmname) == -1) {
            my $msg = "Some errors happened trying to modify the resurrectime.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # Modify Client Request Timeout
    if (exists($json_obj->{reqtimeout})) {
        if (&setHTTPFarmClientTimeout($json_obj->{reqtimeout}, $farmname) == -1) {
            my $msg = "Some errors happened trying to modify the reqtimeout.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # Modify Rewrite Location Headers
    if (exists($json_obj->{rewritelocation})) {
        my $rewritelocation = 0;
        my $path            = 0;
        if ($json_obj->{rewritelocation} eq "disabled") {
            $rewritelocation = 0;
        }
        elsif ($json_obj->{rewritelocation} eq "enabled") {
            $rewritelocation = 1;
        }
        elsif ($json_obj->{rewritelocation} eq "enabled-backends") {
            $rewritelocation = 2;
        }
        elsif ($json_obj->{rewritelocation} eq "enabled-path") {
            $rewritelocation = 1;
            $path            = 1;
        }
        elsif ($json_obj->{rewritelocation} eq "enabled-backends-path") {
            $rewritelocation = 2;
            $path            = 1;
        }

        if (my $error = &setHTTPFarmRewriteL($farmname, $rewritelocation, $path)) {
            my $msg = "Some errors happened trying to modify the rewritelocation.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # Enable the log connection tracking
    if (exists($json_obj->{logs})) {
        require Relianoid::Farm::HTTP::Config;
        my $status = &setHTTPFarmLogs($farmname, $json_obj->{logs});

        if ($status) {
            my $msg = "Some errors happened trying to modify the log parameter.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # Enable or disable ignore 100 continue header
    if (exists($json_obj->{ignore_100_continue})
        and ($json_obj->{ignore_100_continue} ne $farm_st->{ignore_100_continue}))    # this is a bugfix
    {
        my $action = ($json_obj->{ignore_100_continue} eq "true") ? 1 : 0;

        my $status = &setHTTPFarm100Continue($farmname, $action);

        if ($status == -1) {
            my $msg = "Some errors happened trying to modify the ignore_100_continue parameter.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # Modify HTTP Verbs Accepted
    if (exists($json_obj->{httpverb})) {
        my $code = &getHTTPFarmVerbCode($json_obj->{httpverb});
        if (&setHTTPFarmHttpVerb($code, $farmname) == -1) {
            my $msg = "Some errors happened trying to modify the httpverb.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    #Modify Error 414
    if (exists($json_obj->{error414})) {
        if (&setHTTPFarmErr($farmname, $json_obj->{error414}, "414") == -1) {
            my $msg = "Some errors happened trying to modify the error414.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    #Modify Error 500
    if (exists($json_obj->{error500})) {
        if (&setHTTPFarmErr($farmname, $json_obj->{error500}, "500") == -1) {
            my $msg = "Some errors happened trying to modify the error500.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    #Modify Error 501
    if (exists($json_obj->{error501})) {
        if (&setHTTPFarmErr($farmname, $json_obj->{error501}, "501") == -1) {
            my $msg = "Some errors happened trying to modify the error501.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    #Modify Error 503
    if (exists($json_obj->{error503})) {
        if (&setHTTPFarmErr($farmname, $json_obj->{error503}, "503") == -1) {
            my $msg = "Some errors happened trying to modify the error503.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # Modify Farm Listener
    if (exists($json_obj->{listener})) {
        eval { &setHTTPFarmListen($farmname, $json_obj->{listener}); 1 } or do {
            my $msg = "Some errors happened trying to modify the listener.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        };

        $farm_st->{listener} = $json_obj->{listener};    # update listener type
    }

    # Discard parameters of the HTTPS listener when it is not configured
    if ($farm_st->{listener} ne "https") {
        for my $key (keys %{$params}) {
            if (    exists $json_obj->{$key}
                and exists $params->{$key}{listener}
                and $params->{$key}{listener} eq 'https')
            {
                my $msg = "The farm listener has to be 'HTTPS' to configure the parameter '$key'.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }
    }

    # Modify HTTPS Params
    if ($farm_st->{listener} eq "https") {
        require Relianoid::Farm::HTTP::HTTPS;

        # Cipher groups
        # API parameter => library parameter
        my %c = (
            all            => "cipherglobal",
            customsecurity => "ciphercustom",
            highsecurity   => "cipherpci",
            ssloffloading  => "cipherssloffloading",
        );
        my $ciphers_lib;

        # Modify Ciphers
        if (exists($json_obj->{ciphers})) {
            $ciphers_lib = $c{ $json_obj->{ciphers} };

            my $ssloff = 1;
            $ssloff = &eload(
                module => 'Relianoid::EE::Farm::HTTP::HTTPS::Ext',
                func   => 'getFarmCipherSSLOffLoadingSupport',
            ) if ($eload);

            unless ($ssloff) {
                &log_warn("The CPU does not support SSL offloading.", "system");
            }

            if (&setFarmCipherList($farmname, $ciphers_lib, $json_obj->{cipherc}) == -1) {
                my $msg = "Error modifying ciphers.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }

            $farm_st->{ciphers} = $json_obj->{ciphers};    # update ciphers value
        }

        # Modify Customized Ciphers
        if (exists($json_obj->{cipherc})) {
            $ciphers_lib = $c{ $farm_st->{ciphers} };

            if ($farm_st->{ciphers} eq "customsecurity") {
                $json_obj->{cipherc} =~ s/\ //g;
                if (&setFarmCipherList($farmname, $ciphers_lib, $json_obj->{cipherc}) == -1) {
                    my $msg = "Some errors happened trying to modify the cipherc.";
                    return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
                }
            }
            else {
                my $msg = "'ciphers' has to be 'customsecurity' to set the 'cipherc' parameter.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        # Add Certificate to SNI list
        if (exists($json_obj->{certname})) {
            my $status;
            my $configdir = &getGlobalConfiguration('configdir');

            if (!-f "$configdir/$json_obj->{certname}") {
                my $msg = "The certificate $json_obj->{certname} has to be uploaded to use it in a farm.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }

            if ($eload) {
                $status = &eload(
                    module => 'Relianoid::EE::Farm::HTTP::HTTPS::Ext',
                    func   => 'setFarmCertificateSNI',
                    args   => [ $json_obj->{certname}, $farmname ],
                );
            }
            else {
                $status = &setFarmCertificate($json_obj->{certname}, $farmname);
            }

            if ($status == -1) {
                my $msg = "Some errors happened trying to modify the certname.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }

        # Disable security protocol
        # API parameter => l7 proxy parameter
        my %ssl_proto_hash = (
            disable_sslv2   => "SSLv2",
            disable_sslv3   => "SSLv3",
            disable_tlsv1   => "TLSv1",
            disable_tlsv1_1 => "TLSv1_1",
            disable_tlsv1_2 => "TLSv1_2",
        );

        my %bool_to_int = (
            false => 0,
            true  => 1,
        );

        my $action;
        my $ssl_proto;

        for my $key_ssl (keys %ssl_proto_hash) {
            next if (!exists $json_obj->{$key_ssl});
            next if ($farm_st->{$key_ssl} && $json_obj->{$key_ssl} eq $farm_st->{$key_ssl});

            $action    = $bool_to_int{ $json_obj->{$key_ssl} };
            $ssl_proto = $ssl_proto_hash{$key_ssl}
              if exists $ssl_proto_hash{$key_ssl};

            if (&setHTTPFarmDisableSSL($farmname, $ssl_proto, $action) == -1) {
                my $msg = "Some errors happened trying to modify $key_ssl.";
                return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
            }
        }
    }

    if (exists($json_obj->{vip})) {
        # the ip must exist in some interface
        require Relianoid::Net::Interface;
        unless (&getIpAddressExists($json_obj->{vip})) {
            my $msg = "The vip IP must exist in some interface.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # Modify vip and vport
    if (exists($json_obj->{vip}) or exists($json_obj->{vport})) {
        if (&setFarmVirtualConf($vip, $vport, $farmname)) {
            my $msg = "Could not set the virtual configuration.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    &log_info("Success, some parameters have been changed in farm $farmname.", "LSLB");

    # Return the received json object updated.
    require Relianoid::HTTP::Controllers::API::Farm::Output::HTTP;

    #~ my $farm_upd = &getFarmStruct( $farmname );
    #~ for my $key ( keys %{$json_obj} )
    #~ {
    #~ $json_obj->{$key} = $farm_upd->{$key};
    #~ }

    my $out_obj = &getHTTPOutFarm($farmname);

    if ($reload_ipds and $eload) {
        &eload(
            module => 'Relianoid::EE::IPDS::Base',
            func   => 'runIPDSStartByFarm',
            args   => [$farmname],
        );

        &eload(
            module => 'Relianoid::EE::Cluster',
            func   => 'runClusterRemoteManager',
            args   => [ 'ipds', 'start', $farmname ],
        );
    }

    my $body = {
        description => $desc,
        params      => $out_obj,
        message     => "Some parameters have been changed in farm $farmname."
    };

    if (exists $json_obj->{newfarmname}) {
        $body->{params}{newfarmname} = $json_obj->{newfarmname};
    }

    if ($farm_st->{status} ne 'down') {
        &setFarmRestart($farmname);
        $body->{status} = 'needed restart';
    }

    return &httpResponse({ code => 200, body => $body });
}

1;

