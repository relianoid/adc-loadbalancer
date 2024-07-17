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

=pod

=head1 Module

Relianoid::CGI

=cut

use strict;
use warnings;
use feature qw(signatures state);
use CGI::Simple;

$CGI::Simple::DISABLE_UPLOADS = 0;                # enable uploads
$CGI::Simple::POST_MAX        = 1_048_576_000;    # allow 1000MB uploads

=pod

=head1 getCGI

Get a L<CGI::Simple> object. The object is reused if called more than once in the request.

Parameters: None

Returns: L<CGI::Simple> object

=cut

sub getCGI () {
    state $cgi = CGI::Simple->new();
    return $cgi;
}

=pod

=head1 getCgiParam

Get CGI variables. This functions can be used in two diferent ways:

1. When a variable name is passed as an argument, the variable value is returned:

    &getCgiParam(variableName);

2. When no arguments are passed, a hash reference with all the variables is returned:

    $hash_ref = &getCgiParam();
    $hash_ref->{variableName};

Parameters:

    param - string - Optional. CGI variable name.

Returns:

- When a variable name has been passed as an argument:

    &getCgiParam( 'variableName' );

  - If the variable is found: string - Variable value.
  - If the variable is not found: undefined

- When the function is run without arguments:

    &getCgiParam();

    hash reference - With all the CGI variables.

=cut

sub getCgiParam ($param = undef) {
    my $cgi = getCGI();

    return eval { $cgi->param($param) } if $param;
    return $cgi->Vars;
}

1;

