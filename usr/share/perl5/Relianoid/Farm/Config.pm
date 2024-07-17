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

Relianoid::Farm::Config

=cut

=pod

=head1 setFarmBlacklistTime

Configure check time for resurected back-end. It is a farm paramter.

Parameters:

    blacklist_time - time for resurrected checks
    farm_name - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setFarmBlacklistTime ($blacklist_time, $farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;
        $output = &setHTTPFarmBlacklistTime($blacklist_time, $farm_name);
    }

    return $output;
}

=pod

=head1 setFarmSessionType

Configure type of persistence

Parameters:

    session  - type of session: nothing, HEADER, URL, COOKIE, PARAM, BASIC or IP, for HTTP farms; none or ip, for l4xnat farms
    farm_name - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setFarmSessionType ($session, $farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;
        $output = &setHTTPFarmSessionType($session, $farm_name);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Config;
        $output = &setL4FarmParam('persist', $session, $farm_name);
    }

    #if persistence is enabled
    require Relianoid::Farm::Config;
    if (&getPersistence($farm_name) == 0) {
        #register farm in ssyncd
        if ($eload) {
            &eload(
                module => 'Relianoid::EE::Ssyncd',
                func   => 'setSsyncdFarmUp',
                args   => [$farm_name],
            );
        }
    }
    else {
        #unregister farm in ssyncd
        if ($eload) {
            &eload(
                module => 'Relianoid::EE::Ssyncd',
                func   => 'setSsyncdFarmDown',
                args   => [$farm_name],
            );
        }
    }
    return $output;
}

=pod

=head1 setFarmTimeout

Asign a timeout value to a farm

Parameters:

    timeout  - Time out in seconds
    farm_name - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setFarmTimeout ($timeout, $farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    &zenlog("setting 'Timeout $timeout' for $farm_name farm $farm_type", "info", "LSLB");

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;
        $output = &setHTTPFarmTimeout($timeout, $farm_name);
    }

    return $output;
}

=pod

=head1 setFarmAlgorithm

Set the load balancing algorithm to a farm.

Supports farm types: TCP, Datalink, L4xNAT.

Parameters:

    algorithm - Type of balancing mode
    farm_name - Farm name

Returns:

    none

FIXME:

    set a return value, and do error control

=cut

sub setFarmAlgorithm ($algorithm, $farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    &zenlog("setting 'Algorithm $algorithm' for $farm_name farm $farm_type", "info", "FARMS");

    if ($farm_type eq "datalink" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Config',
            func   => 'setDatalinkFarmAlgorithm',
            args   => [ $algorithm, $farm_name ],
        );
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Config;
        $output = &setL4FarmParam('alg', $algorithm, $farm_name);
    }

    return $output;
}

=pod

=head1 getFarmAlgorithm

Get type of balancing algorithm.

Supports farm types: Datalink, L4xNAT.

Parameters:

    farm_name - Farm name

Returns:

    scalar - return a string with type of balancing algorithm or -1 on failure

=cut

sub getFarmAlgorithm ($farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my $algorithm = -1;

    if ($farm_type eq "datalink" && $eload) {
        $algorithm = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Config',
            func   => 'getDatalinkFarmAlgorithm',
            args   => [$farm_name],
        );
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Config;
        $algorithm = &getL4FarmParam('alg', $farm_name);
    }

    return $algorithm;
}

=pod

=head1 setFarmMaxClientTime

Set the maximum time for a client

Parameters:

    maximumTO - Maximum client time
    farm_name - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setFarmMaxClientTime ($max_client_time, $track, $farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    &zenlog("setting 'MaxClientTime $max_client_time $track' for $farm_name farm $farm_type", "info", "LSLB");

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;
        $output = &setHTTPFarmMaxClientTime($track, $farm_name);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Config;
        $output = &setL4FarmParam('persisttm', $track, $farm_name);
    }

    return $output;
}

=pod

=head1 setFarmVirtualConf

Set farm virtual IP and virtual PORT

Parameters:

    vip - virtual ip

    vip_port - virtual port (interface in datalink farms).
               If the port is not sent, the port will not be changed

    farm_name - Farm name

Returns:

    Integer - return 0 on success or other value on failure

See Also:

    To get values use getFarmVip.

=cut

sub setFarmVirtualConf ($vip, $vip_port, $farm_name) {
    my $farm_type = &getFarmType($farm_name);
    my $stat      = -1;
    $vip_port //= '';

    &zenlog("setting 'VirtualConf $vip $vip_port' for $farm_name farm $farm_type", "info", "FARMS");

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;
        $stat = &setHTTPFarmVirtualConf($vip, $vip_port, $farm_name);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Config;
        $stat = 0;

        if ($vip ne "") {
            $stat = &setL4FarmParam('vip', $vip, $farm_name);
        }

        return $stat if $stat;

        if ($vip_port ne "") {
            $stat = &setL4FarmParam('vipp', $vip_port, $farm_name);
        }
    }
    elsif ($farm_type eq "datalink" && $eload) {
        $stat = &eload(
            module => 'Relianoid::EE::Farm::Datalink::Config',
            func   => 'setDatalinkFarmVirtualConf',
            args   => [ $vip, $vip_port, $farm_name ],
        );
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $stat = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Config',
            func   => 'setGSLBFarmVirtualConf',
            args   => [ $vip, $vip_port, $farm_name ],
        );
    }

    return $stat;
}

=pod

=head1 setAllFarmByVip

This function change the virtual interface for a set of farms. If some farm
is up, this function will restart it.

Parameters:

    IP        - New virtual interface for the farms
    farm list - List of farms to update. This list will send as reference

Returns:

    None

=cut

sub setAllFarmByVip ($vip, $farmList) {
    require Relianoid::Farm::Action;

    for my $farm (@{$farmList}) {
        # get status
        my $status = &getFarmStatus($farm);

        # stop farm
        if ($status eq 'up') { &runFarmStop($farm); }

        # change vip
        &setFarmVirtualConf($vip, undef, $farm);

        # start farm
        if ($status eq 'up') { &runFarmStart($farm); }
    }

    return;
}

=pod

=head1 getFarmVS

Return virtual server parameter

Parameters:

    farm_name - Farm name
    service  - Service name
    tag      - Indicate which field will be returned

Returns:

    Integer - The requested parameter value

=cut

sub getFarmVS ($farm_name, $service, $tag) {
    my $output = "";
    require Relianoid::Farm::Core;
    my $farm_type = &getFarmType($farm_name);

    if ($farm_type =~ /http/) {
        require Relianoid::Farm::HTTP::Service;
        $output = &getHTTPFarmVS($farm_name, $service, $tag);
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $output = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Service',
            func   => 'getGSLBFarmVS',
            args   => [ $farm_name, $service, $tag ],
        );
    }

    return $output;
}

=pod

=head1 setFarmVS

Set values for service parameters

Parameters:

    farm_name - Farm name
    service  - Service name
    tag      - Indicate which parameter modify
    string   - value for the field "tag"

Returns:

    Integer - Error code: 0 on success or -1 on failure

=cut

sub setFarmVS ($farm_name, $service, $tag, $string) {
    my $output    = "";
    my $farm_type = &getFarmType($farm_name);

    if ($farm_type =~ /http/) {
        require Relianoid::Farm::HTTP::Service;
        $output = &setHTTPFarmVS($farm_name, $service, $tag, $string);
    }
    elsif ($farm_type eq "gslb") {
        $output = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Service',
            func   => 'setGSLBFarmVS',
            args   => [ $farm_name, $service, $tag, $string ],
        ) if $eload;
    }

    return $output;
}

=pod

=head1 getFarmStruct

    Generic subroutine for the struct retrieval

Parameters:

    farmname - Farm name

Returns:

    farm - reference of the farm hash

=cut

sub getFarmStruct ($farmName) {
    require Relianoid::Farm::Core;
    my $farm;    # declare output hash
    my $farmType = &getFarmType($farmName);
    return if ($farmType eq 1);

    if ($farmType =~ /http|https/) {
        require Relianoid::Farm::HTTP::Config;
        $farm = &getHTTPFarmStruct($farmName, $farmType);
    }
    elsif ($farmType =~ /l4xnat/) {
        require Relianoid::Farm::L4xNAT::Config;
        $farm = &getL4FarmStruct($farmName);
    }
    elsif ($farmType =~ /gslb/) {
        $farm = &eload(
            module => 'Relianoid::EE::Farm::GSLB::Config',
            func   => 'getGSLBFarmStruct',
            args   => [$farmName],
        );
    }

    # elsif ( $farmType =~ /datalink/ && $eload)
    # {
    #     $farm = &eload(
    #         module => 'Relianoid::EE::Farm::Datalink::Config',
    #         func   => 'getDatalinkFarmStruct',
    #         args   => [$farmName],
    #     );
    # }
    return $farm;    # return a hash reference
}

=pod

=head1 getFarmPlainInfo

Return the L4 farm text configuration

Parameters:

    farm_name - farm name to get the status

Returns:

    Scalar - Reference of the file content in plain text

=cut

sub getFarmPlainInfo ($farm_name, $file = undef) {
    my @content;

    my $configdir = &getGlobalConfiguration('configdir');

    my $farm_filename = &getFarmFile($farm_name);

    if ($farm_filename =~ /(?:gslb)\.cfg$/ && defined $file) {
        open my $fd, '<', "$configdir/$farm_filename/$file" or return;
        chomp(@content = <$fd>);
        close $fd;
    }
    else {
        open my $fd, '<', "$configdir/$farm_filename" or return;
        chomp(@content = <$fd>);
        close $fd;
    }

    return \@content;
}

=pod

=head1 reloadFarmsSourceAddress

Reload source address rules of farms

Parameters:

    none

Returns:

    none


FIXME:

    one source address per farm, not for backend

=cut

sub reloadFarmsSourceAddress () {
    require Relianoid::Farm::Core;

    for my $farm_name (&getFarmNameList()) {
        &reloadFarmsSourceAddressByFarm($farm_name);
    }

    return;
}

=pod

=head1 reloadL7FarmsSourceAddress

Reload source address rules of HTTP/HTTPS farms

Parameters:

    none

Returns:

    none

=cut

sub reloadL7FarmsSourceAddress () {
    require Relianoid::Farm::Core;

    my @farms = &getFarmsByType('http');
    push @farms, &getFarmsByType('https');

    for my $farm_name (@farms) {
        &reloadFarmsSourceAddressByFarm($farm_name);
    }

    return;
}

=pod

=head1 reloadFarmsSourceAddressbyFarm

Reload source address rules of a certain farm (l4 in NAT mode and HTTP)

HTTP:

    Add backend only if use a different sourceaddr

Parameters:

    farm_name - name of the farm to apply the source address

Returns:

    none

FIXME:

    one source address per farm, not per backend

=cut

sub reloadFarmsSourceAddressByFarm ($farm_name) {
    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    return if &getFarmStatus($farm_name) ne 'up';

    my $farm_type = &getFarmType($farm_name);

    if ($farm_type eq 'l4xnat') {
        my $farm_ref = &getL4FarmStruct($farm_name);

        return if $farm_ref->{nattype} ne 'nat';

        if ($eload) {
            &eload(
                module => 'Relianoid::EE::Net::Floating',
                func   => 'setFloatingSourceAddr',
                args   => [ $farm_ref, undef ],
            );

            # reload the backend source address
            for my $bk (@{ $farm_ref->{servers} }) {
                &eload(
                    module => 'Relianoid::EE::Net::Floating',
                    func   => 'setFloatingSourceAddr',
                    args   => [ $farm_ref, $bk ],
                );
            }
        }
    }

    return;
}

=pod

=head1 checkLocalFarmSourceAddress

Check if an HTTP farm should exist as a local farm in nftlb in order to do snat in any of its backends.
The function will return 1 in case the farm's vip contains floating ip or any of the farm's backends 
are on a network with floating ip or is on an unknown network or custom routes.

Parameters:

    farm_name    - name of the farm to check
    floating_ref - Hash ref with floating system information

Returns:

    Scalar - Integer : 0 if the source address is not needed.

    1 - if farm must be configured for snat.
    2 - if some backend must be configured for snat.
    3 - if farm and some backend must be configured for snat.
    -1 - if there is an error.

=cut

sub checkLocalFarmSourceAddress ($farm_name, $floating_ref) {
    my $farm_srcaddr_ref;

    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    my $farm_type = &getFarmType($farm_name);

    if ($farm_type eq 'http' || $farm_type eq 'https') {
        my $floating = 0;

        if ($eload && &getGlobalConfiguration('floating_L7') eq 'true') {
            $floating = 1;
        }
        return $farm_srcaddr_ref if not $floating;

        # check system floating
        my $floating_config = &eload(
            module => 'Relianoid::EE::Net::Floating',
            func   => 'getFloatingConfig',
        );

        if (not $floating_config) {
            return $farm_srcaddr_ref;
        }

        # check farm vip has floating
        require Relianoid::Farm::HTTP::Config;
        my $farm_vip = &getHTTPFarmVip("vip", $farm_name);
        my $floating_system_ref;

        if ($floating_ref) {
            $floating_system_ref = $floating_ref;
        }
        else {
            $floating_system_ref = &eload(
                module => 'Relianoid::EE::Net::Floating',
                func   => 'get_floating_struct',
            );
        }

        require Relianoid::Net::Interface;
        my $if_system_status = &getInterfaceSystemStatusAll();

        my $farm_floating = &eload(
            module => 'Relianoid::EE::Net::Floating',
            func   => 'getFloatingSourceAddr',
            args   => [ $farm_vip, undef, $floating_system_ref, $if_system_status ]
        );

        # if iface with floating, needs snat
        if ($farm_floating->{out}{floating_ip}) {
            $farm_srcaddr_ref->{farm} = $farm_floating;
        }

        # check backends for every service
        require Relianoid::Farm::HTTP::Service;
        my @services = &getHTTPFarmServices($farm_name);

        require Relianoid::Farm::HTTP::Backend;
        my $ip_floating_ref;
        my $bk_floating;
        my $exists_floating_backend = 0;

        for my $serv_name (@services) {
            my $backends_ref = &getHTTPFarmBackends($farm_name, $serv_name, "false");

            for my $bk (@{$backends_ref}) {
                if (not $ip_floating_ref->{ $bk->{ip} }) {
                    # get sourceaddress
                    my $mark = sprintf("0x%x", $bk->{tag});
                    $bk_floating = &eload(
                        module => 'Relianoid::EE::Net::Floating',
                        func   => 'getFloatingSourceAddr',
                        args   => [ $bk->{ip}, $mark, $floating_system_ref, $if_system_status ]
                    );

                    $ip_floating_ref->{ $bk->{ip} } = $bk_floating;
                }
                else {
                    %{ $bk_floating->{in} }  = %{ $ip_floating_ref->{ $bk->{ip} }{in} };
                    %{ $bk_floating->{out} } = %{ $ip_floating_ref->{ $bk->{ip} }{out} };
                }

                $bk_floating->{in}{mark} = $bk->{tag};

                # check if backend uses floating
                if ($bk_floating->{out}{floating_ip}) {
                    $exists_floating_backend = 1;
                }

                push @{ $farm_srcaddr_ref->{backends} }, $bk_floating;
                $bk_floating = undef;
            }
        }

        if (not $exists_floating_backend) {
            delete $farm_srcaddr_ref->{backends};
        }
    }

    return $farm_srcaddr_ref;
}

=pod

=head1 reloadBackendsSourceAddressByIface

Reload source address rules of a certain farm (l4 in NAT mode and HTTP) by Iface

Parameters:

    iface_name - Interface which the the route is appplied in

Returns:

    none

=cut

sub reloadBackendsSourceAddressByIface ($iface_name) {
    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    for my $farm_name (&getFarmNameList()) {
        my $farm_type = &getFarmType($farm_name);

        next if &getFarmStatus($farm_name) ne 'up';

        if ($farm_type eq 'l4xnat') {
            my $farm_ref = &getL4FarmStruct($farm_name);
            next if $farm_ref->{nattype} ne 'nat';
            &reloadFarmsSourceAddressByFarm($farm_name);
        }
    }

    return;
}

=pod

=head1 getPersistence

Checks if persistence is enabled in the farm through config file

Parameters:

    farm_name - name of the farm where check persistence

Returns: integer

    0 - true
    1 - false

=cut

sub getPersistence ($farm_name) {
    my $farm_type  = &getFarmType($farm_name);
    my $nodestatus = "";

    return 1 if $farm_type !~ /l4xnat|http/;

    if ($eload) {
        $nodestatus = &eload(
            module => 'Relianoid::EE::Cluster',
            func   => 'getZClusterNodeStatus',
            args   => [],
        );
    }

    if ($nodestatus ne "master") {
        return 1;
    }

    if ($farm_type eq 'l4xnat') {
        require Relianoid::Farm::L4xNAT::Config;

        my $persist = &getL4FarmParam('persist', $farm_name);

        if ($persist !~ /^$/) {
            &zenlog("Persistence enabled to $persist for farm $farm_name", "info", "farm");
            return 0;
        }
    }

    if ($farm_type =~ /http/) {
        require Relianoid::Farm::HTTP::Service;
        require Relianoid::Config;
        require Relianoid::Lock;

        my $farm_file = &getFarmFile($farm_name);
        my $pathconf  = &getGlobalConfiguration('configdir');
        my $lock_fh   = &openlock("$pathconf/$farm_file", 'r');

        while (<$lock_fh>) {
            if ($_ =~ /[^#]Session/) {
                &zenlog("Persistence enabled for farm $farm_name", "info", "farm");
                return 0;
            }
        }
        close $lock_fh;
    }

    return 1;
}

1;

