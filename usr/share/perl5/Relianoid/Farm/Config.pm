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

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::Farm::Config

=cut

=pod

=head1 setFarmBlacklistTime

Configure check time for resurected back-end. It is a farm paramter.

Parameters:

    checktime - time for resurrected checks
    farmname  - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

See Also:

    zapi/v3/put_http.cgi

=cut

sub setFarmBlacklistTime    # ($blacklist_time,$farm_name)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my ($blacklist_time, $farm_name) = @_;

    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;
        $output = &setHTTPFarmBlacklistTime($blacklist_time, $farm_name);
    }

    return $output;
}

=pod

=head1 getFarmBlacklistTime

Return time for resurrected checks for a farm.

Parameters:

    farmname - Farm name

Returns:

    integer - seconds for check or -1 on failure.

See Also:

    zapi/v3/put_http.cgi

=cut

sub getFarmBlacklistTime    # ($farm_name)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my ($farm_name) = @_;

    my $farm_type      = &getFarmType($farm_name);
    my $blacklist_time = -1;

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;
        $blacklist_time = &getHTTPFarmBlacklistTime($farm_name);
    }

    return $blacklist_time;
}

=pod

=head1 setFarmSessionType

Configure type of persistence

Parameters:

    session  - type of session: nothing, HEADER, URL, COOKIE, PARAM, BASIC or IP, for HTTP farms; none or ip, for l4xnat farms
    farmname - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

See Also:

    zapi/v3/put_l4.cgi

=cut

sub setFarmSessionType    # ($session,$farm_name)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my ($session, $farm_name) = @_;

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
                module => 'Relianoid::Ssyncd',
                func   => 'setSsyncdFarmUp',
                args   => [$farm_name],
            );
        }

    }
    else {

        #unregister farm in ssyncd
        if ($eload) {
            &eload(
                module => 'Relianoid::Ssyncd',
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
    farmname - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

See Also:

    zapi/v3/put_http.cgi

=cut

sub setFarmTimeout    # ($timeout,$farm_name)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my ($timeout, $farm_name) = @_;

    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    &zenlog("setting 'Timeout $timeout' for $farm_name farm $farm_type",
        "info", "LSLB", "info", "LSLB");

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;
        $output = &setHTTPFarmTimeout($timeout, $farm_name);
    }

    return $output;
}

=pod

=head1 getFarmTimeout

Return the farm time out

Parameters:

    farmname - Farm name

Returns:

    Integer - Return time out, or -1 on failure.

See Also:

    zapi/v3/get_http.cgi

=cut

sub getFarmTimeout    # ($farm_name)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my ($farm_name) = @_;

    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;
        $output = &getHTTPFarmTimeout($farm_name);
    }

    return $output;
}

=pod

=head1 setFarmAlgorithm

Set the load balancing algorithm to a farm.

Supports farm types: TCP, Datalink, L4xNAT.

Parameters:

    algorithm - Type of balancing mode
    farmname - Farm name

Returns:

    none

FIXME:

    set a return value, and do error control

See Also:

    zapi/v3/put_l4.cgi
    zapi/v3/put_datalink.cgi

=cut

sub setFarmAlgorithm    # ($algorithm,$farm_name)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my ($algorithm, $farm_name) = @_;

    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    &zenlog("setting 'Algorithm $algorithm' for $farm_name farm $farm_type", "info", "FARMS");

    if ($farm_type eq "datalink") {
        require Relianoid::Farm::Datalink::Config;
        $output = &setDatalinkFarmAlgorithm($algorithm, $farm_name);
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

    farmname - Farm name

Returns:

    scalar - return a string with type of balancing algorithm or -1 on failure

See Also:

    <_runDatalinkFarmStart>

    zapi/v3/get_l4.cgi
    zapi/v3/get_datalink.cgi

=cut

sub getFarmAlgorithm    # ($farm_name)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my ($farm_name) = @_;

    my $farm_type = &getFarmType($farm_name);
    my $algorithm = -1;

    if ($farm_type eq "datalink") {
        require Relianoid::Farm::Datalink::Config;
        $algorithm = &getDatalinkFarmAlgorithm($farm_name);
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
    farmname - Farm name

Returns:

    Integer - Error code: 0 on success, or -1 on failure.

=cut

sub setFarmMaxClientTime    # ($max_client_time,$track,$farm_name)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my ($max_client_time, $track, $farm_name) = @_;

    my $farm_type = &getFarmType($farm_name);
    my $output    = -1;

    &zenlog("setting 'MaxClientTime $max_client_time $track' for $farm_name farm $farm_type",
        "info", "LSLB");

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

=head1 getFarmMaxClientTime

Return the maximum time for a client

Parameters:

    farmname - Farm name

Returns:

    Integer - Return maximum time, or -1 on failure.

=cut

sub getFarmMaxClientTime    # ($farm_name)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my ($farm_name) = @_;

    my $farm_type = &getFarmType($farm_name);
    my @max_client_time;

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;
        @max_client_time = &getHTTPFarmMaxClientTime($farm_name);
    }
    elsif ($farm_type eq "l4xnat") {
        require Relianoid::Farm::L4xNAT::Config;
        @max_client_time = &getL4FarmParam('persisttm', $farm_name);
    }

    return @max_client_time;
}

=pod

=head1 setFarmVirtualConf

Set farm virtual IP and virtual PORT

Parameters:

    vip - virtual ip

    port or inteface - virtual port (interface in datalink farms). 
                       If the port is not sent, the port will not be changed

    farmname - Farm name

Returns:

    Integer - return 0 on success or other value on failure

See Also:

    To get values use getFarmVip.

=cut

sub setFarmVirtualConf    # ($vip,$vip_port,$farm_name)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my ($vip, $vip_port, $farm_name) = @_;

    my $farm_type = &getFarmType($farm_name);
    my $stat      = -1;

    &zenlog("setting 'VirtualConf $vip $vip_port' for $farm_name farm $farm_type", "info", "FARMS");

    if ($farm_type eq "http" || $farm_type eq "https") {
        require Relianoid::Farm::HTTP::Config;
        $stat = &setHTTPFarmVirtualConf($vip, $vip_port, $farm_name);
    }
    elsif ($farm_type eq "datalink") {
        require Relianoid::Farm::Datalink::Config;
        $stat = &setDatalinkFarmVirtualConf($vip, $vip_port, $farm_name);
    }
    elsif ($farm_type eq "l4xnat") {
        $stat = 0;
        require Relianoid::Farm::L4xNAT::Config;
        if ($vip ne "") {
            $stat = &setL4FarmParam('vip', $vip, $farm_name);
        }
        return $stat if ($stat != 0);
        if ($vip_port ne "") {
            $stat = &setL4FarmParam('vipp', $vip_port, $farm_name);
        }
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $stat = &eload(
            module => 'Relianoid::Farm::GSLB::Config',
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

sub setAllFarmByVip {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my $vip      = shift;
    my $farmList = shift;

    require Relianoid::Farm::Action;

    foreach my $farm (@{$farmList}) {

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

=head1 checkFarmnameOK

Checks the farmname has correct characters (number, letters and lowercases)

Parameters:

    farmname - Farm name

Returns:

    Integer - return 0 on success or -1 on failure

FIXME:

    Use check_function.cgi regexp instead.

    WARNING: Only used in HTTP function setFarmHTTPNewService.

NOTE:

    Generic function.

=cut

sub checkFarmnameOK    # ($farm_name)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my $farm_name = shift;

    return ($farm_name =~ /^[a-zA-Z0-9\-]+$/)
      ? 0
      : -1;
}

=pod

=head1 getFarmVS

Return virtual server parameter

Parameters:

    farmname - Farm name
    service  - Service name
    tag      - Indicate which field will be returned

Returns:

    Integer - The requested parameter value

=cut

sub getFarmVS    # ($farm_name, $service, $tag)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my ($farm_name, $service, $tag) = @_;

    my $output = "";
    require Relianoid::Farm::Core;
    my $farm_type = &getFarmType($farm_name);

    if ($farm_type =~ /http/) {
        require Relianoid::Farm::HTTP::Service;
        $output = &getHTTPFarmVS($farm_name, $service, $tag);
    }
    elsif ($farm_type eq "gslb" && $eload) {
        $output = &eload(
            module => 'Relianoid::Farm::GSLB::Service',
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

    farmname - Farm name
    service  - Service name
    tag      - Indicate which parameter modify
    string   - value for the field "tag"

Returns:

    Integer - Error code: 0 on success or -1 on failure

=cut

sub setFarmVS    # ($farm_name,$service,$tag,$string)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my ($farm_name, $service, $tag, $string) = @_;

    my $output    = "";
    my $farm_type = &getFarmType($farm_name);

    if ($farm_type =~ /http/) {
        require Relianoid::Farm::HTTP::Service;
        $output = &setHTTPFarmVS($farm_name, $service, $tag, $string);
    }
    elsif ($farm_type eq "gslb") {
        $output = &eload(
            module => 'Relianoid::Farm::GSLB::Service',
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

sub getFarmStruct {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    require Relianoid::Farm::Core;
    my $farm;                                 # declare output hash
    my $farmName = shift;                     # input: farm name
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
            module => 'Relianoid::Farm::GSLB::Config',
            func   => 'getGSLBFarmStruct',
            args   => [$farmName],
        );
    }

    # elsif ( $farmType =~ /datalink/ )
    # {
    # 	require Relianoid::Farm::Datalink::Config;
    # 	$farm = &getDatalinkFarmStruct ( $farmName );
    # }
    return $farm;    # return a hash reference
}

=begin nd

Function: getFarmPlainInfo

Return the L4 farm text configuration

Parameters:

    farm_name - farm name to get the status

Returns:

    Scalar - Reference of the file content in plain text

=cut

sub getFarmPlainInfo    # ($farm_name)
{
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my $farm_name = shift;
    my $file      = shift // undef;
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

sub reloadFarmsSourceAddress {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

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

sub reloadL7FarmsSourceAddress {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

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

sub reloadFarmsSourceAddressByFarm {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    my $farm_name = shift;
    return if &getFarmStatus($farm_name) ne 'up';

    my $farm_type = &getFarmType($farm_name);
    if ($farm_type eq 'l4xnat') {
        my $farm_ref = &getL4FarmStruct($farm_name);
        return if $farm_ref->{nattype} ne 'nat';

        if ($eload) {
            &eload(
                module => 'Relianoid::Net::Floating',
                func   => 'setFloatingSourceAddr',
                args   => [ $farm_ref, undef ],
            );

            # reload the backend source address
            foreach my $bk (@{ $farm_ref->{servers} }) {
                &eload(
                    module => 'Relianoid::Net::Floating',
                    func   => 'setFloatingSourceAddr',
                    args   => [ $farm_ref, $bk ],
                );
            }
        }
    }
    elsif ($farm_type eq 'http' || $farm_type eq 'https') {
        if ($eload && &getGlobalConfiguration("proxy_ng") eq 'true') {
            return if &getGlobalConfiguration('floating_L7') ne 'true';

            my $farm_ref;
            $farm_ref->{name}  = $farm_name;
            $farm_ref->{vip}   = &getHTTPFarmVip("vip",  $farm_name);
            $farm_ref->{vport} = &getHTTPFarmVip("vipp", $farm_name);
            my $farm_floating_ref = &checkLocalFarmSourceAddress($farm_name);

            if (    not defined $farm_floating_ref->{farm}
                and not defined $farm_floating_ref->{backends})
            {

                # no floating needed
                &eload(
                    module => 'Relianoid::Net::Floating',
                    func   => 'removeL7FloatingSourceAddr',
                    args   => [$farm_name],
                );
            }
            else {
                if (defined $farm_floating_ref->{farm}) {

                    # farm needs floating
                    $farm_ref->{float} =
                      $farm_floating_ref->{farm}->{out}->{floating_ip};
                    &eload(
                        module => 'Relianoid::Net::Floating',
                        func   => 'setL7FloatingSourceAddr',
                        args   => [ $farm_ref, undef, $farm_floating_ref ],
                    );
                }
                if (defined $farm_floating_ref->{backends}) {
                    foreach my $backend_floating_ref (@{ $farm_floating_ref->{backends} }) {
                        my $bk_ref->{tag} = $backend_floating_ref->{in}->{mark};

                        if ($backend_floating_ref->{out}->{floating_ip}) {

                            # backend needs floating
                            $bk_ref->{ip} = $backend_floating_ref->{in}->{ip};
                            $bk_ref->{float} =
                              $backend_floating_ref->{out}->{floating_ip};
                            &eload(
                                module => 'Relianoid::Net::Floating',
                                func   => 'setL7FloatingSourceAddr',
                                args   => [ $farm_ref, $bk_ref, $farm_floating_ref ],
                            );
                        }
                        else {

                            # backend does not need floating
                            &eload(
                                module => 'Relianoid::Net::Floating',
                                func   => 'removeL7FloatingSourceAddr',
                                args   => [ $farm_name, $bk_ref ],
                            );
                        }
                    }
                }
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

sub checkLocalFarmSourceAddress {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my ($farm_name, $floating_ref) = @_;

    my $farm_srcaddr_ref;

    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    my $farm_type = &getFarmType($farm_name);

    if ($farm_type eq 'http' || $farm_type eq 'https') {
        my $floating = 0;
        if ($eload) {
            $floating = 1 if (&getGlobalConfiguration('floating_L7') eq 'true');
        }
        return $farm_srcaddr_ref if not $floating;

        # check system floating
        my $floating_config = &eload(
            module => 'Relianoid::Net::Floating',
            func   => 'getFloatingConfig',
        );
        return $farm_srcaddr_ref if not $floating_config;

        # check farm vip has floating

        require Relianoid::Farm::HTTP::Config;
        my $farm_vip = &getHTTPFarmVip("vip", $farm_name);

        my $floating_system_ref;
        if ($floating_ref) {
            $floating_system_ref = $floating_ref;
        }
        else {
            $floating_system_ref = &eload(
                module => 'Relianoid::Net::Floating',
                func   => 'get_floating_struct',
            );
        }

        require Relianoid::Net::Interface;
        my $if_system_status = &getInterfaceSystemStatusAll();

        my $farm_floating = &eload(
            module => 'Relianoid::Net::Floating',
            func   => 'getFloatingSourceAddr',
            args   => [ $farm_vip, undef, $floating_system_ref, $if_system_status ]
        );

        # if iface with floating, needs snat
        if ($farm_floating->{out}->{floating_ip}) {
            $farm_srcaddr_ref->{farm} = $farm_floating;
        }

        # check backends for every service
        require Relianoid::Farm::HTTP::Service;
        my @services = &getHTTPFarmServices($farm_name);

        require Relianoid::Farm::HTTP::Backend;
        my $ip_floating_ref;
        my $bk_floating;
        my $exists_floating_backend = 0;

        foreach my $serv_name (@services) {
            my $backends_ref = &getHTTPFarmBackends($farm_name, $serv_name, "false");
            foreach my $bk (@{$backends_ref}) {
                if (not $ip_floating_ref->{ $bk->{ip} }) {

                    # get sourceaddress
                    my $mark = sprintf("0x%x", $bk->{tag});
                    $bk_floating = &eload(
                        module => 'Relianoid::Net::Floating',
                        func   => 'getFloatingSourceAddr',
                        args   => [ $bk->{ip}, $mark, $floating_system_ref, $if_system_status ]
                    );

                    $ip_floating_ref->{ $bk->{ip} } = $bk_floating;
                }
                else {
                    %{ $bk_floating->{in} } =
                      %{ $ip_floating_ref->{ $bk->{ip} }->{in} };
                    %{ $bk_floating->{out} } =
                      %{ $ip_floating_ref->{ $bk->{ip} }->{out} };
                }
                $bk_floating->{in}->{mark} = $bk->{tag};

                # check if backend uses floating
                if ($bk_floating->{out}->{floating_ip}) {
                    $exists_floating_backend = 1;
                }
                push @{ $farm_srcaddr_ref->{backends} }, $bk_floating;
                $bk_floating = undef;
            }
        }
        delete $farm_srcaddr_ref->{backends} if not $exists_floating_backend;
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

sub reloadBackendsSourceAddressByIface {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    foreach my $farm_name (&getFarmNameList()) {
        my $farm_type = &getFarmType($farm_name);

        next if &getFarmStatus($farm_name) ne 'up';

        if ($farm_type eq 'http' || $farm_type eq 'https') {
            next if (&getGlobalConfiguration("proxy_ng") ne 'true');
            my $floating = 0;
            if ($eload) {
                $floating = 1
                  if (&getGlobalConfiguration('floating_L7') eq 'true');
            }
            next if !$floating;
            &reloadFarmsSourceAddressByFarm($farm_name);
        }
        elsif ($farm_type eq 'l4xnat') {
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

Returns:

    int - 0 = "true" or 1 = "false"

=cut

sub getPersistence {

    my $farm_name = shift;
    my $farm_type = &getFarmType($farm_name);
    my $farm_ref;
    my $nodestatus = "";

    return 1 if $farm_type !~ /l4xnat|http/;

    if ($eload) {
        $nodestatus = &eload(
            module => 'Relianoid::Cluster',
            func   => 'getZClusterNodeStatus',
            args   => [],
        );
    }

    return 1 if ($nodestatus ne "master");

    if ($farm_type eq 'l4xnat') {
        require Relianoid::Farm::L4xNAT::Config;

        #return 1 if (&getL4FarmStatus($farm_name)) ne "up";
        $farm_ref = &getL4FarmStruct($farm_name);
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

        #return 1 if (&getHTTPFarmStatus($farm_name)) ne "up";
        $farm_ref = &getHTTPServiceBlocks($farm_name);
        ##search in a hash string "Session" with no #.
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

