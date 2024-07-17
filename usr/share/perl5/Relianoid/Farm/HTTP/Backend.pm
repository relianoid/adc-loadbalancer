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

require Relianoid::Netfilter;
require Relianoid::Farm::Config;

my $configdir = &getGlobalConfiguration('configdir');

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::Farm::HTTP::Backend

=cut

=pod

=head1 setHTTPFarmServer

Add a new backend to a HTTP service or modify if it exists

Parameters:

    ids       - integer - backend id
    rip       - string  - backend ip
    port      - integer - backend port
    weight    - integer - The weight of this backend (between 1 and 9). Higher weight backends will be used more often than lower weight ones.
    timeout   - integer - Override the global time out for this backend
    farm_name - string  - Farm name
    service   - string  - service name
    priority  - integer - Optional. The priority of this backend (greater than 1). Lower value indicates higher priority

Returns: integer - Error code - non-zero when there is an error.

=cut

sub setHTTPFarmServer ($ids, $rip, $port, $weight, $timeout, $farm_name, $service, $priority = 1) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;

    $priority = 1 if (not defined $priority) or $priority eq '';
    $priority = 1 unless ($priority == 1 || $priority == 2);

    require Relianoid::Lock;
    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @contents, 'Tie::File', "${configdir}/${farm_filename}";

    if ($ids ne "") {
        my $index_count = -1;
        my $i           = -1;
        my $sw          = 0;

        for my $line (@contents) {
            $i++;

            #search the service to modify
            if ($line =~ /^\s*Service "$service"/) {
                $sw = 1;
            }

            if ($line =~ /^\s*(BackEnd|Emergency)/ && $sw) {
                $index_count++;

                if ($index_count == $ids) {
                    #server for modify $ids;
                    #HTTPS
                    if ($line =~ /^\s*BackEnd/ && $priority == 2) {
                        $contents[$i] = "\t\tEmergency";
                    }
                    elsif ($line =~ /^\s*Emergency/ && $priority == 1) {
                        $contents[$i] = "\t\tBackEnd";
                    }

                    my $httpsbe = &getHTTPFarmVS($farm_name, $service, "httpsbackend");

                    if ($httpsbe eq "true") {
                        #add item
                        $i++;
                    }

                    $output             = 0;
                    $contents[ $i + 1 ] = "\t\t\tAddress $rip";
                    $contents[ $i + 2 ] = "\t\t\tPort $port";

                    my $p_m = 0;

                    if ($contents[ $i + 3 ] =~ /^\s*TimeOut/) {
                        $contents[ $i + 3 ] = "\t\t\tTimeOut $timeout";
                        &zenlog("Modified current timeout", "info", "LSLB");
                    }

                    if ($contents[ $i + 4 ] =~ /^\s*Priority/) {
                        $contents[ $i + 4 ] = "\t\t\tPriority $weight";
                        splice @contents, $i + 4, 1, if ($priority == 2);
                        &zenlog("Modified current priority", "info", "LSLB");
                        $p_m = 1;
                    }

                    if ($contents[ $i + 3 ] =~ /^\s*Priority/) {
                        $contents[ $i + 3 ] = "\t\t\tPriority $weight";
                        splice @contents, $i + 3, 1, if ($priority == 2);
                        $p_m = 1;
                    }

                    #delete item
                    if (!defined $timeout || $timeout =~ /^$/) {
                        if ($contents[ $i + 3 ] =~ /^\s*TimeOut/) {
                            splice @contents, $i + 3, 1,;
                        }
                    }

                    if (!defined $weight || $weight =~ /^$/) {
                        if ($contents[ $i + 3 ] =~ /^\s*Priority/) {
                            splice @contents, $i + 3, 1,;
                        }
                        if ($contents[ $i + 4 ] =~ /^\s*Priority/) {
                            splice @contents, $i + 4, 1,;
                        }
                    }

                    #new item
                    if (   defined $timeout
                        && $timeout !~ /^$/
                        && ($contents[ $i + 3 ] =~ /^\s*End/ || $contents[ $i + 3 ] =~ /^\s*Priority/))
                    {
                        splice @contents, $i + 3, 0, "\t\t\tTimeOut $timeout";
                    }

                    if (   defined $weight
                        && $p_m eq 0
                        && $weight !~ /^$/
                        && ($contents[ $i + 3 ] =~ /^\s*End/ || $contents[ $i + 4 ] =~ /^\s*End/))
                    {
                        if ($contents[ $i + 3 ] =~ /^\s*TimeOut/) {
                            splice @contents, $i + 4, 0, "\t\t\tPriority $weight" if ($priority == 1);
                        }
                        else {
                            splice @contents, $i + 3, 0, "\t\t\tPriority $weight" if ($priority == 1);
                        }
                    }
                }
            }
        }
    }
    else {
        #add new server
        my $nsflag     = "true";
        my $index      = -1;
        my $backend    = 0;
        my $be_section = -1;

        for my $line (@contents) {
            $index++;

            if ($be_section == 1 && $line =~ /^\s*Address/) {
                $backend++;
            }

            if ($line =~ /^\s*Service \"$service\"/ && $be_section == -1) {
                $be_section++;
            }

            if ($line =~ /^\s*#BackEnd/ && $be_section == 0) {
                $be_section++;
            }

            if ($be_section == 1 && $line =~ /^\s*#End/) {
                if ($priority == 1) {
                    splice @contents, $index, 0, "\t\tBackEnd";
                }
                else {
                    splice @contents, $index, 0, "\t\tEmergency";
                }

                $output = 0;
                $index++;

                splice @contents, $index, 0, "\t\t\tAddress $rip";
                my $httpsbe = &getHTTPFarmVS($farm_name, $service, "httpsbackend");

                if ($httpsbe eq "true") {
                    #add item
                    splice @contents, $index, 0, "\t\t\tHTTPS";
                    $index++;
                }

                $index++;
                splice @contents, $index, 0, "\t\t\tPort $port";
                $index++;

                #Timeout?
                if ($timeout) {
                    splice @contents, $index, 0, "\t\t\tTimeOut $timeout";
                    $index++;
                }

                #Priority?
                if ($weight && ($priority == 1)) {
                    splice @contents, $index, 0, "\t\t\tPriority $weight";
                    $index++;
                }

                splice @contents, $index, 0, "\t\tEnd";
                $be_section++;    # Backend Added
            }

            # if backend added then go out of form
        }

        if ($nsflag eq "true") {
            my $idservice = &getFarmVSI($farm_name, $service);

            if ($idservice ne "") {
                &setHTTPFarmBackendStatusFile($farm_name, $backend, "active", $idservice);
            }
        }
    }

    untie @contents;
    close $lock_fh;

    return $output;
}

=pod

=head1 runHTTPFarmServerDelete

Delete a backend in a HTTP service

Parameters:

    ids       - backend id to delete it
    farm_name - Farm name
    service   - service name where is the backend

Returns:

    Integer - return 0 on success or -1 on failure

=cut

sub runHTTPFarmServerDelete ($ids, $farm_name, $service) {
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = -1;
    my $i             = -1;
    my $j             = -1;
    my $sw            = 0;
    my $dec_mark;
    my $farm_ref = getFarmStruct($farm_name);

    require Relianoid::Lock;
    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @contents, 'Tie::File', "$configdir\/$farm_filename";

    for my $line (@contents) {
        $i++;

        if ($line =~ /^\s*Service \"$service\"/) {
            $sw = 1;
        }

        if ($line =~ /^\s*(BackEnd|Emergency)/ && $sw) {
            $j++;

            if ($j == $ids) {
                splice @contents, $i, 1,;
                $output = 0;

                while ($contents[$i] !~ /^\s*End/) {
                    splice @contents, $i, 1,;
                }

                splice @contents, $i, 1,;
            }
        }
    }
    untie @contents;

    close $lock_fh;

    if ($output != -1) {
        &runRemoveHTTPBackendStatus($farm_name, $ids, $service);
    }

    return $output;
}

=pod

=head1 getHTTPFarmBackendStatusCtl

Get status of a HTTP farm and its backends, sessions can be not included

Parameters:

    farm_name - Farm name
    sessions  - "true" show sessions info. "false" sessions are not shown.

Returns:

    array - return the output of proxyctl command for a farm

=cut

sub getHTTPFarmBackendStatusCtl ($farm_name, $sessions = undef) {
    my $proxyctl = &getGlobalConfiguration('proxyctl');

    my $sessions_option = "-C";
    if (defined $sessions and $sessions = "true") {
        $sessions_option = "";
    }
    return @{ &logAndGet("$proxyctl $sessions_option -c /tmp/$farm_name\_proxy.socket", "array") };
}

=pod

=head1 getHTTPFarmBackends

Return a list with all backends in a service and theirs configuration

Parameters:

    farmname     - Farm name
    service      - Service name
    param_status - "true" or "false" to indicate to get backend status.

Returns:

    array ref - Each element in the array it is a hash ref to a backend.
                the array index is the backend id

=cut

sub getHTTPFarmBackends ($farmname, $service, $param_status = undef) {
    require Relianoid::Farm::HTTP::Service;

    my $backendsvs = &getHTTPFarmVS($farmname, $service, "backends");

    my @be = split("\n", $backendsvs);
    my @be_status;
    my @out_ba;
    my $backend_ref;

    if (not $param_status or $param_status eq "true") {
        @be_status = @{ &getHTTPFarmBackendsStatus($farmname, $service) };
    }

    for my $subl (@be) {
        my @subbe = split(' ', $subl);
        my $id    = $subbe[1] + 0;

        my $ip   = $subbe[3];
        my $port = $subbe[5] + 0;
        my $tout = $subbe[7];
        my $prio = $subbe[9];
        my $weig = $subbe[11];

        $tout = $tout eq '-' ? undef : $tout + 0;
        $prio = $prio eq '-' ? undef : $prio + 0;
        $weig = $weig eq '-' ? undef : $weig + 0;

        my $status = "undefined";
        if (not $param_status or $param_status eq "true") {
            $status = $be_status[$id] if $be_status[$id];
        }

        $backend_ref = {
            id       => $id,
            ip       => $ip,
            port     => $port + 0,
            timeout  => $tout,
            weight   => $prio,
            priority => $weig,
        };

        if (not $param_status or $param_status eq "true") {
            $backend_ref->{status} = $status;
        }

        push @out_ba, $backend_ref;
        $backend_ref = undef;
    }

    return \@out_ba;
}

=pod

=head1 getHTTPFarmBackendsStatus

Get the status of all backends in a service. The possible values are:

    up         - The farm is in up status and the backend is OK.
    down       - The farm is in up status and the backend is unreachable
    maintenace - The backend is in maintenance mode.
    undefined  - The farm is in down status and backend is not in maintenance mode.

Parameters:

    farm_name - Farm name
    service - Service name

Returns:

    Array ref - the index is backend index, the value is the backend status

=cut

#ecm possible bug here returns 2 values instead of 1 (1 backend only)
sub getHTTPFarmBackendsStatus ($farm_name, $service) {
    require Relianoid::Farm::Base;

    my @status;
    my $farmStatus = &getFarmStatus($farm_name);
    my $stats;

    if ($farmStatus eq "up") {
        require Relianoid::Farm::HTTP::Backend;
        $stats = &getHTTPFarmBackendsStatusInfo($farm_name);
    }

    require Relianoid::Farm::HTTP::Service;

    my $backendsvs = &getHTTPFarmVS($farm_name, $service, "backends");
    my @be         = split("\n", $backendsvs);
    my $id         = 0;

    # @be is used to get size of backend array
    for (@be) {
        my $backendstatus = &getHTTPBackendStatusFromFile($farm_name, $id, $service);
        if ($backendstatus ne "maintenance") {
            if ($farmStatus eq "up") {
                $backendstatus = $stats->{$service}{backends}[$id]->{status};
            }
            else {
                $backendstatus = "undefined";
            }
        }
        push @status, $backendstatus;
        $id = $id + 1;
    }

    return \@status;
}

=pod

=head1 setHTTPFarmBackendStatus

Set backend status for an http farm and stops traffic to that backend when needed.

Parameters:

    farm_name          - Farm name
    service            - Service name
    backend_index      - Backend index
    status             - Backend status. The possible values are: "up", "maintenance" or "fgDOWN".
    cutmode            - "cut" to remove sessions for such backend
    backends_info_ref  - array ref including status and prio of all backends of the service.

Returns:

    hash reference

    $error_ref->{code}

        0 on success
        1 on failure changing status,
        2 on failure removing sessions.

    $error_ref->{desc} - error message.

=cut

sub setHTTPFarmBackendStatus ($farm_name, $service, $backend_index, $status, $cutmode, $backends_info_ref = undef) {
    require Relianoid::Farm::HTTP::Service;
    require Relianoid::Farm::HTTP::Config;

    my $socket_file       = &getHTTPFarmSocket($farm_name);
    my $service_id        = &getFarmVSI($farm_name, $service);
    my $error_ref->{code} = -1;
    my $output;

    $cutmode = "" if &getHTTPFarmVS($farm_name, $service, "sesstype") eq "";

    my $proxyctl = &getGlobalConfiguration('proxyctl');
    if ($status eq 'maintenance' or $status eq 'fgDOWN') {
        $output = &logAndRun("$proxyctl -c $socket_file -b 0 $service_id $backend_index");
        if ($output) {
            my $msg = "Backend '$backend_index' in service '$service' of farm '$farm_name' cannot be disabled";
            $error_ref->{code} = 1;
            $error_ref->{desc} = $msg;
            return $error_ref;
        }
        else {
            $error_ref->{code} = 0;
        }
        &setHTTPFarmBackendStatusFile($farm_name, $backend_index, $status, $service_id);
        if ($cutmode eq 'cut') {
            $output = &setHTTPFarmBackendsSessionsRemove($farm_name, $service, $backend_index);
            if ($output) {
                my $msg = "Sessions for backend '$backend_index' in service '$service' of farm '$farm_name' were not deleted.";
                &zenlog($msg, "error", "LSLB");
                $error_ref->{code} = 2;
                $error_ref->{desc} = $msg;
                return $error_ref;
            }
        }
    }
    elsif ($status eq 'up') {
        $output = &logAndRun("$proxyctl -c $socket_file -B 0 $service_id $backend_index");
        if ($output) {
            my $msg = "Backend '$backend_index' in service '$service' of farm '$farm_name' cannot be enabled";
            $error_ref->{code} = 1;
            $error_ref->{desc} = $msg;
            return $error_ref;
        }
        else {
            $error_ref->{code} = 0;
        }
        &setHTTPFarmBackendStatusFile($farm_name, $backend_index, 'active', $service_id);
    }

    return $error_ref;
}

=pod

=head1 getHTTPBackendStatusFromFile

Function that return if a l7 proxy backend is active, down by farmguardian or it's in maintenance mode

Parameters:

    farm_name - Farm name
    backend  - backend id
    service  - service name

Returns:

    scalar - return backend status: "maintentance", "fgDOWN", "active" or -1 on failure

=cut

sub getHTTPBackendStatusFromFile ($farm_name, $backend, $service) {
    require Relianoid::Farm::HTTP::Service;

    my $index;
    my $stfile = "$configdir\/$farm_name\_status.cfg";

    # if the status file does not exist the backend is ok
    my $output = "active";

    if (!-e $stfile) {
        return $output;
    }

    $index = &getFarmVSI($farm_name, $service);

    if (open(my $fh, '<', $stfile)) {
        my @lines = <$fh>;
        close $fh;

        for my $line (@lines) {
            #service index
            if ($line =~ /\ 0\ ${index}\ ${backend}/) {
                if ($line =~ /maintenance/) {
                    $output = "maintenance";
                }
                elsif ($line =~ /fgDOWN/) {
                    $output = "fgDOWN";
                }
                else {
                    $output = "active";
                }
            }
        }
    }

    return $output;
}

=pod

=head1 setHTTPFarmBackendStatusFile

Function that save in a file the backend status (maintenance or not)

Parameters:

    farm_name   - Farm name
    backend     - Backend id
    status      - backend status to save in the status file
    idsv        - Service id

Returns: Nothing

FIXME:

    Not return anything, do error control

=cut

sub setHTTPFarmBackendStatusFile ($farm_name, $backend, $status, $idsv) {
    require Tie::File;

    my $statusfile = "${configdir}/${farm_name}_status.cfg";
    my $changed    = "false";

    unless (-e $statusfile) {
        my $proxyctl = &getGlobalConfiguration('proxyctl');
        my @run      = @{ &logAndGet("${proxyctl} -C -c /tmp/${farm_name}_proxy.socket", "array") };
        my @sw;
        my @bw;
        my @statusfile_ln;

        for my $line (@run) {
            if ($line =~ /\.\ Service\ /) {
                @sw = split("\ ", $line);
                $sw[0] =~ s/\.//g;
                chomp $sw[0];
            }
            if ($line =~ /\.\ Backend\ /) {
                @bw = split("\ ", $line);
                $bw[0] =~ s/\.//g;
                chomp $bw[0];
                if ($bw[3] eq "active") {
                    #~ print FW "-B 0 $sw[0] $bw[0] active\n";
                }
                else {
                    push(@statusfile_ln, "-b 0 $sw[0] $bw[0] fgDOWN\n");
                }
            }
        }

        open my $fh, '>', $statusfile;
        print $fh join("\n", @statusfile_ln);
        close $fh;
    }

    tie my @filelines, 'Tie::File', "$statusfile";
    my $i = 0;

    for my $linea (@filelines) {
        if ($linea =~ / 0 ${idsv} ${backend}/) {
            if ($status =~ /maintenance/ || $status =~ /fgDOWN/) {
                $linea   = "-b 0 ${idsv} $backend $status";
                $changed = "true";
            }
            else {
                splice(@filelines, $i, 1);
                $changed = "true";
            }
        }
        $i++;
    }

    untie @filelines;

    if ($changed eq "false") {
        open(my $fh, '>>', $statusfile);

        if ($status =~ /maintenance/ || $status =~ /fgDOWN/) {
            print {$fh} "-b 0 ${idsv} $backend $status\n";
        }

        close $fh;
    }

    return;
}

=pod

=head1 setHTTPFarmBackendMaintenance

Function that enable the maintenance mode for backend

Parameters:

    farm_name - Farm name
    backend   - Backend id
    mode      - Maintenance mode, the options are:
                - drain, the backend continues working with the established connections
                - cut, the backend cuts all the established connections
    service   - Service name

Returns:

    Integer - return 0 on success or -1 on failure

=cut

sub setHTTPFarmBackendMaintenance ($farm_name, $backend, $mode, $service) {
    my $output = 0;

    &zenlog("setting Maintenance mode for $farm_name service $service backend $backend", "info", "LSLB");

    if (&getFarmStatus($farm_name) eq 'up') {
        $output = &setHTTPFarmBackendStatus($farm_name, $service, $backend, 'maintenance', $mode);
    }

    return $output;
}

=pod

=head1 setHTTPFarmBackendNoMaintenance

Function that disable the maintenance mode for backend

Parameters:

    farm_name - Farm name
    backend   - Backend id
    service   - Service name

Returns:

    Integer - return 0 on success or -1 on failure

=cut

sub setHTTPFarmBackendNoMaintenance ($farm_name, $backend, $service) {
    my $output = 0;

    &zenlog("setting Disabled maintenance mode for $farm_name service $service backend $backend", "info", "LSLB");

    if (&getFarmStatus($farm_name) eq 'up') {
        $output = &setHTTPFarmBackendStatus($farm_name, $service, $backend, 'up', 'cut');
    }

    return $output;
}

=pod

=head1 runRemoveHTTPBackendStatus

Function that removes a backend from the status file

Parameters:

    farm_name - Farm name
    backend   - Backend id
    service   - Service name

Returns:

    none

FIXME:

    This function returns nothing, do error control

=cut

sub runRemoveHTTPBackendStatus ($farm_name, $backend, $service) {
    require Tie::File;

    my $i          = -1;
    my $serv_index = &getFarmVSI($farm_name, $service);

    tie my @contents, 'Tie::File', "$configdir\/$farm_name\_status.cfg";

    for my $line (@contents) {
        $i++;
        if ($line =~ /0\ ${serv_index}\ ${backend}/) {
            splice @contents, $i, 1,;
            last;
        }
    }
    untie @contents;

    # decrease backend index in greater backend ids
    tie my @filelines, 'Tie::File', "$configdir\/$farm_name\_status.cfg";

    for my $line (@filelines) {
        if ($line =~ /0\ ${serv_index}\ (\d+) (\w+)/) {
            my $backend_index = $1;
            my $status        = $2;
            if ($backend_index > $backend) {
                $backend_index = $backend_index - 1;
                $line          = "-b 0 $serv_index $backend_index $status";
            }
        }
    }
    untie @filelines;

    return;
}

=pod

=head1 setHTTPFarmBackendStatusFromFile

For a HTTP farm, it gets each backend status from status file and set it in ly proxy daemon

Parameters:

    farmname - Farm name

Returns:

    none

FIXME:

    This function returns nothing, do error control

=cut

sub setHTTPFarmBackendStatusFromFile ($farm_name) {
    &zenlog("Setting backends status in farm $farm_name", "info", "LSLB");

    my $be_status_filename = "$configdir\/$farm_name\_status.cfg";
    my $proxyctl           = &getGlobalConfiguration('proxyctl');

    unless (-f $be_status_filename) {
        open my $fh, ">", $be_status_filename;
        close $fh;
        return;
    }

    if (open(my $fh, "<", $be_status_filename)) {
        my @lines = <$fh>;
        close $fh;

        for my $line_aux (@lines) {
            my @line = split("\ ", $line_aux);
            &logAndRun("$proxyctl -c /tmp/$farm_name\_proxy.socket $line[0] $line[1] $line[2] $line[3]");
        }
    }
    else {
        my $msg = "Error opening $be_status_filename: $!. Aborting execution.";
        &zenlog($msg, "error", "LSLB");
        die $msg;
    }

    return;
}

=pod

=head1 setHTTPFarmBackendsSessionsRemove

Remove all the active sessions enabled to a backend in a given service
Used by farmguardian

Parameters:

    farm_name - Farm name
    service   - Service name
    backendid - Backend id

Returns:

    Integer - Error code: It returns 0 on success or another value if it fails deleting some sessions

=cut

sub setHTTPFarmBackendsSessionsRemove ($farm_name, $service, $backendid) {
    my $serviceid;
    my $err = 0;

    &zenlog("Deleting established sessions to a backend $backendid from farm $farm_name in service $service",
        "info", "LSLB");

    $serviceid = &getFarmVSI($farm_name, $service);

    my $proxyctl = &getGlobalConfiguration('proxyctl');
    my $cmd      = "$proxyctl -c /tmp/$farm_name\_proxy.socket -f 0 $serviceid $backendid";
    $err = &logAndRun($cmd);

    return $err;
}

sub getHTTPFarmBackendAvailableID ($farmname, $service) {
    require Relianoid::Farm::HTTP::Service;

    # get an ID for the new backend
    my $backendsvs = &getHTTPFarmVS($farmname, $service, "backends");
    my @be         = split("\n", $backendsvs);
    my $id         = 0;

    for my $subl (@be) {
        my @subbe = split(' ', $subl);
        $id = $subbe[1] + 1;
    }

    if (defined $id && $id eq '') {
        $id = 0;
    }

    return $id;
}

=pod

=head1 getHTTPFarmBackendsStatusInfo

This function take data from proxy and it gives hash format

Parameters:

    farm_name - Farm name

Returns:

    hash ref - hash with backends farm status

    services => [
        "id" => $service_id,            # index in the service array
        "name" => $service_name,
        "backends" => [
            {
                "id" = $backend_id      # index in the backend array
                "ip" = $backend_ip
                "port" = $backend_port
                "status" = $backend_status
                "service" = $service_name
            }
        ]
    ]

=cut

sub getHTTPFarmBackendsStatusInfo ($farm_name) {
    require Relianoid::Farm::Base;
    require Relianoid::Farm::HTTP::Backend;
    require Relianoid::Validate;
    my $status = {};

    my $serviceName;
    my $service_re = &getValidFormat('service');

    # Get l7 proxy info
    #i.e. of proxyctl:

    #Requests in queue: 0
    #0. http Listener 185.76.64.223:80 a
    #0. Service "HTTP" active (4)
    #0. Backend 172.16.110.13:80 active (1 0.780 sec) alive (61)
    #1. Backend 172.16.110.14:80 active (1 0.878 sec) alive (90)
    #2. Backend 172.16.110.11:80 active (1 0.852 sec) alive (99)
    #3. Backend 172.16.110.12:80 active (1 0.826 sec) alive (75)
    my @proxyctl = &getHTTPFarmBackendStatusCtl($farm_name);

    # Parse l7 proxy info
    for my $line (@proxyctl) {
        # i.e.
        #     0. Service "HTTP" active (10)
        if ($line =~ /(\d+)\. Service "($service_re)"/) {
            $serviceName = $2;
        }

        # Parse backend connections
        # i.e.
        #      0. Backend 192.168.100.254:80 active (5 0.000 sec) alive (0)
        if ($line =~ /(\d+)\. Backend (\d+\.\d+\.\d+\.\d+|[a-fA-F0-9:]+):(\d+) (\w+) .+ (\w+)(?: \((\d+)\))?/) {
            my $backendHash = {
                id     => $1 + 0,
                ip     => $2,
                port   => $3 + 0,
                status => $5,
            };

            # Getting real status
            my $backend_disabled = $4;
            if ($backend_disabled eq "DISABLED") {
                require Relianoid::Farm::HTTP::Backend;

                #Checkstatusfile
                $backendHash->{status} = &getHTTPBackendStatusFromFile($farm_name, $backendHash->{id}, $serviceName);

                # not show fgDOWN status
                $backendHash->{status} = "down" if ($backendHash->{status} ne "maintenance");
            }
            elsif ($backendHash->{status} eq "alive") {
                $backendHash->{status} = "up";
            }
            elsif ($backendHash->{status} eq "DEAD") {
                $backendHash->{status} = "down";
            }

            push(@{ $status->{$serviceName}{backends} }, $backendHash);
        }
    }

    return $status;
}

1;
