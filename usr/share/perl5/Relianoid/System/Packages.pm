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
require Relianoid::Log;
use Relianoid::SystemInfo;
use autodie;

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::System::Packages

=cut

=pod

=head1 setSystemPackagesRepo

It configures the system to connect with the APT.

Parameters:

    none

Returns:

    Integer - Error code, 0 on success or another value on failure

=cut

sub setSystemPackagesRepo () {
    if ($eload) {
        return &eload(
            module => 'Relianoid::EE::Apt',
            func   => 'setAPTRepo',
        );
    }

    require Relianoid::File;

    my $host         = &getGlobalConfiguration('repo_url_relianoid');
    my $file         = &getGlobalConfiguration('apt_source_relianoid');
    my $aptget_bin   = &getGlobalConfiguration('aptget_bin');
    my $distribution = "bookworm";
    my $repo_version = "v7";
    my $content      = "deb http://$host/ce/$repo_version/ $distribution main\n";

    &log_info("Configuring the APT repository", "SYSTEM");

    my $success    = 1;
    my $error_code = (setFile($file, $content) == $success) ? 0 : 1;

    return $error_code;
}

=pod

=head1 getSystemPackagesUpdatesList

It returns information about the status of the system regarding updates.
This information is parsed from a file

Parameters:

    none

Returns:

    Hash reference

    'message'    : message with the instructions to update the system
    'last_check' : date of the last time that nod-updater (or apt-get) was executed
    'status'     : information about if there is pending updates.
    'number'     : number of packages pending of updating
    'packages'   : list of packages pending of updating

=cut

sub getSystemPackagesUpdatesList () {
    require Relianoid::Lock;
    my $package_list = &getGlobalConfiguration('apt_outdated_list');
    my $message_file = &getGlobalConfiguration('apt_msg');

    my @pkg_list = ();
    my $msg;
    my $date        = "";
    my $status      = "unknown";
    my $install_msg = "To upgrade the system, please, execute in a shell the following command:\n    'noid-updater -i'";

    my $fh = &openlock($package_list, 'r');
    if ($fh) {
        @pkg_list = split(' ', <$fh>);
        close $fh;

        # remove the first item
        shift @pkg_list
          if ((exists $pkg_list[0]) and ($pkg_list[0] eq 'Listing...'));
    }

    $fh = &openlock($message_file, 'r');
    if (defined $fh) {
        $msg = <$fh>;
        close $fh;

        if ($msg =~ /last check at (.+) -/) {
            $date   = $1;
            $status = "Updates available";
        }
        elsif ($msg =~ /Relianoid Packages are up-to-date/) {
            $status = "Updated";
        }
    }

    return {
        'message'    => $install_msg,
        'last_check' => $date,
        'status'     => $status,
        'number'     => scalar @pkg_list,
        'packages'   => \@pkg_list
    };
}

1;
