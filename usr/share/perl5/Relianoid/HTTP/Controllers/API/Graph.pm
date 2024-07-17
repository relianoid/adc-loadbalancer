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

use Relianoid::RRD;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::Graph

=cut

my $eload = eval { require Relianoid::ELoad };

#GET the list of graphs availables in the load balancer
sub list_graphs_controller () {
    require Relianoid::Stats;

    my @farms = ();
    for my $graph (&getGraphs2Show("Farm")) {
        $graph =~ s/-farm$//;
        push(@farms, $graph);
    }

    if ($eload) {
        @farms = @{
            &eload(
                module => 'Relianoid::EE::RBAC::Group::Core',
                func   => 'getRBACResourcesFromList',
                args   => [ 'farms', \@farms ],
            )
        };
    }

    my @net = ();
    for my $graph (&getGraphs2Show("Network")) {
        $graph =~ s/iface$//;
        push(@net, $graph);
    }

    my @sys = ("cpu", "load", "ram", "swap");

    # Get mount point of disks
    my @mount_points;
    my $partitions = &getDiskPartitionsInfo();

    for my $key (keys %{$partitions}) {
        # mount point : root/mount_point
        push(@mount_points, "root$partitions->{$key}{mount_point}");
    }

    @mount_points = sort @mount_points;
    push @sys, { disks => \@mount_points };

    my @vpns = ();
    if ($eload) {
        for my $graph (&getGraphs2Show("VPN")) {
            $graph =~ s/-vpn$//;
            push(@vpns, $graph);
        }
        @vpns = @{
            &eload(
                module => 'Relianoid::EE::RBAC::Group::Core',
                func   => 'getRBACResourcesFromList',
                args   => [ 'vpns', \@vpns ],
            )
        };
    }
    my $body = {
        description => "These are the possible graphs, you'll be able to access to the daily, weekly, monthly or yearly graph",
        system      => \@sys,
        interfaces  => \@net,
        farms       => \@farms
    };

    if ($eload) {
        $body->{ipds} = \@farms;
        $body->{vpns} = \@vpns;
    }

    return &httpResponse({ code => 200, body => $body });
}

# GET all system graphs
sub list_sys_graphs_controller () {
    require Relianoid::Stats;

    # System values
    my @sys = ("cpu", "load", "ram", "swap");

    # Get mount point of disks
    my @mount_points;
    my $partitions = &getDiskPartitionsInfo();

    for my $key (keys %{$partitions}) {
        # mount point : root/mount_point
        push(@mount_points, "root$partitions->{$key}{mount_point}");
    }

    @mount_points = sort @mount_points;
    push @sys, { disk => \@mount_points };

    my $body = {
        description =>
          "These are the possible system graphs, you'll be able to access to the daily, weekly, monthly or yearly graph",
        system => \@sys
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET system graphs
sub get_sys_graphs_controller ($key) {
    my $desc = "Get $key graphs";

    $key = 'mem'   if ($key eq 'ram');
    $key = 'memsw' if ($key eq 'swap');

    # Print Graph Function
    my @graphs = ();
    for my $freq ('daily', 'weekly', 'monthly', 'yearly') {
        my $g = &printGraph($key, $freq);
        push @graphs,
          {
            frequency  => $freq,
            graph      => $g->{img},
            start_time => $g->{start},
            last_time  => $g->{last},
          };
    }

    my $body = { description => $desc, graphs => \@graphs };

    return &httpResponse({ code => 200, body => $body });
}

# GET frequency system graphs
sub get_sys_graphs_freq_controller ($key, $frequency) {
    my $desc = "Get $frequency $key graphs";

    $key = 'mem'   if ($key eq 'ram');
    $key = 'memsw' if ($key eq 'swap');

    # Print Graph Function
    my $graph = &printGraph($key, $frequency);
    my $body  = {
        description => $desc,
        graphs      => $graph->{img},
        start_time  => $graph->{start},
        last_time   => $graph->{last}
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET a system graph using an interval
# /graphs/system/cpu/custom/start/11-25-2020-05:55/end/11-25-2020-22:25
sub get_sys_graphs_interval_controller ($key, $start, $end) {
    my $desc = "Get $key graphs";

    $key = 'mem'   if ($key eq 'ram');
    $key = 'memsw' if ($key eq 'swap');

    # Print Graph Function
    my $graph = &printGraph($key, $start, $end);
    my $body  = {
        description => $desc,
        graphs      => $graph->{img},
        start_time  => $graph->{start},
        last_time   => $graph->{last}
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET all interface graphs
sub list_iface_graphs_controller () {
    my @iface = ();
    for my $graph (&getGraphs2Show("Network")) {
        $graph =~ s/iface$//;
        push(@iface, $graph);
    }

    my $body = {
        description =>
          "These are the possible interface graphs, you'll be able to access to the daily, weekly, monthly or yearly graph",
        interfaces => \@iface
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET interface graphs
sub get_iface_graphs_controller ($iface) {
    require Relianoid::Net::Interface;

    my $desc              = "Get interface graphs";
    my @system_interfaces = &getInterfaceList();

    # validate NIC NAME
    if (!grep { $iface eq $_ } @system_interfaces) {
        my $msg = "Nic interface not found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # graph for this farm doesn't exist
    elsif (!grep { /${iface}iface$/ } &getGraphs2Show("Network")) {
        my $msg = "There is no rrd files yet.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # Print Graph Function
    my @graphs = ();
    for my $freq ('daily', 'weekly', 'monthly', 'yearly') {
        my $g = &printGraph("${iface}iface", $freq);
        push @graphs,
          {
            frequency  => $freq,
            graph      => $g->{img},
            start_time => $g->{start},
            last_time  => $g->{last},
          };
    }

    my $body = { description => $desc, graphs => \@graphs };

    return &httpResponse({ code => 200, body => $body });
}

# GET frequency interface graphs
sub get_iface_graphs_frec_controller ($iface, $frequency) {
    require Relianoid::Net::Interface;

    my $desc              = "Get interface graphs";
    my @system_interfaces = &getInterfaceList();

    # validate NIC NAME
    if (!grep { $iface eq $_ } @system_interfaces) {
        my $msg = "Nic interface not found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }
    elsif (!grep { /${iface}iface$/ } &getGraphs2Show("Network")) {
        my $msg = "There is no rrd files yet.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # Print Graph Function
    my $graph = &printGraph("${iface}iface", $frequency);
    my $body  = {
        description => $desc,
        graphs      => $graph->{img},
        start_time  => $graph->{start},
        last_time   => $graph->{last}
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET interface graph in an interval
sub get_iface_graphs_interval_controller ($iface, $start, $end) {
    require Relianoid::Net::Interface;

    my $desc              = "Get interface graphs";
    my @system_interfaces = &getInterfaceList();

    # validate NIC NAME
    if (!grep { $iface eq $_ } @system_interfaces) {
        my $msg = "Nic interface not found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }
    elsif (!grep { /${iface}iface$/ } &getGraphs2Show("Network")) {
        my $msg = "There is no rrd files yet.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # Print Graph Function
    my $graph = &printGraph("${iface}iface", $start, $end);
    my $body  = {
        description => $desc,
        graphs      => $graph->{img},
        start_time  => $graph->{start},
        last_time   => $graph->{last}
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET all farm graphs
sub list_farm_graphs_controller () {
    my @farms = ();
    for my $graph (&getGraphs2Show("Farm")) {
        $graph =~ s/-farm$//;
        push(@farms, $graph);
    }

    if ($eload) {
        my $ref_farm = &eload(
            module => 'Relianoid::EE::RBAC::Group::Core',
            func   => 'getRBACResourcesFromList',
            args   => [ 'farms', \@farms ]
        );
        @farms = @{$ref_farm};
    }

    my $body = {
        description =>
          "These are the possible farm graphs, you'll be able to access to the daily, weekly, monthly or yearly graph",
        farms => \@farms
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET farm graphs
sub get_farm_graphs_controller ($farmName) {
    require Relianoid::Farm::Core;

    my $desc = "Get farm graphs";

    # this farm doesn't exist
    if (!&getFarmExists($farmName)) {
        my $msg = "$farmName doesn't exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # graph for this farm doesn't exist
    elsif (!grep { "${farmName}-farm" eq $_ } &getGraphs2Show("Farm")) {
        my $msg = "There are no rrd files yet.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # Print Graph Function
    my @graphs = ();
    for my $freq ('daily', 'weekly', 'monthly', 'yearly') {
        my $g = &printGraph("$farmName-farm", $freq);
        push @graphs,
          {
            frequency  => $freq,
            graph      => $g->{img},
            start_time => $g->{start},
            last_time  => $g->{last},
          };
    }

    my $body = { description => $desc, graphs => \@graphs };

    return &httpResponse({ code => 200, body => $body });
}

# GET frequency farm graphs
sub get_farm_graphs_frec_controller ($farmName, $frequency) {
    require Relianoid::Farm::Core;

    my $desc = "Get farm graphs";

    # this farm doesn't exist
    if (!&getFarmExists($farmName)) {
        my $msg = "$farmName doesn't exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # graph for this farm doesn't exist
    elsif (!grep { /$farmName-farm/ } &getGraphs2Show("Farm")) {
        my $msg = "There is no rrd files yet.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # Print Graph Function
    my $graph = &printGraph("$farmName-farm", $frequency);
    my $body  = {
        description => $desc,
        graphs      => $graph->{img},
        start_time  => $graph->{start},
        last_time   => $graph->{last}
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET farm graph in an interval
sub get_farm_graphs_interval_controller ($farmName, $start, $end) {
    require Relianoid::Farm::Core;

    my $desc = "Get farm graphs";

    # this farm doesn't exist
    if (!&getFarmExists($farmName)) {
        my $msg = "$farmName doesn't exist.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    # graph for this farm doesn't exist
    elsif (!grep { /$farmName-farm/ } &getGraphs2Show("Farm")) {
        my $msg = "There is no rrd files yet.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    # Print Graph Function
    my $graph = &printGraph("$farmName-farm", $start, $end);
    my $body  = {
        description => $desc,
        graphs      => $graph->{img},
        start_time  => $graph->{start},
        last_time   => $graph->{last}
    };

    return &httpResponse({ code => 200, body => $body });
}

#GET mount points list
sub list_disks_graphs_controller () {
    require Relianoid::Stats;

    my @mount_points;
    my $partitions = &getDiskPartitionsInfo();

    for my $key (keys %{$partitions}) {
        # mount point : root/mount_point
        push(@mount_points, "root$partitions->{$key}{mount_point}");
    }

    @mount_points = sort @mount_points;

    my $body = {
        description => "List disk partitions",
        params      => \@mount_points,
    };

    return &httpResponse({ code => 200, body => $body });
}

#GET disk graphs for all periods
sub get_disk_graphs_controller ($mount_point) {
    require Relianoid::Stats;

    $mount_point =~ s/^root[\/]?/\//;    # remove leading 'root/'
    my $desc  = "Disk partition usage graphs";
    my $parts = &getDiskPartitionsInfo();

    my ($part_key) =
      grep { $parts->{$_}{mount_point} eq $mount_point } keys %{$parts};

    unless ($part_key) {
        my $msg = "Mount point not found";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $dev_id = $parts->{$part_key}{rrd_id};
    my @graphs = ();
    for my $freq ('daily', 'weekly', 'monthly', 'yearly') {
        my $g = &printGraph($dev_id, $freq);
        push @graphs,
          {
            frequency  => $freq,
            graph      => $g->{img},
            start_time => $g->{start},
            last_time  => $g->{last},
          };
    }
    my $body = {
        description => $desc,
        graphs      => \@graphs,
    };

    return &httpResponse({ code => 200, body => $body });
}

#GET disk graph for a single period
sub get_disk_graphs_freq_controller ($mount_point, $frequency) {
    require Relianoid::Stats;

    my $desc  = "Disk partition usage graph";
    my $parts = &getDiskPartitionsInfo();
    $mount_point =~ s/^root[\/]?/\//;

    my ($part_key) =
      grep { $parts->{$_}{mount_point} eq $mount_point } keys %{$parts};

    unless ($part_key) {
        my $msg = "Mount point not found";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $dev_id = $parts->{$part_key}{rrd_id};
    my $graph  = &printGraph($dev_id, $frequency);
    my $body   = {
        description => $desc,
        graph       => $graph->{img},
        start_time  => $graph->{start},
        last_time   => $graph->{last},
    };

    return &httpResponse({ code => 200, body => $body });
}

#GET disk graph in an interval
sub get_disk_graphs_interval_controller ($mount_point, $start, $end) {
    require Relianoid::Stats;

    my $desc  = "Disk partition usage graph";
    my $parts = &getDiskPartitionsInfo();
    $mount_point =~ s/^root[\/]?/\//;

    my ($part_key) =
      grep { $parts->{$_}{mount_point} eq $mount_point } keys %{$parts};

    unless ($part_key) {
        my $msg = "Mount point not found";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $dev_id = $parts->{$part_key}{rrd_id};

    my $graph = &printGraph($dev_id, $start, $end);
    my $body  = {
        description => $desc,
        graph       => $graph->{img},
        start_time  => $graph->{start},
        last_time   => $graph->{last},
    };

    return &httpResponse({ code => 200, body => $body });
}

1;

