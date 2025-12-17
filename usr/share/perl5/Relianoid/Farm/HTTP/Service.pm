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
    require Tie::File;
    require Relianoid::Lock;
    require Relianoid::File;
    require Relianoid::Farm::Config;

    my $output = -1;

    #first check if service name exist
    if ($service =~ /(?=)/ && $service =~ /^$/) {
        #error 2 eq $service is empty
        $output = 2;
        return $output;
    }

    if (!grep { /^\s*Service "$service"/ } readFileAsArray("$configdir/$farm_name\_proxy.cfg")) {
        #create service
        my @newservice;
        my $sw       = 0;
        my $count    = 0;
        my $poundtpl = &getGlobalConfiguration('poundtpl');

        tie my @poundtpl, 'Tie::File', "$poundtpl";

        for my $line (@poundtpl) {
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

        untie @poundtpl;

        $newservice[0]  =~ s/#//g;
        $newservice[-1] =~ s/#//g;

        my $lock_file = &getLockFile($farm_name);
        my $lock_fh   = &openlock($lock_file, 'w');

        my @fileconf;
        if (!grep { /^\s*Service "$service"/ } readFileAsArray("$configdir/$farm_name\_proxy.cfg")) {
            tie @fileconf, 'Tie::File', "$configdir/$farm_name\_proxy.cfg";

            my $i         = 0;
            my $farm_type = &getFarmType($farm_name) // "";

            for my $line (@fileconf) {
                if ($line =~ /#ZWACL-END/) {
                    $output = 0;

                    for my $lline (@newservice) {
                        if ($lline =~ /\[DESC\]/) {
                            $lline =~ s/\[DESC\]/$service/;
                        }

                        if ($lline =~ /StrictTransportSecurity/ && $farm_type eq "https") {
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
        unlink $lock_file;
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
    require Tie::File;
    require Relianoid::Lock;
    require Relianoid::File;
    require Relianoid::Farm::Config;

    my $output = -1;

    #first check if service name exist
    if ($service =~ /(?=)/ && $service =~ /^$/) {
        #error 2 eq $service is empty
        $output = 2;
        return $output;
    }

    if (!grep { /^\s*Service "$service"/ } readFileAsArray("$configdir/$farm_name\_proxy.cfg")) {
        #create service
        my @newservice;
        my $sw       = 0;
        my $count    = 0;
        my $poundtpl = &getGlobalConfiguration('poundtpl');

        tie my @poundtpl, 'Tie::File', "$poundtpl";

        for my $line (@poundtpl) {
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

        untie @poundtpl;

        $newservice[0]  =~ s/#//g;
        $newservice[-1] =~ s/#//g;

        my $lock_file = &getLockFile($farm_name);
        my $lock_fh   = &openlock($lock_file, 'w');
        my @fileconf;

        if (!grep { /^\s*Service "$service"/ } readFileAsArray("${configdir}/${farm_name}_proxy.cfg")) {
            tie @fileconf, 'Tie::File', "$configdir/$farm_name\_proxy.cfg";

            my $i         = 0;
            my $farm_type = "";
            $farm_type = &getFarmType($farm_name);

            for my $line (@fileconf) {
                if ($line =~ /#ZWACL-INI/) {
                    $output = 0;

                    for my $lline (@newservice) {
                        if ($lline =~ /\[DESC\]/) {
                            $lline =~ s/\[DESC\]/$service/;
                        }

                        if ($lline =~ /StrictTransportSecurity/ && $farm_type eq "https") {
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
        unlink $lock_file;
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

        if ($sw) {
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
    unlink $lock_file;

    # delete service's backends  in status file
    if ($counter > -1) {
        while ($counter > -1) {
            require Relianoid::Farm::HTTP::Backend;
            &runRemoveHTTPBackendStatus($farm_name, $counter, $service);
            $counter--;
        }
    }

    # change the ID value of services with an ID higher than the service deleted (value - 1)
    tie my @contents, 'Tie::File', "$configdir\/$farm_name\_status.cfg";
    for my $line (@contents) {
        my @params = split(" ", $line);
        my $newval = $params[2] - 1;

        if ($params[2] > $sindex) {
            my $old = join " ", @params;
            $params[2] = $newval;
            my $new = join " ", @params;
            $line =~ s/$old/$new/g;
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

    $service_ref->{$service_name} - Service index

FIXME:

    &getHTTPFarmVS(farmname) does same but in a string

=cut

sub getHTTPFarmServices ($farm_name, $service_name = undef) {
    require Relianoid::Farm::Core;

    my $farm_filename = &getFarmFile($farm_name);
    my @output        = ();

    open my $fh, '<', "${configdir}/${farm_filename}";
    my @file = <$fh>;
    close $fh;

    my $index = 0;
    for my $line (@file) {
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

    farm_name - Farm name
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

=cut

sub getHTTPServiceStruct ($farm_name, $service_name) {
    require Relianoid::FarmGuardian;
    require Relianoid::Farm::HTTP::Backend;

    # http services
    my $services_str = &getHTTPFarmVS($farm_name, "", "");
    my @services     = split(' ', $services_str);

    # return error if service is not found
    return unless grep ({ $service_name eq $_ } @services);

    my $service = {
        id           => $service_name,
        vhost        => &getHTTPFarmVS($farm_name, $service_name, "vs"),
        urlp         => &getHTTPFarmVS($farm_name, $service_name, "urlp"),
        redirect     => &getHTTPFarmVS($farm_name, $service_name, "redirect"),
        redirecttype => &getHTTPFarmVS($farm_name, $service_name, "redirecttype"),
        persistence  => &getHTTPFarmVS($farm_name, $service_name, "sesstype"),
        ttl          => &getHTTPFarmVS($farm_name, $service_name, "ttl"),
        sessionid    => &getHTTPFarmVS($farm_name, $service_name, "sessionid"),
        leastresp    => &getHTTPFarmVS($farm_name, $service_name, "dynscale")     || "false",
        httpsb       => &getHTTPFarmVS($farm_name, $service_name, "httpsbackend") || "false",
        backends     => &getHTTPFarmBackends($farm_name, $service_name),
        farmguardian => &getFGFarm($farm_name, $service_name),
    };
    # Remove backend status 'undefined', it is for news api versions
    for my $be (@{ $service->{backends} }) {
        $be->{status} = 'up' if $be->{status} eq 'undefined';
    }

    if ($eload) {
        $service->{backends} = &eload(
            module => 'Relianoid::EE::Alias',
            func   => 'addAliasBackendsStruct',
            args   => [ $service->{backends} ],
        );

        $service = &eload(
            module => 'Relianoid::EE::Farm::HTTP::Service::Ext',
            func   => 'add_service_cookie_insertion',
            args   => [ $farm_name, $service ],
        );

        $service->{redirect_code} = &eload(
            module => 'Relianoid::EE::Farm::HTTP::Service::Ext',
            func   => 'getHTTPServiceRedirectCode',
            args   => [ $farm_name, $service_name ],
        );
        $service->{sts_status} = &eload(
            module => 'Relianoid::EE::Farm::HTTP::Service::Ext',
            func   => 'getHTTPServiceSTSStatus',
            args   => [ $farm_name, $service_name ],
        );

        $service->{sts_timeout} = &eload(
            module => 'Relianoid::EE::Farm::HTTP::Service::Ext',
            func   => 'getHTTPServiceSTSTimeout',
            args   => [ $farm_name, $service_name ],
        );
    }

    return $service;
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

    for my $service (@services) {
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
    my $farm_filename = &getFarmFile($farm_name);
    my $output        = "";

    my $directive_index = 0;
    my @lines           = ();

    if (open my $fh, '<', "${configdir}/${farm_filename}") {
        @lines = <$fh>;
        close $fh;
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
    my $outputa;
    my $outputp;
    my @return;

    for my $line (@lines) {
        if ($line =~ /^\s*Service \"$service\"/) { $sw         = 1; }
        if ($line =~ /^\s*Session/ && $sw)       { $se_section = 1; }
        if ($line =~ /^\s*End\s*$/) {
            if    ($se_section)                { $se_section = 0; }
            elsif (!$be_section && !$be_emerg) { $sw         = 0; }
        }

        # returns all services for this farm
        if ($tag eq "" && $service eq "") {
            if ($line =~ /^\s*Service\ \"/) {
                @return = split("\ ", $line);
                $return[1] =~ s/\"//g;
                $return[1] =~ s/^\s+//;
                $return[1] =~ s/\s+$//;
                $output = "$output $return[1]";
            }
        }

        #vs tag
        if ($tag eq "vs") {
            if ($line =~ /^\s*HeadRequire/ && $sw) {
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
            if ($line =~ /^\s*Url \"/ && $sw) {
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
            if ($line =~ /^\s*Redirect(?:Append)?\s/ && $sw) {
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
            if ($line =~ /^\s*Redirect(?:Append)?\s/ && $sw) {
                if    ($line =~ /Redirect /)       { $output = "default"; }
                elsif ($line =~ /RedirectAppend /) { $output = "append"; }
                last;
            }
        }

        # leastresp
        if ($tag eq "dynscale") {
            if ($line =~ /^\s*DynScale\ / && $sw) {
                $output = "true";
                last;
            }
        }

        #######################
        # Session has 3 fields:
        # - Type
        # - TTL
        # - ID

        # session type
        # only get the session type when it's not commented
        if ($tag eq "sesstype") {
            if ($line =~ /^\s*Type/ && $sw) {
                @return = split(" ", $line);
                $return[1] =~ s/\"//g;
                $return[1] =~ s/^\s+//;
                $return[1] =~ s/\s+$//;
                $output = $return[1];
                last;
            }
        }

        # session ttl
        # Get ttl value whether the line is commented or not
        if ($tag eq "ttl") {
            if ($line =~ /^[\s#]*TTL/ && $sw) {
                @return = split(" ", $line);
                $return[1] =~ s/\"//g;
                $return[1] =~ s/^\s+//;
                $return[1] =~ s/\s+$//;
                $output = $return[1] + 0;
                last;
            }
        }

        # session id
        # only get the session name when it's not commented
        # Format: sessionid "sessionname"
        if ($tag eq "sessionid") {
            if ($line =~ /^\s*ID/ && $sw) {
                @return = split(" ", $line);
                $return[1] =~ s/\"//g;
                $return[1] =~ s/^\s+//;
                $return[1] =~ s/\s+$//;
                $output = $return[1];
                last;
            }
        }

        # End of session section
        ########################

        #HTTPS tag
        if ($tag eq "httpsbackend") {
            if ($line =~ "##True##HTTPS-backend##" && $sw) {
                $output = "true";
                last;
            }
        }

        #backends
        if ($tag eq "backends") {
            if ($line =~ /^\s*BackEnd|^\s*Emergency/ && $sw) {
                $be_section = 1;
            }
            if ($line =~ /^\s*Emergency/ && $sw) {
                $be_emerg = 1;
            }
            if ($be_section) {
                if ($line =~ /^\s*End/ && $sw) {
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

                    my @line_parts = ($output, $outputa, $outputp, $output_ti, $output_pr, $output_w);
                    $output    = join(" ", @line_parts) . "\n";
                    $output_ti = "";
                    $output_pr = "";
                    $sw_ti     = 0;
                    $sw_pr     = 0;
                    $sw_w      = 0;
                }
                elsif ($line =~ /^\s*Address/) {
                    $be++;
                    chomp($line);
                    $outputa = "Server $be $line";
                }
                elsif ($line =~ /^\s*Port/) {
                    chomp($line);
                    $outputp = "$line";
                }
                elsif ($line =~ /^\s*TimeOut/) {
                    chomp($line);

                    #$output = $output . "$line";
                    $output_ti = $line;
                    $sw_ti     = 1;
                }
                elsif ($line =~ /^\s*Priority/) {
                    chomp($line);

                    #$output = $output . "$line";
                    $output_pr = $line;
                    $sw_pr     = 1;
                }
                elsif ($line =~ /^\s*Weight/) {
                    chomp($line);

                    #$output = $output . "$line";
                    $output_w = $line;
                    $sw_w     = 1;
                }
            }
            if ($sw && $be_section && $line =~ /#End/) {
                last;
            }
        }
    }

    return $output;
}

=pod

=head1 setHTTPFarmVS

Set values for service parameters. The parameters are: vs, urlp, redirect, redirectappend, dynscale, sesstype, ttl, sessionid, httpsbackend or backends

An empty string/value will comment the tag/attribute/field in config file.

Examples of service section:

	Service "newservice"
		##False##HTTPS-backend##
		#DynScale 1
		#BackendCookie "NOIDSESSIONID" "" "/" 3600
		#HeadRequire "Host: "
		#Url ""
		#Redirect ""
		#StrictTransportSecurity 21600000
		#Session
			#Type nothing
			#TTL 120
			#ID "sessionname"
		#End
		#BackEnd

		#End
	End

	Service "newservice"
		##False##HTTPS-backend##
		DynScale 1
		BackendCookie "TESTING" "domaintesting.com" "/a" 17
		HeadRequire "Host: www.mywebserver.com"
		Url "^/myapp1$"
		Redirect 302 "http://www.mysite.com"
		#StrictTransportSecurity 21600000
		Session
			Type URL
			TTL 120
			ID "sessionname"
		End
		#BackEnd

		#End
	End

Parameters:

    farm_name - Farm name
    service   - Service name
    tag       - Indicate which parameter modify
    string    - value for the field "tag"

Returns:

    Integer - Error code: 0 on success or -1 on failure

=cut

sub setHTTPFarmVS ($farm_name, $service, $tag, $string = '') {
    my $farm_filename  = &getFarmFile($farm_name);
    my $output         = 0;
    my $in_service     = 0;                          # Found service block
    my $be_section     = 0;
    my $se_section     = 0;
    my $clean_sessions = 0;
    my $line_index     = -1;

    $string =~ s/^\s+//;
    $string =~ s/\s+$//;

    require Relianoid::Lock;
    my $lock_file = &getLockFile($farm_name);
    my $lock_fh   = &openlock($lock_file, 'w');

    require Tie::File;
    tie my @fileconf, 'Tie::File', "$configdir/$farm_filename";

    for my $line (@fileconf) {
        $line_index++;
        if ($line =~ /^\s*Service "$service"/)                 { $in_service = 1; next; }
        if ($line =~ /^\s*Session/ && $in_service)             { $se_section = 1; }
        if ($line =~ /^\s*(BackEnd|Emergency)/ && $in_service) { $be_section = 1; }

        if ($line =~ /^\s*End\s*$/ && $in_service && !$se_section && !$be_section) { last; }
        if ($in_service && $line =~ /\s*Service "/ && $line !~ /\s*Service "$service"/) { last; }

        next if not $in_service;

        # vhost or vs tag
        if ($tag eq "vs") {
            if ($line =~ /^[\s#]*HeadRequire / && $string ne "") {
                $line = "\t\tHeadRequire \"Host: $string\"";
                last;
            }
            if ($line =~ /^[\s#]*HeadRequire / && $string eq "") {
                $line = "\t\t#HeadRequire \"Host:\"\n";
                last;
            }
        }

        # urlp or url pattern
        if ($tag eq "urlp") {
            if ($line =~ /^[\s#]*Url / && $string ne "") {
                $line = "\t\tUrl \"$string\"";
                last;
            }
            if ($line =~ /^[\s#]*Url / && $string eq "") {
                $line = "\t\t#Url \"\"";
                last;
            }
        }

        # leastresp or dynscale tag
        if ($tag eq "dynscale") {
            if ($line =~ /^[\s#]*DynScale / && $string ne "") {
                $line = "\t\tDynScale 1";
                last;
            }
            if ($line =~ /^[\s#]*DynScale / && $string eq "") {
                $line = "\t\t#DynScale 1";
                last;
            }
        }

        # client redirect default
        if ($tag eq "redirect") {
            if ($line =~ /^[\s#]*(Redirect(?:Append)?) (30[127] )?.*/) {
                my $policy        = $string ? $1 : "Redirect";
                my $redirect_code = $2 // '';
                my $comment       = $string ? '' : '#';
                $line = qq(\t\t${comment}${policy} ${redirect_code}"${string}");
                last;
            }
        }

        # redirecttype
        if ($tag eq "redirecttype") {
            if ($line =~ /^[\s#]*Redirect(?:Append)? (.*)/) {
                my $rest    = $1;
                my $policy  = $string eq 'append' ? 'RedirectAppend' : 'Redirect';
                my $comment = $string             ? ''               : '#';
                $line = "\t\t${comment}${policy} $rest";
                last;
            }
        }

        # ttl
        if ($tag eq "ttl") {
            if ($line =~ /^[\s#]*TTL / && $string ne "") {
                $line = "\t\t\tTTL $string";
                last;
            }
            if ($line =~ /^[\s#]*TTL / && $string eq "") {
                $line = "\t\t\t#TTL 120";
                last;
            }
        }

        # session id
        if ($tag eq "sessionid") {
            if ($line =~ /^[\s#]*ID / && $string ne "") {
                $line = "\t\t\tID \"$string\"";
                last;
            }
            if ($line =~ /^[\s#]*ID / && $string eq "") {
                $line = "\t\t\t#ID \"$string\"";
                last;
            }
        }

        # httpsb or HTTPS Backends tag
        if ($tag eq "httpsbackend") {
            if ($line =~ "##HTTPS-backend##" && $string ne "") {
                #turn on
                $line = "\t\t##True##HTTPS-backend##";
            }
            elsif ($line =~ "##HTTPS-backend##" && $string eq "") {
                #turn off
                $line = "\t\t##False##HTTPS-backend##";
            }

            #Delete HTTPS tag in a BackEnd
            if ($line =~ /^\s*HTTPS$/ && $string eq "") {
                #Delete HTTPS tag
                splice @fileconf, $line_index, 1,;
            }

            #Add HTTPS tag
            if ($line =~ /^\s*(BackEnd|Emergency)$/ && $string ne "") {
                $line .= "\n\t\t\tHTTPS";
            }
        }

        # session type
        if ($tag eq "session") {
            # Session section enabled
            if ($string ne "nothing") {
                if ($line =~ /^[\s#]*Session/) {
                    $line = "\t\tSession";
                }
                elsif ($line =~ /^[\s#]*End/) {
                    $line = "\t\tEnd";
                    last;
                }
                elsif ($line =~ /^[\s#]*Type\s+(.*)\s*/) {
                    $line           = "\t\t\tType $string";
                    $clean_sessions = 1 if $1 ne $string;
                }
                elsif ($line =~ /^[\s#]*TTL /) {
                    $line =~ s/#//g;
                }
                elsif ($line =~ /^[\s#]*ID /) {
                    if (grep { $string eq $_ } ("URL", "COOKIE", "HEADER")) {
                        $line =~ s/#//g;
                    }
                    else {
                        $line = "#$line";
                    }
                }
            }
            # Session section disabled
            else {
                if ($line =~ /^[\s#]*Session/) {
                    $line = "\t\t#Session";
                }
                elsif ($line =~ /^[\s#]*End/) {
                    $line = "\t\t#End";
                    last;
                }
                elsif ($line =~ /^[\s#]*TTL /) {
                    $line = "\t\t\t#TTL 120";
                }
                elsif ($line =~ /^[\s#]*Type /) {
                    $line           = "\t\t\t#Type nothing";
                    $clean_sessions = 1;
                }
                elsif ($line =~ /^[\s#]*ID /) {
                    $line = "\t\t\t#ID \"sessionname\"";
                }
            }
        }
    }

    untie @fileconf;
    close $lock_fh;
    unlink $lock_file;

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

    for my $service (@services) {
        if ($service eq $target_service) {
            return $index;
        }
        $index++;
    }

    return -1;
}

=pod

=head1 get_http_all_services_summary_struct

=cut

sub get_http_all_services_summary_struct ($farmname) {
    # Output
    my @services_list = ();

    for my $service (&getHTTPFarmServices($farmname)) {
        push @services_list, { id => $service };
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

    for my $backend (@{$backends}) {
        if (defined $backend->{priority} and $backend->{priority} > 1) {
            push @priorities, $backend;
        }
    }

    return \@priorities;
}

1;

