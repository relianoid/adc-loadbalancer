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
use Unix::Syslog qw(:macros :subs);    # Syslog macros

use Relianoid::Debug;

=pod

=head1 Module

Relianoid::Log 

=cut

sub warning_signal {    ## no critic Subroutines::RequireArgUnpacking
    print STDERR @_;
    zenlog("@_", "warn");
}

# Get the program name for zenlog
my $program_name =
    ($0 ne '-e')                                     ? $0
  : (exists $ENV{_} && $ENV{_} !~ /enterprise.bin$/) ? $ENV{_}
  :                                                    $^X;

my $basename = (split('/', $program_name))[-1];

=pod

=head1 zenlog

Write logs through syslog

Usage:

    &zenlog($text, $priority, $tag);

Examples:

    &zenlog("This is a message.", "info", "LSLB");
    &zenlog("Some errors happened.", "err", "FG");
    &zenlog("testing debug mode", "debug", "SYSTEM");

The different debug levels are:

    1 - Command executions.
        API inputs.
    2 - The command standart output, when there isn't any error.
        API outputs.
        Parameters modified in configuration files.
    3 - (reserved)
    4 - (reserved)
    5 - Profiling.

Parametes:

    message - String to be written in log.
    type    - Log level. info, error, debug, debug2, warn. Default: info
    tag     - RBAC, LSLB, GSLB, DSLB, IPDS, FG, NOTIF, NETWORK, MONITOR, SYSTEM, CLUSTER, AWS

Returns:

    none - .

=cut

sub zenlog ($message, $type = 'info', $tag = '') {
    if ($tag eq 'PROFILING') {
        $type = "debug5";
        return if &debug() < 5;
    }

    if ($type =~ /^debug(\d)?$/i) {
        my $log_debug_level = $1 // 1;

        # skip logs messages not included in the log level
        if (&debug() lt $log_debug_level) {
            return;
        }

        $type = "DEBUG";
        $type .= $log_debug_level if $log_debug_level > 1;
    }
    else {
        $type = uc($type);
    }

    if ($tag) {
        $tag = lc "${tag} :: ";
    }

    openlog($basename, LOG_PID, LOG_LOCAL0);
    syslog(LOG_INFO, "(${type}) ${tag}${message}");
    closelog();

    return;
}

=pod

=head1 notlog

Write logs through syslog. Exclusive use for logging notifications.

Usage:

    &notlog($text, $priority, $tag);

Examples:

    &notlog("This is a message.", "info", "LSLB");
    &notlog("Some errors happened.", "err", "FG");
    &notlog("testing debug mode", "debug", "SYSTEM");

The different debug levels are:

    1 - Command executions.
        API inputs.
    2 - The command standart output, when there isn't any error.
        API outputs.
        Parameters modified in configuration files.
    3 - (reserved)
    4 - (reserved)
    5 - Profiling.

Parametes:

    message - String to be written in log.
    type    - Log level. info, error, debug, debug2, warn. Default: info
    tag     - RBAC, LSLB, GSLB, DSLB, IPDS, FG, NOTIF, NETWORK, MONITOR, SYSTEM, CLUSTER, AWS

Returns:

    none - .

=cut

sub notlog ($message, $type = 'info', $tag = "") {
    if ($tag eq 'PROFILING') {
        $type = "debug5";
        return 0 if (&debug() < 5);
    }

    if ($type =~ /^(debug)(\d*)?$/) {
        my $debug_lvl = $2;
        $debug_lvl = 1 if not $debug_lvl;
        $type      = "$1$debug_lvl";
        return 0 if (&debug() lt $debug_lvl);
    }

    if ($tag) {
        $tag = lc "${tag} :: ";
    }

    my $program = $basename;
    $type = uc($type);

    openlog($program, LOG_PID, LOG_LOCAL2);
    syslog(LOG_INFO, "(${type}) ${tag}${message}");
    closelog();

    return;
}

=pod

=head1 logAndRun

Log and run the command string input parameter returning execution error code.

Parameters:

    command - String with the command to be run.

Returns:

    integer - Return code.

See Also:

    Widely used.

=cut

sub logAndRun ($command) {
    my $program     = $basename;
    my @cmd_output  = `$command 2>&1`;
    my $return_code = $?;

    if ($return_code) {
        &zenlog($program . " running: $command", "error", "SYSTEM");
        &zenlog("out: @cmd_output",              "error", "SYSTEM") if @cmd_output;
        &zenlog("last command failed!",          "error", "SYSTEM");
    }
    else {
        &zenlog($program . " running: $command", "debug",  "SYSTEM");
        &zenlog("out: @cmd_output",              "debug2", "SYSTEM");
    }

    return $return_code;
}

=pod

=head1 logAndRunBG()

Non-blocking version of logging and running a command, returning execution error code.

Parameters:

    command - String with the command to be run.

Returns:

    boolean - true on error, false on success launching the command.

=cut

sub logAndRunBG ($command) {
    my $program = $basename;

    # system("command &") always returns 0
    my $return_code = system("$command >/dev/null 2>&1 &");

    if ($return_code) {
        &zenlog($program . " running: $command", "error", "SYSTEM");
        &zenlog("last command failed!",          "error", "SYSTEM");
    }
    else {
        &zenlog($program . " running: $command", "debug", "SYSTEM");
    }

    return $return_code;
}

=pod

=head1 zsystem

Run a command with the environment parameters customized.

Parameters:

    exec - Command to run.

Returns:

    integer - Returns 0 on success or another value on failure

See Also:

    <runFarmGuardianStart>, <_runHTTPFarmStart>, <runHTTPFarmCreate>, <_runGSLBFarmStart>, <_runGSLBFarmStop>, <runGSLBFarmReload>, <runGSLBFarmCreate>

=cut

sub zsystem (@command) {
    my $program = $basename;

    my @cmd_output = `. /etc/profile -notbui >/dev/null 2>&1 && @command 2>&1`;
    my $out        = $?;

    if ($out) {
        &zenlog($program . " running: @command", "error", "SYSTEM");
        &zenlog("@cmd_output", "error", "error", "SYSTEM") if @cmd_output;
        &zenlog("last command failed!", "error", "SYSTEM");
    }
    else {
        &zenlog($program . " running: @command", "debug",  "SYSTEM");
        &zenlog("out: @cmd_output",              "debug2", "SYSTEM");
    }

    return $out;
}

=pod

=head1 zsystem_bg

Run a command with the environment parameters customized in the background.

Parameters:

    exec - Command to run.

Returns:

    integer - Returns 0 on success or another value on failure

See Also:

    C<_runGSLBFarmStart>, C<runGSLBFarmCreate>

=cut

sub zsystem_bg (@command) {
    my $program = $basename;

    my @cmd_output = `. /etc/profile -notbui >/dev/null 2>&1 && @command 2>&1 &`;
    my $out        = $?;

    if ($out) {
        &zenlog($program . " running: @command", "error", "SYSTEM");
        &zenlog("@cmd_output", "error", "error", "SYSTEM") if @cmd_output;
        &zenlog("last command failed!", "error", "SYSTEM");
    }
    else {
        &zenlog($program . " running: @command", "debug",  "SYSTEM");
        &zenlog("out: @cmd_output",              "debug2", "SYSTEM");
    }

    return $out;
}

=pod

=head1 logAndGet

Execute a command in the system to get the output. If the command fails,
it logs the error and returns a empty string or array.
It returns only the standard output, it does not return stderr.

Parameters:

    command - String with the command to be run in order to get info from the system.
    output format - Force that the output will be convert to 'string' or 'array'. String by default
    stderr flag - If this parameter is different of 0, the stderr will be added to the command output '2>&1'

Returns:

    Array ref or string - data obtained from the system. The type of output is specified
    in the type input param

See Also:

    logAndRun

TODO:

    Add an option to manage exclusively the output error and discard the standard output

=cut

sub logAndGet ($cmd, $type = 'string', $add_stderr = 0) {
    my $tmp_err  = ($add_stderr) ? '&1' : "/tmp/err.log";
    my $out      = `$cmd 2>$tmp_err` // '';
    my $err_code = $? >> 8;

    if (&debug() >= 2) {
        &zenlog("Executed (out: $err_code): $cmd", "debug2", "system");
    }

    if ($err_code and not $add_stderr) {
        # execute again, removing stdout and getting stderr
        if (open(my $fh, '<', $tmp_err)) {
            local $/ = undef;
            my $err_str = <$fh>;
            &zenlog("sterr: $err_str", "debug2", "SYSTEM");
            close $fh;
        }
        else {
            &zenlog("file '$tmp_err' not found", "error", "SYSTEM");
        }
    }

    chomp($out);

    # logging if there is not any error
    &zenlog("out: $out", "debug3", "SYSTEM");

    if ($type eq 'array') {
        my @out = split("\n", $out);
        return \@out;
    }

    return $out;
}

=pod

=head1 logAndRunCheck

It executes a command but is does not log anything if it fails. This functions
is useful to check things in the system as if a process is running or doing connectibity tests.
This function will log the command if the loglevel is greater than 1, and will
log the error output if the loglevel is greater than 2.

Parameters:

    command - String with the command to be run.

Returns:

    integer - error code of the command. 0 on success or another value on failure

See Also:

    logAndRun

=cut

sub logAndRunCheck ($command) {
    my $program = $basename;

    my @cmd_output  = `$command 2>&1`;
    my $return_code = $? >> 8;

    if (&debug() >= 2) {
        &zenlog($program . " err_code '$return_code' checking: $command", "debug2", "SYSTEM");
    }
    if (&debug() >= 3) {
        &zenlog($program . " output: @cmd_output", "debug3", "SYSTEM");
    }

    # returning error code of the execution
    return $return_code;
}

=pod

=head1 logRunAndGet

Execute a command in the system to get both the standard output and the stderr.

Parameters:

    command - String with the command to be run in order to get info from the system.
    format - Force that the output will be convert to 'string' or 'array'. String by default.
    outflush - Flush standard output. If true, the standard output will be sent to null.

Returns:

    Hash ref - hash reference with the items:

    stdout - standard output of the command executed in the given format. If 'array'
             format is selected, then a hash array is provided. 'string' by default.

    stderr - output error code of the command executed.

=cut

sub logRunAndGet ($command, $format = 'string', $outflush = 0) {
    $command .= " 2>&1";
    $command .= " > /dev/null" if ($outflush);

    my @get = ($_ = qx{$command}, $? >> 8);

    my $exit;
    $exit->{stdout} = $get[0];
    $exit->{stderr} = $get[1];

    &zenlog("Executed (out: $exit->{stderr}): $command", "debug", "system");

    if ($format eq 'array') {
        my @out = split("\n", $get[0]);
        $exit->{stdout} = \@out;
    }

    return $exit;
}

=pod

=head1 run3

Execute a command and returns errno, stdout and stderr of such command.

Parameters:

    command - String with the command to be run.

Returns:

    ($errno, \@stdout, \@stderr) - Array with:

    errno  - Scalar integer. The value is the error number returned.
    stdout - Array reference. Each element of the array is a line of stdout.
    stderr - Array reference. Each element of the array is a line of stderr.

=cut

sub run3 ($command) {
    require IPC::Open3;
    require Symbol;

    my $in_fh;
    my $out_fh;
    my $err_fh = Symbol::gensym();                                        # required to separate stdout and stderr
    my $pid    = IPC::Open3::open3($in_fh, $out_fh, $err_fh, $command);
    waitpid($pid, 0);
    my $status = $? >> 8;

    chomp(my @out = <$out_fh>);
    chomp(my @err = <$err_fh>);
    return ($status, \@out, \@err);
}

1;

