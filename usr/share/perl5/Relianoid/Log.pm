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

sub warning_signal (@args) {
    print STDERR @args;
    log_warn("@args");
    return;
}

# Get the program name for logs messages
my $program_name =
    ($0 ne '-e')                                     ? $0
  : (exists $ENV{_} && $ENV{_} !~ /enterprise.bin$/) ? $ENV{_}
  :                                                    $^X;

my $basename = (split('/', $program_name))[-1];

=pod

=head1 _log

Write logs through syslog

Usage:

    &_log($text, $priority, $tag);

Examples:

    &_log("This is a message.", "info", "LSLB");
    &_log("Some errors happened.", "err", "FG");
    &_log("testing debug mode", "debug", "SYSTEM");

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

Returns: nothing

=cut

sub _log ($message, $type = 'info', $tag = '') {
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

sub log_info ($message, $tag = '') {
    return _log($message, 'info', $tag);
}

sub log_warn ($message, $tag = '') {
    return _log($message, 'warning', $tag);
}

sub log_error ($message, $tag = '') {
    return _log($message, 'error', $tag);
}

sub log_debug ($message, $tag = '') {
    return _log($message, 'debug', $tag);
}

sub log_debug2 ($message, $tag = '') {
    return _log($message, 'debug2', $tag);
}

sub log_debug3 ($message, $tag = '') {
    return _log($message, 'debug3', $tag);
}

sub log_debug4 ($message, $tag = '') {
    return _log($message, 'debug4', $tag);
}

sub log_debug5 ($message, $tag = '') {
    return _log($message, 'debug5', $tag);
}

=pod

=head1 logAndRun

Runs a command, logging stdout and stderr, and returning the errno.

Parameters:

    command - String with the command to be run.

Returns: integer - Errno.

=cut

sub logAndRun ($command) {
    my $program     = $basename;
    my @cmd_output  = `$command 2>&1`;
    my $return_code = $?;

    if ($return_code) {
        &log_error("${program} running: ${command}", "SYSTEM");
        &log_error("out: @cmd_output",               "SYSTEM") if @cmd_output;
        &log_error("last command failed!",           "SYSTEM");
    }
    else {
        &log_debug("${program} running: ${command}", "SYSTEM");
        &log_debug2("out: @cmd_output", "SYSTEM");
    }

    return $return_code;
}

=pod

=head1 logAndRunBG

Non-blocking version of logging and running a command, returning execution error code.

Parameters:

    command - String with the command to be run.

Returns: boolean - true on error, false on success launching the command.

=cut

sub logAndRunBG ($command) {
    my $program = $basename;

    # system("command &") always returns 0
    my $return_code = system("$command >/dev/null 2>&1 &");

    if ($return_code) {
        &log_error("${program} running: ${command}", "SYSTEM");
        &log_error("last command failed!",           "SYSTEM");
    }
    else {
        &log_debug("${program} running: ${command}", "SYSTEM");
    }

    return $return_code;
}

=pod

=head1 run_with_env

Run a command with the environment parameters customized.

Parameters:

    @command - string array - Command to run.

Returns: integer - Errno.

=cut

sub run_with_env (@command) {
    my $program = $basename;

    my @cmd_output = `. /etc/profile -notbui >/dev/null 2>&1 && @command 2>&1`;
    my $errno      = $?;

    if ($errno) {
        &log_error("${program} running: @command", "SYSTEM");
        &log_error("@cmd_output",                  "SYSTEM") if @cmd_output;
        &log_error("last command failed!",         "SYSTEM");
    }
    else {
        &log_debug("${program} running: @command", "SYSTEM");
        &log_debug2("out: @cmd_output", "SYSTEM");
    }

    return $errno;
}

=pod

=head1 logAndGet

Execute a command in the system to get the output. If the command fails,
it logs the error and returns a empty string or array.
It returns only the standard output, it does not return stderr.

Parameters:

    cmd        - string  - Command to be run in order to get info from the system.
    type       - string  - Force that the output will be convert to 'string' or 'array'. 'string' by default
    add_stderr - integer - If this parameter is different of 0, the stderr will be added to the command output '2>&1'

Returns: string | array ref

The type of output is specified in the type input parameter.

See Also:

    logAndRun

TODO:

    Add an option to manage exclusively the output error and discard the standard output

=cut

sub logAndGet ($cmd, $type = 'string', $add_stderr = 0) {
    my $stderr_file = "/tmp/err.log";
    my $tmp_err     = ($add_stderr) ? '&1' : $stderr_file;
    my $out         = `$cmd 2>$tmp_err`;
    my $err_code    = $? >> 8;

    if (&debug() >= 2) {
        &log_debug2("Executed (out: $err_code): $cmd", "system");
    }

    # - !$add_stderr - stderr is not captured with stdout
    #                  stderr is captured on $stderr_file
    # - &debug() <= 2 - stderr is sent to log when debugging
    if ($err_code && !$add_stderr && -f $stderr_file && &debug() <= 2) {
        if (open(my $fh, '<', $stderr_file)) {
            local $/ = undef;
            my $stderr_str = <$fh>;
            close $fh;

            &log_debug2("stderr: $stderr_str", "SYSTEM");
        }
        else {
            &log_error("Could not open file '$stderr_file': $!", "SYSTEM");
        }
    }

    unlink $stderr_file
      if -f $stderr_file;

    chomp($out);

    # logging if there is not any error
    &log_debug3("out: $out", "SYSTEM");

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

    command - string - Command to be run.

Returns: integer - errno.

See Also:

    logAndRun

=cut

sub logAndRunCheck ($command) {
    my $program = $basename;

    my @cmd_output  = `$command 2>&1`;
    my $return_code = $? >> 8;

    if (&debug() >= 2) {
        &log_debug2("${program} err_code '${return_code}' checking: ${command}", "SYSTEM");
    }
    if (&debug() >= 3) {
        &log_debug3("${program} output: @cmd_output", "SYSTEM");
    }

    return $return_code;
}

=pod

=head1 logRunAndGet

Execute a command in the system to get both the standard output and the stderr.

Parameters:

    command  - string  - Command to be run in order to get info from the system.
    format   - string  - Force that the output will be convert to 'string' or 'array'. String by default.
    outflush - integer - Flush standard output. If true, the standard output will be sent to null.

Returns: hash ref

Hash reference with the items:

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

    &log_debug("Executed (out: $exit->{stderr}): $command", "system");

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

    command - string - Command to be run.

Returns: ($errno, \@stdout, \@stderr)

Array with:

    errno  - integer   - The value is the error number returned.
    stdout - array ref - Each element of the array is a line of stdout.
    stderr - array ref - Each element of the array is a line of stderr.

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

