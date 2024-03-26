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

my $passfile = "/etc/shadow";

=pod

=head1 Module

Relianoid::Login

=cut

=pod

=head1 changePassword

Change the password of a username.

Parameters:

    user - User name.
    newpass - New password.
    verifypass - New password again.

Returns:

    integer - ERRNO or return code .

Bugs:

    Verify password? Really?!

See Also:

    API v4: <set_user>, <set_user_zapi>

=cut

sub changePassword ($user, $newpass, $verifypass) {
    $verifypass = $newpass if (!$verifypass);

    ##write \$ instead $
    $newpass    =~ s/\$/\\\$/g;
    $verifypass =~ s/\$/\\\$/g;

    chomp($newpass);
    chomp($verifypass);

    ##no move the next lines
    my $cmd = "
/usr/bin/passwd $user 2>/dev/null<<EOF
$newpass
$verifypass
EOF
    ";

    my $output = system($cmd );
    if ($output) {
        &zenlog("Error trying to change the $user password", "error");
    }
    else { &zenlog("The $user password was changed", "info"); }

    return $output;
}

=pod

=head1 checkValidUser

Validate an user's password.

Parameters:

    user - User name.
    curpasswd - Password.

Returns:

    scalar - Boolean. 1 for valid password, or 0 for invalid one.

Bugs:

    Not a bug, but using pam would be desirable.

See Also:

    API v4: <set_user>

=cut

sub checkValidUser ($user, $passwd_in) {
    my $output = 0;
    use Authen::Simple::Passwd;
    my $passwd = Authen::Simple::Passwd->new(path => "$passfile");
    if ($passwd->authenticate($user, $passwd_in)) {
        $output = 1;
    }

    return $output;
}

1;

