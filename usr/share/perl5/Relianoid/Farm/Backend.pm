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

use Carp;
use Relianoid::Farm::Backend::Maintenance;

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::Farm::Backend

=cut

=pod

=head1 getFarmServerIds

It returns a list with the backend servers for a farm and service.
The backends are read from the config file.
This function is to not use the getFarmservers that does stats checks.

Parameters:

    farm_name - Farm name
    service - service backends related (optional)

Returns:

    array ref - list of backends IDs

=cut

sub getFarmServerIds ($farm_name, $service) {
    my @servers   = ();
    my $farm_type = &getFarmType($farm_name);

    if ($farm_type =~ /http/) {
        require Relianoid::Farm::HTTP::Service;
        my $backendsvs = &getHTTPFarmVS($farm_name, $service, "backends");
        @servers = split("\n", $backendsvs);
        @servers = 0 .. $#servers if (@servers);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Backend;
        @servers = @{ &getL4FarmServers($farm_name) };
        @servers = 0 .. $#servers if (@servers);
    }
    elsif ($farm_type eq "datalink") {
        my $configdir     = &getGlobalConfiguration('configdir');
        my $farm_filename = &getFarmFile($farm_name);
        open my $fh, '<', "$configdir/$farm_filename";
        {
            while (my $line = <$fh>) {
                push @servers, $line if ($line =~ /^;server;/);
            }
            close $fh;
        }
        @servers = 0 .. $#servers if (@servers);
    }
    elsif ($farm_type eq "gslb" && $eload) {
        my $backendsvs = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Service',
            func   => 'getGSLBFarmVS',
            args   => [ $farm_name, $service, "backends" ],
        );
        my @be = split("\n", $backendsvs);
        my $id;
        for my $b (@be) {
            $b =~ s/^\s+//;
            next if ($b =~ /^$/);

            # ID and IP
            my @subbe = split(" => ", $b);
            $id = $subbe[0];
            $id =~ s/^primary$/1/;
            $id =~ s/^secondary$/2/;
            $id += 0;
            push @servers, $id;
        }
    }

    return \@servers;
}

=pod

=head1 getFarmServers

List all farm backends and theirs configuration

Parameters:

    farm_name - Farm name
    service - service backends related (optional)

Returns:

    array ref - list of backends

FIXME:

    changes output to hash format

=cut

sub getFarmServers ($farm_name, $service = undef) {
    my $farm_type = &getFarmType($farm_name);
    my $servers;

    if ($farm_type =~ /http/) {
        require Relianoid::Farm::HTTP::Backend;
        $servers = &getHTTPFarmBackends($farm_name, $service);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Backend;
        $servers = &getL4FarmServers($farm_name);
    }
    elsif ($farm_type eq "datalink" && $eload) {
        $servers = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Backend',
            func   => 'getDatalinkFarmBackends',
            args   => [$farm_name],
        );
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $servers = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Backend',
            func   => 'getGSLBFarmBackends',
            args   => [ $farm_name, $service ],
        );
    }

    return $servers;
}

=pod

=head1 getFarmServer

Return the backend with the specified value on the specified parameter.

Parameters:

    backends_ref - Array ref of backends hashes.
    value - Parameter value to match
    param - Parameter to match. Default value "id"

Returns:

    hash ref - bachend hash reference or undef if there aren't backends

=cut

sub getFarmServer ($bcks_ref, $value, $param = "id") {
    for my $server (@{$bcks_ref}) {
        # preserve type param number
        if ($param eq "id") {
            return $server if ($server->{$param} == $value);
        }
        else {
            return $server if ($server->{$param} eq "$value");
        }
    }

    # Error, not found so return undef
    return;
}

=pod

=head1 setFarmServer

Add a new Backend

Parameters:

    farm_name -  Farm name
    service   -  Optional. service name. For HTTP farms
    ids       -  Backend id, if this id doesn't exist, it will create a new backend
    bk        -  hash with backend configuration. 
                 Depend on the type of farms, the backend can have the following keys:
                 ip, port, weight, priority, timeout, max_conns or interface

Returns:

    Scalar - Error code: undef on success or -1 on error

=cut

sub setFarmServer ($farm_name, $service, $ids, $bk) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    my $attrs_msg = sprintf(
        'Server %s ip:%s port:%u max:%u weight:%u prio:%u timeout:%u',
        $ids             // '', $bk->{ip},
        $bk->{port}      // 0,
        $bk->{max_conns} // 0,
        $bk->{weight}    // 0,
        $bk->{priority}  // 0,
        $bk->{timeout}   // 0
    );
    my $msg = sprintf("setting '$attrs_msg' for %s farm, %s service of type %s", $farm_name, $service // 'no', $farm_type);
    &log_info($msg, "FARMS");

    if ($farm_type eq "datalink" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Backend',
            func   => 'setDatalinkFarmServer',
            args   => [ $ids, $bk->{ip}, $bk->{interface}, $bk->{weight}, $bk->{priority}, $farm_name ],
        );
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Backend;
        $output = &setL4FarmServer(
            $farm_name, $ids, $bk->{ip},
            $bk->{port}      // "",
            $bk->{weight}    // 1,
            $bk->{priority}  // 1,
            $bk->{max_conns} // 0
        );
    }
    elsif ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Backend;
        $output = &setHTTPFarmServer(
            $ids,           $bk->{ip},  $bk->{port}, $bk->{weight},    #
            $bk->{timeout}, $farm_name, $service,    $bk->{priority}
        );
    }

    # FIXME: include setGSLBFarmNewBackend
    return $output;
}

=pod

=head1 runFarmServerDelete

Delete a Backend

Parameters:

    ids       - Backend id, if this id doesn't exist, it will create a new backend
    farm_name - Farm name
    service   - service name. For HTTP farms

Returns:

    Scalar - Error code: undef on success or -1 on error

=cut

sub runFarmServerDelete ($ids, $farm_name, $service = undef) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    &log_info("running 'ServerDelete $ids' for $farm_name farm $farm_type", "FARMS");

    if ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Backend;
        $output = &runL4FarmServerDelete($ids, $farm_name);
    }
    elsif ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Backend;
        $output = &runHTTPFarmServerDelete($ids, $farm_name, $service);
    }
    elsif ($farm_type eq "datalink" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Backend',
            func   => 'runDatalinkFarmServerDelete',
            args   => [ $ids, $farm_name ],
        );
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Backend',
            func   => 'runGSLBFarmServerDelete',
            args   => [ $ids, $farm_name, $service ],
        );
    }
    elsif ($farm_type eq "eproxy" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Backend',
            func   => 'delEproxyFarmBackend',
            args   => [ { farm_name => $farm_name, service_name => $service, backend_id => $ids } ],
        );
    }

    return $output;
}

=pod

=head1 getFarmBackendAvailableID

Get next available backend ID

Parameters:

    farmname - farm name

Returns:

    integer

=cut

sub getFarmBackendAvailableID ($farmname) {
    my $nbackends;

    if (&getFarmType($farmname) eq 'l4xnat') {
        require Relianoid::Farm::L4xNAT::Backend;
        $nbackends = &getL4FarmBackendAvailableID($farmname);
    }
    else {
        my $backends = &getFarmServers($farmname);
        $nbackends = $#{$backends} + 1;
    }

    return $nbackends;
}

=pod

=head1 setBackendRule

Add or delete the route rule according to the backend mark.

Parameters:

    action    - "add" to create the mark or "del" to remove it.
    farm_ref  - farm reference.
    mark      - backend mark to apply in the rule.
    farm_type - type of farm (l4xnat, http, https).

Returns:

    integer - 0 if successful, otherwise error.

=cut

sub setBackendRule ($action, $farm_ref, $mark, $farm_type = undef) {
    $farm_type //= getFarmType($farm_ref->{name});

    unless ($action eq "add" or $action eq "del") {
        croak("Rule action must be 'add' or 'del'");
    }

    unless (defined $farm_ref) {
        croak("A farm configuration is required");
    }

    unless (length $mark and hex $mark) {
        croak("Invalid mark received");
    }

    require Relianoid::Net::Util;
    require Relianoid::Net::Route;

    my $vip_if_name = &getInterfaceOfIp($farm_ref->{vip});
    my $vip_if      = &getInterfaceConfig($vip_if_name);
    my $table_if =
      ($vip_if->{type} eq 'virtual') ? $vip_if->{parent} : $vip_if->{name};

    my $rule = {
        table  => "table_$table_if",
        type   => $farm_type,
        from   => 'all',
        fwmark => "$mark/0x7fffffff",
    };
    return &setRule($action, $rule);
}

=pod

=head1 getPriorityAlgorithmStatus

Calculates the Priroty algorithm status of the backend list

Parameters:

    $backends_ref - list of backend_ref
    $bk_index     - backend index if defined, only returns this index values. Optional. 

    $backend_ref->{status}   - Status of the backend. Possibles values:"up","down".
    $backend_ref->{priority} - Priority of the backend

Returns:

    $availability_ref - Hash of algorithm values.

Variable:

    $availability_ref->{priority} - algorithm priority.
    $availability_ref->{status}   - Array - list of backend availability.

    If defined parameter $backend_ref->{status}:
    - "true" if the backend is used.
    - "false" if is available to be used.

    If not defined parameter $backend_ref->{status}:
    - "true" if the backend is used or available to be used.
    - "false" if the backend will never be used.

=cut

sub getPriorityAlgorithmStatus ($backends_ref, $bk_index = undef) {
    my $alg_status_ref;
    my $sum_prio_ref;

    for my $bk (@{$backends_ref}) {
        #determine number of backends down for each level of priority
        if (not defined $bk->{status} or $bk->{status} eq "down") {
            $sum_prio_ref->{ $bk->{priority} }++;
        }
    }

    #determine the lowest priority level where backends are being used
    my $current_alg_prio = 1;
    my $alg_prio         = 1;

    while ($current_alg_prio <= $alg_prio) {
        #when the level of priority matches the number of down backends, loop stops
        #and $alg_prio indicates the lowest level of prio being used.
        #else, keep increasing the level of priority checked in the next iteration.
        if (defined $sum_prio_ref->{$current_alg_prio}) {
            $alg_prio += $sum_prio_ref->{$current_alg_prio};
        }
        last if $alg_prio == $current_alg_prio;
        $current_alg_prio++;
    }

    $alg_status_ref->{priority} = $alg_prio;
    $alg_status_ref->{status}   = [];

    if (defined $bk_index) {
        if (@{$backends_ref}[$bk_index]->{priority} <= $alg_prio) {
            push @{ $alg_status_ref->{status} }, "true";
        }
        else {
            push @{ $alg_status_ref->{status} }, "false";
        }
    }
    else {
        for my $bk (@{$backends_ref}) {
            if ($bk->{priority} <= $alg_prio) {
                push @{ $alg_status_ref->{status} }, "true";
            }
            else {
                push @{ $alg_status_ref->{status} }, "false";
            }
        }
    }

    return $alg_status_ref;
}

1;
