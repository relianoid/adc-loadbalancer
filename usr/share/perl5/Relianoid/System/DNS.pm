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

Relianoid::System::DNS

=cut

=pod

=head1 getDns

Get the dns servers.

Parameters:

    none - .

Returns:

    scalar - Hash reference.

    Example:

    $dns = {
        primary => "value",
        secundary => "value",
    };

See Also:

    api/v4/system.cgi

=cut

sub getDns () {
    my $dns     = { 'primary' => '', 'secondary' => '' };
    my $dnsFile = &getGlobalConfiguration('filedns');

    if (!-f $dnsFile) {
        return;
    }

    open(my $fd, '<', $dnsFile);
    my @file = <$fd>;
    close $fd;

    my $index = 1;
    foreach my $line (@file) {
        if ($line =~ /nameserver\s+([^\s]+)/) {
            $dns->{'primary'}   = $1 if ($index == 1);
            $dns->{'secondary'} = $1 if ($index == 2);

            $index++;
            last if ($index > 2);
        }
    }

    return $dns;
}

=pod

=head1 setDns

Set a primary or secondary dns server.

Parameters:

    dns - 'primary' or 'secondary'.
    value - ip addres of dns server.

Returns:

    none - .

Bugs:

    Returned value.

See Also:

    zapi/v4/system.cgi

=cut

sub setDns ($dns, $value) {
    my $dnsFile = &getGlobalConfiguration('filedns');

    if (!-f $dnsFile) {
        my $bin = &getGlobalConfiguration('touch');
        &logAndRun("$bin $dnsFile");
    }

    require Tie::File;
    tie my @dnsArr, 'Tie::File', $dnsFile;

    my $index      = 1;
    my $line_index = 0;
    foreach my $line (@dnsArr) {
        $line_index++;
        if ($line =~ /\s*nameserver/) {
            $line = "nameserver $value"
              if ($index == 1 and $dns eq 'primary' and $value ne '');
            $line = "nameserver $value"
              if ($index == 2 and $dns eq 'secondary' and $value ne '');
            splice @dnsArr, ($line_index - 1)
              if ($index == 2 and $dns eq 'secondary' and $value eq '');
            $index++;
            last if ($index > 2);
        }
    }

    # if there is not any nameserver, add one
    push @dnsArr, "nameserver $value"
      if ($index == 1 and $value ne '');

    # if the secondary nameserver has not been found, add it
    push @dnsArr, "nameserver $value"
      if ($index == 2 and $dns eq 'secondary' and $value ne '');

    untie @dnsArr;

    return 0;
}

1;
