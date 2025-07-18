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

Relianoid::Stats

=cut

=pod

=head1 getMemStats

Get stats of memory usage of the system.

Parameters:

    format - "b" for bytes, "kb" for KBytes and "mb" for MBytes (default: mb).

Returns:

    list - Two dimensional array.

    @data = (
        [$ram_total_label,     $ram_total],
        [$ram_free_label,    $ram_free],
        ['MemUsed',  $ram_used],
        [$ram_buffers_label,    $ram_buffers],
        [$ram_cached_label,    $ram_cached],
        [$swap_total_label,   $swap_total],
        [$swap_free_label,   $swap_free],
        ['SwapUsed', $swap_used],
        [$swap_cached_label,   $swap_cached],
    );

=cut

sub getMemStats ($format = "mb") {
    my $meminfo_filename = '/proc/meminfo';

    my ($ram_total, $ram_free, $ram_used, $ram_buffers, $ram_cached, $swap_total, $swap_free, $swap_used, $swap_cached);
    my (
        $ram_total_label,  $ram_free_label,  $ram_cached_label, $ram_buffers_label,
        $swap_total_label, $swap_free_label, $swap_cached_label
    );

    unless (-f $meminfo_filename) {
        print "$0: Error: File $meminfo_filename not exist ...\n";
        exit 1;
    }

    my @lines = ();

    if (open my $file, '<', $meminfo_filename) {
        @lines = <$file>;
        close $file;
    }

    for my $line (@lines) {
        if ($line =~ /^MemTotal:/) {
            ($ram_total_label, $ram_total) = split /[: ]+/, $line;
            $ram_total = $ram_total / 1024 if $format eq "mb";
            $ram_total = $ram_total * 1024 if $format eq "b";
        }
        elsif ($line =~ /^MemFree:/) {
            ($ram_free_label, $ram_free) = split(": ", $line);
            $ram_free =~ /^\s+(\d+)\ /;
            $ram_free = $1;
            $ram_free = $ram_free / 1024 if $format eq "mb";
            $ram_free = $ram_free * 1024 if $format eq "b";
        }
        elsif ($line =~ /^MemAvailable:/) {
            my (undef, $ram_available) = split(/ +/, $line);
            $ram_available = $ram_available / 1024 if $format eq "mb";
            $ram_available = $ram_available * 1024 if $format eq "b";
            $ram_used      = $ram_total - $ram_available;
        }
        elsif ($line =~ /^Buffers:/) {
            ($ram_buffers_label, $ram_buffers) = split /[: ]+/, $line;
            $ram_buffers = $ram_buffers / 1024 if $format eq "mb";
            $ram_buffers = $ram_buffers * 1024 if $format eq "b";
        }
        elsif ($line =~ /^Cached:/) {
            ($ram_cached_label, $ram_cached) = split /[: ]+/, $line;
            $ram_cached = $ram_cached / 1024 if $format eq "mb";
            $ram_cached = $ram_cached * 1024 if $format eq "b";
        }
        elsif ($line =~ /swaptotal/i) {
            ($swap_total_label, $swap_total) = split /[: ]+/, $line;
            $swap_total = $swap_total / 1024 if $format eq "mb";
            $swap_total = $swap_total * 1024 if $format eq "b";
        }
        elsif ($line =~ /swapfree/i) {
            ($swap_free_label, $swap_free) = split /[: ]+/, $line;
            $swap_free = $swap_free / 1024 if $format eq "mb";
            $swap_free = $swap_free * 1024 if $format eq "b";
            $swap_used = $swap_total - $swap_free;
        }
        elsif ($line =~ /swapcached/i) {
            ($swap_cached_label, $swap_cached) = split /[: ]+/, $line;
            $swap_cached = $swap_cached / 1024 if $format eq "mb";
            $swap_cached = $swap_cached * 1024 if $format eq "b";
        }
    }

    return (
        [ $ram_total_label,   sprintf('%.2f', $ram_total) ],
        [ $ram_free_label,    sprintf('%.2f', $ram_free) ],
        [ 'MemUsed',          sprintf('%.2f', $ram_used) ],
        [ $ram_buffers_label, sprintf('%.2f', $ram_buffers) ],
        [ $ram_cached_label,  sprintf('%.2f', $ram_cached) ],
        [ $swap_total_label,  sprintf('%.2f', $swap_total) ],
        [ $swap_free_label,   sprintf('%.2f', $swap_free) ],
        [ 'SwapUsed',         sprintf('%.2f', $swap_used) ],
        [ $swap_cached_label, sprintf('%.2f', $swap_cached) ],
    );
}

=pod

=head1 getLoadStats

Get the system load values.

Parameters:

    none

Returns:

    list - Two dimensional array.

    @data = (
        ['Last', $last],
        ['Last 5', $last5],
        ['Last 15', $last15]
    );

=cut

sub getLoadStats () {
    my $load_filename = '/proc/loadavg';

    my $last;
    my $last5;
    my $last15;

    if (-f $load_filename) {
        my $lastline;

        open my $file, '<', $load_filename;
        while (my $line = <$file>) {
            $lastline = $line;
        }
        close $file;

        ($last, $last5, $last15) = split(" ", $lastline);
    }

    my @data = ([ 'Last', $last ], [ 'Last 5', $last5 ], [ 'Last 15', $last15 ],);

    return @data;
}

=pod

=head1 getNetworkStats

Get stats for the network interfaces.

Parameters:

    format - 'raw', 'hash' or nothing.

Returns:

    When 'format' is not defined:

    @data = (
        [
            'eth0 in',
            '46.11'
        ],
        [
            'eth0 out',
            '63.02'
        ],
        ...
    );

    When 'format' is 'raw':

    @data = (
        [
            'eth0 in',
            '48296309'
        ],
        [
            'eth0 out',
            '66038087'
        ],
        ...
    );

    When 'format' is 'hash':

    @data = (
        {
            in        => '46.12',
            interface => 'eth0',
            out       => '63.04'
        },
        ...
    );

=cut

sub getNetworkStats ($format = "") {
    my $netinfo_filename = '/proc/net/dev';

    unless (-f $netinfo_filename) {
        print "$0: Error: File $netinfo_filename not found.\n";
        exit 1;
    }

    my @outHash;
    my @lines;

    if (open(my $file, '<', $netinfo_filename)) {
        chomp(@lines = <$file>);
        close $file;
    }
    else {
        my $msg = "Could not open the file '$netinfo_filename': $!";
        log_error($msg);
        die $msg;
    }

    my ($in, $out);
    my @data;
    my @interface;
    my @interfacein;
    my @interfaceout;

    my $alias;
    $alias = &eload(
        module => 'Relianoid::EE::Alias',
        func   => 'getAlias',
        args   => ['interface']
    ) if $eload;

    my $i = -1;

    my @skip_interfaces = ();
    push @skip_interfaces, qw(gre0 gretap0 erspan0);    # fallback devices from ip_gre module
    push @skip_interfaces, qw(ip6gre0 ip6tnl0);         # fallback devices from ip6_gre module
    push @skip_interfaces, qw(sit0);                    # fallback devices from sit module
    push @skip_interfaces, qw(cl_maintenance);          # cluster interface
    push @skip_interfaces, qw(lo);                      # loopback interface

    for my $line (@lines) {
        unless ($line =~ /:/) {
            next;
        }

        my @iface = split(":", $line);
        my $if    = $iface[0];
        $if =~ s/ //g;

        # ignore skipped interfaces
        if (grep { $if eq $_ } @skip_interfaces) {
            next;
        }

        $i++;

        if ($line =~ /: /) {
            ($in, $out) = (split /\s+/, $iface[1])[ 1, 9 ];
        }
        else {
            ($in, $out) = (split /\s+/, $line)[ 0, 8 ];
            $in = (split /:/, $in)[1];
        }

        if ($format ne "raw") {
            $in  = (($in / 1024) / 1024);
            $out = (($out / 1024) / 1024);
            $in  = sprintf('%.2f', $in);
            $out = sprintf('%.2f', $out);
        }

        push @interface,    $if;
        push @interfacein,  $in;
        push @interfaceout, $out;
        push @outHash, { interface => $if, in => $in, out => $out };

        $outHash[-1]->{alias} = $alias->{$if} if $eload;
    }

    for (my $j = 0 ; $j <= $i ; $j++) {
        my $label_in  = $interface[$j] . ' in';
        my $label_out = $interface[$j] . ' out';
        push @data, [ $label_in, $interfacein[$j] ], [ $label_out, $interfaceout[$j] ];
    }

    if ($format eq 'hash') {
        @data = sort { $a->{interface} cmp $b->{interface} } @outHash;
    }

    return @data;
}

=pod

=head1 getCPU

Get system CPU usage stats.

Parameters:

    none

Returns:

    list - Two dimensional array.

    Example:

    @data = (
              ['CPUuser',    $cpu_user],
              ['CPUnice',    $cpu_nice],
              ['CPUsys',     $cpu_sys],
              ['CPUiowait',  $cpu_iowait],
              ['CPUirq',     $cpu_irq],
              ['CPUsoftirq', $cpu_softirq],
              ['CPUidle',    $cpu_idle],
              ['CPUusage',   $cpu_usage],
    );

=cut

sub getCPU () {
    my @data;
    my $interval         = 1;
    my $cpuinfo_filename = '/proc/stat';

    unless (-f $cpuinfo_filename) {
        print "$0: Error: File $cpuinfo_filename not exist ...\n";
        exit 1;
    }

    my $cpu_user1;
    my $cpu_nice1;
    my $cpu_sys1;
    my $cpu_idle1;
    my $cpu_iowait1;
    my $cpu_irq1;
    my $cpu_softirq1;
    my $cpu_total1;

    my $cpu_user2;
    my $cpu_nice2;
    my $cpu_sys2;
    my $cpu_idle2;
    my $cpu_iowait2;
    my $cpu_irq2;
    my $cpu_softirq2;
    my $cpu_total2;

    my @line_s;

    if (open my $file, '<', $cpuinfo_filename) {
        my @lines = <$file>;
        close $file;

        for my $line (@lines) {
            if ($line =~ /^cpu\ /) {
                @line_s       = split("\ ", $line);
                $cpu_user1    = $line_s[1];
                $cpu_nice1    = $line_s[2];
                $cpu_sys1     = $line_s[3];
                $cpu_idle1    = $line_s[4];
                $cpu_iowait1  = $line_s[5];
                $cpu_irq1     = $line_s[6];
                $cpu_softirq1 = $line_s[7];
                $cpu_total1   = $cpu_user1 + $cpu_nice1 + $cpu_sys1 + $cpu_idle1 + $cpu_iowait1 + $cpu_irq1 + $cpu_softirq1;
            }
        }
    }

    sleep $interval;

    if (open my $file, '<', $cpuinfo_filename) {
        my @lines = <$file>;
        close $file;

        for my $line (@lines) {
            if ($line =~ /^cpu\ /) {
                @line_s       = split("\ ", $line);
                $cpu_user2    = $line_s[1];
                $cpu_nice2    = $line_s[2];
                $cpu_sys2     = $line_s[3];
                $cpu_idle2    = $line_s[4];
                $cpu_iowait2  = $line_s[5];
                $cpu_irq2     = $line_s[6];
                $cpu_softirq2 = $line_s[7];
                $cpu_total2   = $cpu_user2 + $cpu_nice2 + $cpu_sys2 + $cpu_idle2 + $cpu_iowait2 + $cpu_irq2 + $cpu_softirq2;
            }
        }
    }

    my $diff_cpu_user    = $cpu_user2 - $cpu_user1;
    my $diff_cpu_nice    = $cpu_nice2 - $cpu_nice1;
    my $diff_cpu_sys     = $cpu_sys2 - $cpu_sys1;
    my $diff_cpu_idle    = $cpu_idle2 - $cpu_idle1;
    my $diff_cpu_iowait  = $cpu_iowait2 - $cpu_iowait1;
    my $diff_cpu_irq     = $cpu_irq2 - $cpu_irq1;
    my $diff_cpu_softirq = $cpu_softirq2 - $cpu_softirq1;
    my $diff_cpu_total   = $cpu_total2 - $cpu_total1;

    my $cpu_user    = (100 * $diff_cpu_user) / $diff_cpu_total;
    my $cpu_nice    = (100 * $diff_cpu_nice) / $diff_cpu_total;
    my $cpu_sys     = (100 * $diff_cpu_sys) / $diff_cpu_total;
    my $cpu_idle    = (100 * $diff_cpu_idle) / $diff_cpu_total;
    my $cpu_iowait  = (100 * $diff_cpu_iowait) / $diff_cpu_total;
    my $cpu_irq     = (100 * $diff_cpu_irq) / $diff_cpu_total;
    my $cpu_softirq = (100 * $diff_cpu_softirq) / $diff_cpu_total;

    my $cpu_usage = $cpu_user + $cpu_nice + $cpu_sys + $cpu_iowait + $cpu_irq + $cpu_softirq;

    $cpu_user    = sprintf("%.2f", $cpu_user);
    $cpu_nice    = sprintf("%.2f", $cpu_nice);
    $cpu_sys     = sprintf("%.2f", $cpu_sys);
    $cpu_iowait  = sprintf("%.2f", $cpu_iowait);
    $cpu_irq     = sprintf("%.2f", $cpu_irq);
    $cpu_softirq = sprintf("%.2f", $cpu_softirq);
    $cpu_idle    = sprintf("%.2f", $cpu_idle);
    $cpu_usage   = sprintf("%.2f", $cpu_usage);

    $cpu_user    =~ s/,/\./g;
    $cpu_nice    =~ s/,/\./g;
    $cpu_sys     =~ s/,/\./g;
    $cpu_iowait  =~ s/,/\./g;
    $cpu_softirq =~ s/,/\./g;
    $cpu_idle    =~ s/,/\./g;
    $cpu_usage   =~ s/,/\./g;

    @data = (
        [ 'CPUuser',    $cpu_user ],
        [ 'CPUnice',    $cpu_nice ],
        [ 'CPUsys',     $cpu_sys ],
        [ 'CPUiowait',  $cpu_iowait ],
        [ 'CPUirq',     $cpu_irq ],
        [ 'CPUsoftirq', $cpu_softirq ],
        [ 'CPUidle',    $cpu_idle ],
        [ 'CPUusage',   $cpu_usage ],
    );

    return @data;
}

sub getCPUUsageStats () {
    my $out;

    my @data_cpu = &getCPU();

    for my $x (0 .. @data_cpu - 1) {
        my $name  = $data_cpu[$x][0];
        my $value = $data_cpu[$x][1] + 0;

        (undef, $name) = split('CPU', $name);

        $out->{$name} = $value;
    }

    return $out;
}

=pod

=head1 getDiskSpace

Return total, used and free space for every partition in the system.

Parameters:

    none

Returns:

    list - Two dimensional array.

    @data = (
        [
            'dev-dm-0 Total',
            1981104128
        ],
        [
            'dev-dm-0 Used',
            1707397120
        ],
        [
            'dev-dm-0 Free',
            154591232
        ],
        ...
    );

See Also:

    disk-rrd.pl

=cut

sub getDiskSpace () {
    my @data;

    my $df_bin = &getGlobalConfiguration('df_bin');
    my @system = @{ &logAndGet("$df_bin -k", "array") };
    chomp(@system);
    my @df_system = @system;

    for my $line (@system) {
        next if $line !~ /^\/dev/;

        my @dd_name = split(' ', $line);
        my $dd_name = $dd_name[0];

        my ($line_df) = grep ({ /^$dd_name\s/ } @df_system);
        my @s_line = split(/\s+/, $line_df);

        my $partitions = $s_line[0];
        $partitions =~ s/\///;
        $partitions =~ s/\//-/g;

        my $tot  = $s_line[1] * 1024;
        my $used = $s_line[2] * 1024;
        my $free = $s_line[3] * 1024;

        push(@data, [ $partitions . ' Total', $tot ], [ $partitions . ' Used', $used ], [ $partitions . ' Free', $free ]);
    }

    return @data;
}

=pod

=head1 getDiskPartitionsInfo

Get a reference to a hash with the partitions devices, mount points and name of rrd database.

Parameters:

    none

Returns:

    scalar - Hash reference.

    Example:

    $partitions = {
        '/dev/dm-0' => {
            mount_point => '/',
            rrd_id      => 'dev-dm-0hd'
        },
        '/dev/mapper/zva64-config' => {
            mount_point => '/usr/local/relianoid/config',
            rrd_id      => 'dev-mapper-zva64-confighd'
        },
        '/dev/mapper/zva64-log' => {
            mount_point => '/var/log',
            rrd_id      => 'dev-mapper-zva64-loghd'
        },
        '/dev/xvda1' => {
            mount_point => '/boot',
            rrd_id      => 'dev-xvda1hd'
        }
    };

=cut

sub getDiskPartitionsInfo () {
    my $partitions;

    my $df_bin = &getGlobalConfiguration('df_bin');

    my @out      = @{ &logAndGet("$df_bin -k", "array") };
    my @df_lines = grep { /^\/dev/ } @out;
    chomp(@df_lines);

    for my $line (@df_lines) {
        my @df_line = split(/\s+/, $line);

        my $mount_point = $df_line[5];
        my $partition   = $df_line[0];
        my $part_id     = $df_line[0];
        $part_id =~ s/\///;
        $part_id =~ s/\//-/g;

        $partitions->{$partition} = {
            mount_point => $mount_point,
            rrd_id      => "${part_id}hd",
        };
    }

    return $partitions;
}

=pod

=head1 getDiskMountPoint

Get the mount point of a partition device

Parameters:

    dev - Partition device.

Returns:

    string - Mount point for such partition device.
    undef  - The partition device is not mounted

See Also:

    <genDiskGraph>

=cut

sub getDiskMountPoint ($dev) {
    my $df_bin    = &getGlobalConfiguration('df_bin');
    my @df_system = @{ &logAndGet("$df_bin -k", "array") };
    my $mount;

    for my $line_df (@df_system) {
        if ($line_df =~ /$dev/) {
            my @s_line = split("\ ", $line_df);
            chomp(@s_line);

            $mount = $s_line[5];
        }
    }

    return $mount;
}

=pod

=head1 getCPUTemp

Get the CPU temperature in celsius degrees.

Parameters:

    none

Returns:

    string - Temperature in celsius degrees.

See Also:

    temperature-rrd.pl

=cut

sub getCPUTemp () {
    my $filename = &getGlobalConfiguration("temperatureFile");
    my $lastline;

    unless (-f $filename) {
        exit 1;
    }

    open my $file, '<', $filename;

    while (my $line = <$file>) {
        $lastline = $line;
    }

    close $file;

    my @lastlines = split("\:", $lastline);
    my $temp      = $lastlines[1];
    $temp =~ s/\ //g;
    $temp =~ s/\n//g;
    $temp =~ s/C//g;

    return $temp;
}

1;

