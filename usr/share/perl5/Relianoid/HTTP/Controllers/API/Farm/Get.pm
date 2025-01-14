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
use Relianoid::Farm::Base;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::Farm::Get

=cut

my $eload = eval { require Relianoid::ELoad };

#GET /farms
sub list_farms_controller () {
    require Relianoid::Farm::Base;

    my @out;
    my @files = &getFarmList();

    for my $file (@files) {
        my $name   = &getFarmName($file);
        my $type   = &getFarmType($name);
        my $status = &getFarmVipStatus($name);
        my $vip    = &getFarmVip('vip',  $name);
        my $port   = &getFarmVip('vipp', $name);

        push @out,
          {
            farmname => $name,
            profile  => $type,
            status   => $status,
            vip      => $vip,
            vport    => $port
          };
    }

    if ($eload) {
        @out = @{
            &eload(
                module => 'Relianoid::EE::RBAC::Group::Core',
                func   => 'getRBACUserSet',
                args   => [ 'farms', \@out ],
            )
        };
    }

    my $body = {
        description => "List farms",
        params      => \@out,
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET /farms/modules/lslb
sub list_lslb_controller () {
    require Relianoid::Farm::Base;

    my @out;
    my @files = &getFarmList();

    for my $file (@files) {
        my $name = &getFarmName($file);
        my $type = &getFarmType($name);
        next unless $type =~ /^(?:https?|l4xnat|eproxy)$/;
        my $status = &getFarmVipStatus($name);
        my $vip    = &getFarmVip('vip',  $name);
        my $port   = &getFarmVip('vipp', $name);

        push @out,
          {
            farmname => $name,
            profile  => $type,
            status   => $status,
            vip      => $vip,
            vport    => $port
          };
    }

    if ($eload) {
        @out = @{
            &eload(
                module => 'Relianoid::EE::RBAC::Group::Core',
                func   => 'getRBACUserSet',
                args   => [ 'farms', \@out ],
            )
        };
    }

    my $body = {
        description => "List LSLB farms",
        params      => \@out,
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET /farms/modules/dslb
sub list_dslb_controller () {
    require Relianoid::Farm::Base;

    my @out;
    my @files = &getFarmList();

    for my $file (@files) {
        my $name = &getFarmName($file);
        my $type = &getFarmType($name);
        next unless $type eq 'datalink';
        my $status = &getFarmVipStatus($name);
        my $vip    = &getFarmVip('vip',  $name);
        my $iface  = &getFarmVip('vipp', $name);

        push @out,
          {
            farmname  => $name,
            status    => $status,
            vip       => $vip,
            interface => $iface
          };
    }

    if ($eload) {
        @out = @{
            &eload(
                module => 'Relianoid::EE::RBAC::Group::Core',
                func   => 'getRBACUserSet',
                args   => [ 'farms', \@out ],
            )
        };
    }

    my $body = {
        description => "List DSLB farms",
        params      => \@out,
    };

    return &httpResponse({ code => 200, body => $body });
}

#GET /farms/<name>/summary
sub get_farm_summary_controller ($farmname) {
    my $desc = "Show farm $farmname";
    # Check if the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "Farm not found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type =~ /https?/) {
        require Relianoid::HTTP::Controllers::API::Farm::Get::HTTP;
        &farms_name_http_summary($farmname);
    }
    else {
        &get_farm_controller($farmname);
    }

    return;
}

#GET /farms/<name>
sub get_farm_controller ($farmname) {
    my $desc = "Show farm $farmname";

    # Check if the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "Farm not found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);

    if ($type =~ /https?/) {
        require Relianoid::HTTP::Controllers::API::Farm::Get::HTTP;
        &farms_name_http($farmname);
    }
    elsif ($type eq 'l4xnat') {
        require Relianoid::HTTP::Controllers::API::Farm::Get::L4xNAT;
        &farms_name_l4($farmname);
    }
    elsif ($type eq 'datalink') {
        require Relianoid::EE::HTTP::Controllers::API::Farm::Get::Datalink;
        &farms_name_datalink($farmname);
    }
    elsif ($type eq 'gslb' && $eload) {
        &eload(
            module => 'Relianoid::EE::HTTP::Controllers::API::Farm::Get::GSLB',
            func   => 'farms_name_gslb',
            args   => [$farmname],
        );
    }
    elsif ($type eq 'eproxy' && $eload) {
        &eload(
            module => 'Relianoid::EE::HTTP::Controllers::API::Farm::Get::Eproxy',
            func   => 'farms_name_eproxy',
            args   => [$farmname],
        );
    }

    return;
}

#GET /farms/<name>/status
sub get_farm_status_controller ($farmname) {
    my $desc = "Show farm $farmname status";

    # Check if the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "Farm not found.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $status = &getFarmVipStatus($farmname);

    # Output
    my $body = {
        description => $desc,
        params      => { status => $status },
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET /farms/modules/summary
sub get_farm_modules_controller () {
    require Relianoid::Farm::Service;
    my $out = { lslb => [], gslb => [], dslb => [], };

    for my $farm_name (&getFarmNameList()) {
        my $type = &getFarmType($farm_name);
        $type =~ s/https/http/;
        my $it = {
            name    => $farm_name,
            profile => $type,
        };

        if ($type eq 'gslb' or $type eq 'http') {
            my @srv = &getFarmServices($farm_name);
            $it->{services} = \@srv;
        }

        if    ($type eq 'datalink') { push @{ $out->{dslb} }, $it; }
        elsif ($type eq 'gslb')     { push @{ $out->{gslb} }, $it; }
        else                        { push @{ $out->{lslb} }, $it; }
    }

    my $body = {
        description => "Farm Modules summary",
        params      => $out,
    };

    return &httpResponse({ code => 200, body => $body });
}

1;

