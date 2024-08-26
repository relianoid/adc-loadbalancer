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

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::Netfilter

=cut

=pod

=head1 loadNfModule

=cut

sub loadNfModule ($modname, $params) {
    my $status  = 0;
    my $lsmod   = &getGlobalConfiguration('lsmod');
    my @modules = @{ &logAndGet($lsmod, "array") };

    if (!grep { /^$modname /x } @modules) {
        my $modprobe         = &getGlobalConfiguration('modprobe');
        my $modprobe_command = "$modprobe $modname $params";

        &log_info("L4 loadNfModule: $modprobe_command", "SYSTEM");
        $status = &logAndRun("$modprobe_command");
    }

    return $status;
}

=pod

=head1 removeNfModule

=cut

sub removeNfModule ($modname) {
    my $modprobe         = &getGlobalConfiguration('modprobe');
    my $modprobe_command = "$modprobe -r $modname";

    &log_info("L4 removeNfModule: $modprobe_command", "SYSTEM");

    return &logAndRun("$modprobe_command");
}

=pod

=head1 getNewMark

=cut

sub getNewMark ($farm_name) {
    require Tie::File;
    require Relianoid::Lock;

    my $found       = 0;
    my $marknum     = 0x200;
    my $fwmarksconf = &getGlobalConfiguration('fwmarksconf');
    my @contents;

    &ztielock(\@contents, "$fwmarksconf");

    for my $i (512 .. 4095) {
        my $num = sprintf("0x%x", $i);
        if (!grep { /^$num/x } @contents) {
            $found   = 1;
            $marknum = $num;
            last;
        }
    }

    if ($found) {
        push @contents, "$marknum // FARM\_$farm_name\_";
    }

    untie @contents;

    return $marknum;
}

=pod

=head1 delMarks

=cut

sub delMarks ($farm_name = "", $mark = "") {
    require Relianoid::Lock;

    my $status      = 0;
    my $fwmarksconf = &getGlobalConfiguration('fwmarksconf');
    my @contents;

    if ($farm_name ne "") {
        &ztielock(\@contents, "$fwmarksconf");
        @contents = grep { !/ \/\/ FARM\_$farm_name\_$/ } @contents;
        untie @contents;
    }

    if ($mark ne "") {
        &ztielock(\@contents, "$fwmarksconf");
        @contents = grep { !/^$mark \/\/ FARM\_/ } @contents;
        untie @contents;
    }

    return $status;
}

1;
