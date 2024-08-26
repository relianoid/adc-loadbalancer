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
use Relianoid::Nft;

my $eload     = eval { require Relianoid::ELoad };
my $configdir = &getGlobalConfiguration('configdir');

=pod

=head1 Module

Relianoid::Farm::L4xNAT::Action

=cut

=pod

=head1 startL4Farm

Run a l4xnat farm

Parameters:

    farm_name - Farm name
    writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:

    Integer - return 0 on success or different of 0 on failure

=cut

sub startL4Farm ($farm_name, $writeconf = 0) {
    require Relianoid::Farm::L4xNAT::Config;

    &log_info("Starting L4xNAT farm $farm_name") if &debug();

    my $status = 0;
    my $farm   = &getL4FarmStruct($farm_name);

    &loadL4Modules($$farm{vproto});

    $status = &startL4FarmNlb($farm_name, $writeconf);
    if ($status != 0) {
        return $status;
    }

    &doL4FarmRules("start", $farm_name);

    &reloadFarmsSourceAddressByFarm($farm_name);

    # Enable IP forwarding
    require Relianoid::Net::Util;
    &setIpForward('true');

    if ($farm->{lbalg} eq 'leastconn') {
        require Relianoid::Farm::L4xNAT::L4sd;
        &sendL4sdSignal();
    }

    return $status;
}

=pod

=head1 stopL4Farm

Stop a l4xnat farm

Parameters:

    farm_name - Farm name
    writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:

    Integer - return 0 on success or other value on failure

=cut

sub stopL4Farm ($farm_name, $writeconf) {
    my $pidfile = &getL4FarmPidFile($farm_name);

    require Relianoid::Farm::Core;
    require Relianoid::Farm::L4xNAT::Config;

    &log_info("Stopping L4xNAT farm $farm_name") if &debug();

    my $farm = &getL4FarmStruct($farm_name);

    &doL4FarmRules("stop", $farm_name);

    my $pid = &getNlbPid();
    if ($pid <= 0) {
        return 0;
    }

    my $status = &stopL4FarmNlb($farm_name, $writeconf);

    # Flush conntrack
    &resetL4FarmConntrack($farm_name) unless ($status);

    unlink "$pidfile" if (-e "$pidfile");

    &unloadL4Modules($$farm{vproto});

    if ($farm->{lbalg} eq 'leastconn') {
        require Relianoid::Farm::L4xNAT::L4sd;
        &sendL4sdSignal();
    }

    return $status;
}

=pod

=head1 setL4NewFarmName

Function that renames a farm

Parameters:

    farmname - Farm name
    newfarmname - New farm name

Returns:

    Integer - return 0 on success or <> 0 on failure

=cut

sub setL4NewFarmName ($farm_name, $new_farm_name) {
    my $err = &setL4FarmParam('name', "$new_farm_name", $farm_name);

    unlink "$configdir\/${farm_name}_l4xnat.cfg";

    if (!$err) {
        $err = &setL4FarmParam('log-prefix', undef, $new_farm_name);
    }

    return $err;
}

=pod

=head1 copyL4Farm

Function that copies a l4xnat farm.
If the flag has the value 'del', the old farm will be deleted.

Parameters:

    farmname - Farm name

    newfarmname - New farm name

    flag - It expets a 'del' string to delete the old farm. It is used to copy or rename the farm.

Returns:

    Integer - return 0 on success or <> 0 on failure

=cut

sub copyL4Farm ($farm_name, $new_farm_name, $del = '') {
    my $output = 0;

    use File::Copy qw(copy);

    my $file_ori = "$configdir/" . &getFarmFile($farm_name);
    my $file_new = "$configdir/${new_farm_name}_l4xnat.cfg";

    copy($file_ori, $file_new);

    # replace the farm directive
    my @lines;
    &ztielock(\@lines, $file_new);
    require Relianoid::Netfilter;
    my $backend_block = 0;

    for my $line (@lines) {
        if ($line =~ /(^\s+"name": )"$farm_name(.*)",/) {
            $line = $1 . "\"$new_farm_name" . $2 . "\",";
        }
        if ((!$backend_block) and ($line =~ /^(\s+"state": )"\w+",/)) {
            $line = $1 . "\"down\",";
        }
        if ($line =~ /^\s+"backends": \[/) {
            $backend_block = 1;
        }
        if (($backend_block) and ($line =~ /(^\s+"mark": )"0x\w+",/)) {
            my $new_mark = &getNewMark($new_farm_name);
            $line = $1 . "\"$new_mark\",";
        }
        if ($line =~ /(^\s+"log-prefix":)(.*)$farm_name ",/) {
            $line = $1 . $2 . "$new_farm_name \",";
        }
    }

    untie @lines;

    unlink $file_ori if ($del eq 'del');

    return $output;
}

=pod

=head1 loadL4NlbFarm

Load farm configuration in nftlb

Parameters:

    farm_name - farm name configuration to be loaded

Returns:

    Integer - 0 on success or -1 on failure

=cut

sub loadL4FarmNlb ($farm_name) {
    require Relianoid::Farm::Core;

    my $farmfile = &getFarmFile($farm_name);

    return 0 if ($farmfile eq "-1" or (!-e "$configdir/$farmfile"));

    return &httpNlbRequest({
        farm   => $farm_name,
        method => "POST",
        uri    => "/farms",
        body   => qq(\@$configdir/$farmfile)
    });
}

=pod

=head1 startL4FarmNlb

Start a new farm in nftlb

Parameters:

    farm_name - farm name to be started
    writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:

    Integer - 0 on success or -1 on failure

=cut

sub startL4FarmNlb ($farm_name, $writeconf) {
    require Relianoid::Farm::L4xNAT::Config;

    my $output = &setL4FarmParam(($writeconf) ? 'bootstatus' : 'status', "up", $farm_name);

    my $pidfile = &getL4FarmPidFile($farm_name);

    if (!-e $pidfile) {
        open my $fh, '>', $pidfile;
        close $fh;
    }

    return $output;
}

=pod

=head1 stopL4FarmNlb

Stop an existing farm in nftlb

Parameters:

    farm_name - farm name to be started
    writeconf - write this change in configuration status "writeconf" for true or omit it for false

Returns:

    Integer - 0 on success or -1 on failure

=cut

sub stopL4FarmNlb ($farm_name, $writeconf) {
    require Relianoid::Farm::Core;

    my $out = &setL4FarmParam(($writeconf) ? 'bootstatus' : 'status', "down", $farm_name);

    return $out;
}

=pod

=head1 getL4FarmPidFile

Return the farm pid file

Parameters:

    farm_name - Name of the given farm

Returns:

    String - Pid file path or -1 on failure

=cut

sub getL4FarmPidFile ($farm_name) {
    my $piddir  = &getGlobalConfiguration('piddir');
    my $pidfile = "$piddir/$farm_name\_l4xnat.pid";

    return $pidfile;
}

=pod

=head1 sendL4NlbCmd

Send the param to Nlb for a L4 Farm

Parameters:

    self - hash that includes hash_keys:

    farm        - it is the farm that is going to be modified
    farm_new_name - this field is defined when the farm name is going to be modified.
    backend     - backend id to modify
    file        - file where the HTTP body response of the nftlb is saved
    method      - HTTP verb for nftlb request
    body        - body to use in POST and PUT requests

Returns:

    Integer - return code of the request command

=cut

sub sendL4NlbCmd ($self) {
    my $cfgfile = "";
    my $output  = -1;

    # load the configuration file first if the farm is down
    my $status = &getL4FarmStatus($self->{farm});
    if ($status ne "up") {
        my $out = &loadL4FarmNlb($self->{farm});
        return $out if ($out != 0);
    }

    # avoid farm configuration file destruction by asking nftlb only for modifications
    # or deletion of attributes of the farm
    if ($self->{method} =~ /PUT/
        || ($self->{method} =~ /DELETE/ && defined $self->{uri} && $self->{uri} =~ /farms\/.*\/.*/))
    {
        my $file  = "/tmp/get_farm_$$";
        my $match = 0;

        $output = &httpNlbRequest({
            method => "GET",
            uri    => "/farms/" . $self->{farm},
            file   => $file,
        });

        if (-e $file) {
            open my $fh, "<", $file;
            while (my $line = <$fh>) {
                if ($line =~ /\"name\"\: \"$$self{farm}\"/) {
                    $match = 1;
                    last;
                }
            }
            close $fh;
            unlink $file;
        }

        if (!$match) {
            &log_error("The farms was not loaded properly, trying it again");
            &loadL4FarmNlb($self->{farm});
        }
    }

    if ($self->{method} =~ /PUT|DELETE/) {
        $cfgfile = $self->{file};
        $self->{file} = "";
    }

    if (defined $self->{backend} && $self->{backend} ne "") {
        $self->{uri} = "/farms/$self->{farm}/backends/$self->{backend}";
    }
    elsif (!defined $self->{uri}) {
        $self->{uri} = "/farms";
        $self->{uri} = "/farms/$self->{farm}" if $self->{method} eq "DELETE";
    }

    # use the new name
    $self->{farm} = $self->{farm_new_name} if exists $self->{farm_new_name};

    $output = &httpNlbRequest($self);

    if ($self->{method} eq "GET" or not defined $self->{file}) {
        return $output;
    }

    # end if the farm was deleted
    if ($self->{method} eq "DELETE" and not exists $self->{backend}) {
        return $output;
    }

    # save the conf
    if ($self->{method} =~ /PUT|DELETE/) {
        $self->{file} = $cfgfile;
    }

    $self->{method} = "GET";
    $self->{uri}    = "/farms/" . $self->{farm};
    $self->{body}   = "";

    $output = &httpNlbRequest($self);

    return $output;
}

1;

