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

Relianoid::Farm::Factory

=cut

=pod

=head1 runFarmCreate

Create a farm

Parameters:

    farm_type - Farm type. The available options are: "http", "https", "datalink", "l4xnat" or "gslb"
    vip       - Virtual IP where the virtual service is listening
    vip_port  - Virtual port where the virtual service is listening
    farm_name - Farm name
    fdev      - Inteface wich uses the VIP. This parameter is only used in datalink farms

Returns:

    Integer - return 0 on success or different of 0 on failure

FIXME:

    Use hash to pass the parameters

=cut

sub runFarmCreate ($farm_type, $vip, $vip_port, $farm_name, $fdev) {
    my $output        = -1;
    my $farm_filename = &getFarmFile($farm_name);

    if ($farm_filename != -1) {

        # the farm name already exists
        $output = -2;
        return $output;
    }

    my $status = 'up';
    if ($farm_type ne 'datalink') {
        require Relianoid::Net::Interface;
        $status = 'down'
          if (!&validatePort($vip, $vip_port, $farm_type, $farm_name));
    }

    &zenlog("running 'Create' for $farm_name farm $farm_type", "info", "LSLB");

    if ($farm_type =~ /^HTTPS?$/i) {
        require Relianoid::Farm::HTTP::Factory;
        $output = &runHTTPFarmCreate($vip, $vip_port, $farm_name, $farm_type, $status);
    }
    elsif ($farm_type =~ /^DATALINK$/i) {
        require Relianoid::Farm::Datalink::Factory;
        $output = &runDatalinkFarmCreate($farm_name, $vip, $fdev);
    }
    elsif ($farm_type =~ /^L4xNAT$/i) {
        require Relianoid::Farm::L4xNAT::Factory;
        $output = &runL4FarmCreate($vip, $farm_name, $vip_port, $status);
    }
    elsif ($farm_type =~ /^GSLB$/i) {
        $output = &eload(
            module => 'Relianoid::Farm::GSLB::Factory',
            func   => 'runGSLBFarmCreate',
            args   => [ $vip, $vip_port, $farm_name, $status ],
        ) if $eload;
    }

    &eload(
        module => 'Relianoid::RBAC::Group::Config',
        func   => 'addRBACUserResource',
        args   => [ $farm_name, 'farms' ],
    ) if $eload;

    return $output;
}

=pod

=head1 runFarmCreateFrom

Function that does a copy of a farm and set the new virtual ip and virtual port.
Apply the same farguardians to the services and the same ipds rules.

Parameters:

    params - hash reference. The hash has to contain the following keys:

    profile:   is the type of profile is going to be copied
    farmname:  the name of the new farm
    copy_from: it is the name of the farm from is copying
    vip:       the new virtual ip for the new farm
    vport:     the new virtual port for the new farm. This parameters is skipped in datalink farms
    interface: it is the interface for the new farm. This parameter is for datalink farms

Returns:

    Integer - Error code: return 0 on success or another value on failure

=cut

sub runFarmCreateFrom ($params) {
    my $err = 0;

    require Relianoid::Lock;

    # lock farm
    my $lock_file = &getLockFile($params->{farmname});
    my $lock_fh   = &openlock($lock_file, 'w');

    # add ipds rules
    my $ipds;
    if ($eload) {
        $ipds = &eload(
            module => 'Relianoid::IPDS::Core',
            func   => 'getIPDSfarmsRules',
            args   => [ $params->{copy_from} ],
        );

        # they doesn't have to be applied, they already are in the config file
        delete $ipds->{waf};
    }

    # create file
    require Relianoid::Farm::Action;
    $err = &copyFarm($params->{copy_from}, $params->{farmname});

    # add fg
    require Relianoid::FarmGuardian;
    if ($params->{profile} eq 'l4xnat') {
        if (my $fg = &getFGFarm($params->{copy_from})) {
            &linkFGFarm($fg, $params->{farmname});
        }
    }
    elsif ($params->{profile} ne 'datalink') {
        my $fg;
        require Relianoid::Farm::Service;
        foreach my $s (&getFarmServices($params->{farmname})) {
            if (my $fg = &getFGFarm($params->{copy_from}, $s)) {
                &linkFGFarm($fg, $params->{farmname}, $s);
            }
        }
    }

    # unlock farm
    close $lock_fh;

    # modify vport, vip, interface
    if ($params->{profile} ne 'datalink') {
        require Relianoid::Farm::Config;
        $err = &setFarmVirtualConf($params->{vip}, $params->{vport}, $params->{farmname});
    }
    else {
        require Relianoid::Farm::Datalink::Config;
        $err =
          &setDatalinkFarmVirtualConf($params->{vip}, $params->{interface}, $params->{farmname});
    }

    if ($eload and not $err) {
        $err = &eload(
            module => 'Relianoid::IPDS::Core',
            func   => 'addIPDSFarms',
            args   => [ $params->{farmname}, $ipds ],
        );
    }

    if (($params->{profile} eq 'l4xnat') and (!$err)) {
        require Relianoid::Net::Interface;
        if (&validatePort($params->{vip}, $params->{vport}, 'l4xnat', $params->{farmname})) {
            $err = &startL4Farm($params->{farmname});
        }
    }

    return $err;
}

1;

