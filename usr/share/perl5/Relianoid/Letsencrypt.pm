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

=pod

=head1 Module

Relianoid::Letsencrypt

=cut

=pod

=head1 getLetsencryptConfigPath

Returns the dirpath for Letsencrypt Config

Parameters:

    none

Returns:

    string -  dir path.

=cut

sub getLetsencryptConfigPath () {
    return &getGlobalConfiguration('le_config_path');
}

=pod

=head1 getLetsencryptConfig

Returns the Letsencrypt Config

Parameters:

    none

Returns:

    Hash ref - Letsencrypt Configuration

=cut

sub getLetsencryptConfig () {
    return { email => &getGlobalConfiguration('le_email') };
}

=pod

=head1 setLetsencryptConfig

Set the Letsencrypt Config

Parameters:

    Hash ref

Returns:

    Integer - 0 on succesfull, otherwise on error.

=cut

sub setLetsencryptConfig ($le_conf_re) {
    return &setGlobalConfiguration('le_email', $le_conf_re->{email});
}

=pod

=head1 getLetsencryptCronFile

Returns the Letsencrypt Cron Filepath

Parameters:

    none

Returns:

    string - Letsencrypt Cron filepath

=cut

sub getLetsencryptCronFile () {
    return &getGlobalConfiguration('le_cron_file');
}

=pod

=head1 getLetsencryptCertificates

Returns Letsencrypt Certificates

Parameters:

    le_cert_name - String. LE Certificate Name. None means all certificates.

Returns:

    Array ref - Letsencrypt Certificates

=cut

sub getLetsencryptCertificates ($le_cert_name = undef) {
    my $le_certs_ref = [];

    my $le_config_path = &getLetsencryptConfigPath();
    my $le_live_path   = $le_config_path . "live";

    my $certs;
    if (defined $le_cert_name) {
        push @{$certs}, "$le_cert_name";
    }
    else {
        if (opendir(my $directory, $le_live_path)) {
            while (defined(my $file = readdir $directory)) {
                next if $file eq ".";
                next if $file eq "..";

                if (-d "$le_live_path/$file") {
                    push @{$certs}, $file;
                }
            }
            closedir($directory);
        }
        else {
            log_warn("Could not open directory $le_live_path: $!");
        }
    }

    require Crypt::OpenSSL::X509;
    my $cert_ref;
    my $domains;

    for my $cert (@{$certs}) {
        my $key_path  = "${le_live_path}/${cert}/privkey.pem";
        my $cert_path = "${le_live_path}/${cert}/fullchain.pem";

        $cert_ref->{name} = $cert;

        if (-l $key_path) {
            $cert_ref->{keypath} = $key_path;
        }

        if (-l $cert_path) {
            $cert_ref->{certpath} = $cert_path;

            # domains
            eval {
                my $x509 = Crypt::OpenSSL::X509->new_from_file($cert_ref->{certpath});
                my $exts = $x509->extensions_by_name();

                if (defined $exts->{subjectAltName}) {
                    my $value = $exts->{subjectAltName}->to_string() . ", ";
                    @{$domains} = $value =~ /(?:DNS:(.*?), )/g;
                }
            };
            if ($@) {
                log_error("Could not read Let's Encrypt certificate $cert_ref->{certpath}: $@");
            }

            $cert_ref->{domains} = $domains;
        }

        if (defined $domains) {
            push @{$le_certs_ref}, $cert_ref;
        }

        $cert_ref = undef;
        $domains  = undef;
    }

    return $le_certs_ref;
}

=pod

=head1 getLetsencryptCertificateInfo

Returns the Letsencrypt no Wildcard Certificates Info

Parameters:

    le_cert_name . LE Certificate name

Returns:

    Hash ref - Letsencrypt Certificate Info

=cut

sub getLetsencryptCertificateInfo ($le_cert_name) {
    my $cert_ref  = {};
    my $cert_info = &getLetsencryptCertificates($le_cert_name);

    return if (!$cert_info);

    $cert_info = @{$cert_info}[0];

    require Crypt::OpenSSL::X509;

    my $status = "unknown";
    my $CN     = "";
    my $ISSUER = "";
    my $x509;
    my @domains;

    eval {
        $x509 = Crypt::OpenSSL::X509->new_from_file($cert_info->{certpath});
        my $time_offset = 60 * 60 * 24 * 15;    # 15 days
        if ($x509->checkend(0)) { $status = 'expired' }
        else {
            $status = ($x509->checkend($time_offset)) ? 'about to expire' : 'valid';
        }
        if (defined $x509->subject_name()->get_entry_by_type('CN')) {
            $CN = $x509->subject_name()->get_entry_by_type('CN')->value;
        }
        if (defined $x509->issuer_name()) {
            for my $entry (@{ $x509->issuer_name()->entries() }) {
                $ISSUER .= $entry->value() . ",";
            }
            chop $ISSUER;
        }
        my $exts = $x509->extensions_by_name();
        if (defined $exts->{subjectAltName}) {
            my $value = $exts->{subjectAltName}->to_string() . ", ";
            @domains = $value =~ /(?:DNS:(.*?), )/g;
        }
    };

    $cert_ref->{file}     = $cert_info->{certpath};
    $cert_ref->{type}     = 'LE Certificate';
    $cert_ref->{wildcard} = 'false';
    $cert_ref->{status}   = $status;

    if ($@) {
        $cert_ref->{CN}         = '';
        $cert_ref->{issuer}     = '';
        $cert_ref->{creation}   = '';
        $cert_ref->{expiration} = '';
        $cert_ref->{domains}    = '';
    }
    else {
        $cert_ref->{CN}         = $CN;
        $cert_ref->{issuer}     = $ISSUER;
        $cert_ref->{creation}   = $x509->notBefore();
        $cert_ref->{expiration} = $x509->notAfter();
        $cert_ref->{domains}    = \@domains;
    }

    my $autorenewal = &getLetsencryptCron($le_cert_name);
    $cert_ref->{autorenewal} = $autorenewal if $autorenewal;

    return $cert_ref;
}

=pod

=head1 setLetsencryptFarmService

Configure the Letsencrypt Service on a Farm

Parameters:

    farm_name - Farm Name.
    vip - Virtual IP to use with Temporal Farm.

Returns:

    Integer - 0 on succesfull, otherwise on error.

=cut

sub setLetsencryptFarmService ($farm_name, $vip) {
    # if no exists farm return -1,
    my $le_service = &getGlobalConfiguration('le_service');
    my $le_farm    = &getGlobalConfiguration('le_farm');

    my $error;

    require Relianoid::Farm::Core;

    # create a temporal farm
    if ($farm_name eq $le_farm) {
        require Relianoid::Farm::HTTP::Factory;

        if ($error = &runHTTPFarmCreate($vip, 80, $farm_name, "HTTP")) {
            &log_error("Error creating temporal Farm $farm_name", "letsencrypt");
            return 1;
        }

        &log_info("The temporal Farm $farm_name has been created", "letsencrypt");
    }

    #create Letsencrypt service
    require Relianoid::Farm::HTTP::Service;

    # check Letsencrypt service
    my $service_ref = &getHTTPFarmServices($farm_name, $le_service);
    if (not $service_ref) {
        if ($eload) {
            $error = &setFarmHTTPNewService($farm_name, $le_service);
        }
        else {
            $error = &setFarmHTTPNewServiceFirst($farm_name, $le_service);
        }

        if ($error) {
            &log_error("Error creating the service $le_service", "letsencrypt");
            return 1;
        }

        &log_info("The Service $le_service in Farm $farm_name has been created", "letsencrypt");
    }
    else {
        &log_warn("The Service $le_service in Farm $farm_name already exists", "letsencrypt");
    }

    if ($eload) {
        #Move the service to position 0
        if (not $service_ref or $service_ref->{$le_service}) {
            $error = &eload(
                module => 'Relianoid::EE::Farm::HTTP::Service::Ext',
                func   => 'setHTTPFarmMoveService',
                args   => [ $farm_name, $le_service, 0 ],
            );
            if ($error) {
                &log_error("Error moving the service $le_service", "letsencrypt");
                return 4;
            }
        }
        else {
            &log_warn("The Service $le_service in Farm $farm_name is already in the first position", "letsencrypt");
        }
    }

    # create local Web Server Backend
    require Relianoid::Farm::HTTP::Backend;
    $error = &setHTTPFarmServer("", "127.0.0.1", 80, "", "", $farm_name, $le_service);
    if ($error) {
        &log_error("Error creating the Local Web Server backend on service $le_service", "letsencrypt");
        return 2;
    }

    # create Letsencrypt URL Pattern http challenge
    $error = &setHTTPFarmVS($farm_name, $le_service, "urlp", "^/.well-known/acme-challenge/");
    if ($error) {
        &log_error("Error creating the URL pattern on service $le_service", "letsencrypt");
        return 3;
    }

    &log_info("The Service $le_service in Farm $farm_name has been configured", "letsencrypt");

    # Restart the farm
    require Relianoid::Farm::Action;

    if ($error = &runFarmStop($farm_name)) {
        &log_error("Error stopping the farm $farm_name", "letsencrypt");
        return 5;
    }

    $error = &runFarmStart($farm_name);
    if ($error) {
        &log_error("Error starting the farm $farm_name", "letsencrypt");
        return 6;
    }

    &log_info("The Farm $farm_name has been restarted", "letsencrypt");

    return 0;
}

=pod

=head1 unsetLetsencryptFarmService

Remove the Letsencrypt Service on a Farm

Parameters:

    farm_name - Farm Name.

Returns:

    Integer - 0 on succesfull, otherwise on error.

=cut

sub unsetLetsencryptFarmService ($farm_name) {
    # if no exists farm return -1,
    my $le_service = &getGlobalConfiguration('le_service');
    my $le_farm    = &getGlobalConfiguration('le_farm');

    if ($farm_name eq $le_farm) {
        require Relianoid::Farm::Action;

        if (my $error = &runFarmStop($farm_name)) {
            &log_error("Error stopping the farm $farm_name", "letsencrypt");
            return 1;
        }

        if (my $error = &runFarmDelete($farm_name)) {
            &log_error("Error deleting the farm $farm_name", "letsencrypt");
            return 2;
        }

        &log_info("The Farm $farm_name has been deleted", "letsencrypt");
    }
    else {
        require Relianoid::Farm::HTTP::Service;

        if (&getHTTPFarmServices($farm_name, $le_service)) {
            if (my $error = &delHTTPFarmService($farm_name, $le_service)) {
                &log_error("Error Deleting the service $le_service on farm $farm_name", "letsencrypt");
                return 3;
            }
            &log_info("The service $le_service on farm $farm_name has been deleted", "letsencrypt");

            # Restart the farm
            require Relianoid::Farm::Action;

            if (my $error = &runFarmStop($farm_name)) {
                &log_error("Error stopping the farm $farm_name", "letsencrypt");
                return 1;
            }

            if (my $error = &runFarmStart($farm_name)) {
                &log_error("Error starting the farm $farm_name", "letsencrypt");
                return 4;
            }

            &log_info("The Farm $farm_name has been restarted", "letsencrypt");
        }
        else {
            &log_warn("The Service $le_service in Farm $farm_name can not be deleted, it does not exist", "letsencrypt");
        }
    }

    return 0;
}

=pod

=head1 runLetsencryptLocalWebserverStart

Start Local Webserver listening on localhost:80

Parameters:

    None

Returns:

    Integer - 0 on succesfull, otherwise on error.

=cut

sub runLetsencryptLocalWebserverStart () {
    my $http_dir                 = &getGlobalConfiguration('http_server_dir');
    my $pid_file                 = "$http_dir/var/run/cherokee_localhost.pid";
    my $le_webserver_config_file = &getGlobalConfiguration('le_webserver_config_file');
    my $http_bin                 = &getGlobalConfiguration('http_bin');

    my $rc = 0;

    my $status = &getLetsencryptLocalWebserverRunning();

    if ($status == 1) {
        &log_info("$http_bin -d -C $le_webserver_config_file", "letsencrypt");
        &logAndRunBG("$http_bin -d -C $le_webserver_config_file");
    }

    use Time::HiRes qw(usleep);
    my $retry     = 0;
    my $max_retry = 50;
    while (not -f $pid_file and $retry < $max_retry) {
        $retry++;
        usleep(100_000);
    }
    if (not -f $pid_file) {
        &log_error("Error starting Local Web Server", "letsencrypt");
        $rc = 1;
    }
    else {
        &log_info("Letsencrypt Local Web Server is running", "letsencrypt");
    }

    return $rc;
}

=pod

=head1 runLetsencryptLocalWebserverStop

Stop Local Webserver listening on localhost:80

Parameters:

    None

Returns:

    Integer - 0 on succesfull, otherwise on error.

=cut

sub runLetsencryptLocalWebserverStop () {
    my $http_dir = &getGlobalConfiguration('http_server_dir');
    my $pid_file = "$http_dir/var/run/cherokee_localhost.pid";
    my $pid      = "0";
    my $kill_bin = &getGlobalConfiguration('kill_bin');
    my $cat_bin  = &getGlobalConfiguration('cat_bin');

    my $status = &getLetsencryptLocalWebserverRunning();

    if ($status == 0) {
        $pid = &logAndGet("$cat_bin $pid_file");
        my $error = &logAndRun("$kill_bin -15 $pid");
        if ($error) {
            &log_error("Error stopping Letsencrypt Local Web Server", "letsencrypt");
            return 1;
        }
        use Time::HiRes qw(usleep);
        my $retry     = 0;
        my $max_retry = 20;
        while (-f $pid_file and $retry < $max_retry) {
            $retry++;
            usleep(100_000);
        }
        unlink $pid_file if (-f $pid_file);
        &log_info("Letsencrypt Local Web Server is stopped", "letsencrypt");
    }

    return 0;
}

=pod

=head1 getLetsencryptLocalWebserverRunning

Check Local Webserver is running

Parameters:

    None

Returns:

    Integer - 0 on succesfull, otherwise on error.

=cut

sub getLetsencryptLocalWebserverRunning () {
    my $rc;
    my $http_dir = &getGlobalConfiguration('http_server_dir');
    my $pid_file = "$http_dir/var/run/cherokee_localhost.pid";

    if (-f $pid_file) {
        use Relianoid::System;

        if (&checkPidFileRunning($pid_file)) {
            &log_warn("Letsencrypt Local Webser is not running but PID file $pid_file exists!", "letsencrypt");
            unlink $pid_file;
        }
        $rc = 0;
    }
    else {
        my $pgrep                    = &getGlobalConfiguration('pgrep');
        my $http_bin                 = &getGlobalConfiguration('http_bin');
        my $le_webserver_config_file = &getGlobalConfiguration('le_webserver_config_file');

        if (&logAndRunCheck("$pgrep -f \"$http_bin -d -C $le_webserver_config_file\"")) {
            &log_warn("Letsencrypt Local Webserver is running but no PID file $pid_file exists!", "letsencrypt");
            $rc = 2;
        }
        else {
            $rc = 1;
        }
    }

    return $rc;
}

=pod

=head1 setLetsencryptCert

Create RELIANOID Pem Certificate. Dot characters are replaced with underscore character.

Parameters:

    le_cert_name - Certificate main domain name.

Returns:

    Integer - 0 on succesfull, otherwise on error.

=cut

sub setLetsencryptCert ($le_cert_name) {
    my $rc = 1;

    my $le_cert_conf = &getLetsencryptCertificates($le_cert_name);
    if (@{$le_cert_conf}) {
        $le_cert_conf = @{$le_cert_conf}[0];
        if (    (defined $le_cert_conf->{certpath})
            and (defined $le_cert_conf->{keypath}))
        {
            if (    (-e $le_cert_conf->{keypath})
                and (-e $le_cert_conf->{certpath}))
            {
                my $cert_name = $le_cert_name;
                $cert_name =~ s/\./_/g;
                my $cat_bin   = &getGlobalConfiguration('cat_bin');
                my $cert_dir  = &getGlobalConfiguration('certdir');
                my $cert_file = "$cert_dir/${cert_name}.pem";
                &logAndRun("$cat_bin $le_cert_conf->{keypath} $le_cert_conf->{certpath} > $cert_file");
                return 1 if (!-f $cert_file);
                $rc = 0;
            }
        }
    }

    return $rc;
}

=pod

=head1 runLetsencryptObtain

Obtain a new LetsEncrypt Certificate for the Domains especified.

Parameters:

    farm_name - Farm Name where Letsencrypt will connect.
    vip - VIP where the new Farm and service is created. The virtual Port will be 80.
    domains_list - List of Domains the certificate is created for.
    test - if "true" the action simulates all the process but no certificate is created.
    force - if "true" forces an update cert and renewal the domains if exists.

Returns:

    Integer - 0 on succesfull, otherwise on error.

=cut

sub runLetsencryptObtain ($farm_name = undef, $vip = undef, $domains_list = undef, $test = undef, $force = undef) {
    return 1 if (!$domains_list);
    return 2 if (!$vip && !$farm_name);
    my $status;
    my $rc = 0;

    my $le_farm = &getGlobalConfiguration('le_farm');
    $farm_name = $le_farm if (!$farm_name);

    # check is a wildcard
    my $challenge = "http";

    # start local Web Server
    $status = &runLetsencryptLocalWebserverStart();

    return 1 if $status;

    # add le service
    $status = &setLetsencryptFarmService($farm_name, $vip);
    return 2 if $status;

    # run le_binary command
    my $test_opt      = ($test eq "true")  ? "--test-cert"                      : "";
    my $force_opt     = ($force eq "true") ? "--force-renewal --break-my-certs" : "";
    my $certname_opt  = "--cert-name " . @{$domains_list}[0];
    my $domains_opt   = "-d " . join(',', @{$domains_list});
    my $fullchain_opt = "--fullchain-path " . &getGlobalConfiguration('le_fullchain_path');
    my $method_opt;

    if ($challenge eq "http") {
        $method_opt = "--webroot --webroot-path " . &getGlobalConfiguration('le_webroot_path');
    }
    my $configdir_opt = "--config-dir " . &getLetsencryptConfigPath();
    my $email_opt     = "-m " . &getLetsencryptConfig()->{email};
    my $challenge_opt = "--preferred-challenges $challenge";
    my $opts          = "--agree-tos --no-eff-email -n";

    my $le_binary    = &getGlobalConfiguration('le_certbot_bin');
    my @command_args = (
        $le_binary,     "certonly", $certname_opt, $domains_opt,   $fullchain_opt, $method_opt,
        $configdir_opt, $email_opt, $test_opt,     $challenge_opt, $force_opt,     $opts
    );

    my $cmd = join " ", @command_args;

    &log_info("Executing Letsencrypt obtain command : $cmd", "letsencrypt");

    $status = &logRunAndGet($cmd, "array", 1);

    if ($status->{stderr} and ($challenge eq "http")) {
        &log_error("Letsencrypt obtain command failed!: $status->{stdout}[-1]", "letsencrypt");
        $rc = 3;
    }
    else {
        # create RELIANOID PEM cert
        $status = &setLetsencryptCert(@{$domains_list}[0]);

        if ($status) {
            &log_error("Letsencrypt create PEM cert failed!", "letsencrypt");
            $rc = 4;
        }
    }

    # delete le service
    &unsetLetsencryptFarmService($farm_name);

    # stop local Web Server
    &runLetsencryptLocalWebserverStop();

    return $rc;
}

=pod

=head1 runLetsencryptDestroy

Revoke a LetsEncrypt Certificate.

Parameters:

    le_cert_name - LE Certificate name.

Returns:

    Integer - 0 on succesfull, otherwise on error.

=cut

sub runLetsencryptDestroy ($le_cert_name) {
    my $le_config_path = &getLetsencryptConfigPath();
    my $local_path     = &getGlobalConfiguration('localconfig');
    my $le_backup_file = "$local_path/le_backup-$le_cert_name.tgz";
    my $rm_bck_cmd     = "rm -f $le_backup_file";

    return 1 if (!$le_cert_name);
    return 2 if (!-d "$le_config_path/live/$le_cert_name");

    if (-f "$le_backup_file") {
        &logAndRun($rm_bck_cmd);
    }

    my $le_binary = &getGlobalConfiguration('le_certbot_bin');

    # run le_binary revoke command ??
    # revoke --cert-path /PATH/TO/live/$cert_name/cert.pem --key-path /PATH/TO/live/$cert_name/privkey.pem

    # run le_binary delete command
    # delete --cert-name $cert_name --config-dir $le_config_path --reason unspecified

    my $certname_opt  = "--cert-name " . $le_cert_name;
    my $configdir_opt = "--config-dir " . &getLetsencryptConfigPath();
    my $opts          = "--reason unspecified";

    my $cmd = "$le_binary delete $certname_opt $configdir_opt $opts";
    &log_info("Executing Letsencrypt delete command : $cmd", "letsencrypt");

    my $status = &logRunAndGet($cmd, "array");
    if ($status->{stderr}) {
        &log_error("Letsencrypt delete command failed!", "letsencrypt");
        return 3;
    }
    return 3 if (-d "$le_config_path/live/$le_cert_name");

    return 0;
}

=pod

=head1 runLetsencryptRenew

Renew a LetsEncrypt Certificate.

Parameters:

    le_cert_name  - LetsEncrypt Certificate Name
    farm_name     - Farm Name where Letsencrypt will connect.
    vip           - VIP where the new Farm and service is created. The virtual Port will be 80.
    force         - if "true" forces a renew even the cert not yet due for renewal( over 30 days for expire ).
    lock_fh       - FileHandle to lock the process

Returns: hash reference

Error object.

    code - integer - Error code. 0 on success.
    desc - string - Description of the error.

=cut

sub runLetsencryptRenew ($le_cert_name, $farm_name, $vip, $force, $lock_fh) {
    my $status;
    my $error_ref = { code => 0 };

    if (!$le_cert_name) {
        $error_ref->{code} = 1;
        $error_ref->{desc} = "No 'certificate' param found";
        return $error_ref;
    }

    if (!$vip && !$farm_name) {
        $error_ref->{code} = 1;
        $error_ref->{desc} = "No 'farm' param or 'vip' param found";
        return $error_ref;
    }

    my $le_farm = &getGlobalConfiguration('le_farm');
    $farm_name = $le_farm if (!$farm_name);

    # Lock process
    my $lock_le_renew = "/tmp/letsencrypt-renew.lock";
    my $lock_le_renew_fh;

    if (not $lock_fh) {
        if (not -f $lock_le_renew) {
            my $touch = &getGlobalConfiguration('touch');
            &logAndRun("$touch $lock_le_renew");
        }
        $lock_le_renew_fh = &openlock($lock_le_renew, "w");
    }
    else {
        $lock_le_renew_fh = $lock_fh;
    }

    # start local Web Server
    $status = &runLetsencryptLocalWebserverStart();

    if ($status) {
        $error_ref->{code} = 1;
        $error_ref->{desc} = "Letsencrypt Local Webserver can not be created.";
        close $lock_le_renew_fh;
        unlink $lock_le_renew;
        return $error_ref;
    }

    # add le service
    $status = &setLetsencryptFarmService($farm_name, $vip);
    if ($status) {
        $error_ref->{code} = 2;
        $error_ref->{desc} = "Letsencrypt Service can not be created.";
        close $lock_le_renew_fh;
        unlink $lock_le_renew;
        return $error_ref;
    }

    # run le_binary command
    my $test_opt  = &isLetsencryptStaging($le_cert_name) ? "--test-cert"                      : "";
    my $force_opt = ($force eq "true")                   ? "--force-renewal --break-my-certs" : "";

    my $fullchain_opt = "--fullchain-path " . &getGlobalConfiguration('le_fullchain_path');
    my $webroot_opt   = "--webroot --webroot-path " . &getGlobalConfiguration('le_webroot_path');
    my $configdir_opt = "--config-dir " . &getLetsencryptConfigPath();
    my $email_opt     = "-m " . &getLetsencryptConfig()->{email};
    my $opts          = "--preferred-challenges http-01 --agree-tos --no-eff-email -n --no-random-sleep-on-renew";

    my $le_binary = &getGlobalConfiguration('le_certbot_bin');
    my $cmd =
      "$le_binary certonly -d $le_cert_name $fullchain_opt $webroot_opt $configdir_opt $email_opt $test_opt $force_opt $opts";

    &log_info("Executing Letsencrypt renew command : $cmd", "letsencrypt");
    $status = &logRunAndGet($cmd, "array");

    alarm(0);

    if ($status->{stderr}) {
        my $error_response = "Error creating new order";

        if (my ($le_msg) = grep { /$error_response/ } @{ $status->{stdout} }) {
            &log_error("$le_msg", "letsencrypt");
            $error_ref->{code} = 6;
            $error_ref->{desc} = $le_msg;
        }
        else {
            my $le_msg = "Letsencrypt renew command failed!";
            &log_error($le_msg, "letsencrypt");
            $error_ref->{code} = 3;
            $error_ref->{desc} = $le_msg;
        }
    }
    else {
        # check is not due to renewal response
        my $renewal_response = "Cert not yet due for renewal";

        if (grep { /$renewal_response/ } @{ $status->{stdout} }) {
            my $le_msg = "Letsencrypt certificate '$le_cert_name' not yet due for renewal!";
            &log_error($le_msg, "letsencrypt");
            $error_ref->{code} = 5;
            $error_ref->{desc} = $le_msg;
        }
        else {
            # create RELIANOID PEM cert
            $status = &setLetsencryptCert($le_cert_name);

            if ($status) {
                my $le_msg = "Letsencrypt create PEM cert failed!";
                &log_error($le_msg, "letsencrypt");
                $error_ref->{code} = 4;
                $error_ref->{desc} = $le_msg;
            }
        }
    }

    # delete le service
    &unsetLetsencryptFarmService($farm_name);

    # stop local Web Server
    &runLetsencryptLocalWebserverStop();

    close $lock_le_renew_fh;
    unlink $lock_le_renew;

    return $error_ref;
}

=pod

=head1 isLetsencryptStaging

Check the LetsEncrypt Certificate API server.

Parameters:

    le_cert_name - Certificate Name.

Returns: integer - 1 for staging, 0 for production.

=cut

sub isLetsencryptStaging ($le_cert_name) {
    my $le_config_path = &getLetsencryptConfigPath();
    my $rc             = 0;

    return $rc if (!$le_cert_name);

    my $le_cert_renewal_file = "$le_config_path/renewal/$le_cert_name.conf";

    if (-f $le_cert_renewal_file) {
        require Config::Tiny;

        my $le_cert_renewal_conf = Config::Tiny->read($le_cert_renewal_file);
        my $le_api_server        = $le_cert_renewal_conf->{renewalparams}{server};

        $rc = int($le_api_server =~ /acme-staging/);
    }

    return $rc;
}

=pod

=head1 setLetsencryptCron

Set a cron entry for an automatic renewal Letsencrypt certificate

Parameters:

    le_cert_name - LE Cert Name
    farm_name    - Farm Name where Letsencrypt will connect.
    vip          - VIP where the new Farm and service is created. The virtual Port will be 80.
    force        - if "true" forces a renew flag even the cert not yet due for renewal( over 30 days for expire ).
    restart      - if "true" forces a restart flag to restart farms affected by the certificate.

Returns:

    Integer - 0 on succesfull, otherwise on error.

=cut

sub setLetsencryptCron ($le_cert_name, $farm_name, $vip, $force, $restart) {
    my $rc = 0;

    return 1 if (!$le_cert_name);
    return 2 if (!$vip && !$farm_name) or ($vip && $farm_name);

    my $le_cron_file   = &getLetsencryptCronFile();
    my $le_renewal_bin = &getGlobalConfiguration('le_renewal_bin');
    my $minute         = int rand(59);

    require Relianoid::Lock;
    &ztielock(\my @le_cron_list, $le_cron_file);
    my $frequency = "$minute 22 * * * ";
    my $command   = "root $le_renewal_bin --cert $le_cert_name";
    @le_cron_list = grep { !/ $command / } @le_cron_list;

    $command .= " --farm $farm_name" if $farm_name;
    $command .= " --vip $vip"        if $vip;
    $command .= " --force"           if (defined $force   and ($force eq "true"));
    $command .= " --restart"         if (defined $restart and ($restart eq "true"));

    push @le_cron_list, "$frequency $command";
    untie @le_cron_list;

    return $rc;
}

=pod

=head1 unsetLetsencryptCron

Delete a cron entry for an automatic renewal Letsencrypt certificate

Parameters:

    le_cert_name - LE Cert Name

Returns:

    Integer - 0 on succesfull, otherwise on error.

=cut

sub unsetLetsencryptCron ($le_cert_name) {
    my $rc = 0;

    return 1 if (!$le_cert_name);

    my $le_cron_file   = &getLetsencryptCronFile();
    my $le_renewal_bin = &getGlobalConfiguration('le_renewal_bin');

    require Relianoid::Lock;
    &ztielock(\my @le_cron_list, $le_cron_file);
    my $command = "root $le_renewal_bin --cert $le_cert_name";
    @le_cron_list = grep { !/ $command / } @le_cron_list;
    untie @le_cron_list;

    return $rc;
}

=pod

=head1 getLetsencryptCron

get the cron entry for an automatic renewal Letsencrypt certificate

Parameters:

    le_cert_name - LE Cert Name

Returns:

    Hash - cron entry Hash ref with values on successful.

=cut

sub getLetsencryptCron ($le_cert_name) {
    my $cron_ref = {
        status  => "disabled",
        farm    => undef,
        vip     => undef,
        force   => undef,
        restart => undef
    };

    my $le_cron_file   = &getLetsencryptCronFile();
    my $le_renewal_bin = &getGlobalConfiguration('le_renewal_bin');

    my @le_cron_list = ();
    if (open my $fd, '<', $le_cron_file) {
        @le_cron_list = <$fd>;
        close $fd;
        chomp(@le_cron_list);
    }
    else {
        log_debug("Could not open $le_cron_file: $!");
    }

    my $command = "root $le_renewal_bin --cert $le_cert_name";
    my @le_cron = grep { / $command / } @le_cron_list;

    if (scalar @le_cron > 0) {
        require Relianoid::Validate;

        my $farm_name = &getValidFormat('farm_name');
        my $vip       = &getValidFormat('ip_addr');

        if ($le_cron[0] =~ /$command(?: --farm ($farm_name))?(?: --vip ($vip))?(?:( --force))?(?:( --restart))?$/) {
            $cron_ref->{status}  = "enabled";
            $cron_ref->{farm}    = $1;
            $cron_ref->{vip}     = $2;
            $cron_ref->{force}   = defined $3 ? "true" : "false";
            $cron_ref->{restart} = defined $4 ? "true" : "false";
        }
    }

    return $cron_ref;
}

=pod

=head1 getLetsencryptCertConfigIsBroken

Detect if the LetsEncrypt configuration folder is broken

Parameters:

    cert_name - the name of the certificate

Returns:

    Integer - 0 if it's not broken, 1 if it's broken.

=cut

sub getLetsencryptCertConfigIsBroken ($cert_name) {
    my $le_fullchain_path = &getGlobalConfiguration('le_fullchain_path');
    my $broken            = 0;
    my $cmd               = "find $le_fullchain_path/live/$cert_name/ -type l ! -exec test -e \{\} \\; -print";

    my $output = &logAndGet($cmd);
    if (   ($output ne "")
        or (!-f "$le_fullchain_path/renewal/$cert_name.conf")
        or (!-d "$le_fullchain_path/archive/$cert_name/"))
    {
        $broken = 1;
        &log_error("Detected LetsEncrypt configuration broken", "letsencrypt");
    }

    return $broken;
}

=pod

=head1 runLetsencryptCertConfigBackup

Create a backup for the Lets Encrypt configuration

Parameters:

    cert_name - the name of the certificate

Returns:

    Integer - 0 on succesful, 1 if there was a problem generating the backup.

=cut

sub runLetsencryptCertConfigBackup ($cert_name) {
    my $le_fullchain_path = &getGlobalConfiguration('le_fullchain_path');
    my $le_backup_path    = &getGlobalConfiguration('localconfig');
    my $le_backup_file    = "le_backup-$cert_name.tgz";
    my $cmd =
      "cd $le_fullchain_path && tar zcf $le_backup_path/$le_backup_file live/$cert_name/ archive/$cert_name/ renewal/$cert_name.conf";
    my $output = 0;

    &log_info("Creating LetsEncrypt Configuration Backup to $le_backup_path/$le_backup_file", "letsencrypt");
    if (-f "$le_backup_path/$le_backup_file") {
        &logAndRun("mv $le_backup_path/$le_backup_file $le_backup_path/$le_backup_file.bck");
    }
    $output = &logAndRun($cmd);
    if (-f "$le_backup_path/$le_backup_file.bck") {
        if ($output) {
            &log_error("Creating LetsEncrypt Configuration Backup Failed, recovering backup", "letsencrypt");
            &logAndRun("mv $le_backup_path/$le_backup_file.bck $le_backup_path/$le_backup_file");
        }
        else {
            &logAndRun("rm $le_backup_path/$le_backup_file.bck");
        }
    }

    return $output;
}

=pod

=head1 runLetsencryptCertConfigRecovery

Apply a backup recovery for the Lets Encrypt configuration

Parameters:

    cert_name - the name of the certificate

Returns:

    Integer - 0 if recovery successful, 1 if there was a problem with the recovery.

=cut

sub runLetsencryptCertConfigRecovery ($cert_name) {
    my $le_fullchain_path = &getGlobalConfiguration('le_fullchain_path');
    my $le_backup_path    = &getGlobalConfiguration('localconfig');
    my $le_backup_file    = "le_backup-$cert_name.tgz";
    my $cmd =
      "cd $le_fullchain_path && rm -rf live/$cert_name/ archive/$cert_name/ renewal/$cert_name.conf && tar zxf $le_backup_path/$le_backup_file";
    my $output = 0;

    if (-f "$le_backup_path/$le_backup_file") {
        &log_info("Recovery LetsEncrypt Configuration Backup from $le_backup_path/$le_backup_file", "letsencrypt");
        &logAndRun($cmd);
        $output = 1;
    }
    else {
        &log_warn("No backup available to recover at $le_backup_path/$le_backup_file", "letsencrypt");
        $output = 1;
    }

    return $output;
}

=pod

=head1 runLetsencryptCertConfigProtection

Protection to ensure that the configuration files in letsencrypt are not corrupted.
Always maintain a copy to be deployed in case a corruption is detected.

Parameters:

    cert_name - the name of the certificate

Returns:

    Integer - 0 if not recovery required, 1 if it was recovered.

=cut

sub runLetsencryptCertConfigProtection ($cert_name) {
    my $output = 0;

    if (!&getLetsencryptCertConfigIsBroken($cert_name)) {
        &runLetsencryptCertConfigBackup($cert_name);
    }
    else {
        $output = &runLetsencryptCertConfigRecovery($cert_name);
        $output = 1;
    }

    return $output;
}

1;
