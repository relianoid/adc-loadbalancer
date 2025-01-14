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

use Relianoid::Config;
use Relianoid::Farm::Core;

my $configdir = &getGlobalConfiguration('configdir');
my $eload     = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::Farm::Base

=cut

=pod

=head1 getFarmVip

Returns farm vip or farm port

Parameters:

    tag - requested parameter. The options are 
          - "vip" for virtual ip
          - "vipp" for virtual port

    farmname - Farm name

Returns:

    Scalar - return vip or port of farm or -1 on failure

See Also:

    setFarmVirtualConf

=cut

sub getFarmVip ($info, $farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;
        $output = &getHTTPFarmVip($info, $farm_name);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Config;
        $output = &getL4FarmParam($info, $farm_name);
    }
    elsif ($farm_type eq "datalink" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Config',
            func   => 'getDatalinkFarmVip',
            args   => [ $info, $farm_name ],
        );
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Config',
            func   => 'getGSLBFarmVip',
            args   => [ $info, $farm_name ],
        );
    }
    elsif ($farm_type eq "eproxy" && $eload) {
        my $farm = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Config',
            func   => 'getEproxyFarmStruct',
            args   => [{ farm_name => $farm_name }],
        );
        $output = $farm->{vip} if ($info eq "vip");
        $output = $farm->{vport} if ($info eq "vipp");
    }

    return $output;
}

=pod

=head1 getFarmStatus

Return farm status checking if pid file exists

Parameters:

    farmname - Farm name

Returns:

    String - "down", "up" or -1 on failure

NOTE:

    Generic function

=cut

sub getFarmStatus ($farm_name) {
    my $output = -1;
    return $output if !defined($farm_name);

    my $farm_type = &getFarmType($farm_name);

    if ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Config;
        return &getL4FarmStatus($farm_name);
    }
    elsif ($farm_type =~ /http/) {
        require Relianoid::Farm::HTTP::Config;
        return &getHTTPFarmStatus($farm_name);
    }
    elsif ($farm_type eq "datalink" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Config',
            func   => 'getDatalinkFarmStatus',
            args   => [$farm_name],
        );
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Config',
            func   => 'getGSLBFarmStatus',
            args   => [$farm_name],
        );
    }
    elsif ($farm_type eq "eproxy" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Action',
            func   => 'getEproxyFarmStatus',
            args   => [{ farm_name => $farm_name }],
        );
    }

    return $output;
}

=pod

=head1 getFarmVipStatus

Return a vip status

Parameters:

    farmname - Farm name

Returns:

    String - "needed restart", "critical", "problem", "maintenance", "up", "down" or -1 on failure

    up

        The farm is up and all the backends are working success.

    down

        The farm is not running

    needed restart

        The farm is up but it is pending of a restart action

    critical

        The farm is up and all backends are unreachable or maintenance

    problem

        The farm is up and there are some backend unreachable, 
        but almost a backend is in up status

    maintenance

        The farm is up and there are backends in up status, 
        but almost a backend is in maintenance mode.

NOTE:

    Generic function

=cut

sub getFarmVipStatus ($farm_name) {
    my $output     = -1;
    my $farmStatus = &getFarmStatus($farm_name);
    return $output if !defined($farm_name);

    $output = "problem";

    require Relianoid::Farm::Action;

    if ($farmStatus eq "down") {
        return "down";
    }
    elsif (&getFarmRestartStatus($farm_name)) {
        return "needed restart";
    }
    elsif ($farmStatus ne "up") {
        return -1;
    }

    # types: "http", "https", "datalink", "l4xnat", "gslb", "eproxy" or 1
    my $type = &getFarmType($farm_name);

    my $backends;
    my $up_flag = 0;
    my $down_flag = 0;
    my $maintenance_flag = 0;

    require Relianoid::Farm::Backend;

    # HTTP, optimized for many services
    if ($type =~ /http/) {
        require Relianoid::Farm::HTTP::Backend;
        my $status = &getHTTPFarmBackendsStatusInfo($farm_name);

        for my $service (keys %{$status}) {
            next unless defined $status->{$service}{backends};

            for my $backend (@{ $status->{$service}{backends} }) {
                push @{$backends}, $backend;
            }
        }
    }

    elsif ($type eq "gslb" && $eload) {
        my $stats = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Stats',
            func   => 'getGSLBFarmBackendsStats',
            args   => [$farm_name],
        );
        $backends = $stats->{backends};
    }

    elsif ($type eq "eproxy" && $eload) {
        $backends = &eload(
           module => 'Relianoid::EE::Farm::Eproxy::Backend',
           func   => 'getEproxyFarmBackends',
           args   => [ { farm_name => $farm_name } ],
        );
    }

    else {
        $backends = &getFarmServers($farm_name);
    }

    # checking status
    for my $be (@{$backends}) {
        $up_flag          = 1 if grep { $be->{status} eq $_ } qw(up undefined);
        $maintenance_flag = 1 if grep { $be->{status} eq $_ } qw(maintenance);
        $down_flag        = 1 if grep { $be->{status} eq $_ } qw(down fgDOWN);

        # if there is a backend up and another down, the status is 'problem'
        last if ($down_flag and $up_flag);
    }

    # check if redirect exists when there are not backends
    if ($type =~ /http/) {
        require Relianoid::Farm::HTTP::Service;
        for my $srv (&getHTTPFarmServices($farm_name)) {
            if (&getHTTPFarmVS($farm_name, $srv, 'redirect')) {
                $up_flag = 1;
                last;
            }
        }
    }

    if (!$up_flag) {
        $output = "critical";
    }
    elsif ($down_flag) {
        $output = "problem";
    }
    elsif ($maintenance_flag) {
        $output = "maintenance";
    }
    else {
        $output = "up";
    }

    return $output;
}

=pod

=head1 getFarmPid

Returns farm PID

Parameters:

    farmname - Farm name

Returns:

    Integer - return a list of daemon pids. It can contains more than one value

=cut

sub getFarmPid ($farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my @output    = ();

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;

        @output = &getHTTPFarmPidPound($farm_name);
    }
    elsif ($farm_type eq "gslb" && $eload) {
        my $pid = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Config',
            func   => 'getGSLBFarmPid',
            args   => [$farm_name],
        );
        push(@output, $pid) if $pid;
    }

    return @output;
}

=pod

=head1 getFarmBootStatus

Return the farm status at boot relianoid

Parameters:

    farmname - Farm name

Returns:

    scalar - return "down" if the farm not run at boot or "up" if the farm run at boot

=cut

sub getFarmBootStatus ($farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = "down";

    if ($farm_type =~ /http/) {
        require Relianoid::Farm::HTTP::Config;
        $output = &getHTTPFarmBootStatus($farm_name);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Config;
        $output = &getL4FarmParam('bootstatus', $farm_name);
    }
    elsif ($farm_type eq "datalink" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Config',
            func   => 'getDatalinkFarmBootStatus',
            args   => [$farm_name],
        );
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Config',
            func   => 'getGSLBFarmBootStatus',
            args   => [$farm_name],
        );
    }
    elsif ($farm_type eq "eproxy" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::Eproxy::Config',
            func   => 'getEproxyFarmBootStatus',
            args   => [{ farm_name => $farm_name }],
        );
    }

    return $output;
}

=pod

=head1 getFarmProto

Return basic transport protocol used by the farm protocol

Parameters:

    farmname - Farm name

Returns:

    String - "udp" or "tcp"

BUG:

    Gslb works with tcp protocol too

FIXME:

    Use getL4ProtocolTransportLayer to get l4xnat protocol

=cut

sub getFarmProto ($farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    if ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Config;
        $output = &getL4FarmParam('proto', $farm_name);
    }
    elsif ($farm_type =~ /http/i) {
        $output = "tcp";
    }
    elsif ($farm_type eq "gslb") {
        $output = "all";
    }

    return $output;
}

=pod

=head1 getNumberOfFarmTypeRunning

    Counter how many farms exists in a farm profile.

Parameters:

    type - Farm profile: "http", "l4xnat", "gslb" or "datalink"

Returns:

    integer- Number of farms

=cut

sub getNumberOfFarmTypeRunning ($type) {
    my $counter = 0;

    for my $farm_name (&getFarmNameList()) {
        # count if requested farm type and running
        my $current_type = &getFarmType($farm_name);

        if ($current_type eq $type) {
            my $current_status = &getFarmStatus($farm_name);

            if ($current_status eq 'up') {
                $counter++;
            }
        }
    }

    return $counter;
}

=pod

=head1 getFarmListByVip

Returns a list of farms that have the same IP address.

Parameters:

    ip   - ip address
    port - virtual port. This parameter is optional

Returns:

    Array - List of farm names

=cut

sub getFarmListByVip ($ip, $port = undef) {
    require Relianoid::Net::Validate;

    my @out = ();

    for my $farm (&getFarmNameList()) {
        if (&getFarmVip('vip', $farm) eq $ip) {
            next if defined $port && !grep { $port eq $_ } @{ &getMultiporExpanded(&getFarmVip('vipp', $farm)) };
            push @out, $farm;
        }
    }

    return @out;
}

=pod

=head1 getFarmRunning

Returns the farms are currently running in the system.

Parameters:

    none

Returns:

    Array - List of farm names

=cut

sub getFarmRunning() {
    my @out = ();

    for my $farm (&getFarmNameList()) {
        if (&getFarmStatus($farm) eq 'up') {
            push @out, $farm;
        }
    }
    return @out;
}

1;

