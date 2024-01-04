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

use Relianoid::SNMP;

# GET /system/snmp
sub get_snmp {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my $desc = "Get snmp";
    my $snmp = &translateSNMPConfigToApi( &getSnmpdConfig() );

    &httpResponse({ code => 200, body => { description => $desc, params => $snmp } });
    return;
}

#  POST /system/snmp
sub set_snmp {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");
    my $json_obj = shift;

    my $desc = "Post snmp";

    require Relianoid::Net::Interface;
    my $ip_list = &getIpAddressList();
    push @{$ip_list}, '*';

    my $params = &getAPIModel("system_snmp-modify.json");
    $params->{ip}->{values} = $ip_list;

    # Check allowed parameters
    my $error_msg = &checkApiParams($json_obj, $params, $desc);
    return &httpErrorResponse(code => 400, desc => $desc, msg => $error_msg)
      if ($error_msg);

    # check scope value
    if (defined $json_obj->{'scope'}) {
        my $network = NetAddr::IP->new($json_obj->{'scope'})->network();
        if ($network ne $json_obj->{'scope'}) {
            my $msg =
              "The value '$json_obj->{ 'scope' }' is not a valid network value for the parameter 'scope'.";
            &httpErrorResponse(code => 400, desc => $desc, msg => $msg);
        }
    }

    my $snmp       = &getSnmpdConfig();

    my $status = $json_obj->{'status'} // $snmp->{ status };
    my $port   = $json_obj->{'port'}   // $snmp->{port};
    my $ip     = $json_obj->{'ip'}     // $snmp->{ip};

    if (($port ne $snmp->{port}) or ($ip ne $snmp->{ip})) {
        if ($status eq 'true' and not &validatePort($ip, $port, 'udp', undef, 'snmp')) {
            my $msg = "The '$ip' ip and '$port' port are in use.";
            &httpErrorResponse(code => 400, desc => $desc, msg => $msg);
        }
    }

    delete $json_obj->{'status'} if exists $json_obj->{'status'};
    foreach my $key (keys %{$json_obj}) {
        $snmp->{$key} = $json_obj->{$key};
    }

    my $error = &setSnmpdConfig($snmp);
    &translateSNMPConfigToApi( $snmp );

    if ($error) {
        my $msg = "There was an error modifying SNMP.";
        &httpErrorResponse(code => 400, desc => $desc, msg => $msg);
    }

    if ($status eq 'true' && $snmp->{ status } eq 'false') {
        &setSnmpdStatus('true');
    }
    elsif ($status eq 'false' && $snmp->{ status } eq 'true') {
        &setSnmpdStatus('false');
    }
    elsif ($status ne 'false' && $snmp->{ status } ne 'false') {
        &setSnmpdStatus('false');
        &setSnmpdStatus('true');
    }

    # wait to check pid values
    sleep(1);
    $snmp->{status} = &getSnmpdStatus();

    &httpResponse(
        {
            code => 200,
            body => {
                description => $desc,
                params      => $snmp,
                message     => "The SNMP service has been updated successfully."
            }
        }
    );
    return;
}

1;

