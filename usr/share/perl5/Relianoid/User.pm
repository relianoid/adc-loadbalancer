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

=pod

=head1 Module

Relianoid::User

=cut

=pod

=head1 getUser

Get the user that is executing the API or WEBGUI

Parameters:

    None

Returns:

    String - User name

=cut

sub getUser () {
    return $ENV{REQ_USER} // '';
}

=pod

=head1 setUser

Save the user that is executing the API or WEBGUI

Parameters:

    None - .

Returns:

    String - User name

=cut

sub setUser ($user) {
    $ENV{REQ_USER} = $user;    ## no critic (Variables::RequireLocalizedPunctuationVars)

    return;
}

=pod

=head1 getSysGroupList

List all Operating System groups

Parameters:

    None

Returns:

    Array - List of groups

=cut

sub getSysGroupList () {
    require Relianoid::Lock;
    my @groupSet   = ();
    my $group_file = &openlock("/etc/group", "r");
    while (my $group = <$group_file>) {
        push(@groupSet, $1) if ($group =~ m/(\w+):x:.*/g);
    }
    close $group_file;

    return @groupSet;
}

=pod

=head1 getSysUserList

List all Operating System users

Parameters:

    None

Returns:

    Array - List of users

=cut

sub getSysUserList () {
    require Relianoid::Lock;
    my @userSet   = ();
    my $user_file = &openlock("/etc/passwd", "r");
    while (my $user = <$user_file>) {
        push(@userSet, $1) if ($user =~ m/(\w+):x:.*/g);
    }
    close $user_file;

    return @userSet;
}

=pod

=head1 getSysUserExists

    Check if a user exists in the Operting System

Parameters:

    User - User name

Returns:

    Integer - 1 if the user exists or 0 if it doesn't exist

=cut

sub getSysUserExists ($user) {
    my $out = 0;
    $out = 1 if (grep { $user eq $_ } &getSysUserList());

    return $out;
}

=pod

=head1 getSysGroupExists

    Check if a group exists in the Operting System

Parameters:

    Group - group name

Returns:

    Integer - 1 if the group exists or 0 if it doesn't exist

=cut

sub getSysGroupExists ($group) {
    my $out = 0;
    $out = 1 if (grep { $group eq $_ } &getSysGroupList());

    return $out;
}

1;

