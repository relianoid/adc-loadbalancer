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

my $configdir = &getGlobalConfiguration('configdir');

=pod

=head1 Module

Relianoid::Farm::L4xNAT::Service

=cut

=pod

=head1 loadL4FarmModules

Load L4farm system modules and conntrack

Parameters:

    none

Returns:

    Integer - 0 on success or any other value on failure

=cut

sub loadL4FarmModules () {
    my $modprobe_bin = &getGlobalConfiguration("modprobe");
    my $error        = 0;
    if ($eload) {
        my $cmd = "$modprobe_bin nf_conntrack enable_hooks=1";
        $error += &logAndRun("$cmd");
    }
    else {
        $error += &logAndRun("$modprobe_bin nf_conntrack");

        # Initialize conntrack
        my $nftbin = &getGlobalConfiguration("nft_bin");

        # Flush nft tables
        &logAndRun("$nftbin flush table ip dummyTable");

        my $nftCmd =
          "$nftbin add table ip dummyTable; $nftbin add chain ip dummyTable dummyChain { type nat hook input priority 0 \\; }; $nftbin add rule ip dummyTable dummyChain ct state established accept";

        $error += &logAndRun("$nftCmd")
          if (&logAndRunCheck("$nftbin list table dummyTable"));
    }

    return $error;
}

1;

