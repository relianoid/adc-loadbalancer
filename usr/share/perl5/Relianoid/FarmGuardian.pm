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

use Carp;
use Relianoid::Log;
use Config::Tiny;

my $configdir   = &getGlobalConfiguration("configdir");
my $fg_conf     = "$configdir/farmguardian.conf";
my $fg_template = &getGlobalConfiguration("templatedir") . "/farmguardian.template";

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::FarmGuardian

=cut

=pod

=head1 getFGStatusFile

The function returns the path of the file that is used to save the backend status for a farm.

Parameters:

    fname - Farm name

Returns:

    String - file path

=cut

sub getFGStatusFile ($farm) {
    return "$configdir\/$farm\_status.cfg";
}

=pod

=head1 getFGStruct

It returns a default struct with all farmguardian parameters

Parameters:

    none

Returns:

    Hash ref - hash with the available parameters of fg

    example:

    {
        description   => "",       # Tiny description about the check
        command       => "",       # Command to check. The check must return 0 on sucess
        farms         => [],       # farm list where the farm guardian is applied
        log           => "false",  # logg farm guardian
        interval      => "10",     # Time between checks
        cut_conns     => "false",  # cut the connections with the backend is marked as down
        template      => "false",  # it is a template. The fg cannot be deleted, only reset its configuration
        backend_alias => "false",  # Use the backend alias to do the farmguardian check. The load balancer must resolve the alias
    }

=cut

sub getFGStruct() {
    return {
        description   => "",         # Tiny description about the check
        command       => "",         # Command to check. The check must return 0 on sucess
        farms         => [],         # farm list where the farm guardian is applied
        log           => "false",    # logg farm guardian
        interval      => "10",       # Time between checks
        cut_conns     => "false",    # cut the connections with the backend is marked as down
        template      => "false",
        backend_alias => "false",
    };
}

=pod

=head1 getFGExistsConfig

It checks out if the fg already exists in the configuration file.

Parameters:

    Farmguardian - Farmguardian name

Returns:

    Integer - 1 if the fg already exists or 0 if it is not

=cut

sub getFGExistsConfig ($fg_name) {
    if (!-f "$fg_conf") {
        return 0;
    }
    my $fh = Config::Tiny->read($fg_conf);
    return (exists $fh->{$fg_name}) ? 1 : 0;
}

=pod

=head1 getFGExistsTemplate

It checks out if a template farmguardian exists with this name.

Parameters:

    Farmguardian - Farmguardian name

Returns:

    Integer - 1 if the fg exists or 0 if it is not

=cut

sub getFGExistsTemplate ($fg_name) {
    if (!-f "$fg_template") {
        return 0;
    }
    my $fh = Config::Tiny->read($fg_template);
    return (exists $fh->{$fg_name}) ? 1 : 0;
}

=pod

=head1 getFGExists

It checks out if the fg exists, in the template file or in the configuraton file

Parameters:

    Farmguardian - Farmguardian name

Returns:

    Integer - 1 if the fg already exists or 0 if it is not

=cut

sub getFGExists ($fg_name) {
    return (&getFGExistsTemplate($fg_name) or &getFGExistsConfig($fg_name));
}

=pod

=head1 getFGConfigList

It returns a list of farmguardian names of the configuration file

Parameters:

    None

Returns:

    Array - List of fg names

=cut

sub getFGConfigList() {
    if (!-f "$fg_conf") {
        return ();
    }

    my $fg_file = Config::Tiny->read($fg_conf);
    return keys %{$fg_file};
}

=pod

=head1 getFGTemplateList

It returns a list of farmguardian names of the template file

Parameters:

    None

Returns:

    Array - List of fg names

=cut

sub getFGTemplateList() {
    if (!-f "$fg_template") {
        return ();
    }
    my $fg_file = Config::Tiny->read($fg_template);
    return keys %{$fg_file};
}

=pod

=head1 getFGList

It is a list with all fg, templates and created by the user

Parameters:

    None

Returns:

    Array - List of fg names

=cut

sub getFGList() {
    my @list = &getFGConfigList();

    # get from template file
    for my $fg (&getFGTemplateList()) {
        next if grep { $fg eq $_ } @list;
        push @list, $fg;
    }

    return @list;
}

=pod

=head1 getFGObject

Get the configuration of a farmguardian

Parameters:

    fg_name - Farmguardian name
    use_template - If this parameter has the value "template", the function returns the object from the template file

Returns:

    Hash ref - It returns a hash with the configuration of the farmguardian

    example:

    hash => {
        description   => "",       # Tiny description about the check
        command       => "",       # Command to check. The check must return 0 on sucess
        farms         => [],       # farm list where the farm guardian is applied
        log           => "false",  # log farm guardian
        interval      => "10",     # Time between checks
        cut_conns     => "false",  # cut the connections with the backend is marked as down
        template      => "false",  # it is a template. The fg cannot be deleted, only reset its configuration
        backend_alias => "false",  # Use the backend alias to do the farmguardian check. The load balancer must resolve the alias
    };

=cut

sub getFGObject ($fg_name, $use_template = '') {
    unless ($fg_name) {
        croak("Farmguardian name required");
    }

    my $file = "";

    # using template file if this parameter is sent
    if ($use_template eq 'template') {
        $file = $fg_template;
    }

    # using farmguardian config file by default
    elsif (grep { $fg_name eq $_ } &getFGConfigList()) {
        $file = $fg_conf;
    }

    # using template file if farmguardian is not defined in config file
    else { $file = $fg_template; }

    my $obj;
    if (!-f "$file") {
        require Relianoid::File;
        createFile($file);
        $obj = Config::Tiny->new;
        return $obj;
    }

    $obj = Config::Tiny->read($file);

    if (!defined $fg_name || $fg_name =~ /^$/) {
        return $obj;
    }

    if (exists $obj->{$fg_name}) {
        $obj = $obj->{$fg_name};
        $obj = &setConfigStr2Arr($obj, ['farms']);
        return $obj;
    }

    return;
}

=pod

=head1 getFGFarm

Get the farmguardian name that a farm is using

Parameters:

    farm    - string - Farm name
    service - string - Optional. Service of the farm. This parameter is mandatory for HTTP and GSLB farms

Returns: string|undef - Farmguardian name if found or undef if not found.

=cut

sub getFGFarm ($farm, $service = undef) {
    my $farmguardian = undef;
    my $farm_tag     = $service ? "${farm}_${service}" : $farm;

    if (!-f $fg_conf) {
        return $farmguardian;
    }

    my $fg_list = Config::Tiny->read($fg_conf);

    for my $fg_name (keys %{$fg_list}) {
        next if not exists $fg_list->{$fg_name}{farms};

        if (grep { /(^| )$farm_tag( |$)/ } $fg_list->{$fg_name}{farms}) {
            $farmguardian = $fg_name;
            last;
        }
    }

    return $farmguardian;
}

=pod

=head1 createFGBlank

Create a fg without configuration

Parameters:

    Name - Farmguardian name

Returns:

    none

=cut

sub createFGBlank ($name) {
    my $values = &getFGStruct();
    &setFGObject($name, $values);

    return;
}

=pod

=head1 createFGTemplate

Create a fg from a template

Parameters:

    Farmguardian - Farmguardian name
    template - If this parameter has the value "template", the function returns the object from the template file

Returns:

    None

=cut

sub createFGTemplate ($name, $template) {
    my $values = &getFGObject($template, 'template');
    return if (!defined $values);
    $values->{template} = "false";

    &setFGObject($name, $values);

    return;
}

=pod

=head1 createFGConfig

Create a farm guardian from another farm guardian

Parameters:

    Farmguardian - Farmguardian name
    template - Farmguardian name of the fg used as template

Returns:

    None

=cut

sub createFGConfig ($name, $fg_config) {
    my $values = &getFGObject($fg_config);
    $values->{farms} = [];
    &setFGObject($name, $values);

    return;
}

=pod

=head1 delFGObject

Remove a farmguardianfrom the configuration file. First, it stops it.
This function will restart the fg process.

Parameters:

    Farmguardian - Farmguardian name

Returns:

    Integer - 0 on success or another value on failure

=cut

sub delFGObject ($fg_name) {
    my $out = &runFGStop($fg_name);
    $out = &delTinyObj($fg_conf, $fg_name);

    return $out;
}

=pod

=head1 setFGObject

Set a configuration for fg.
This function has 2 behaviour:

    * passing to the function a hash with several parameters
    * passing to the function 2 parameters, key and value. So, only is updated one parater.

If the farmguardian name is not found in the configuration file, the configuraton will be got
from the template file and save it in the configuration file.

This function will restart the fg process

Parameters:

    Farmguardian - Farmguardian name
    object / key - object: hash reference with a set of parameters, or key: parameter name to set
    value        - value for the "key"

Returns:

    Integer - 0 on success or another value on failure

=cut

sub setFGObject ($fg_name, $key = undef, $value = undef) {
    my $restart = 0;
    my $out     = 0;

    # not restart if only is changed the parameter description
    if (&getFGExistsConfig($fg_name)) {
        if (@{ &getFGRunningFarms($fg_name) }) {
            if (ref $key and grep { !/^description$/ } keys %{$key}) {
                $restart = 1;
            }
            elsif ($key ne 'description') { $restart = 1; }
        }
    }

    # if the fg does not exist in config file, take it from template file
    unless (&getFGExistsConfig($fg_name)) {
        my $template = &getFGObject($fg_name, 'template');

        if (defined $template) {
            $out = &setTinyObj($fg_conf, $fg_name, $template);
        }
    }

    $out = &runFGStop($fg_name) if $restart;
    $out = &setTinyObj($fg_conf, $fg_name, $key, $value);
    $out = &runFGStart($fg_name) if $restart;

    if ($eload) {
        $out += &eload(
            module => 'Relianoid::EE::Farm::GSLB::FarmGuardian',
            func   => 'updateGSLBFg',
            args   => [$fg_name],
        );
    }

    return $out;
}

=pod

=head1 setFGFarmRename

Re-asign farmguardian to a farm that has been renamed

Parameters:

    old name - Old farm name
    new name - New farm name

Returns:

    Integer - 0 on success or another value on failure

=cut

sub setFGFarmRename ($farm, $new_farm) {
    my $fh;
    my $srv;
    my $farm_tag;
    my $new_farm_tag;
    my $out;

    if (!-f $fg_conf) {
        return 1;
    }
    $fh = Config::Tiny->read($fg_conf);

    # foreach farm check, remove and add farm
    for my $fg (keys %{$fh}) {
        if ($fh->{$fg}{farms} =~ /(?:^| )${farm}_?([\w-]+)?(?:$| )/) {
            $srv          = $1;
            $farm_tag     = ($srv) ? "${farm}_$srv"     : $farm;
            $new_farm_tag = ($srv) ? "${new_farm}_$srv" : $new_farm;

            $out = &setTinyObj($fg_conf, $fg, 'farms', $farm_tag,     'del');
            $out = &setTinyObj($fg_conf, $fg, 'farms', $new_farm_tag, 'add');

            my $status_file     = &getFGStatusFile($farm);
            my $new_status_file = &getFGStatusFile($new_farm);
            &log_info("renaming $status_file =>> $new_status_file") if &debug();
            rename $status_file, $new_status_file;
        }
    }

    return $out;
}

=pod

=head1 linkFGFarm

Assign a farmguardian to a farm (or service of a farm).
Farmguardian will run if the farm is up.

Parameters:

    Farmguardian - Farmguardian name
    Farm         - Farm name
    Service      - Service name. It is used for GSLB and HTTP farms

Returns: integer - errno

- 0: success
- !0: error

=cut

sub linkFGFarm ($fg_name, $farm, $srv = undef) {
    croak("Farmguardian name required") unless ($fg_name);
    croak("Farm name required")         unless ($farm);

    my $out;

    require Relianoid::Farm::Base;
    my $farm_tag = ($srv) ? "${farm}_$srv" : "$farm";

    # if the fg does not exist in config file, take it from template file
    unless (&getFGExistsConfig($fg_name)) {
        my $template = &getFGObject($fg_name, 'template');
        if (defined $template) {
            $out = &setTinyObj($fg_conf, $fg_name, $template);
            return $out if $out;
        }
    }

    $out = &setTinyObj($fg_conf, $fg_name, 'farms', $farm_tag, 'add');
    return $out if $out;

    if (&getFarmType($farm) eq 'gslb' and $eload) {
        $out = &eload(
            module => 'Relianoid::EE::Farm::GSLB::FarmGuardian',
            func   => 'linkGSLBFg',
            args   => [ $fg_name, $farm, $srv ],
        );
    }
    elsif (&getFarmStatus($farm) eq 'up') {
        $out = &runFGFarmStart($farm, $srv);
    }

    return $out;
}

=pod

=head1 unlinkFGFarm

Remove a farmguardian from a farm (or service of a farm).
Farmguardian will be stopped if it is running.

Parameters:

    Farmguardian - Farmguardian name
    Farm         - Farm name
    Service      - Service name. It is used for GSLB and HTTP farms

Returns: integer - errno

- 0: success
- !0: error

=cut

sub unlinkFGFarm ($fg_name, $farm, $srv = undef) {
    my $type = &getFarmType($farm);

    require Relianoid::Log;

    my $farm_tag = ($srv) ? "${farm}_$srv" : "$farm";
    my $out;

    $out = &setTinyObj($fg_conf, $fg_name, 'farms', $farm_tag, 'del');
    return $out if $out;

    if (($type eq 'gslb') and $eload) {
        $out = &eload(
            module => 'Relianoid::EE::Farm::GSLB::FarmGuardian',
            func   => 'unlinkGSLBFg',
            args   => [ $farm, $srv ],
        );
    }
    else {
        $out = &runFGFarmStop($farm, $srv);
    }

    return $out;
}

=pod

=head1 delFGFarm

Function used if a farm is deleted. All farmguardian assigned to it will be unliked.

Parameters:

    Farm    - Farm name
    Service - Service name. It is used for GSLB and HTTP farms

Returns:

    None

=cut

sub delFGFarm ($farm, $service = undef) {
    require Relianoid::Farm::Service;

    my $err  = &runFGFarmStop($farm, $service);
    my $type = &getFarmType($farm);

    # NOT MATCH qw(http https gslb eproxy)
    if (!grep { $type eq $_ } qw(http https gslb eproxy)) {
        if (my $fg = &getFGFarm($farm)) {
            $err |= &setTinyObj($fg_conf, $fg, 'farms', $farm, 'del');
        }

        return;
    }

    # MATCH qw(http https gslb eproxy)
    my @services = $service ? ($service) : &getFarmServices($farm);

    for my $service (@services) {
        if (my $fg = &getFGFarm($farm, $service)) {
            $err |= &setTinyObj($fg_conf, $fg, 'farms', "${farm}_${service}", 'del');
        }
    }

    return;
}

############# run process

=pod

=head1 getFGPidFile

Get the path of the file where the pid of the farmguardian is saved.

Parameters:

    Farm - Farm name
    Service - Service name. It is used for GSLB and HTTP farms. It expects 'undef' for l4 farms

Returns:

    String - Pid file path.

=cut

sub getFGPidFile ($fname, $svice = undef) {
    my $piddir = &getGlobalConfiguration('piddir');
    my $file;

    if (defined $svice and length $svice) {
        # return a regexp for a farm the request service
        $file = "$piddir/${fname}_${svice}_guardian.pid";
    }
    else {
        # return a regexp for a farm and all its services
        $file = "$piddir/${fname}_guardian.pid";
    }

    return $file;
}

=pod

=head1 getFGPidFarm

It returns the farmguardian PID assigned to a farm (and service)

Parameters:

    Farm - Farm name
    Service - Service name. It is used for GSLB and HTTP farms

Returns:

    Integer - 0 on failure, or a natural number for PID

=cut

sub getFGPidFarm ($farm, $service = undef) {
    my $pid     = 0;
    my $pidFile = &getFGPidFile($farm, $service);

    if (!-f "$pidFile") {
        return $pid;
    }

    open my $fh, '<', $pidFile or return 0;
    $pid = <$fh>;
    close $fh;

    my $run;

    # check if the pid exists
    if ($pid > 0) {
        $run = kill 0, $pid;
    }

    # if it does not exist, remove the pid file
    if (!$run) {
        $pid = 0;
        unlink $pidFile;
    }

    # return status
    return $pid;
}

=pod

=head1 runFGStop

It stops all farmguardian process are using the passed fg name

Parameters:

    Farmguardian - Farmguardian name

Returns: integer - errno

- 0: success
- !0: error

=cut

sub runFGStop ($fgname) {
    &log_debug("Stopping farmguardian $fgname", "FG");

    my $out;
    my $obj = &getFGObject($fgname);

    for my $farm (@{ $obj->{farms} }) {
        my $srv;
        if ($farm =~ /([^_]+)_(.+)/) {
            $farm = $1;
            $srv  = $2;
        }

        $out |= &runFGFarmStop($farm, $srv);
    }

    return $out;
}

=pod

=head1 runFGStart

It runs fg for each farm is using it and it is running

Parameters:

    Farmguardian - Farmguardian name

Returns: integer - errno

- 0: success
- !0: error

=cut

sub runFGStart ($fgname) {
    &log_debug("Starting farmguardian $fgname", "FG");

    my $out;
    my $obj = &getFGObject($fgname);

    for my $farm (@{ $obj->{farms} }) {
        my $srv;
        if ($farm =~ /([^_]+)_(.+)/) {
            $farm = $1;
            $srv  = $2;
        }

        $out |= &runFGFarmStart($farm, $srv);
    }

    return $out;
}

=pod

=head1 runFGRestart

It restarts all farmguardian process for each farm is using the passed fg

Parameters:

    Farmguardian - Farmguardian name

Returns:

    Integer - 0 on failure, or another value on success

=cut

sub runFGRestart ($fgname) {
    my $out = &runFGStop($fgname);
    $out |= &runFGStart($fgname);

    return $out;
}

=pod

=head1 runFGFarmStop

It stops farmguardian process used by the farm. If the farm is GSLB or HTTP
and is not passed the service name, all farmguardians will be stoped.

Parameters:

    Farm - Farm name
    Service - Service name. This parameter is for HTTP and GSLB farms. If the farm has not services, this parameter expect 'undef'

Returns: integer - errno

- 0: success
- !0: error

=cut

sub runFGFarmStop ($farm, $service = undef) {
    # optional, if the farm is http and the service is not sent to
    # the function, all services will be restarted
    $service = undef if (defined $service and not length $service);

    my $out = 0;

    require Relianoid::Farm::Core;
    my $type = &getFarmType($farm);

    # Stop Farmguardian for every service
    if ($type =~ /http|eproxy/ and not defined $service) {
        require Relianoid::Farm::Service;

        for my $srv (&getFarmServices($farm)) {
            $out |= &runFGFarmStop($farm, $srv);
        }

        return $out;
    }

    my $fgpid = &getFGPidFarm($farm, $service);

    if ($fgpid && $fgpid > 0) {
        my $service_str = $service // '';
        &log_debug("running 'kill 9, $fgpid' stopping FarmGuardian $farm $service_str", "FG");

        # kill returns the number of process affected
        $out = kill 9, $fgpid;
        $out = (not $out);

        if ($out) {
            &log_error("running 'kill 9, $fgpid' stopping FarmGuardian $farm $service_str", "FG");
        }

        # delete pid files
        unlink &getFGPidFile($farm, $service);

        # put backend up
        if ($type eq "http" || $type eq "https") {
            my $status_file = &getFGStatusFile($farm);

            if (-e $status_file && -s $status_file) {
                require Relianoid::Farm::HTTP::Service;
                require Tie::File;

                my $idsv = &getFarmVSI($farm, $service);

                tie my @filelines, 'Tie::File', $status_file;

                my @fileAux = @filelines;
                my $lines   = scalar @fileAux;

                while ($lines > 0) {
                    $lines--;

                    my $matched = $fileAux[$lines] =~ /0 $idsv (\d+) fgDOWN/;
                    my $index   = $1;

                    next if not $matched;

                    splice(@fileAux, $lines, 1,);

                    require Relianoid::Farm::HTTP::Backend;
                    my $error_ref = &setHTTPFarmBackendStatus($farm, $service, $index, 'up', 'cut');

                    if ($error_ref->{code} != 1 and $error_ref->{code} != -1) {
                        $error_ref->{code} = 0;
                    }

                    $out |= $error_ref->{code};
                }

                @filelines = @fileAux;
                untie @filelines;
            }
        }

        elsif ($type eq "l4xnat") {
            require Relianoid::Farm::Backend;

            my $be = &getFarmServers($farm);

            for my $l_serv (@{$be}) {
                unless ($l_serv->{status} eq "fgDOWN") {
                    next;
                }

                my $error_ref = &setL4FarmBackendStatus($farm, $l_serv->{id}, "up");
                if ($error_ref->{code} != 1 and $error_ref->{code} != -1) {
                    $error_ref->{code} = 0;
                }
                $out |= $error_ref->{code};
            }
        }

        elsif ($type eq "eproxy") {
            # TODO LGL
        }
    }

    my $srvtag = defined $service ? "${service}_" : '';
    unlink "$configdir/${farm}_${srvtag}status.cfg";

    return $out;
}

=pod

=head1 runFGFarmStart

It starts the farmguardian process used by the farm.

The pid file is created by the farmguardian process.

If the farm is GSLB or HTTP and is not passed the service name,
all farmguardians will be run.

- Supported farm types without farmguardian support return 0.
- Unknown farm types return 1.

Parameters:

    Farm - Farm name
    Service - Service name. This parameter is for HTTP and GSLB farms.

Returns: integer - errno

- 0: success
- !0: error

=cut

sub runFGFarmStart ($farm, $svice = undef) {
    my $errno = 0;
    my $log   = "";
    my $sv    = "";

    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    my $ftype = &getFarmType($farm);

    # check if the farm is up
    return 0 if (&getFarmStatus($farm) ne 'up');

    # if the farmguardian is running...
    if (&getFGPidFarm($farm, $svice)) {
        return 0;
    }

    # check if the node is master
    if ($eload) {
        my $node = &eload(
            module => 'Relianoid::EE::Cluster',
            func   => 'getClusterNodeStatus',
        );
        return 0 unless (not $node or $node eq 'master');
    }

    $svice = '' if not defined $svice;
    &log_debug("Start fg for farm $farm, $svice", "FG");

    if ($ftype =~ /http|eproxy/ && $svice eq "") {
        require Relianoid::Farm::Service;

        for my $service (&getFarmServices($farm)) {
            $errno |= &runFGFarmStart($farm, $service);
        }
    }
    elsif ($ftype =~ /http|l4xnat|eproxy/) {
        my $fgname = &getFGFarm($farm, $svice);

        return 0 if not $fgname;

        &log_debug("Starting fg $fgname, farm $farm, $svice", "FG");
        my $fg = &getFGObject($fgname);

        if ($fg->{log} eq 'true') {
            $log = "-l";
        }

        if ($svice ne "") {
            $sv = "-s $svice";
        }

        my $farmguardian = &getGlobalConfiguration('farmguardian');
        my $fg_cmd       = "$farmguardian $farm $sv $log";

        require Relianoid::Log;
        &logAndRunBG($fg_cmd);

        # necessary for waiting that fg process write its process
        use Time::HiRes qw(usleep);
        $errno = 1;
        my $pid_file = &getFGPidFile($farm, $svice);

        # wait for 2 seconds
        for (my $it = 0 ; $it < 4000 ; $it += 1) {
            if (-f $pid_file) {
                $errno = 0;
                last;
            }

            # 500 microseconds == 0.5 milliseconds
            usleep(500);
        }

        if ($errno) {
            my $msg = "The farmguardian for the farm '$farm'";
            $msg .= " and the service '$svice'" if ($svice);
            $msg .= " could not start properly";
            &log_error($msg, "fg");
        }
    }
    elsif ($ftype eq 'gslb')     { }
    elsif ($ftype eq 'datalink') { }
    else {
        $errno = 1;
    }

    return $errno;
}

=pod

=head1 runFGFarmRestart

It restarts the farmguardian process used by the farm. If the farm is GSLB or HTTP
and is not passed the service name, all farmguardians will be restarted.

Parameters:

    Farm    - Farm name
    Service - Service name. This parameter is for HTTP and GSLB farms.

Returns: integer - errno

- 0: success
- !0: error

=cut

sub runFGFarmRestart ($farm, $service = undef) {
    my $out = &runFGFarmStop($farm, $service);
    $out |= &runFGFarmStart($farm, $service);

    return $out;
}

=pod

=head1 getFGRunningFarms

Get a list with all running farms where the farmguardian is applied.

Parameters:

    Farmguardian - Farmguardian name

Returns:

    Array ref - list of farm names

=cut

sub getFGRunningFarms ($fg) {
    require Relianoid::Farm::Core;
    require Relianoid::Farm::Base;

    my @runfarm = ();

    for my $farm (@{ &getFGObject($fg)->{farms} }) {
        my $srv;

        if ($farm =~ /([^_]+)_(.+)/) {
            $farm = $1;
            $srv  = $2;
        }

        if (&getFarmStatus($farm) eq 'up') {
            push @runfarm, $farm;
        }
    }

    return \@runfarm;
}

=pod

=head1 getFGMigrateFile

This function returns a standard name used to migrate the old farmguardians.

Parameters:

    Farm - Farm name
    Service - Service name. This parameter is for HTTP and GSLB farms.

Returns:

    String - Farmguardian name

=cut

sub getFGMigrateFile ($farm, $srv = undef) {
    return ($srv) ? "_default_${farm}_$srv" : "_default_$farm";
}

=pod

=head1 setOldFarmguardian

Create a struct of the new fg using the parameters of the old fg

Parameters:

    Configuration - Hash with the configuration of the old FG

Returns:

    None

=cut

sub setOldFarmguardian ($obj) {
    my $srv  = $obj->{service} // "";
    my $farm = $obj->{farm};
    my $name = &getFGMigrateFile($obj->{farm}, $srv);
    my $type = &getFarmType($farm);
    my $set;

    &log_debug2("setOldFarmguardian: $farm, $srv", "FG");

    # default object
    my $def = {
        description => "This farmguardian was created automatically to migrate to Relianoid 5.2 version or higher",
        command     => $obj->{command},
        log         => $obj->{log},
        interval    => $obj->{interval},
        cut_conns   => ($type =~ /http/) ? "true" : "false",
        template    => "false",
        farms       => [],
    };

    &runFGFarmStop($farm, $srv);

    # if exists, update it
    if (&getFGExistsConfig($name)) {
        $set             = &getFGObject($name);
        $set->{command}  = $obj->{command}  if exists $obj->{command};
        $set->{log}      = $obj->{log}      if exists $obj->{log};
        $set->{interval} = $obj->{interval} if exists $obj->{interval};
    }

    # else create it
    else {
        $set = $def;
    }

    &setFGObject($name, $set);
    my $farm_tag = ($srv) ? "${farm}_$srv" : $farm;

    if ($obj->{enable} eq 'true') {
        &setTinyObj($fg_conf, $name, 'farms', $farm_tag, 'add');
    }

    return;
}

####################################################################
######## ######## 	OLD FUNCTIONS 	######## ########
# Those functions are for compatibility with the APIs 3.0 and 3.1
####################################################################

=pod

=head1 runFarmGuardianStart

Start FarmGuardian rutine

Parameters:

    farm_name - string - Farm name.
    service   - string - Optional. Service name.
                         Only apply if the farm profile has services.
                         Leave undefined for farms without services.

Returns: integer

- -1 - If farmguardian file was not found or if farmguardian is not running.
- 0  - If farm profile is not supported by farmguardian, or farmguardian was executed.

=cut

sub runFarmGuardianStart ($farm_name, $service = undef) {
    return &runFGFarmStart($farm_name, $service);
}

=pod

=head1 runFarmGuardianStop

Stop FarmGuardian rutine

Parameters:

    farm_name - string - Farm name.
    service   - string - Optional. Service name.
                         Only apply if the farm profile has services.
                         Leave undefined for farms without services.

Returns: integer - errno

- 0: success
- !0: error

=cut

sub runFarmGuardianStop ($farm_name, $service = undef) {
    return &runFGFarmStop($farm_name, $service);
}

=pod

=head1 runFarmGuardianCreate

Create or update farmguardian config file

ttcheck and script must be defined and non-empty to enable farmguardian.

Parameters:

    fname - Farm name.
    ttcheck - Time between command executions for all the backends.
    script - Command to run.
    usefg - 'true' to enable farmguardian, or 'false' to disable it.
    fglog - 'true' to enable farmguardian verbosity in logs, or 'false' to disable it.
    svice - Service name.

Returns: integer - errno

- -1 - If ttcheck or script is not defined or empty and farmguardian is enabled.
-  0 - If farmguardian configuration was created.

=cut

sub runFarmGuardianCreate ($fname, $ttcheck, $script, $usefg, $fglog, $svice) {
    &log_debug("runFarmGuardianCreate( farm: $fname, interval: $ttcheck, cmd: $script, log: $fglog, enabled: $usefg )",
        "FG");

    my $output = -1;

    # get default name and check not exist
    my $obj = {
        service  => $svice,
        farm     => $fname,
        command  => $script,
        log      => $fglog,
        interval => $ttcheck,
        enable   => $usefg,
    };

    $output = &setOldFarmguardian($obj);

    # start
    $output |= &runFGFarmStart($fname, $svice);

    return $output;
}

=pod

=head1 runFarmGuardianRemove

Remove farmguardian down status on backends.

When farmguardian is stopped or disabled any backend marked as down by farmgardian must reset it's status.

Parameters:

    fname - Farm name.
    svice - Service name. Only apply if the farm profile has services. Leave undefined for farms without services.

Returns:

    none - Nothing is returned explicitly.

=cut

sub runFarmGuardianRemove ($fname, $svice) {
    my $fg = &getFGFarm($fname, $svice);

    return if (not $fg);

    # "unlink" stops the fg
    my $out = &unlinkFGFarm($fg, $fname, $svice);

    if ($fg eq &getFGMigrateFile($fname, $svice) and not @{ &getFGObject($fg)->{farms} }) {
        $out |= &delFGObject($fg);
    }

    return;
}

=pod

=head1 getFarmGuardianPid

Read farmgardian pid from pid file. Check if the pid is running and return it,
else it removes the pid file.

Parameters:

    fname   - Farm name.
    service - Service name. Only apply if the farm profile has services. Leave undefined for farms without services.

Returns:

    -1      - If farmguardian PID file was not found (farmguardian not running).
    integer - PID number (unsigned integer) if farmguardian is running.

Bugs:

    Regex with .* should be fixed.

See Also:

    relianoid

=cut

sub getFarmGuardianPid ($fname, $service = undef) {
    my $pid = &getFGPidFarm($fname, $service);

    return $pid;
}

1;
