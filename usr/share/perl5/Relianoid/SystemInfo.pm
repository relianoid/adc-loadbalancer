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
use feature qw(signatures state);

=pod

=head1 Module

Relianoid::SystemInfo

=cut

=pod

=head1 getDate

Get string of the current date.

Parameters: none

Returns: string - Date string.

 Example: "Mon May 22 10:42:39 2017"

=cut

sub getDate() {
    return scalar CORE::localtime();
}

=pod

=head1 getHostname

Get system hostname, and it is saved all the process life time

Parameters: none

Returns: string - Hostname.

=cut

sub getHostname() {
    require Sys::Hostname;
    state $hostname = Sys::Hostname::hostname();
    return Sys::Hostname::hostname();
}

=pod

=head1 getApplianceVersion

Returns a string with the description of the appliance.

NOTE: This function uses Tie::File, this module should be used only for writing files.

Parameters: none

Returns: string - Version string.

=cut

sub getApplianceVersion() {
    my $version;
    my $hyperv;
    my $applianceFile = &getGlobalConfiguration('applianceVersionFile');
    my $lsmod         = &getGlobalConfiguration('lsmod');
    my @packages      = @{ &logAndGet("$lsmod", "array") };
    my @hypervisor    = grep { /(xen|vm|hv|kvm)_/ } @packages;

    # look for appliance vesion
    if (-f $applianceFile) {
        require Tie::File;
        Tie::File->import;

        tie my @filelines, 'Tie::File', $applianceFile;
        $version = $filelines[0];
        untie @filelines;
    }

    # generate appliance version
    if (!$version) {
        my $kernel = &getKernelVersion();

        my $awk      = &getGlobalConfiguration('awk');
        my $ifconfig = &getGlobalConfiguration('ifconfig');

        # look for mgmt interface
        my @ifaces = @{ &logAndGet("$ifconfig -s | $awk '{print $1}'", "array") };

        # Network appliance
        if (grep { /mgmt/ } @ifaces) {
            $version = "ZNA 3300";
        }
        else {
            # select appliance verison
            if    ($kernel =~ /3\.2\.0\-4/)      { $version = "3110"; }
            elsif ($kernel =~ /3\.16\.0\-4/)     { $version = "4000"; }
            elsif ($kernel =~ /3\.16\.7\-ckt20/) { $version = "4100"; }
            else                                 { $version = "8000"; }

            # virtual appliance or baremetal
            $version = "RSA $version";
        }

        # save version for future request
        require Tie::File;
        Tie::File->import;

        tie my @filelines, 'Tie::File', $applianceFile;
        $filelines[0] = $version;
        untie @filelines;
    }

    # virtual appliance
    if (@hypervisor && $hypervisor[0] =~ /(xen|vm|hv|kvm)_/) {
        $hyperv = $1;
        $hyperv = 'HyperV' if ($hyperv eq 'hv');
        $hyperv = 'Vmware' if ($hyperv eq 'vm');
        $hyperv = 'Xen'    if ($hyperv eq 'xen');
        $hyperv = 'KVM'    if ($hyperv eq 'kvm');
    }

    # before relianoid versions had hypervisor in appliance version file, so not inclue it in the chain
    if ($hyperv && $version !~ /hypervisor/) {
        $version = "$version, hypervisor: $hyperv";
    }

    return $version;
}

=pod

=head1 getCpuCores

Get the number of CPU cores in the system.

Parameters: none

Returns: integer - Number of CPU cores.

=cut

sub getCpuCores() {
    my $cpuinfo_filename = '/proc/stat';
    my $cores            = 1;

    open my $stat_file, '<', $cpuinfo_filename;

    while (my $line = <$stat_file>) {
        next unless $line =~ /^cpu(\d+) /;
        $cores = $1 + 1;
    }

    close $stat_file;

    return $cores;
}

=head1 setEnv

Set envorioment variables. Get variables from global.conf

Parameters: none

Returns: nothing

=cut

sub setEnv() {
    use Relianoid::Config;

    local $ENV{http_proxy}  = &getGlobalConfiguration('http_proxy')  // "";
    local $ENV{https_proxy} = &getGlobalConfiguration('https_proxy') // "";

    my $provider = &getGlobalConfiguration('cloud_provider');

    if ($provider && $provider eq 'aws') {
        local $ENV{AWS_SHARED_CREDENTIALS_FILE} = &getGlobalConfiguration('aws_credentials') // "";
        local $ENV{AWS_CONFIG_FILE}             = &getGlobalConfiguration('aws_config')      // "";
    }

    return;
}

=pod

=head1 getKernelVersion

Returns the kernel version.

Parameters: none

Returns: string - kernel version

=cut

sub getKernelVersion() {
    require Relianoid::Config;
    my $uname   = &getGlobalConfiguration('uname');
    my $version = &logAndGet("$uname -r");
    return $version;
}

=pod

=head1 get_api_versions_list

Returns a list of strings with the API versions supported.

Parameters: none

Returns: string array

=cut

sub get_api_versions_list() {
    return (sort split ' ', &getGlobalConfiguration("api_versions"));
}

1;

