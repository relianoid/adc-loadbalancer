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

my $eload     = eval { require Relianoid::ELoad };
my $configdir = &getGlobalConfiguration('configdir');

=pod

=head1 Module

Relianoid::Farm::HTTP::Service

=cut

=pod

=head1 setFarmHTTPNewService

Create a new Service in a HTTP farm

Parameters:

    farm_name - Farm name

    service - Service name

Returns:

    Integer - Error code: 0 on success, other value on failure

FIXME:

    This function returns nothing, do error control

=cut

sub setFarmHTTPNewService ($farm_name, $service) {
    use File::Grep 'fgrep';
    require Tie::File;
    require Relianoid::Lock;
    require Relianoid::Farm::Config;

    my $output = -1;

    #first check if service name exist
    if ($service =~ /(?=)/ && $service =~ /^$/) {

        #error 2 eq $service is empty
        $output = 2;
        return $output;
    }

    if (!fgrep { /^\s*Service "$service"/ } "$configdir/$farm_name\_proxy.cfg") {

        #create service
        my @newservice;
        my $sw       = 0;
        my $count    = 0;
        my $proxytpl = &getGlobalConfiguration('proxytpl');
        tie my @proxytpl, 'Tie::File', "$proxytpl";

        foreach my $line (@proxytpl) {
            if ($line =~ /Service \"\[DESC\]\"/) {
                $sw = 1;
            }

            if ($sw eq "1") {
                push(@newservice, $line);
            }

            if ($line =~ /End/) {
                $count++;
            }

            if ($count eq "4") {
                last;
            }
        }
        untie @proxytpl;

        $newservice[0]  =~ s/#//g;
        $newservice[-1] =~ s/#//g;

        my $lock_file = &getLockFile($farm_name);
        my $lock_fh   = &openlock($lock_file, 'w');

        my @fileconf;
        if (
            !fgrep { /^\s*Service "$service"/ }
            "$configdir/$farm_name\_proxy.cfg"
          )
        {
            tie @fileconf, 'Tie::File', "$configdir/$farm_name\_proxy.cfg";
            my $i         = 0;
            my $farm_type = "";
            $farm_type = &getFarmType($farm_name);

            foreach my $line (@fileconf) {
                if ($line =~ /#ZWACL-END/) {
                    $output = 0;
                    foreach my $lline (@newservice) {
                        if ($lline =~ /\[DESC\]/) {
                            $lline =~ s/\[DESC\]/$service/;
                        }
                        if (   $lline =~ /StrictTransportSecurity/
                            && $farm_type eq "https")
                        {
                            $lline =~ s/#//;
                        }
                        splice @fileconf, $i, 0, "$lline";
                        $i++;
                    }
                    last;
                }
                $i++;
            }
        }
        untie @fileconf;
        close $lock_fh;
    }
    else {
        $output = 1;
    }

    return $output;
}

=pod

=head1 setFarmHTTPNewServiceFirst

Create a new Service in a HTTP farm on first position

Parameters:

    farm_name - Farm name

    service - Service name

Returns:

    Integer - Error code: 0 on success, other value on failure

=cut

sub setFarmHTTPNewServiceFirst ($farm_name, $service) {
    use File::Grep 'fgrep';
    require Tie::File;
    require Relianoid::Lock;
    require Relianoid::Farm::Config;

    my $output = -1;

    #first check if service name exist
    if ($service =~ /(?=)/ && $service =~ /^$/) {

        #error 2 eq $service is empty
        $output = 2;
        return $output;
    }

    if (!fgrep { /^\s*Service "$service"/ } "$configdir/$farm_name\_proxy.cfg") {

        #create service
        my @newservice;
        my $sw       = 0;
        my $count    = 0;
        my $proxytpl = &getGlobalConfiguration('proxytpl');
        tie my @proxytpl, 'Tie::File', "$proxytpl";

        foreach my $line (@proxytpl) {
            if ($line =~ /Service \"\[DESC\]\"/) {
                $sw = 1;
            }

            if ($sw eq "1") {
                push(@newservice, $line);
            }

            if ($line =~ /End/) {
                $count++;
            }

            if ($count eq "4") {
                last;
            }
        }
        untie @proxytpl;

        $newservice[0]  =~ s/#//g;
        $newservice[-1] =~ s/#//g;

        my $lock_file = &getLockFile($farm_name);
        my $lock_fh   = &openlock($lock_file, 'w');

        my @fileconf;
        if (
            !fgrep { /^\s*Service "$service"/ }
            "$configdir/$farm_name\_proxy.cfg"
          )
        {
            tie @fileconf, 'Tie::File', "$configdir/$farm_name\_proxy.cfg";
            my $i         = 0;
            my $farm_type = "";
            $farm_type = &getFarmType($farm_name);

            foreach my $line (@fileconf) {
                if ($line =~ /#ZWACL-INI/) {
                    $output = 0;
                    foreach my $lline (@newservice) {
                        if ($lline =~ /\[DESC\]/) {
                            $lline =~ s/\[DESC\]/$service/;
                        }
                        if (   $lline =~ /StrictTransportSecurity/
                            && $farm_type eq "https")
                        {
                            $lline =~ s/#//;
                        }
                        $i++;
                        splice @fileconf, $i, 0, "$lline";
                    }
                    last;
                }
                $i++;
            }
        }
        untie @fileconf;
        close $lock_fh;
    }
    else {
        $output = 1;
    }

    return $output;
}

=pod

=head1 delHTTPFarmService

Delete a service in a Farm

Parameters:

    farm_name - Farm name
    service - Service name

Returns:

    Integer - Error code: 0 on success, -1 on failure

=cut

sub delHTTPFarmService ($farm_name, $service) {
    require Tie::File;
    require Relianoid::Lock;
    require Relianoid::FarmGuardian;
    require Relianoid::Farm::HTTP::Service;
    require Relianoid::Farm::HTTP::Sessions;
    require Relianoid::Farm::Config;

    my $farm_filename = &getFarmFile($farm_name);
    my $sw            = 0;
    my $output        = -1;
    my $farm_ref      = getFarmStruct($farm_name);

    # Counter the Service's backends
    my $sindex     = &getFarmVSI($farm_name, $service);
    my $backendsvs = &getHTTPFarmVS($farm_name, $service, "backends");
    my @be         = split("\n", $backendsvs);
    my $counter    = @be;

    # Stop FG service
    &delFGFarm($farm_name, $service);

    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    tie my @fileconf, 'Tie::File', "$configdir/$farm_filename";

    my $i = 0;
    for ($i = 0 ; $i < $#fileconf ; $i++) {
        my $line = $fileconf[$i];
        if ($sw eq "1" && ($line =~ /ZWACL-END/ || $line =~ /Service/)) {
            $output = 0;
            last;
        }

        if ($sw == 1) {
            if ($line =~ /\s*NfMark\s*(.*)/) {
                require Relianoid;
                require Relianoid::Farm::Backend;
                my $mark = sprintf("0x%x", $1);
                &delMarks("", $mark);
                &setBackendRule("del", $farm_ref, $mark)
                  if (&getGlobalConfiguration('mark_routing_L7') eq 'true');
                if ($eload) {
                    if (&getGlobalConfiguration('floating_L7') eq 'true') {

                        # Delete backend if exists in nftlb
                        &eload(
                            module => 'Relianoid::Net::Floating',
                            func   => 'removeL7FloatingSourceAddr',
                            args   => [ $farm_ref->{name}, { tag => $1 } ],
                        );
                    }
                }
            }
            splice @fileconf, $i, 1,;
            $i--;
        }

        if ($line =~ /Service "$service"/) {
            $sw = 1;
            splice @fileconf, $i, 1,;
            $i--;
        }
    }

    if ($eload) {
        if (&getGlobalConfiguration('floating_L7') eq 'true') {
            &reloadFarmsSourceAddressByFarm($farm_name);
        }
    }

    untie @fileconf;
    close $lock_fh;

    # delete service's backends  in status file
    if ($counter > -1) {
        while ($counter > -1) {
            require Relianoid::Farm::HTTP::Backend;
            &runRemoveHTTPBackendStatus($farm_name, $counter, $service);
            $counter--;
        }
    }

    # delete service's sessions from config file

    if (&getGlobalConfiguration('proxy_ng')) {
        &deleteConfL7FarmAllSession($farm_name, $service);
    }

    # change the ID value of services with an ID higher than the service deleted (value - 1)
    tie my @contents, 'Tie::File', "$configdir\/$farm_name\_status.cfg";
    foreach my $line (@contents) {
        my @params = split("\ ", $line);
        my $newval = $params[2] - 1;

        if ($params[2] > $sindex) {
            $line =~
              s/$params[0]\ $params[1]\ $params[2]\ $params[3]\ $params[4]/$params[0]\ $params[1]\ $newval\ $params[3]\ $params[4]/g;
        }
    }
    untie @contents;

    return $output;
}

=pod

=head1 getHTTPFarmServices

Get an array containing all service name configured in an HTTP farm.

If Service name is sent, get an array containing the service name foundand index.

Parameters:

    farm_name - Farm name
    service_name - Service name

Returns:

    Array - service names if service name param does not exist. 
    Hash ref  - Hash ref $service_ref if service name param exists.

Variable: $service_ref

    $service_ref->{ $service_name } - Service index

FIXME:

    &getHTTPFarmVS(farmname) does same but in a string

=cut

sub getHTTPFarmServices ($farm_name, $service_name = undef) {
    require Relianoid::Farm::Core;

    my $farm_filename = &getFarmFile($farm_name);
    my @output        = ();

    open my $fh, '<', "$configdir\/$farm_filename";
    my @file = <$fh>;
    close $fh;

    my $index = 0;
    foreach my $line (@file) {
        if ($line =~ /^\s*Service\s+\"(.*)\"\s*$/) {
            my $service = $1;
            if ($service_name) {
                if ($service_name eq $service) {
                    return { $service => $index };
                }
                $index++;
            }
            else {
                push(@output, $service);
            }
        }
    }

    return @output;
}

=pod

=head1 getHTTPServiceStruct

Get a struct with all parameters of a HTTP service

Parameters:

    farmname - Farm name
    service_name  - Service name

Returns:

    hash ref - hash with service configuration

    Example output:

    {
        "backends" : [
            {
                "id" : 0,
                "ip" : "48.5.25.5",
                "port" : 70,
                "status" : "up",
                "timeout" : null,
                "weight" : null
            }
        ],
        "fgenabled" : "false",
        "fglog" : "false",
        "fgscript" : "",
        "fgtimecheck" : 5,
        "httpsb" : "false",
        "id" : "srv3",
        "leastresp" : "false",
        "persistence" : "",
        "redirect" : "",
        "redirecttype" : "",
        "sessionid" : "",
        "ttl" : 0,
        "urlp" : "",
        "vhost" : ""
    };

    Enterprise Edition also includes:

    {
        ...
        "cookiedomain" : "",
        "cookieinsert" : "false",
        "cookiename" : "",
        "cookiepath" : "",
        "cookiettl" : 0,
        ...
    };

Notes:

    Similar to the function get_http_service_struct

=cut

sub getHTTPServiceStruct ($farmname, $service_name) {
    require Relianoid::FarmGuardian;
    require Relianoid::Farm::HTTP::Backend;

    my $proxy_ng = &getGlobalConfiguration('proxy_ng');

    # http services
    my $services = &getHTTPFarmVS($farmname, "", "");
    my @serv     = split(' ', $services);

    # return error if service is not found
    return unless grep ({ $service_name eq $_ } @serv);

    my $vser         = &getHTTPFarmVS($farmname, $service_name, "vs");
    my $urlp         = &getHTTPFarmVS($farmname, $service_name, "urlp");
    my $redirect     = &getHTTPFarmVS($farmname, $service_name, "redirect");
    my $redirecttype = &getHTTPFarmVS($farmname, $service_name, "redirecttype");
    my $session      = &getHTTPFarmVS($farmname, $service_name, "sesstype");
    my $ttl          = &getHTTPFarmVS($farmname, $service_name, "ttl");
    my $sesid        = &getHTTPFarmVS($farmname, $service_name, "sessionid");
    my $dyns         = &getHTTPFarmVS($farmname, $service_name, "dynscale");
    my $httpsbe      = &getHTTPFarmVS($farmname, $service_name, "httpsbackend");
    my $pinnedConn   = &getHTTPFarmVS($farmname, $service_name, "pinnedConnection");
    my $routingPol   = &getHTTPFarmVS($farmname, $service_name, "routingPolicy");

    my $rewriteLocation = &getHTTPFarmVS($farmname, $service_name, "rewriteLocation");

    $dyns    = "false" if $dyns eq '';
    $httpsbe = "false" if $httpsbe eq '';

    # Backends
    my $backends = &getHTTPFarmBackends($farmname, $service_name);

    # Remove backend status 'undefined', it is for news api versions
    foreach my $be (@{$backends}) {
        $be->{'status'} = 'up' if $be->{'status'} eq 'undefined';
    }
    if ($eload) {
        my $backends = &eload(
            module => 'Relianoid::Alias',
            func   => 'addAliasBackendsStruct',
            args   => [$backends],
        );
    }

    my $service_ref = {
        id           => $service_name,
        vhost        => $vser,
        urlp         => $urlp,
        redirect     => $redirect,
        redirecttype => $redirecttype,
        persistence  => $session,
        ttl          => $ttl + 0,
        sessionid    => $sesid,
        leastresp    => $dyns,
        httpsb       => $httpsbe,
        backends     => $backends,
    };

    if ($proxy_ng eq 'true') {
        $service_ref->{pinnedconnection} = $pinnedConn;
        $service_ref->{routingpolicy}    = $routingPol;
        $service_ref->{rewritelocation}  = $rewriteLocation;
    }

    # add fg
    $service_ref->{farmguardian} = &getFGFarm($farmname, $service_name);

    if ($eload) {
        if ($proxy_ng eq 'true') {
            my $addRequestHeader      = &getHTTPFarmVS($farmname, $service_name, "addRequestHeader");
            my $addResponseHeader     = &getHTTPFarmVS($farmname, $service_name, "addResponseHeader");
            my $removeRequestHeader   = &getHTTPFarmVS($farmname, $service_name, "removeRequestHeader");
            my $removeResponseHeader  = &getHTTPFarmVS($farmname, $service_name, "removeResponseHeader");
            my $replaceRequestHeader  = &getHTTPFarmVS($farmname, $service_name, "replaceRequestHeader");
            my $replaceResponseHeader = &getHTTPFarmVS($farmname, $service_name, "replaceResponseHeader");
            my $rewriteUrl            = &getHTTPFarmVS($farmname, $service_name, "rewriteUrl");

            $service_ref->{replacerequestheader}  = $replaceRequestHeader;
            $service_ref->{replaceresponseheader} = $replaceResponseHeader;
            $service_ref->{rewriteurl}            = $rewriteUrl;
            $service_ref->{addrequestheader}      = $addRequestHeader;
            $service_ref->{addresponseheader}     = $addResponseHeader;
            $service_ref->{removerequestheader}   = $removeRequestHeader;
            $service_ref->{removeresponseheader}  = $removeResponseHeader;
        }

        $service_ref = &eload(
            module => 'Relianoid::Farm::HTTP::Service::Ext',
            func   => 'add_service_cookie_insertion',
            args   => [ $farmname, $service_ref ],
        );

        $service_ref->{redirect_code} = &eload(
            module => 'Relianoid::Farm::HTTP::Service::Ext',
            func   => 'getHTTPServiceRedirectCode',
            args   => [ $farmname, $service_name ],
        );
        $service_ref->{sts_status} = &eload(
            module => 'Relianoid::Farm::HTTP::Service::Ext',
            func   => 'getHTTPServiceSTSStatus',
            args   => [ $farmname, $service_name ],
        );

        $service_ref->{sts_timeout} = int(&eload(
            module => 'Relianoid::Farm::HTTP::Service::Ext',
            func   => 'getHTTPServiceSTSTimeout',
            args   => [ $farmname, $service_name ],
        ));
    }

    return $service_ref;
}

=pod

=head1 getHTTPServiceId

Returns the service id

Parameters:

    farmname - Farm name
    service_name - Service name

Returns:

    integer - id of service

    undefined - if the service was not found

=cut

sub getHTTPServiceId ($farmname, $service_name) {
    my $id       = undef;
    my @services = getHTTPFarmServices($farmname);
    my $index    = 0;
    my $exist    = 0;

    foreach my $service (@services) {
        if ($service eq $service_name) {
            $id    = $index;
            $exist = 1;
            last;
        }
        $index++;
    }
    return unless ($exist);
    return $id;
}

=pod

=head1 getHTTPFarmVS

Return virtual server parameter

Parameters:

    farm_name - Farm name

    service - Service name

    tag - Indicate which field will be returned. The options are: vs, urlp, redirect, redirecttype, dynscale, sesstype, ttl, sessionid, httpsbackend or backends

Returns:

    scalar - if service and tag is blank, return all services in a string: "service0 service1 ..." else return the parameter value

FIXME:

    return a hash with all parameters

=cut

sub getHTTPFarmVS ($farm_name, $service = "", $tag = "") {
    my $proxy_mode = &getGlobalConfiguration('proxy_ng');

    my $farm_filename = &getFarmFile($farm_name);
    my $output        = "";
    if (   $tag eq 'replaceRequestHeader'
        || $tag eq 'replaceResponseHeader'
        || $tag eq 'rewriteUrl'
        || $tag eq 'addRequestHeader'
        || $tag eq 'addResponseHeader'
        || $tag eq 'removeRequestHeader'
        || $tag eq 'removeResponseHeader')
    {
        $output = [];
    }
    else {
        $output = "";
    }

    my $directive_index = 0;
    my @lines           = ();

    if (open my $fileconf, '<', "$configdir/$farm_filename") {
        @lines = <$fileconf>;
        close $fileconf;
    }

    my $sw         = 0;
    my $be_section = 0;
    my $se_section = 0;
    my $be_emerg   = 0;
    my $be         = -1;
    my $sw_ti      = 0;
    my $output_ti  = "";
    my $sw_pr      = 0;
    my $output_pr  = "";
    my $sw_w       = 0;
    my $output_w   = "";
    my $sw_co      = 0;
    my $output_co  = "";
    my $sw_tag     = 0;
    my $output_tag = "";
    my $outputa;
    my $outputp;
    my @return;

    foreach my $line (@lines) {
        if ($line =~ /^\s+Service \"$service\"/) { $sw         = 1; }
        if ($line =~ /^\s+Session/ && $sw == 1)  { $se_section = 1; }
        if ($line =~ /^\s+End\s*$/) {
            if    ($se_section)                { $se_section = 0; }
            elsif (!$be_section && !$be_emerg) { $sw         = 0; }
        }

        # returns all services for this farm
        if ($tag eq "" && $service eq "") {
            if ($line =~ /^\s+Service\ \"/ && $line !~ "#") {
                @return = split("\ ", $line);
                $return[1] =~ s/\"//g;
                $return[1] =~ s/^\s+//;
                $return[1] =~ s/\s+$//;
                $output = "$output $return[1]";
            }
        }

        #vs tag
        if ($tag eq "vs") {
            if ($line =~ "HeadRequire" && $sw == 1 && $line !~ /^\s*#/) {
                @return = split("Host:", $line);
                $return[1] =~ s/\"//g;
                $return[1] =~ s/^\s+//;
                $return[1] =~ s/\s+$//;
                $output = $return[1];
                last;

            }
        }

        #url pattern
        if ($tag eq "urlp") {
            if ($line =~ /^\s*Url \"/ && $sw == 1) {
                @return = split("Url", $line);
                $return[1] =~ s/\"//g;
                $return[1] =~ s/^\s+//;
                $return[1] =~ s/\s+$//;
                $output = $return[1];
                last;
            }
        }

        #redirect
        if ($tag eq "redirect") {

            # Redirect types: 301, 302 or 307.
            if (   $line =~ /Redirect(?:Append)?\s/
                && $sw == 1
                && $line !~ /^\s*#/)
            {
                @return = split(" ", $line);

                my $url = $return[-1];
                $url =~ s/\"//g;
                $url =~ s/^\s+//;
                $url =~ s/\s+$//;
                $output = $url;
                last;
            }
        }

        if ($tag eq "redirecttype") {
            if (   $line =~ /Redirect(?:Append)?\s/
                && $sw == 1
                && $line !~ "#")
            {
                if    ($line =~ /Redirect /)       { $output = "default"; }
                elsif ($line =~ /RedirectAppend /) { $output = "append"; }
                last;
            }
        }

        #dynscale
        if ($tag eq "dynscale") {
            if ($line =~ "DynScale\ " && $sw == 1 && $line !~ "#") {
                $output = "true";
                last;
            }

        }

        #sesstion type
        if ($tag eq "sesstype") {
            if ($line =~ "Type" && $sw == 1 && $line !~ "#") {
                @return = split("\ ", $line);
                $return[1] =~ s/\"//g;
                $return[1] =~ s/^\s+//;
                $return[1] =~ s/\s+$//;
                $output = $return[1];
                last;
            }
        }

        #ttl
        if ($tag eq "ttl") {
            if ($line =~ "TTL" && $sw == 1) {
                @return = split("\ ", $line);
                $return[1] =~ s/\"//g;
                $return[1] =~ s/^\s+//;
                $return[1] =~ s/\s+$//;
                $output = $return[1];
                last;
            }
        }

        #session id
        if ($tag eq "sessionid") {
            if ($line =~ /\s+ID/ && $sw == 1 && $line !~ /^\s*#/) {
                @return = split("\ ", $line);
                $return[1] =~ s/\"//g;
                $return[1] =~ s/^\s+//;
                $return[1] =~ s/\s+$//;
                $output = $return[1];
                last;
            }
        }

        #HTTPS tag
        if ($tag eq "httpsbackend") {
            if ($line =~ "##True##HTTPS-backend##" && $sw == 1) {
                $output = "true";
                last;
            }
        }

        #PinnedConnection tag
        if ($tag eq "pinnedConnection") {
            if ($proxy_mode eq "true") {
                if ($line =~ /^\s+(#?)PinnedConnection\s+(.*)/ && $sw == 1) {
                    if ($1 eq "#") {
                        $output = 0;
                        last;
                    }
                    else {
                        $2 =~ s/^\s+//;
                        $output = $2;
                        last;
                    }
                }
                elsif ($sw == 1 && $line =~ /\s+#BackEnd/) {
                    $output = 0;
                    last;
                }
            }
            else {
                $output = undef;
                last;
            }
        }

        #RoutingPolicy tag
        if ($tag eq "routingPolicy") {
            if ($proxy_mode eq "true") {
                if ($line =~ /^\s+(#?)RoutingPolicy\s+(.*)/ && $sw == 1) {
                    if ($1 eq "#") {
                        $output = "ROUND_ROBIN";
                        last;
                    }
                    else {
                        $2 =~ s/^\s+//;
                        $output = $2;
                        last;
                    }
                }
                elsif ($sw == 1 && $line =~ /\s+#BackEnd/) {
                    $output = "ROUND_ROBIN";
                    last;
                }
            }
            else {
                $output = undef;
                last;
            }
        }

        #ReplaceRequestHeader tag
        if ($tag eq "replaceRequestHeader") {
            if ($proxy_mode eq "true") {

                if (   $line =~ /^\s+(#?)ReplaceHeader\s+(.+)\s+"(.+)"\s+"(.+)"\s+"(.*)"/
                    && $sw == 1)
                {
                    if ($1 eq "#") {
                        next;
                    }
                    elsif ($2 eq 'Response') {
                        next;
                    }
                    else {
                        push @{$output},
                          {
                            "id"      => $directive_index++,
                            "header"  => $3,
                            "match"   => $4,
                            "replace" => $5
                          };
                        next;
                    }
                }
                elsif ($sw == 1 && $line =~ /\s+#BackEnd/) {
                    last;
                }
            }
            else {
                $output = undef;
                last;
            }
        }

        #ReplaceResponseHeader tag
        if ($tag eq "replaceResponseHeader") {
            if ($proxy_mode eq "true") {

                if (   $line =~ /^\s+(#?)ReplaceHeader\s+(.+)\s+"(.+)"\s+"(.+)"\s+"(.*)"/
                    && $sw == 1)
                {
                    if ($1 eq "#") {
                        next;
                    }
                    elsif ($2 eq 'Request') {
                        next;
                    }
                    else {
                        push @{$output},
                          {
                            "id"      => $directive_index++,
                            "header"  => $3,
                            "match"   => $4,
                            "replace" => $5
                          };
                        next;
                    }
                }
                elsif ($sw == 1 && $line =~ /\s+#BackEnd/) {
                    last;
                }
            }
            else {
                $output = undef;
                last;
            }
        }

        #RewriteUrl tag
        if ($tag eq "rewriteUrl") {
            if ($proxy_mode eq "true") {
                if (   $line =~ /^\s+(#?)RewriteUrl\s+"(.+)"\s+"(.*)"(\s+last)?/
                    && $sw == 1)
                {
                    if ($1 eq "#") {
                        next;
                    }
                    else {
                        my $last = (defined $4) ? "true" : "false";
                        push @{$output},
                          {
                            "id"      => $directive_index++,
                            "pattern" => $2,
                            "replace" => $3,
                            "last"    => $last
                          };
                        next;
                    }
                }
                elsif ($sw == 1 && $line =~ /\s+#BackEnd/) {
                    last;
                }
            }
            else {
                $output = undef;
                last;
            }
        }

        #RewriteLocation tag
        if ($tag eq "rewriteLocation") {
            if ($proxy_mode eq "true") {

                if (   $line =~ /^\s+(#)?RewriteLocation\s+(\d)\s*(path)?/
                    && $sw == 1)
                {
                    if ($1 eq "#") {
                        next;
                    }
                    else {
                        if    ($2 eq 0) { $output = "disabled"; last; }
                        elsif ($2 eq 1) { $output = "enabled"; }
                        elsif ($2 eq 2) { $output = "enabled-backends"; }

                        if ($3 eq 'path') { $output .= "-path"; }
                        last;
                    }
                }
                elsif ($sw == 1 && $line =~ /\s+#BackEnd/) {
                    $output = "disabled";
                    last;
                }
            }
            else {
                $output = undef;
                last;
            }
        }

        #AddRequestHeader tag
        if ($tag eq "addRequestHeader") {
            if ($proxy_mode eq "true") {
                if (   $line =~ /^\s+(#?)AddHeader\s+"(.+)"/
                    && $sw == 1)
                {
                    if ($1 eq "#") {
                        next;
                    }
                    else {
                        push @{$output},
                          {
                            "id"     => $directive_index++,
                            "header" => $2
                          };
                        next;
                    }
                }
                elsif ($sw == 1 && $line =~ /\s+#BackEnd/) {
                    last;
                }
            }
            else {
                $output = undef;
                last;
            }
        }

        #AddResponseHeader tag
        if ($tag eq "addResponseHeader") {
            if ($proxy_mode eq "true") {
                if (   $line =~ /^\s+(#?)AddResponseHeader\s+"(.+)"/
                    && $sw == 1)
                {
                    if ($1 eq "#") {
                        next;
                    }
                    else {
                        push @{$output},
                          {
                            "id"     => $directive_index++,
                            "header" => $2
                          };
                        next;
                    }
                }
                elsif ($sw == 1 && $line =~ /\s+#BackEnd/) {
                    last;
                }
            }
            else {
                $output = undef;
                last;
            }
        }

        #RemoveRequestHeader tag
        if ($tag eq "removeRequestHeader") {
            if ($proxy_mode eq "true") {
                if (   $line =~ /^\s+(#?)HeadRemove\s+"(.+)"/
                    && $sw == 1)
                {
                    if ($1 eq "#") {
                        next;
                    }
                    else {
                        push @{$output},
                          {
                            "id"      => $directive_index++,
                            "pattern" => $2
                          };
                        next;
                    }
                }
                elsif ($sw == 1 && $line =~ /\s+#BackEnd/) {
                    last;
                }
            }
            else {
                $output = undef;
                last;
            }
        }

        #RemoveResponseHeader tag
        if ($tag eq "removeResponseHeader") {
            if ($proxy_mode eq "true") {
                if (   $line =~ /^\s+(#?)RemoveResponseHeader\s+"(.+)"/
                    && $sw == 1)
                {
                    if ($1 eq "#") {
                        next;
                    }
                    else {
                        push @{$output},
                          {
                            "id"      => $directive_index++,
                            "pattern" => $2
                          };
                        next;
                    }
                }
                elsif ($sw == 1 && $line =~ /\s+#BackEnd/) {
                    last;
                }
            }
            else {
                $output = undef;
                last;
            }
        }

        #backends
        if ($tag eq "backends") {
            if ($line =~ /#BackEnd/ && $sw == 1) {
                $be_section = 1;
            }
            if ($line =~ /Emergency/ && $sw == 1) {
                $be_emerg = 1;
            }
            if ($be_section == 1) {
                if ($line =~ /^\s+End/ && $sw == 1) {
                    if ($sw_ti == 0) {
                        $output_ti = "TimeOut -";
                    }
                    if ($sw_pr == 0) {
                        $output_pr = "Priority -";
                    }
                    if ($sw_w == 0) {
                        $output_w = "Weight 1";
                        $output_w = "Weight 2" if ($be_emerg == 1);
                        $be_emerg = 0;
                    }
                    if ($sw_co == 0) {
                        $output_co = "ConnLimit -";
                    }
                    if ($sw_tag == 0) {
                        $output_tag = "NfMark -";
                    }

                    $output    = "$output $outputa $outputp $output_ti $output_pr $output_w $output_co $output_tag\n";
                    $output_ti = "";
                    $output_pr = "";
                    $sw_ti     = 0;
                    $sw_pr     = 0;
                    $sw_w      = 0;
                    $sw_co     = 0;
                    $sw_tag    = 0;
                }
                elsif ($line =~ /Address/) {
                    $be++;
                    chomp($line);
                    $outputa = "Server $be $line";
                }
                elsif ($line =~ /Port/) {
                    chomp($line);
                    $outputp = "$line";
                }
                elsif ($line =~ /TimeOut/) {
                    chomp($line);

                    #$output = $output . "$line";
                    $output_ti = $line;
                    $sw_ti     = 1;
                }
                elsif ($line =~ /Priority/) {
                    chomp($line);

                    #$output = $output . "$line";
                    $output_pr = $line;
                    $sw_pr     = 1;
                }
                elsif ($line =~ /Weight/) {
                    chomp($line);

                    #$output = $output . "$line";
                    $output_w = $line;
                    $sw_w     = 1;
                }
                elsif ($line =~ /ConnLimit/) {
                    chomp($line);

                    #$output = $output . "$line";
                    $output_co = $line;
                    $sw_co     = 1;
                }
                elsif ($line =~ /NfMark/) {
                    chomp($line);

                    #$output = $output . "$line";
                    $output_tag = $line;
                    $sw_tag     = 1;
                }
            }
            if ($sw == 1 && $be_section == 1 && $line =~ /#End/) {
                last;
            }
        }
    }

    return $output;
}

=pod

=head1 setHTTPFarmVS

Set values for service parameters. The parameters are: vs, urlp, redirect, redirectappend, dynscale, sesstype, ttl, sessionid, httpsbackend or backends

A blank string comment the tag field in config file

Parameters:

    farm_name - Farm name

    service - Service name

    tag - Indicate which parameter modify

    string - value for the field "tag"

Returns:

    Integer - Error code: 0 on success or -1 on failure

=cut

sub setHTTPFarmVS ($farm_name, $service, $tag, $string) {
    my $farm_filename  = &getFarmFile($farm_name);
    my $output         = 0;
    my $sw             = 0;
    my $be_section     = 0;
    my $se_section     = 0;
    my $be_emerg       = 0;
    my $j              = -1;
    my $clean_sessions = 0;

    $string =~ s/^\s+//;
    $string =~ s/\s+$//;

    require Relianoid::Lock;
    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    if ($tag eq 'rewriteLocation') {
        if    ($string eq "disabled")              { $string = "0"; }
        elsif ($string eq "enabled")               { $string = "1"; }
        elsif ($string eq "enabled-backends")      { $string = "2"; }
        elsif ($string eq "enabled-path")          { $string = "1 path"; }
        elsif ($string eq "enabled-backends-path") { $string = "2 path"; }
    }

    require Tie::File;
    tie my @fileconf, 'Tie::File', "$configdir/$farm_filename";

    foreach my $line (@fileconf) {
        $j++;
        if ($line =~ /^\s+Service \"$service\"/) { $sw = 1; }
        if ($line =~ /^\s+#?Session/   && $sw == 1) { $se_section = 1; }
        if ($line =~ /^\s+#?Backend/   && $sw == 1) { $be_section = 1; }
        if ($line =~ /^\s+#?Emergency/ && $sw == 1) { $be_emerg   = 1; }
        if ($line =~ /^\s+End\s*$/     && $sw && !$se_section && !$be_section && !$be_emerg) {
            last;
        }

        next if $sw == 0;

        #vs tag
        if ($tag eq "vs") {
            if ($line =~ /^\s+#?HeadRequire/ && $sw == 1 && $string ne "") {
                $line = "\t\tHeadRequire \"Host: $string\"";
                last;
            }
            if ($line =~ /^\s+#?HeadRequire/ && $sw == 1 && $string eq "") {
                $line = "\t\t#HeadRequire \"Host:\"";
                last;
            }
        }

        #url pattern
        if ($tag eq "urlp") {
            if ($line =~ /^\s+#?Url/ && $sw == 1 && $string ne "") {
                $line = "\t\tUrl \"$string\"";
                last;
            }
            if ($line =~ /^\s+#?Url/ && $sw == 1 && $string eq "") {
                $line = "\t\t#Url \"\"";
                last;
            }
        }

        #dynscale
        if ($tag eq "dynscale") {
            if ($line =~ /^\s+#?DynScale/ && $sw == 1 && $string ne "") {
                $line = "\t\tDynScale 1";
                last;
            }
            if ($line =~ /^\s+#?DynScale/ && $sw == 1 && $string eq "") {
                $line = "\t\t#DynScale 1";
                last;
            }
        }

        #client redirect default
        if ($tag eq "redirect") {
            if ($line =~ /^\s+#?(Redirect(?:Append)?) (30[127] )?.*/) {
                my $policy        = $1;
                my $redirect_code = $2 // '';
                my $comment       = '';
                if ($string eq "") {
                    $comment = '#';
                    $policy  = "Redirect";
                }
                $line = "\t\t${comment}${policy} ${redirect_code}\"${string}\"";
                last;
            }
        }

        #client redirect default
        if ($tag eq "redirecttype") {
            if ($line =~ /^\s+Redirect(?:Append)? (.*)/) {
                my $rest   = $1;
                my $policy = ($string eq 'append') ? 'RedirectAppend' : 'Redirect';

                $line = "\t\t${policy} $rest";
                last;
            }
        }

        #TTL
        if ($tag eq "ttl") {
            if ($line =~ /^\s+#?TTL/ && $sw == 1 && $string ne "") {
                $line = "\t\t\tTTL $string";
                last;
            }
            if ($line =~ /^\s+#?TTL/ && $sw == 1 && $string eq "") {
                $line = "\t\t\t#TTL 120";
                last;
            }
        }

        #session id
        if ($tag eq "sessionid") {
            if ($line =~ /\s+ID|\s+#ID/ && $sw == 1 && $string ne "") {
                $line = "\t\t\tID \"$string\"";
                last;
            }
            if ($line =~ /\s+ID|\s+#ID/ && $sw == 1 && $string eq "") {
                $line = "\t\t\t#ID \"$string\"";
                last;
            }
        }

        #HTTPS Backends tag
        if ($tag eq "httpsbackend") {
            if ($line =~ "##HTTPS-backend##" && $sw == 1 && $string ne "") {

                #turn on
                $line = "\t\t##True##HTTPS-backend##";
            }

            if ($line =~ "##HTTPS-backend##" && $sw == 1 && $string eq "") {

                #turn off
                $line = "\t\t##False##HTTPS-backend##";
            }

            #Delete HTTPS tag in a BackEnd
            if ($sw == 1 && $line =~ /HTTPS$/ && $string eq "") {

                #Delete HTTPS tag
                splice @fileconf, $j, 1,;
            }

            #Add HTTPS tag
            if ($sw == 1 && $line =~ /\s+BackEnd$/ && $string ne "") {
                $line .= "\n\t\t\tHTTPS";
            }

            #go out of the current Service
            if (   $line =~ /\s+Service \"/
                && $sw == 1
                && $line !~ /\s+Service \"$service\"/)
            {
                $tag = "";
                $sw  = 0;
                last;
            }
        }

        #session type
        if ($tag eq "session") {
            require Relianoid::Farm::HTTP::Sessions;
            if ($string ne "nothing" && $se_section) {
                if ($line =~ /^\s+#Session/) {
                    $line = "\t\tSession";
                }
                if ($line =~ /^\s*#End/) {
                    $line = "\t\tEnd";
                }
                if ($line =~ /^\s+#?Type\s+(.*)\s*/) {
                    $line           = "\t\t\tType $string";
                    $clean_sessions = 1 if ($1 ne $string);
                }
                if ($line =~ /^\s+#?TTL/) {
                    $line =~ s/#//g;
                }
                if ($line =~ /\s+#?ID /) {
                    if (   $string eq "URL"
                        || $string eq "COOKIE"
                        || $string eq "HEADER")
                    {
                        $line =~ s/#//g;
                    }
                    else {
                        $line = "#$line";
                    }
                }
            }

            if ($string eq "nothing" && $se_section) {
                if ($line =~ /^\s+Session/) {
                    $line = "\t\t#Session";
                }
                if ($line =~ /^\s*End/) {
                    $line = "\t\t#End";
                }
                if ($line =~ /^\s+TTL/) {
                    $line = "\t\t\t#TTL 120";
                }
                if ($line =~ /^\s+Type/) {
                    $line           = "\t\t\t#Type nothing";
                    $clean_sessions = 1;
                }
                if ($line =~ /^\s+ID |^\s+#ID /) {
                    $line = "\t\t\t#ID \"sessionname\"";
                }
            }
            if ($se_section && $line =~ /^\s*End/) {
                &deleteConfL7FarmAllSession($farm_name, $service)
                  if ($clean_sessions);
                last;
            }
        }

        #PinnedConnection
        if ($tag eq "pinnedConnection") {
            if ($line =~ /^\s+#?PinnedConnection/ && $sw == 1 && $string ne "") {
                $line = "\t\tPinnedConnection $string";
                last;
            }

            if ($sw == 1 && $line =~ /BackEnd/) {
                $line = "\t\tPinnedConnection $string\n" . $line;
                last;
            }
        }

        #RoutingPolicy
        if ($tag eq "routingPolicy") {
            if ($line =~ /^\s+#?RoutingPolicy/ && $sw == 1 && $string ne "") {
                $line = "\t\tRoutingPolicy $string";
                last;
            }

            if ($sw == 1 && $line =~ /BackEnd/) {
                $line = "\t\tRoutingPolicy $string\n" . $line;
                last;
            }
        }

        #RewriteLocation
        if ($tag eq "rewriteLocation") {
            if ($line =~ /^\s+#?RewriteLocation/ && $sw == 1 && $string ne "") {
                $line = "\t\tRewriteLocation $string";
                last;
            }

            if ($sw == 1 && $line =~ /BackEnd/) {
                $line = "\t\tRewriteLocation $string\n" . $line;
                last;
            }
        }

        if ($line =~ /^\s+#?End\s*$/) {
            if    ($se_section) { $se_section = 0; }
            elsif ($be_section) { $be_section = 0; }
            elsif ($be_emerg)   { $be_emerg = 0; }
            elsif ($sw)         { last; }
        }
    }

    untie @fileconf;
    close $lock_fh;

    return $output;
}

=pod

=head1 getFarmVSI

Get the index of a service in a http farm

Parameters:

    farmname - Farm name

    service - Service name

Returns:

    integer - Service index, it returns -1 if the service does not exist

FIXME:

    Rename with intuitive name, something like getHTTPFarmServiceIndex

=cut

sub getFarmVSI ($farm_name, $target_service) {
    my @services = &getHTTPFarmServices($farm_name);
    my $index    = 0;
    foreach my $service (@services) {
        if ($service eq $target_service) {
            return $index;
        }
        $index++;
    }

    return -1;
}

=pod

=head1 get_http_service_struct

FIXME:

    This function is only used in API 3.2. getHTTPServiceStruct should be used.

=cut

sub get_http_service_struct ($farmname, $service_name) {
    require Relianoid::FarmGuardian;
    require Relianoid::Farm::HTTP::Backend;

    my $service_ref = &getHTTPServiceStruct($farmname, $service_name);

    # Backends
    my $backends = &getHTTPFarmBackends($farmname, $service_name);

    # Remove backend status 'undefined', it is for news api versions
    foreach my $be (@{$backends}) {
        $be->{'status'} = 'up' if $be->{'status'} eq 'undefined';
    }

    # Add FarmGuardian
    $service_ref->{farmguardian} = &getFGFarm($farmname, $service_name);

    # Add STS
    if ($eload) {
        $service_ref->{sts_status} = &eload(
            module => 'Relianoid::Farm::HTTP::Service::Ext',
            func   => 'getHTTPServiceSTSStatus',
            args   => [ $farmname, $service_name ],
        );

        $service_ref->{sts_timeout} = int(&eload(
            module => 'Relianoid::Farm::HTTP::Service::Ext',
            func   => 'getHTTPServiceSTSTimeout',
            args   => [ $farmname, $service_name ],
        ));
    }

    return $service_ref;
}

=pod

=head1 get_http_all_services_summary_struct

=cut

sub get_http_all_services_summary_struct ($farmname) {

    # Output
    my @services_list = ();

    foreach my $service (&getHTTPFarmServices($farmname)) {
        push @services_list, { 'id' => $service };
    }

    return \@services_list;
}

=pod

=head1 getHTTPFarmPriorities

Get the list of the backends priorities of the service in a http farm

Parameters:

    farmname - Farm name

    service - Service name

Returns:

    Array Ref - it returns an array ref of priority values

=cut

sub getHTTPFarmPriorities ($farmname, $service_name) {
    my @priorities;
    my $backends = &getHTTPFarmBackends($farmname, $service_name);

    if (&getGlobalConfiguration('proxy_ng') eq 'true') {
        foreach my $backend (@{$backends}) {
            if (defined $backend->{priority}) {
                push @priorities, $backend->{priority};
            }
            else {
                push @priorities, 1;
            }
        }
    }
    else {
        foreach my $backend (@{$backends}) {
            if (defined $backend->{priority} and $backend->{priority} > 1) {
                push @priorities, $backend;
            }
        }
    }
    return \@priorities;
}

1;

