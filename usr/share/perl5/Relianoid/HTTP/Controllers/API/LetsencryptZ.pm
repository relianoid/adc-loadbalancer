#!/usr/bin/perl
##############################################################################
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

Relianoid::HTTP::Controllers::API::LetsencryptZ

=cut

my $eload = eval { require Relianoid::ELoad };

# GET /certificates/letsencryptz
sub list_le_cert_controller () {
    require Relianoid::LetsencryptZ;

    my $desc         = "List LetsEncrypt certificates";
    my $certificates = &getLetsencryptCertificates();
    my @out;

    if ($certificates) {
        for my $cert (@{$certificates}) {
            push @out, &getLetsencryptCertificateInfo($cert->{name});
        }
    }
    if ($eload) {
        my $wildcards = &eload(
            module => 'Relianoid::EE::LetsencryptZ::Wildcard',
            func   => 'getLetsencryptWildcardCertificates'
        );

        for my $cert (@{$wildcards}) {
            push @out,
              &eload(
                module => 'Relianoid::EE::LetsencryptZ::Wildcard',
                func   => 'getLetsencryptWildcardCertificateInfo',
                args   => [ $cert->{name} ]
              );
        }
    }

    my $body = {
        description => $desc,
        params      => \@out,
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET /certificates/letsencryptz/le_cert_re
sub get_le_cert_controller ($le_cert_name) {
    require Relianoid::LetsencryptZ;

    my $desc    = "Show Let's Encrypt certificate $le_cert_name";
    my $le_cert = &getLetsencryptCertificates($le_cert_name);

    if (not defined $le_cert_name or not @{$le_cert}) {
        my $msg = "Let's Encrypt certificate $le_cert_name not found!";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $out = &getLetsencryptCertificateInfo($le_cert_name);

    my $body = {
        description => $desc,
        params      => $out,
    };

    return &httpResponse({ code => 200, body => $body });
}

# POST /certificates/letsencryptz
sub add_le_cert_controller ($json_obj) {
    require Relianoid::Certificate;
    require Relianoid::LetsencryptZ;
    require Relianoid::Net::Interface;
    require Relianoid::Farm::Core;

    my $ip_list   = &getIpAddressList();
    my @farm_list = &getFarmsByType("http");

    my $desc   = "Create LetsEncrypt certificate";
    my $params = &getAPIModel("letsencryptz-create.json");
    $params->{vip}{values}      = $ip_list;
    $params->{farmname}{values} = \@farm_list;

    # avoid farmname when no HTTP Farm exists
    if (not @farm_list and defined $json_obj->{farmname}) {
        my $msg = "There is no HTTP Farms in the system, use 'vip' param instead.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # vip or farmname has to be defined
    if (    not $json_obj->{vip}
        and not $json_obj->{farmname}
        and defined $json_obj->{domains})
    {
        my $msg = "No 'vip' or 'farmname' param found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # avoid wildcards domains
    if (grep { /^\*/ } @{ $json_obj->{domains} }) {
        my $msg = "Wildcard domains are not allowed.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # check if the cert exists
    my $force   = "false";
    my $le_cert = &getLetsencryptCertificates($json_obj->{domains}[0]);
    if (@{$le_cert}) {
        if (exists $json_obj->{force} and $json_obj->{force} eq 'true') {
            $force = "true";
        }
        else {
            my $msg =
              "Let's Encrypt certificate $json_obj->{domains}[0] already exists! Why not use the '--renew' instead? If you are sure, use the '--force' parameter.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # check farm has to be listening on port 80 and up
    if (defined $json_obj->{farmname}) {
        require Relianoid::Farm::Base;
        if (&getFarmVip('vipp', $json_obj->{farmname}) ne 80) {
            my $msg = "Farm $json_obj->{farmname} must be listening on Port 80.";
            return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
        }

        require Relianoid::Farm::HTTP::Config;
        if (&getHTTPFarmStatus($json_obj->{farmname}) ne "up") {
            my $msg = "Farm $json_obj->{farmname} must be up.";
            return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
        }
    }

    # check any farm listening on vip and port 80 and up
    my $le_farm_port = 80;
    if (defined $json_obj->{vip}) {
        require Relianoid::Net::Validate;
        if (&validatePort($json_obj->{vip}, $le_farm_port, "tcp") == 0) {
            #vip:port is in use
            require Relianoid::Farm::Base;
            require Relianoid::Farm::HTTP::Config;

            for my $farm (&getFarmListByVip($json_obj->{vip})) {
                if (    &getHTTPFarmVip("vipp", $farm) eq "$le_farm_port"
                    and &getHTTPFarmStatus($farm) eq "up")
                {
                    my $msg = "Farm $farm is listening on 'vip' $json_obj->{vip} and Port $le_farm_port.";
                    return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
                }
            }
            my $msg = "The system has a process listening on 'vip' $json_obj->{vip} and Port $le_farm_port.";
            return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
        }
    }

    # check Email config
    my $le_conf = &getLetsencryptConfig();
    if (!$le_conf->{email}) {
        my $msg = "LetsencryptZ email is not configured.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $error =
      &runLetsencryptObtain($json_obj->{farmname}, $json_obj->{vip}, $json_obj->{domains}, $json_obj->{test}, $force);
    if ($error) {
        my $strdomains = join(", ", @{ $json_obj->{domains} });
        my $msg        = "The Letsencrypt certificate for Domain $strdomains can't be created";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    &zenlog("Success, the Letsencrypt certificate has been created successfully.", "info", "LestencryptZ");

    my $out  = &getLetsencryptCertificateInfo($json_obj->{domains}[0]);
    my $body = {
        description => $desc,
        params      => $out,
        message     => "The Letsencrypt certificate has been created successfully."
    };

    return &httpResponse({ code => 200, body => $body });
}

# DELETE /certificates/letsencryptz/le_cert_re
sub delete_le_cert_controller ($le_cert_name) {
    my $desc = "Delete LetsEncrypt certificate";

    require Relianoid::LetsencryptZ;

    my $le_cert = &getLetsencryptCertificates($le_cert_name);
    if (!@{$le_cert}) {
        my $msg = "Let's Encrypt certificate $le_cert_name not found!";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $cert_name = $le_cert_name;
    $cert_name =~ s/\./\_/g;
    $cert_name .= ".pem";

    # check the certificate is being used by a Farm
    require Relianoid::Certificate;
    my $farms_used = &getCertFarmsUsed($cert_name);
    if (@{$farms_used}) {
        my $msg =
          "Let's Encrypt Certificate $le_cert_name can not be deleted because it is in use by " . join(", ", @{$farms_used});
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    if ($eload) {
        # check the certificate is being used by ZAPI Webserver
        my $status = &eload(
            module => 'Relianoid::EE::System::HTTP',
            func   => 'getHttpsCertUsed',
            args   => ['$cert_name']
        );
        if ($status == 0) {
            my $msg = "Let's Encrypt Certificate $le_cert_name can not be deleted because it is in use by HTTPS server";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
    }

    # revoke LE cert
    my $error = &runLetsencryptDestroy($le_cert_name);
    if ($error) {
        my $msg = "Let's Encrypt Certificate can not be removed";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # delete autorenewal
    &unsetLetsencryptCron($le_cert_name);

    # delete RELIANOID cert if exists
    my $cert_dir = &getGlobalConfiguration('certdir');
    &delCert($cert_name) if (-f "$cert_dir\/$cert_name");

    if (-f "$cert_dir\/$cert_name") {
        my $msg = "Error deleting certificate $cert_name.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    &zenlog("Success, the Let's Encrypt certificate has been deleted successfully.", "info", "LestencryptZ");

    my $msg  = "Let's Encrypt Certificate $le_cert_name has been deleted.";
    my $body = {
        description => $desc,
        success     => "true",
        message     => $msg,
    };
    return &httpResponse({ code => 200, body => $body });
}

# POST /certificates/letsencryptz/le_cert_re/actions
sub actions_le_cert_controller ($json_obj, $le_cert_name) {
    my $desc = "Let's Encrypt certificate actions";

    require Relianoid::Certificate;
    require Relianoid::LetsencryptZ;

    # check the certificate is a LE cert
    my $le_cert = &getLetsencryptCertificates($le_cert_name);
    if (!@{$le_cert}) {
        my $msg = "Let's Encrypt certificate $le_cert_name not found!";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    require Relianoid::Net::Interface;
    my $ip_list = &getIpAddressList();
    require Relianoid::Farm::Core;
    my @farm_list = &getFarmsByType("http");

    my $params = &getAPIModel("letsencryptz-action.json");
    $params->{vip}{values}      = $ip_list;
    $params->{farmname}{values} = \@farm_list;

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # avoid farmname when no HTTP Farm exists
    if (not @farm_list and defined $json_obj->{farmname}) {
        my $msg = "There is no HTTP Farms in the system, use 'vip' param instead.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # vip or farmname has to be defined
    if (    not $json_obj->{vip}
        and not $json_obj->{farmname})
    {
        my $msg = "No 'vip' or 'farmname' param found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # check farm has to be listening on port 80 and up
    if (defined $json_obj->{farmname}) {
        require Relianoid::Farm::Base;
        if (&getFarmVip('vipp', $json_obj->{farmname}) ne 80) {
            my $msg = "Farm $json_obj->{farmname} must be listening on Port 80.";
            return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
        }

        require Relianoid::Farm::HTTP::Config;
        if (&getHTTPFarmStatus($json_obj->{farmname}) ne "up") {
            my $msg = "Farm $json_obj->{farmname} must be up.";
            return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
        }
    }

    # check any farm listening on vip and port 80 and up
    my $le_farm_port = 80;
    if (defined $json_obj->{vip}) {
        require Relianoid::Net::Validate;
        if (&validatePort($json_obj->{vip}, $le_farm_port, "tcp") == 0) {
            #vip:port is in use
            require Relianoid::Farm::Base;
            require Relianoid::Farm::HTTP::Config;

            for my $farm (&getFarmListByVip($json_obj->{vip})) {
                if (    &getHTTPFarmVip("vipp", $farm) eq "$le_farm_port"
                    and &getHTTPFarmStatus($farm) eq "up")
                {
                    my $msg = "Farm $farm is listening on 'vip' $json_obj->{vip} and Port $le_farm_port.";
                    return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
                }
            }
            my $msg = "The system has a process listening on 'vip' $json_obj->{vip} and Port $le_farm_port.";
            return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
        }
    }

    # check Email config
    my $le_conf = &getLetsencryptConfig();
    if (!$le_conf->{email}) {
        my $msg = "LetsencryptZ email is not configured.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $error_ref = &runLetsencryptRenew($le_cert_name, $json_obj->{farmname}, $json_obj->{vip}, $json_obj->{force_renewal},
        $json_obj->{test});
    if ($error_ref->{code}) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_ref->{desc} });
    }

    &zenlog("Success, the Letsencrypt certificate has been renewed successfully.", "info", "LestencryptZ");

    my @farms_restarted;
    my @farms_restarted_error;
    if (    (defined $json_obj->{restart})
        and ($json_obj->{restart} eq "true"))
    {
        my $cert_name = $le_cert_name;
        $cert_name =~ s/\./\_/g;
        $cert_name .= ".pem";

        my $error;
        require Relianoid::Farm::Action;
        require Relianoid::Farm::Base;
        for my $farm (@{ getCertFarmsUsed($cert_name) }) {
            # restart farm used and up
            if (&getFarmStatus($farm) ne 'down') {
                $error = &runFarmStop($farm, "");
                if ($error) {
                    push @farms_restarted_error, $farm;
                    next;
                }
                $error = &runFarmStart($farm, "");
                if ($error) {
                    push @farms_restarted_error, $farm;
                    next;
                }
                push @farms_restarted, $farm;
            }
        }

        # restart on backup node
        if ($eload) {
            &eload(
                module => 'Relianoid::EE::Cluster',
                func   => 'runZClusterRemoteManager',
                args   => [ 'farm', 'restart_farms', @farms_restarted ],
            ) if @farms_restarted;
        }
    }

    my $info_msg;
    if (@farms_restarted) {
        $info_msg = "The following farms were been restarted: " . join(", ", @farms_restarted);
    }
    if (@farms_restarted_error) {
        $info_msg = "The following farms could not been restarted: " . join(", ", @farms_restarted_error);
    }

    my $msg  = "The Let's Encrypt certificate $le_cert_name has been renewed successfully.";
    my $out  = &getLetsencryptCertificateInfo($le_cert_name);
    my $body = {
        description => $desc,
        params      => $out,
        message     => $msg
    };
    $body->{warning} = $info_msg if defined $info_msg;
    return &httpResponse({ code => 200, body => $body });
}

# PUT /certificates/letsencryptz/le_cert_re
sub set_le_cert_controller ($json_obj, $le_cert_name) {
    my $desc = "Modify Let's Encrypt certificate";

    require Relianoid::Certificate;
    require Relianoid::LetsencryptZ;

    # check the certificate is a LE cert
    my $le_cert = &getLetsencryptCertificates($le_cert_name);
    if (!@{$le_cert}) {
        my $msg = "Let's Encrypt certificate $le_cert_name not found!";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $params = &getAPIModel("letsencryptz-modify.json");

    # dyn_values model
    if (defined $json_obj->{vip}) {
        require Relianoid::Net::Interface;
        my $ip_list = &getIpAddressList();
        $params->{vip}{values} = $ip_list;
    }
    if (defined $json_obj->{farmname}) {
        require Relianoid::Farm::Core;
        my @farm_list = &getFarmsByType("http");
        $params->{farmname}{values} = \@farm_list;
    }

    # depends_on model
    if (defined $json_obj->{farmname}) {
        delete $params->{vip} if defined $json_obj->{vip};
    }

    if (    (defined $json_obj->{autorenewal})
        and ($json_obj->{autorenewal} eq "false"))
    {
        delete $params->{force_renewal} if defined $params->{force_renewal};
        delete $params->{restart}       if defined $params->{restart};
        delete $params->{vip}           if defined $params->{vip};
        delete $params->{farmname}      if defined $params->{farmname};
    }

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    # depends_on model
    # vip or farmname has to be defined
    if (    not $json_obj->{vip}
        and not $json_obj->{farmname}
        and $json_obj->{autorenewal} eq "true")
    {
        my $msg = "No 'vip' or 'farmname' param found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # check farm has to be listening on port 80 and up
    if (defined $json_obj->{farmname}) {
        require Relianoid::Farm::Base;
        if (&getFarmVip('vipp', $json_obj->{farmname}) ne 80) {
            my $msg = "Farm $json_obj->{farmname} must be listening on Port 80.";
            return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
        }

        require Relianoid::Farm::HTTP::Config;
        if (&getHTTPFarmStatus($json_obj->{farmname}) ne "up") {
            my $msg = "Farm $json_obj->{farmname} must be up.";
            return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
        }
    }

    # check any farm listening on vip and port 80 and up
    my $le_farm_port = 80;
    if (defined $json_obj->{vip}) {
        require Relianoid::Net::Validate;
        if (&validatePort($json_obj->{vip}, $le_farm_port, "tcp") == 0) {
            #vip:port is in use
            require Relianoid::Farm::Base;
            require Relianoid::Farm::HTTP::Config;

            for my $farm (&getFarmListByVip($json_obj->{vip})) {
                if (    &getHTTPFarmVip("vipp", $farm) eq "$le_farm_port"
                    and &getHTTPFarmStatus($farm) eq "up")
                {
                    my $msg = "Farm $farm is listening on 'vip' $json_obj->{vip} and Port $le_farm_port.";
                    return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
                }
            }
            my $msg = "The system has a process listening on 'vip' $json_obj->{vip} and Port $le_farm_port.";
            return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
        }
    }

    # check Email config
    my $le_conf = &getLetsencryptConfig();
    if (!$le_conf->{email}) {
        my $msg = "LetsencryptZ email is not configured.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $msg;
    if ($json_obj->{autorenewal} eq "true") {
        my $error = &setLetsencryptCron($le_cert_name, $json_obj->{farmname}, $json_obj->{vip}, $json_obj->{force_renewal},
            $json_obj->{restart});

        if ($error) {
            my $msg = "The Auto Renewal for Let's Encrypt certificate $le_cert_name can't be enabled";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }

        &zenlog("Success, the Auto Renewal for Letsencrypt certificate has been enabled successfully.", "info", "LestencryptZ");
        $msg = "The Auto Renewal for Let's Encrypt certificate $le_cert_name has been enabled successfully.";
    }
    else {
        my $error = &unsetLetsencryptCron($le_cert_name);
        if ($error) {
            my $msg = "The Auto Renewal for Let's Encrypt certificate $le_cert_name can't be disabled";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
        &zenlog("Success, the Auto Renewal for Letsencrypt certificate has been disabled successfully.",
            "info", "LestencryptZ");
        $msg = "The Auto Renewal for Let's Encrypt certificate $le_cert_name has been disabled successfully.";
    }

    my $out  = &getLetsencryptCertificateInfo($le_cert_name);
    my $body = {
        description => $desc,
        params      => $out,
        message     => $msg,
    };
    return &httpResponse({ code => 200, body => $body });
}

# GET /certificates/letsencryptz/config
sub get_le_conf_controller () {
    my $desc = "Get LetsEncrypt Config";

    require Relianoid::LetsencryptZ;
    my $out  = &getLetsencryptConfig();
    my $body = {
        description => $desc,
        params      => $out,
    };
    return &httpResponse({ code => 200, body => $body });
}

# PUT /certificates/letsencryptz/config
sub set_le_conf_controller ($json_obj) {
    my $desc   = "Modify LetsEncrypt Config";
    my $params = &getAPIModel("letsencryptz_config-modify.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    require Relianoid::LetsencryptZ;
    my $error = &setLetsencryptConfig($json_obj);
    if ($error) {
        my $msg = "The Letsencrypt Config can't be updated";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }
    my $msg  = "The Letsencrypt Config has been updated successfully.";
    my $out  = &getLetsencryptConfig();
    my $body = {
        description => $desc,
        success     => "true",
        message     => $msg,
        params      => $out,
    };
    return &httpResponse({ code => 200, body => $body });
}

1;
