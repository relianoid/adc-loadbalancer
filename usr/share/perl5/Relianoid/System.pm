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

use Relianoid::Log;
use Relianoid::Config;

my $eload = eval { require Relianoid::ELoad; };

=pod

=head1 Module

Relianoid::System

=cut

=pod

=head1 getTotalConnections

Get the number of current connections on this appliance.

Parameters:

    none

Returns:

    integer - The number of connections.

=cut

sub getTotalConnections () {
    my $conntrack = &getGlobalConfiguration("conntrack");
    my $conns     = &logAndGet("$conntrack -C");
    $conns =~ s/(\d+)/$1/;
    $conns += 0;

    return $conns;
}

=pod

=head1 indexOfElementInArray

Get the index of the first position where an element if found in an array.

Parameters:

    searched_element - Element to search.
    array_ref        - Reference to the array to be searched.

Returns:

    integer - Zero or higher if the element was found. -1 if the element was not found. -2 if no array reference was received.

See Also:

    API v4: <new_bond>

=cut

sub indexOfElementInArray ($searched_element, $array_ref) {
    if (ref $array_ref ne 'ARRAY') {
        return -2;
    }

    my @arrayOfElements = @{$array_ref};
    my $index           = 0;

    for my $list_element (@arrayOfElements) {
        if ($list_element eq $searched_element) {
            last;
        }

        $index++;
    }

    # if $index is greater than the last element index
    if ($index > $#arrayOfElements) {
        # return an invalid index
        $index = -1;
    }

    return $index;
}

=pod

=head1 slurpFile

Stores the content of a file in a variable.

Parameters:

    path - string with the file location

Returns:

    string - content of the file

=cut

sub slurpFile ($path) {
    my $file;

    if (open(my $fh, '<', $path)) {
        local $/ = undef;
        $file = <$fh>;
        close $fh;
    }
    else {
        my $msg = "Could not open file '$file': $!";
        &log_info($msg);
        die $msg;
    }

    return $file;
}

=pod

=head1 getSpaceFree

It gets the free space that contains a partition. The partition is calculated
from a directory

Parameters:

    directroy - directory to know the free space

Returns:

    Integer - Number of bytes free in the partition

=cut

sub getSpaceFree ($dir) {
    my $df_bin   = &getGlobalConfiguration("df_bin");
    my $sed_bin  = &getGlobalConfiguration("sed_bin");
    my $cut_bin  = &getGlobalConfiguration("cut_bin");
    my $grep_bin = &getGlobalConfiguration("grep_bin");

    my $cmd  = "$df_bin -B1 $dir | $grep_bin -Ev '^(Filesystem|\$)' | $sed_bin -E 's/\\s+/ /g' | $cut_bin -d ' ' -f4";
    my $size = &logAndGet($cmd);

    &log_debug2("Dir: $dir, Free space (Bytes): $size");

    return $size;
}

=pod

=head1 getSpaceFormatHuman

It converts a number of bytes to human format, converting Bytes to KB, MB or GB

Parameters:

    Bytes - Number of bytes

Returns:

    String - String with size and its units

=cut

sub getSpaceFormatHuman ($size) {
    my $human = $size;
    my $unit  = 'B';

    if ($human > 1024) {
        $human = $human / 1024;
        $unit  = "KB";
    }
    if ($human > 1024) {
        $human = $human / 1024;
        $unit  = "MB";
    }
    if ($human > 1024) {
        $human = $human / 1024;
        $unit  = "GB";
    }

    $human = sprintf("%.2f", $human);
    my $out = $human . $unit;
    return $out;
}

=pod

=head1 getSupportSaveSize

It gets the aproximate size that the supportsave will need.
The size is calculated using the config and log directories size and adding
a offset of 20MB

Parameters:

    none

Returns:

    Integer - Number of bytes that supportsave will use

=cut

sub getSupportSaveSize () {
    my $offset = "20971520";                               # 20 MB
    my $dirs   = "/usr/local/relianoid/config /var/log";

    my $tar_bin = &getGlobalConfiguration('tar');
    my $wc      = &getGlobalConfiguration('wc_bin');
    my $size    = &logAndGet("$tar_bin cz - $dirs 2>/dev/null | $wc -c");

    return $offset + $size;
}

=pod

=head1 checkSupportSaveSpace

Check if the disk has enough space to create a supportsave

Parameters:

    directory - Directory where the supportsave will be created

Returns:

    Integer - It returns 0 on success or the number of bytes needed to create a supportsave

=cut

sub checkSupportSaveSpace ($dir = "/tmp") {
    my $supp_size = &getSupportSaveSize();
    my $freeSpace = &getSpaceFree($dir);

    my $out = ($freeSpace > $supp_size) ? 0 : $supp_size;

    if ($out) {
        &log_error("There is no enough free space ('$freeSpace') in the '$dir' partition. Supportsave needs '$supp_size' bytes",
            "system");
    }
    else {
        &log_debug("Checking free space ('$freeSpace') in the '$dir' partition. Supportsave needs '$supp_size' bytes",
            "system");
    }

    return $out;
}

=pod

=head1 getSupportSave

It creates a support save file used for supporting purpose. It is created in the '/tmp/' directory

Parameters:

    none

Returns:

    String - The supportsave file name is returned.

=cut

sub getSupportSave () {
    my $bin_dir   = &getGlobalConfiguration('bin_dir');
    my @ss_output = @{ &logAndGet("${bin_dir}/supportsave", "array") };

    # get the last "word" from the first line
    my $first_line = shift @ss_output;
    my $last_word  = (split(' ', $first_line))[-1];

    my $ss_path = $last_word;

    my (undef, $ss_filename) = split('/tmp/', $ss_path);

    return $ss_filename;
}

=pod

=head1 checkPidRunning

Check if Pid is running on the system.

Parameters:

    pid - pid to check.

Returns:

    scalar - 0 if success, otherwise an error.

=cut

sub checkPidRunning ($pid) {
    my $ret = 1;
    $ret = 0 if (-e "/proc/" . $pid);
    return $ret;
}

=pod

=head1 checkPidFileRunning

Check if PidFile contains a Pid is running on the system.

Parameters:

    pid_file - pid file to check.

Returns:

    scalar - 0 if success, otherwise an error.

=cut

sub checkPidFileRunning ($pid_file) {
    open my $fileh, '<', $pid_file;
    my $pid = <$fileh>;
    chomp $pid;
    close $fileh;
    return &checkPidRunning($pid);
}

=pod

=head1 setSshDefaultConfig

Apply default SSH config if it was not changed by this service
before. Then, reload the service generators.

Parameters:

    None.

Returns:

    ssh_config - Hash reference with SSH default configuration.

=cut

sub setSshDefaultConfig () {
    my $output = 0;
    $output = &eload(
        module => 'Relianoid::EE::System::SSH',
        func   => 'setSshDefaultConfigPriv',
        soft   => 1
    ) if ($eload);
    return $output;
}

=pod

=head1 setSshFactoryReset

Set default configuration of the ssh service.

Parameters:

    None.

Returns:

    integer - 0 on success, or -1 on failure.

=cut

sub setSshFactoryReset () {
    my $ssh_tpl = "/etc/ssh/sshd_config.ucf-dist";
    my $ssh_cfg = "/etc/ssh/sshd_config";
    my $output  = 0;

    if (-f $ssh_tpl) {
        my $cmd = "cp -f $ssh_tpl $ssh_cfg";
        &logAndRun($cmd);
    }

    $output = &eload(
        module => 'Relianoid::EE::System::SSH',
        func   => 'setSshFactoryResetPriv',
        soft   => 1
    ) if ($eload);
    return $output;
}

=pod

=head1 initHttpServer

Initialize required files to make http server to work.

Parameters:

    None.

Returns:

    none 0 on success other value if there is an error.

=cut

sub initHttpServer () {
    my $httpFile          = &getGlobalConfiguration('confhttp');
    my $httpFileTpl       = &getGlobalConfiguration('confhttp_tpl');
    my $httpServerKey     = &getGlobalConfiguration('http_server_key');
    my $httpServerKeyTpl  = &getGlobalConfiguration('http_server_key_tpl');
    my $httpServerCert    = &getGlobalConfiguration('http_server_cert');
    my $httpServerCertTpl = &getGlobalConfiguration('http_server_cert_tpl');
    my $output            = 0;
    my $cmd;

    if (!-f "$httpFile") {
        $cmd = "cp -f $httpFileTpl $httpFile";
        $output += &logAndRun($cmd);
    }

    if (!-f "$httpServerKey") {
        $cmd = "cp -f $httpServerKeyTpl $httpServerKey";
        $output += &logAndRun($cmd);
    }

    if (!-f "$httpServerCert") {
        $cmd = "cp -f $httpServerCertTpl $httpServerCert";
        $output += &logAndRun($cmd);
    }

    $output += &eload(
        module => 'Relianoid::EE::System::HTTP',
        func   => 'setHttpDefaultConfigPriv',
        soft   => 1
    ) if ($eload);
    return $output;
}

=pod

=head1 setHttpDefaultConfig

Apply default HTTP config if it was not changed by this service
before. Then, reload the service generators.

Parameters:

    None.

Returns:

    http_conf - Hash reference with HTTP default configuration.

=cut

sub setHttpDefaultConfig () {
    my $output = 0;
    $output = &eload(
        module => 'Relianoid::EE::System::HTTP',
        func   => 'setHttpDefaultConfigPriv',
        soft   => 1
    ) if ($eload);
    return $output;
}

=pod

=head1 restartHttpServer

Restart the HTTP web server.

Parameters:

    None.

Returns:

    none 0 on success other value if there is an error.

=cut

sub restartHttpServer () {
    my $output = 0;
    $output = &eload(
        module => 'Relianoid::EE::System::HTTP',
        func   => 'restartHttpServerPriv',
        soft   => 1
    ) if ($eload);
    return $output;
}

=pod

=head1 setHttpFactoryReset

Set default configuration of the http service.

Parameters:

    None.

Returns:

    integer - 0 on success, or -1 on failure.

=cut

sub setHttpFactoryReset () {
    my $httpFile          = &getGlobalConfiguration('confhttp');
    my $httpFileTpl       = &getGlobalConfiguration('confhttp_tpl');
    my $httpServerKey     = &getGlobalConfiguration('http_server_key');
    my $httpServerKeyTpl  = &getGlobalConfiguration('http_server_key_tpl');
    my $httpServerCert    = &getGlobalConfiguration('http_server_cert');
    my $httpServerCertTpl = &getGlobalConfiguration('http_server_cert_tpl');
    my $output            = 0;

    my $cmd = "cp -f $httpFileTpl $httpFile";
    $output += &logAndRun($cmd);

    $cmd = "cp -f $httpServerKeyTpl $httpServerKey";
    $output += &logAndRun($cmd);

    $cmd = "cp -f $httpServerCertTpl $httpServerCert";
    $output += &logAndRun($cmd);

    $output += &eload(
        module => 'Relianoid::EE::System::HTTP',
        func   => 'setHttpDefaultConfigPriv',
        soft   => 1
    ) if ($eload);

    return $output;
}

1;

