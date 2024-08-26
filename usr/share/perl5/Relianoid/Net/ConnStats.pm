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

my %conntrack_proto = (
    icmp => 1,
    tcp  => 6,
    udp  => 17,
    gre  => 47,
    sctp => 132,
);

=pod

=head1 Module

Relianoid::Net::ConnStats

=cut

=pod

=head1 getConntrack

Get the connections list.

Parameters:

    orig_src -
    orig_dst -
    reply_src -
    reply_dst -
    protocol -

Returns:

    array ref - Filtered netstat array reference.

=cut

sub getConntrack ($orig_src, $orig_dst, $reply_src, $reply_dst, $protocol) {
    # remove newlines in every argument
    chomp($orig_src, $orig_dst, $reply_src, $reply_dst, $protocol);

    # add iptables options to every available value
    $orig_src  = "-s $orig_src"  if ($orig_src);
    $orig_dst  = "-d $orig_dst"  if ($orig_dst);
    $reply_src = "-r $reply_src" if ($reply_src);
    $reply_dst = "-q $reply_dst" if ($reply_dst);
    $protocol  = "-p $protocol"  if ($protocol);

    my $conntrack     = &getGlobalConfiguration('conntrack');
    my $conntrack_cmd = "$conntrack -L $orig_src $orig_dst $reply_src $reply_dst $protocol";

    # return an array reference
    my @output = @{ &logAndGet($conntrack_cmd, "array") };

    # my $conns_count = scalar @output;
    # &log_info( "getConntrack command: $conntrack_cmd", "MONITOR" );
    # &log_info( "getConntrack returned $conns_count connections.", "MONITOR" );

    return \@output;
}

=pod

=head1 getNetstatFilter

Filter conntrack output

Parameters:

    proto - Protocol: "tcp", "udp", more?
    state - State: ??
    ninfo - Ninfo: ??
    fpid - Fpid: ??
    netstat - Output from getConntrack

Returns:

    array ref - Filtered netstat array reference.

=cut

# Returns array execution of netstat
sub getNetstatFilter ($proto, $state, $ninfo, $fpid, $netstat) {
    my $lfpid = $fpid;
    chomp($lfpid);

    if ($lfpid) {
        $lfpid = "\ $lfpid\/";
    }

    if ($proto ne "tcp" && $proto ne "udp") {
        $proto = "";
    }

    my $filter = "${proto}.* ${ninfo} .* ${state}.*${lfpid}";
    my @output = grep { /$filter/ } @{$netstat};
    my $output = \@output;

    # my $conns_count = scalar @output;
    # &log_info( "getNetstatFilter filter: '$filter'", "MONITOR" );
    # &log_info( "getNetstatFilter returned $conns_count connections.", "MONITOR" );

    return $output;
}

=pod

=head1 getConntrackParams

Get Conntrack params for a filter

Example:

    my $filter = {
        proto         => 'tcp',
        orig_dst      => $vip,
        orig_port_dst => $vip_port,
        state         => 'ESTABLISHED',
    };

Parameters:

    hash ref - Filter of connections

    FILTER PARAMETERS

    src, orig_src IP_ADDRESS
        Match only entries whose source address in the original direction equals the one specified as argument.
        Implies "--mask-src" when CIDR notation is used.

    dst, orig_dst IP_ADDRESS
        Match only entries whose destination address in the original direction equals the one specified as argument.
        Implies "--mask-dst" when CIDR notation is used.

    reply_src IP_ADDRESS
        Match only entries whose source address in the reply direction equals the one specified as argument.

    reply_dst IP_ADDRESS
        Match only entries whose destination address in the reply direction equals the one specified as argument.

    proto PROTO
        Specify layer four (TCP, UDP, ...) protocol.

    family PROTO
        Specify layer three (ipv4, ipv6) protocol This option is only required in conjunction with "-L, --dump".
        If this option is not passed, the default layer 3 protocol will be IPv4.

    timeout TIMEOUT
        Specify the timeout.

    mark MARK[/MASK]
        Specify  the conntrack mark. Optionally, a mask value can be specified.
        In "--update" mode, this mask specifies the bits that should be zeroed before XORing the MARK value into the ctmark.
        Otherwise, the mask is logically ANDed with the existing mark before the comparision.
        In "--create" mode, the mask is ignored.

    label LABEL
        Specify a conntrack label. 
        This option is only available in conjunction with "-L, --dump", "-E, --event", "-U --update" or "-D --delete".
        Match entries whose labels match at least those specified.
        Use multiple -l commands to specify multiple labels that need to be set.
        Match entries whose labels matches at least those specified as arguments.
        --label-add LABEL Specify the conntrack label to add to to the selected conntracks.
        This option is only available in conjunction with "-I, --create" or "-U, --update".
        --label-del [LABEL] Specify the conntrack label to delete from the selected conntracks.
        If no label is given, all labels are  deleted. This option is only available in conjunction with "-U, --update".

    secmark SECMARK
        Specify the conntrack selinux security mark.

    status [ASSURED|SEEN_REPLY|FIXED_TIMEOUT|EXPECTED|UNSET][,...]
        Specify the conntrack status.

    src_nat
        Filter source NAT connections.

    dst_nat
        Filter destination NAT connections.

    any_nat
        Filter any NAT connections.

    zone
        Filter by conntrack zone. See iptables CT target for more information.

    orig_zone
        Filter by conntrack zone in original direction.  See iptables CT target for more information.

    reply_zone
        Filter by conntrack zone in reply direction.  See iptables CT target for more information.

    tuple_src IP_ADDRESS
        Specify the tuple source address of an expectation.  Implies "--mask-src" when CIDR notation is used.

    tuple_dst IP_ADDRESS
        Specify the tuple destination address of an expectation.  Implies "--mask-dst" when CIDR notation is used.

    mask_src IP_ADDRESS
        Specify  the  source  address mask.
        For conntrack this option is only available in conjunction with "-L, --dump", "-E, --event", "-U --update" or "-D --delete".
        For expectations this option is only available in conjunction with "-I, --create".

    mask_dst IP_ADDRESS
        Specify the destination address mask. Same limitations as for "--mask-src".



    PROTOCOL FILTER PARAMETERS

    TCP-specific fields:

    sport, orig_port_src PORT
        Source port in original direction

    dport, orig_port_dst PORT
        Destination port in original direction

    reply_port_src PORT
        Source port in reply direction

    reply_port_dst PORT
        Destination port in reply direction

    state [NONE | SYN_SENT | SYN_RECV | ESTABLISHED | FIN_WAIT | CLOSE_WAIT | LAST_ACK | TIME_WAIT | CLOSE | LISTEN]
        TCP state


    UDP-specific fields:

    sport, orig_port_src PORT
        Source port in original direction

    dport, orig_port_dst PORT
        Destination port in original direction

    reply_port_src PORT
        Source port in reply direction

    reply_port_dst PORT
        Destination port in reply direction

Returns:

    unsigned integer - Number of connections found with the filter applied.

=cut

sub getConntrackParams ($filter) {
    my $conntrack_bin    = &getGlobalConfiguration('conntrack');
    my $conntrack_params = '';

    if (my @protocols = split(/\s/, $filter->{proto})) {
        my @found_protocols = ();
        for my $protocol (@protocols) {
            my $proto_code = $conntrack_proto{$protocol};
            if (defined $proto_code) {
                push(@found_protocols, $proto_code);
            }
            else {
                carp("Protocol '$protocol' not found in conntrack_proto");
            }
        }
        if (@found_protocols) {
            $conntrack_params = "--proto @found_protocols";
        }
    }

    for my $filter_key (keys %$filter) {
        next if $filter_key eq 'proto';

        my $param = $filter_key;
        $param =~ s/_/-/g;

        $conntrack_params = join(" ", $conntrack_params, "--$param $filter->{ $filter_key }");
    }

    return $conntrack_params;
}

=pod

=head1 getConntrackCount

Parameters:

    $conntrack_params - filter received from getConntrackParams()

Returns:

    integer - Count of connection matching the received filter.

=cut

sub getConntrackCount ($conntrack_params) {
    my $conntrack_bin = &getGlobalConfiguration('conntrack');
    my $conntrack_cmd = "$conntrack_bin -L $conntrack_params 2>&1 >/dev/null";

    require Relianoid::Debug;

    &log_debug("Conntrack count: $conntrack_cmd", "MONITOR") if &debug();

    # Do not use the function 'logAndGet', this function manages the output error and code
    my $summary = `$conntrack_cmd`;
    my $error   = $?;
    my ($count) = $summary =~ m/: ([0-9]+) flow entries have been shown./;

    &log_error("Conntrack count: An error happened running the command: $conntrack_cmd", "MONITOR")
      if $error;

    return $count + 0;
}

1;
