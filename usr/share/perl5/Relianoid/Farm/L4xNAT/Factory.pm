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

use Relianoid::Core;
use Relianoid::Farm::L4xNAT::Action;

my $configdir = &getGlobalConfiguration('configdir');

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::Farm::L4xNAT::Factory

=cut

=pod

=head1 runL4FarmCreate

Create a l4xnat farm

Parameters:

    vip - Virtual IP
    farm_name - Farm name
    vip_port - Virtual port. In l4xnat it ls possible to define multiport
               using ',' to add ports and ':' for ranges
    status - Set the initial status of the farm. The possible values are:
             - 'down' for creating the farm and do not run it
             - 'up' (default) for running the farm when it has been created

Returns:

    Integer - return 0 on success or other value on failure

=cut

sub runL4FarmCreate ($vip, $farm_name, $vip_port, $status = 'up') {
    my $output        = -1;
    my $farm_type     = 'l4xnat';
    my $farm_filename = "$configdir/$farm_name\_$farm_type.cfg";

    require Relianoid::Farm::L4xNAT::Action;
    require Relianoid::Farm::L4xNAT::Config;

    my $proto = ($vip_port eq "*") ? 'all' : 'tcp';
    $vip_port = "80" if not defined $vip_port;
    $vip_port = ""   if ($vip_port eq "*");
    $vip_port =~ s/\:/\-/g;

    require Relianoid::Net::Validate;
    my $vip_family;
    if (&ipversion($vip) == 6) {
        $vip_family = "ipv6";
    }
    else {
        $vip_family = "ipv4";
    }

    $output = &sendL4NlbCmd({
        farm   => $farm_name,
        file   => "$farm_filename",
        method => "POST",
        body   =>
          qq({"farms" : [ { "name" : "$farm_name", "virtual-addr" : "$vip", "virtual-ports" : "$vip_port", "protocol" : "$proto", "mode" : "snat", "scheduler" : "weight", "state" : "$status", "family" : "$vip_family" } ] })
    });

    if ($output) {
        require Relianoid::Farm::Action;
        &runFarmDelete($farm_name);
        return 1;
    }

    if ($status eq 'up') {
        $output = &startL4Farm($farm_name);
    }

    return $output;
}

=pod

=head1 runL4FarmDelete

Delete a l4xnat farm

Parameters:

    farm_name - Farm name

Returns:

    Integer - return 0 on success or other value on failure

=cut

sub runL4FarmDelete ($farm_name) {
    my $output = -1;

    require Relianoid::Farm::L4xNAT::Action;
    require Relianoid::Farm::L4xNAT::Config;
    require Relianoid::Farm::Core;
    require Relianoid::Netfilter;

    my $farmfile = &getFarmFile($farm_name);

    $output = &sendL4NlbCmd({ farm => $farm_name, method => "DELETE" });

    unlink("$configdir/$farmfile") if (-f "$configdir/$farmfile");

    &delMarks($farm_name, "");

    return $output;
}

1;

