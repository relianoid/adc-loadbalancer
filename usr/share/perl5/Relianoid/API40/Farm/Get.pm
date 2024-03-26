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

Relianoid::API40::Farm::Get

=cut

my $eload = eval { require Relianoid::ELoad };

#GET /farms
sub farms () {
    require Relianoid::Farm::Base;

    my @out;
    my @files = &getFarmList();

    foreach my $file (@files) {
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
                module => 'Relianoid::RBAC::Group::Core',
                func   => 'getRBACUserSet',
                args   => [ 'farms', \@out ],
            )
        };
    }

    my $body = {
        description => "List farms",
        params      => \@out,
    };

    &httpResponse({ code => 200, body => $body });
    return;
}

# GET /farms/LSLBFARM
sub farms_lslb () {
    require Relianoid::Farm::Base;

    my @out;
    my @files = &getFarmList();

    foreach my $file (@files) {
        my $name = &getFarmName($file);
        my $type = &getFarmType($name);
        next unless $type =~ /^(?:https?|l4xnat)$/;
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
                module => 'Relianoid::RBAC::Group::Core',
                func   => 'getRBACUserSet',
                args   => [ 'farms', \@out ],
            )
        };
    }

    my $body = {
        description => "List LSLB farms",
        params      => \@out,
    };

    &httpResponse({ code => 200, body => $body });
    return;
}

# GET /farms/DATALINKFARM
sub farms_dslb () {
    require Relianoid::Farm::Base;

    my @out;
    my @files = &getFarmList();

    foreach my $file (@files) {
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
                module => 'Relianoid::RBAC::Group::Core',
                func   => 'getRBACUserSet',
                args   => [ 'farms', \@out ],
            )
        };
    }

    my $body = {
        description => "List DSLB farms",
        params      => \@out,
    };

    &httpResponse({ code => 200, body => $body });
    return;
}

#GET /farms/<name>/summary
sub farms_name_summary ($farmname) {
    my $desc = "Show farm $farmname";

    # Check if the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "Farm not found.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);
    if ($type =~ /https?/) {
        require Relianoid::API40::Farm::Get::HTTP;
        &farms_name_http_summary($farmname);
    }
    else {
        &farms_name($farmname);
    }

    return;
}

#GET /farms/<name>
sub farms_name ($farmname) {
    my $desc = "Show farm $farmname";

    # Check if the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "Farm not found.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $type = &getFarmType($farmname);

    if ($type =~ /https?/) {
        require Relianoid::API40::Farm::Get::HTTP;
        &farms_name_http($farmname);
    }
    if ($type eq 'l4xnat') {
        require Relianoid::API40::Farm::Get::L4xNAT;
        &farms_name_l4($farmname);
    }
    if ($type eq 'datalink') {
        require Relianoid::API40::Farm::Get::Datalink;
        &farms_name_datalink($farmname);
    }
    if ($type eq 'gslb' && $eload) {
        &eload(
            module => 'Relianoid::API40::Farm::Get::GSLB',
            func   => 'farms_name_gslb',
            args   => [$farmname],
        );
    }

    return;
}

#GET /farms/<name>/status
sub farms_name_status ($farmname) {
    my $desc = "Show farm $farmname status";

    # Check if the farm exists
    if (!&getFarmExists($farmname)) {
        my $msg = "Farm not found.";
        &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $status = &getFarmVipStatus($farmname);

    # Output
    my $body = {
        description => $desc,
        params      => { status => $status },
    };

    &httpResponse({ code => 200, body => $body });
    return;
}

# function to standarizate the backend output
sub getAPIFarmBackends ($out_b, $type, $add_api_keys = [], $translate = {}) {
    my @api_keys = @{$add_api_keys};

    require Relianoid::Farm::Backend;

    # Backends
    die "Waiting a hash input" if (!ref $out_b);

    # filters:
    if ($type eq 'l4xnat') {
        push @api_keys, qw(id weight port ip priority status max_conns);
    }
    elsif ($type eq 'datalink') {
        push @api_keys, qw(id weight ip priority status interface);
    }
    elsif ($type =~ /http/) {
        if (&getGlobalConfiguration('proxy_ng') eq 'true') {
            push @api_keys, qw(id ip port priority status timeout weight connection_limit);
        }
        else {
            push @api_keys, qw(id ip port weight status timeout);
        }
    }
    elsif ($type eq 'gslb') {
        push @api_keys, qw(id ip );
    }

    # add static translations
    $translate->{status} = { "fgdown" => "down", "undefined" => "up" };

    &buildAPIParams($out_b, \@api_keys, $translate);

    if ($eload) {
        $out_b = &eload(
            module => 'Relianoid::Alias',
            func   => 'addAliasBackendsStruct',
            args   => [$out_b],
        );
    }

    return;
}

# GET /farms/modules/summary
sub farms_module_summary () {
    require Relianoid::Farm::Service;
    my $out = { lslb => [], gslb => [], dslb => [], };

    foreach my $farm_name (&getFarmNameList()) {
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

    &httpResponse({ code => 200, body => $body });

    return;
}

1;

