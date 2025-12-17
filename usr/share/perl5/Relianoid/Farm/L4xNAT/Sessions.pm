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

use Relianoid::Farm::L4xNAT::Config;

=pod

=head1 Module

Relianoid::Farm::L4xNAT::Sessions

=cut

=pod

=head1 parseL4FarmSessions

It transform the session output of nftlb output in a Relianoid session struct

Parameters:

    session ref - It is the session hash returned for nftlb. Example:

    session = {
        expiration => '1h25m31s364ms',
        backend    => 'bck0',
        client     => '192.168.10.162'
    }

Returns:

    Hash ref - It is a hash with the following keys:

    'session'

        Returns the session token.

    'id'

        Returns the backen linked with the session token.
        If any session was found the function will return 'undef'.

    'type'

        Will have the value:

        - 'static' if the session is preloaded by the user.
        - 'dynamic' if the session is created automatically by the system when the connection arrives.

    'ttl'

        Is the time out of the session.
        This field will be 'undef' when the session is static.

        {
            "id" : 3,
            "session" : "192.168.1.186"
            "type" : "dynamic"
            "ttl" : "1h25m31s364ms"
        }

=cut

sub parseL4FarmSessions ($s) {
    # translate session
    my $session = $s->{client};
    $session =~ s/ \. /_/;

    my $obj = {
        session => $session,
        type    => (exists $s->{expiration}) ? 'dynamic'        : 'static',
        ttl     => (exists $s->{expiration}) ? $s->{expiration} : undef,
    };

    if ($s->{backend} =~ /bck(\d+)/) {
        $obj->{id} = $1;
    }

    return $obj;
}

=pod

=head1 listL4FarmSessions

Get a list of the static and dynamic l4 sessions in a farm. Using nftlb

Parameters:

    farmname - Farm name

Returns:

    array ref - Returns a list of hash references with the following parameters:

    "client"

        is the client position entry in the session table

    "id"

        is the backend id assigned to session

    "session"

        is the key that identifies the session

    "type"

        is the key that identifies the session

    [
        {
            "client" : 0,
            "id" : 3,
            "session" : "192.168.1.186",
            "type" : "dynamic",
            "ttl" : "54m5s",
        }
    ]

=cut

sub listL4FarmSessions ($farmname) {
    require Relianoid::Lock;
    require Relianoid::JSON;
    require Relianoid::Nft;

    my $farm     = &getL4FarmStruct($farmname);
    my @sessions = ();
    my $it;

    return [] if ($farm->{persist} eq "");

    my $session_tmp = "/tmp/session_$farmname.data";
    my $lock_file   = &getLockFile($session_tmp);
    my $lock_fd     = &openlock($lock_file, 'w');
    my $err         = &sendL4NlbCmd({
        method => "GET",
        uri    => "/farms/" . $farmname . '/sessions',
        farm   => $farmname,
        file   => $session_tmp,
    });

    my $nftlb_resp;
    if (!$err) {
        $nftlb_resp = &decodeJSONFile($session_tmp);
    }

    close $lock_fd;
    unlink $lock_file;

    if ($err or not defined $nftlb_resp) {
        return [];
    }

    my $client_id = 0;
    my $backend_info;
    for my $bck (@{ $farm->{servers} }) {
        $backend_info->{ $bck->{id} }{ip}   = $bck->{ip};
        $backend_info->{ $bck->{id} }{port} = $bck->{port};
    }

    for my $s (@{ $nftlb_resp->{sessions} }) {
        $it                 = &parseL4FarmSessions($s);
        $it->{client}       = $client_id++;
        $it->{backend_ip}   = $backend_info->{ $it->{id} }{ip};
        $it->{backend_port} = $backend_info->{ $it->{id} }{port};
        push @sessions, $it;
    }

    return \@sessions;
}

1;

