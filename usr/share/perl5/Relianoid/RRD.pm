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
use RRDs;
use MIME::Base64;
use Relianoid::Config;

my $eload = eval { require Relianoid::ELoad };

my $width     = "600";
my $height    = "150";
my $imagetype = "PNG";

=pod

=head1 Module

Relianoid::RRD

=cut

=pod

=head1 translateRRDTime

It translates a time from API format (11-09-2020-14:05) to RRD format (11/09/2020 14:05).
Also, it returns the rrd format for daily, weekly, monthly or yearly.

Parameters:

    time - Time in API format

Returns:

    scalar - Date in RRD format

=cut

sub translateRRDTime ($time) {
    if (!defined $time) {
        return "now";
    }
    elsif ($time =~ /^([dwmy])/) {
        return "-1$1";
    }
    elsif ($time =~ /^(\d\d-\d\d-(?:\d\d)?\d\d)-(\d\d:\d\d)$/) {
        # in (api): "11-09-2020-14:05"
        # out(rrd): "11/09/2020 14:05"
        my $date = $1;
        my $hour = $2;

        $date =~ s'-'/'g;
        return "$date $hour";
    }
    return $time;
}

=pod

=head1 logRRDError

It checks if some error exists in the last RRD read and it logs it

Parameters:

    graph file - it is the graph file created of reading the RRD

Returns: integer - Error code.

- 0: success
- 1: error

=cut

sub logRRDError ($graph) {
    my $error = RRDs::error;

    if ($error || !-s $graph) {
        $error //= 'The graph was not generated';
        &log_error("$0: unable to generate $graph: $error");
        return 1;
    }

    return 0;
}

=pod

=head1 getRRDAxisXLimits

It returns the first and last time value for a graph.
It returns the times with the RELIANOID API format (11-09-2020-14:05)

Parameters:

    start - string - Date of the begining of the chart
    last  - string - Date of the end of the chart

Returns: array

Pair of strings with the dates defining the range of a chart, both included.

=cut

sub getRRDAxisXLimits ($start, $last) {
    my $format = "%m-%d-%Y-%H:%M";

    use POSIX qw(strftime);

    ($start, $last) = RRDs::times($start, $last);

    #     0    1    2     3     4    5     6     7     8
    # my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my @t = localtime($last);
    $last  = strftime($format, @t);
    @t     = localtime($start);
    $start = strftime($format, @t);

    return ($start, $last);
}

=pod

=head1 printImgFile

Get a file encoded in base64 and remove it.

Parameters:

    file - Path to image file.

Returns: string

- On success: Base64 encoded image.
- On error: Empty string.

=cut

sub printImgFile ($file) {
    if (open my $png, '<', $file) {
        my $raw_string = do { local $/ = undef; <$png>; };
        my $encoded    = encode_base64($raw_string);

        close $png;

        unlink($file);
        return $encoded;
    }
    else {
        return "";
    }
}

=pod

=head1 delGraph

Remove a farm,  network interface or vpn graph.

Parameters:

    name - Name of the graph resource, without sufixes.
    type - 'farm', 'iface', 'vpn'.

Returns: Nothing

=cut

sub delGraph ($name, $type) {
    my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');

    if ($type =~ /iface/) {
        my $filename = "${collector_rrd_dir}/${name}iface.rrd";
        &log_info("Delete graph file: ${filename}", "MONITOR");
        unlink($filename);
    }

    if ($type =~ /farm/) {
        my $filename = "${collector_rrd_dir}/${name}-farm.rrd";
        &log_info("Delete graph file: ${filename}", "MONITOR");
        unlink glob($filename);

        &eload(
            module => 'Relianoid::EE::IPDS::Stats',
            func   => 'delIPDSRRDFile',
            args   => [$name],
        ) if $eload;
    }

    if ($type =~ /vpn/) {
        my $filename = "${collector_rrd_dir}/${name}-vpn.rrd";
        &log_info("Delete graph file: ${filename}", "MONITOR");
        unlink glob($filename);
    }

    return;
}

=pod

=head1 printGraph

Get a graph 'type' of a period of time base64 encoded.

Parameters:

    type - Filter or name of the graph.
    time/start - This parameter can have one of the following values: *
        * Period of time shown in the image (Possible values: daily, d, weekly, w, monthly, m, yearly, y).
        * time which the graph starts. Format: MM-DD-YYYY-HH:mm (ie: 11-09-2020-14:05)
    end - time which the graph stops. The default value is "now", the current time.

Returns: hash reference

The output hash contains the following keys:

    img   - Base64 encoded image, or an empty string on failure,
    start - firt time of the graph
    last  - last time of the graph

=cut

sub printGraph ($type, $time, $end = "now") {
    my $graph_fn = sprintf "%s/${type}_${time}.png", &getGlobalConfiguration('img_dir');

    $time = &translateRRDTime($time);
    $end  = &translateRRDTime($end);

    if ($type eq "cpu") {
        &genCpuGraph($type, $graph_fn, $time, $end);
    }
    elsif ($type =~ /^dev-*/) {
        &genDiskGraph($type, $graph_fn, $time, $end);
    }
    elsif ($type eq "load") {
        &genLoadGraph($type, $graph_fn, $time, $end);
    }
    elsif ($type eq "mem") {
        &genMemGraph($type, $graph_fn, $time, $end);
    }
    elsif ($type eq "memsw") {
        &genMemSwGraph($type, $graph_fn, $time, $end);
    }
    elsif ($type =~ /iface$/) {
        &genNetGraph($type, $graph_fn, $time, $end);
    }
    elsif ($type =~ /-farm$/) {
        &genFarmGraph($type, $graph_fn, $time, $end);
    }
    elsif ($eload and $type =~ /ipds$/) {
        &eload(
            module => 'Relianoid::EE::IPDS::Stats',
            func   => 'genIPDSGraph',
            args   => [ $type, $graph_fn, $time, $end ],
        );
    }
    elsif ($eload && $type =~ /-vpn$/) {
        &genVPNGraph($type, $graph_fn, $time);
    }
    else {
        &log_error("The requested graph '$type' is unknown");
        return {};
    }

    if (&logRRDError($graph_fn)) {
        return {};
    }

    ($time, $end) = &getRRDAxisXLimits($time, $end);

    return {
        img   => &printImgFile($graph_fn),
        start => $time,
        last  => $end
    };
}

=pod

=head1 genCpuGraph

Generate CPU usage graph image file for a period of time.

Parameters:

    type  - Database name without extension.
    graph - Path to file to be generated.
    start - time which the graph starts. Format: MM-DD-YYYY-HH:mm (ie: 11-09-2020-14:05)
    end   - time which the graph stops

Returns: Nothing

=cut

sub genCpuGraph ($type, $graph, $start, $end) {
    my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');
    my $cpu_db            = "${collector_rrd_dir}/${type}.rrd";

    if (-e $cpu_db) {
        RRDs::graph(
            $graph,
            "--imgformat=${imagetype}",
            "--start=${start}",
            "--end=${end}",
            "--width=${width}",
            "--height=${height}",
            "--alt-autoscale-max",
            "--lower-limit=0",
            "--title=CPU",
            "--vertical-label=%",
            "DEF:user=${cpu_db}:user:AVERAGE",
            "DEF:nice=${cpu_db}:nice:AVERAGE",
            "DEF:sys=${cpu_db}:sys:AVERAGE",
            "DEF:iowait=${cpu_db}:iowait:AVERAGE",
            "DEF:irq=${cpu_db}:irq:AVERAGE",
            "DEF:softirq=${cpu_db}:softirq:AVERAGE",
            "DEF:idle=${cpu_db}:idle:AVERAGE",
            "DEF:tused=${cpu_db}:tused:AVERAGE",
            "AREA:sys#DC374A:System\\t",
            "GPRINT:sys:LAST:Last\\:%8.2lf %%",
            "GPRINT:sys:MIN:Min\\:%8.2lf %%",
            "GPRINT:sys:AVERAGE:Avg\\:%8.2lf %%",
            "GPRINT:sys:MAX:Max\\:%8.2lf %%\\n",
            "STACK:user#6B2E9A:User\\t\\t",
            "GPRINT:user:LAST:Last\\:%8.2lf %%",
            "GPRINT:user:MIN:Min\\:%8.2lf %%",
            "GPRINT:user:AVERAGE:Avg\\:%8.2lf %%",
            "GPRINT:user:MAX:Max\\:%8.2lf %%\\n",
            "STACK:nice#ACD936:Nice\\t\\t",
            "GPRINT:nice:LAST:Last\\:%8.2lf %%",
            "GPRINT:nice:MIN:Min\\:%8.2lf %%",
            "GPRINT:nice:AVERAGE:Avg\\:%8.2lf %%",
            "GPRINT:nice:MAX:Max\\:%8.2lf %%\\n",
            "STACK:iowait#8D85F3:Iowait\\t",
            "GPRINT:iowait:LAST:Last\\:%8.2lf %%",
            "GPRINT:iowait:MIN:Min\\:%8.2lf %%",
            "GPRINT:iowait:AVERAGE:Avg\\:%8.2lf %%",
            "GPRINT:iowait:MAX:Max\\:%8.2lf %%\\n",
            "STACK:irq#46F2A2:Irq\\t\\t",
            "GPRINT:irq:LAST:Last\\:%8.2lf %%",
            "GPRINT:irq:MIN:Min\\:%8.2lf %%",
            "GPRINT:irq:AVERAGE:Avg\\:%8.2lf %%",
            "GPRINT:irq:MAX:Max\\:%8.2lf %%\\n",
            "STACK:softirq#595959:Softirq\\t",
            "GPRINT:softirq:LAST:Last\\:%8.2lf %%",
            "GPRINT:softirq:MIN:Min\\:%8.2lf %%",
            "GPRINT:softirq:AVERAGE:Avg\\:%8.2lf %%",
            "GPRINT:softirq:MAX:Max\\:%8.2lf %%\\n",
            "STACK:idle#46b971:Idle\\t\\t",
            "GPRINT:idle:LAST:Last\\:%8.2lf %%",
            "GPRINT:idle:MIN:Min\\:%8.2lf %%",
            "GPRINT:idle:AVERAGE:Avg\\:%8.2lf %%",
            "GPRINT:idle:MAX:Max\\:%8.2lf %%\\n",
            "LINE1:tused#000000:Total used\\t",
            "GPRINT:tused:LAST:Last\\:%8.2lf %%",
            "GPRINT:tused:MIN:Min\\:%8.2lf %%",
            "GPRINT:tused:AVERAGE:Avg\\:%8.2lf %%",
            "GPRINT:tused:MAX:Max\\:%8.2lf %%\\n"
        );
    }

    return;
}

=pod

=head1 genDiskGraph

Generate disk partition usage graph image file for a period of time.

Parameters:

    type  - Database name without extension.
    graph - Path to file to be generated.
    start - time which the graph starts. Format: MM-DD-YYYY-HH:mm (ie: 11-09-2020-14:05)
    end   - time which the graph stops

Returns: Nothing

=cut

sub genDiskGraph ($type, $graph, $start, $end) {
    my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');
    my $hd_db             = "${collector_rrd_dir}/${type}.rrd";

    my $device = $type;
    $device =~ s/hd$//;
    $device =~ s/dev-//;
    $device =~ s/-/\// if $device !~ /dm-/;

    my $mount = &getDiskMountPoint($device);

    if (-e $hd_db) {
        RRDs::graph(
            $graph,
            "--start=${start}",                        #
            "--end=${end}",                            #
            "--title=PARTITION ${mount}",              #
            "--vertical-label=SPACE",                  #
            "--width=${width}",                        #
            "--height=${height}",                      #
            "--lazy",                                  #
            "-l 0",                                    #
            "-a",                                      #
            "$imagetype",                              #
            "DEF:tot=${hd_db}:tot:AVERAGE",            #
            "DEF:used=${hd_db}:used:AVERAGE",          #
            "DEF:free=${hd_db}:free:AVERAGE",          #
            "CDEF:total=used,free,+",                  #
            "AREA:used#595959:Used\\t",                #
            "GPRINT:used:LAST:Last\\:%8.2lf %s",       #
            "GPRINT:used:MIN:Min\\:%8.2lf %s",         #
            "GPRINT:used:AVERAGE:Avg\\:%8.2lf %s",     #
            "GPRINT:used:MAX:Max\\:%8.2lf %s\\n",      #
            "STACK:free#46b971:Free\\t",               #
            "GPRINT:free:LAST:Last\\:%8.2lf %s",       #
            "GPRINT:free:MIN:Min\\:%8.2lf %s",         #
            "GPRINT:free:AVERAGE:Avg\\:%8.2lf %s",     #
            "GPRINT:free:MAX:Max\\:%8.2lf %s\\n",      #
            "LINE1:total#000000:Total\\t",             #
            "GPRINT:total:LAST:Last\\:%8.2lf %s",      #
            "GPRINT:total:MIN:Min\\:%8.2lf %s",        #
            "GPRINT:total:AVERAGE:Avg\\:%8.2lf %s",    #
            "GPRINT:total:MAX:Max\\:%8.2lf %s\\n"      #
        );
    }

    return;
}

=pod

=head1 genLoadGraph

Generate system load graph image file for a period of time.

Parameters:

    type  - Database name without extension.
    graph - Path to file to be generated.
    start - Period of time shown in the graph.
    end   - End time period

Returns: Nothing

=cut

sub genLoadGraph ($type, $graph, $start, $end) {
    my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');
    my $load_db           = "${collector_rrd_dir}/${type}.rrd";

    if (-e $load_db) {
        RRDs::graph(
            $graph,                                      #
            "--imgformat=${imagetype}",                  #
            "--start=${start}",                          #
            "--end=${end}",                              #
            "--width=${width}",                          #
            "--height=${height}",                        #
            "--alt-autoscale-max",                       #
            "--lower-limit=0",                           #
            "--title=LOAD AVERAGE",                      #
            "--vertical-label=LOAD",                     #
            "DEF:load=${load_db}:load:AVERAGE",          #
            "DEF:load5=${load_db}:load5:AVERAGE",        #
            "DEF:load15=${load_db}:load15:AVERAGE",      #
            "AREA:load#729e00:last minute\\t\\t",        #
            "GPRINT:load:LAST:Last\\:%3.2lf",            #
            "GPRINT:load:MIN:Min\\:%3.2lf",              #
            "GPRINT:load:AVERAGE:Avg\\:%3.2lf",          #
            "GPRINT:load:MAX:Max\\:%3.2lf\\n",           #
            "STACK:load5#46b971:last 5 minutes\\t",      #
            "GPRINT:load5:LAST:Last\\:%3.2lf",           #
            "GPRINT:load5:MIN:Min\\:%3.2lf",             #
            "GPRINT:load5:AVERAGE:Avg\\:%3.2lf",         #
            "GPRINT:load5:MAX:Max\\:%3.2lf\\n",          #
            "STACK:load15#595959:last 15 minutes\\t",    #
            "GPRINT:load15:LAST:Last\\:%3.2lf",          #
            "GPRINT:load15:MIN:Min\\:%3.2lf",            #
            "GPRINT:load15:AVERAGE:Avg\\:%3.2lf",        #
            "GPRINT:load15:MAX:Max\\:%3.2lf\\n"          #
        );
    }

    return;
}

=pod

=head1 genMemGraph

Generate RAM memory usage graph image file for a period of time.

Parameters:

    type - Database name without extension.
    graph - Path to file to be generated.
    start - time which the graph starts. Format: MM-DD-YYYY-HH:mm (ie: 11-09-2020-14:05)
    end - time which the graph stops

Returns: Nothing

=cut

sub genMemGraph ($type, $graph, $start, $end) {
    my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');
    my $ram_db            = "${collector_rrd_dir}/${type}.rrd";

    if (-e $ram_db) {
        RRDs::graph(
            $graph,                                   #
            "--imgformat=${imagetype}",               #
            "--start=${start}",                       #
            "--end=${end}",                           #
            "--width=${width}",                       #
            "--height=${height}",                     #
            "--alt-autoscale-max",                    #
            "--lower-limit=0",                        #
            "--title=RAM",                            #
            "--vertical-label=MEMORY",                #
            "--base=1024",                            #
            "DEF:memt=${ram_db}:memt:AVERAGE",        #
            "DEF:memu=${ram_db}:memu:AVERAGE",        #
            "DEF:memf=${ram_db}:memf:AVERAGE",        #
            "DEF:memc=${ram_db}:memc:AVERAGE",        #
            "AREA:memu#595959:Used\\t\\t",            #
            "GPRINT:memu:LAST:Last\\:%8.2lf %s",      #
            "GPRINT:memu:MIN:Min\\:%8.2lf %s",        #
            "GPRINT:memu:AVERAGE:Avg\\:%8.2lf %s",    #
            "GPRINT:memu:MAX:Max\\:%8.2lf %s\\n",     #
            "STACK:memf#46b971:Free\\t\\t",           #
            "GPRINT:memf:LAST:Last\\:%8.2lf %s",      #
            "GPRINT:memf:MIN:Min\\:%8.2lf %s",        #
            "GPRINT:memf:AVERAGE:Avg\\:%8.2lf %s",    #
            "GPRINT:memf:MAX:Max\\:%8.2lf %s\\n",     #
            "LINE2:memc#46F2A2:Cache&Buffer\\t",      #
            "GPRINT:memc:LAST:Last\\:%8.2lf %s",      #
            "GPRINT:memc:MIN:Min\\:%8.2lf %s",        #
            "GPRINT:memc:AVERAGE:Avg\\:%8.2lf %s",    #
            "GPRINT:memc:MAX:Max\\:%8.2lf %s\\n",     #
            "LINE1:memt#000000:Total\\t\\t",          #
            "GPRINT:memt:LAST:Last\\:%8.2lf %s",      #
            "GPRINT:memt:MIN:Min\\:%8.2lf %s",        #
            "GPRINT:memt:AVERAGE:Avg\\:%8.2lf %s",    #
            "GPRINT:memt:MAX:Max\\:%8.2lf %s\\n"      #
        );
    }

    return;
}

=pod

=head1 genMemSwGraph

Generate swap memory usage graph image file for a period of time.

Parameters:

    type  - Database name without extension.
    graph - Path to file to be generated.
    start - time which the graph starts. Format: MM-DD-YYYY-HH:mm (ie: 11-09-2020-14:05)
    end   - time which the graph stops

Returns: Nothing

=cut

sub genMemSwGraph ($type, $graph, $start, $end) {
    my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');
    my $swap_db           = "${collector_rrd_dir}/${type}.rrd";

    if (-e $swap_db) {
        RRDs::graph(
            $graph,                                  #
            "--imgformat=${imagetype}",              #
            "--start=${start}",                      #
            "--end=${end}",                          #
            "--width=${width}",                      #
            "--height=${height}",                    #
            "--alt-autoscale-max",                   #
            "--lower-limit=0",                       #
            "--title=SWAP",                          #
            "--vertical-label=MEMORY",               #
            "--base=1024",                           #
            "DEF:swt=${swap_db}:swt:AVERAGE",        #
            "DEF:swu=${swap_db}:swu:AVERAGE",        #
            "DEF:swf=${swap_db}:swf:AVERAGE",        #
            "DEF:swc=${swap_db}:swc:AVERAGE",        #
            "AREA:swu#595959:Used\\t\\t",            #
            "GPRINT:swu:LAST:Last\\:%8.2lf %s",      #
            "GPRINT:swu:MIN:Min\\:%8.2lf %s",        #
            "GPRINT:swu:AVERAGE:Avg\\:%8.2lf %s",    #
            "GPRINT:swu:MAX:Max\\:%8.2lf %s\\n",     #
            "STACK:swf#46b971:Free\\t\\t",           #
            "GPRINT:swf:LAST:Last\\:%8.2lf %s",      #
            "GPRINT:swf:MIN:Min\\:%8.2lf %s",        #
            "GPRINT:swf:AVERAGE:Avg\\:%8.2lf %s",    #
            "GPRINT:swf:MAX:Max\\:%8.2lf %s\\n",     #
            "LINE2:swc#46F2A2:Cached\\t",            #
            "GPRINT:swc:LAST:Last\\:%8.2lf %s",      #
            "GPRINT:swc:MIN:Min\\:%8.2lf %s",        #
            "GPRINT:swc:AVERAGE:Avg\\:%8.2lf %s",    #
            "GPRINT:swc:MAX:Max\\:%8.2lf %s\\n",     #
            "LINE1:swt#000000:Total\\t\\t",          #
            "GPRINT:swt:LAST:Last\\:%8.2lf %s",      #
            "GPRINT:swt:MIN:Min\\:%8.2lf %s",        #
            "GPRINT:swt:AVERAGE:Avg\\:%8.2lf %s",    #
            "GPRINT:swt:MAX:Max\\:%8.2lf %s\\n",     #
        );
    }

    return;
}

=pod

=head1 genNetGraph

Generate network interface usage graph image file for a period of time.

Parameters:

    type  - Database name without extension.
    graph - Path to file to be generated.
    start - time which the graph starts. Format: MM-DD-YYYY-HH:mm (ie: 11-09-2020-14:05)
    end   - time which the graph stops

Returns: Nothing

=cut

sub genNetGraph ($type, $graph, $start, $end) {
    my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');
    my $interface_db      = "${collector_rrd_dir}/${type}.rrd";
    my $interface_name    = $type;
    $interface_name =~ s/iface//g;

    if (-e $interface_db) {
        RRDs::graph(
            $graph,                                                #
            "--imgformat=${imagetype}",                            #
            "--start=${start}",                                    #
            "--end=${end}",                                        #
            "--height=${height}",                                  #
            "--width=${width}",                                    #
            "--lazy",                                              #
            "-l 0",                                                #
            "--alt-autoscale-max",                                 #
            "--title=TRAFFIC ON ${interface_name}",                #
            "--vertical-label=BANDWIDTH",                          #
            "DEF:in=${interface_db}:in:AVERAGE",                   #
            "DEF:out=${interface_db}:out:AVERAGE",                 #
            "CDEF:in_bytes=in,1024,*",                             #
            "CDEF:out_bytes=out,1024,*",                           #
            "CDEF:out_bytes_neg=out_bytes,-1,*",                   #
            "AREA:in_bytes#46b971:In ",                            #
            "LINE1:in_bytes#000000",                               #
            "GPRINT:in_bytes:LAST:Last\\:%5.1lf %sByte/sec",       #
            "GPRINT:in_bytes:MIN:Min\\:%5.1lf %sByte/sec",         #
            "GPRINT:in_bytes:AVERAGE:Avg\\:%5.1lf %sByte/sec",     #
            "GPRINT:in_bytes:MAX:Max\\:%5.1lf %sByte/sec\\n",      #
            "AREA:out_bytes_neg#595959:Out",                       #
            "LINE1:out_bytes_neg#000000",                          #
            "GPRINT:out_bytes:LAST:Last\\:%5.1lf %sByte/sec",      #
            "GPRINT:out_bytes:MIN:Min\\:%5.1lf %sByte/sec",        #
            "GPRINT:out_bytes:AVERAGE:Avg\\:%5.1lf %sByte/sec",    #
            "GPRINT:out_bytes:MAX:Max\\:%5.1lf %sByte/sec\\n",     #
            "HRULE:0#000000"                                       #
        );
    }

    return;
}

=pod

=head1 genFarmGraph

Generate farm connections graph image file for a period of time.

Parameters:

    type  - Database name without extension.
    graph - Path to file to be generated.
    start - time which the graph starts. Format: MM-DD-YYYY-HH:mm (ie: 11-09-2020-14:05)
    end   - time which the graph stops

Returns:

    none

See Also:

    <printGraph>

    <genCpuGraph>, <genDiskGraph>, <genLoadGraph>, <genMemGraph>, <genMemSwGraph>, <genNetGraph>, <genLoadGraph>

=cut

sub genFarmGraph ($type, $graph, $start, $end) {
    my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');
    my $farm_db           = "${collector_rrd_dir}/${type}.rrd";
    my $farm_name         = $type;
    $farm_name =~ s/-farm$//g;

    if (-e $farm_db) {
        RRDs::graph(
            $graph,
            "--start=${start}",
            "--end=${end}",
            "--height=${height}",    #
            "--width=${width}",      #
            "--lazy",
            "-l 0",
            "-a",
            "${imagetype}",
            "--title=CONNECTIONS ON ${farm_name} farm",
            "--vertical-label=Connections",
            "DEF:pending=${farm_db}:pending:AVERAGE",
            "DEF:established=${farm_db}:established:AVERAGE",

            # "DEF:closed=$db_farm:closed:AVERAGE",
            "LINE2:pending#595959:Pending\\t",
            "GPRINT:pending:LAST:Last\\:%6.0lf ",
            "GPRINT:pending:MIN:Min\\:%6.0lf ",
            "GPRINT:pending:AVERAGE:Avg\\:%6.0lf ",
            "GPRINT:pending:MAX:Max\\:%6.0lf \\n",
            "LINE2:established#46b971:Established\\t",
            "GPRINT:established:LAST:Last\\:%6.0lf ",
            "GPRINT:established:MIN:Min\\:%6.0lf ",
            "GPRINT:established:AVERAGE:Avg\\:%6.0lf ",
            "GPRINT:established:MAX:Max\\:%6.0lf \\n"

              # "LINE2:closed#46F2A2:Closed\\t",
              # "GPRINT:closed:LAST:Last\\:%6.0lf ",
              # "GPRINT:closed:MIN:Min\\:%6.0lf ",
              # "GPRINT:closed:AVERAGE:Avg\\:%6.0lf ",
              # "GPRINT:closed:MAX:Max\\:%6.0lf \\n"
        );
    }

    return;
}

=pod

=head1 genVPNGraph

Generate VPN usage graph image file for a period of time.

Parameters:

    type - Database name without extension.
    graph - Path to file to be generated.
    time - Period of time shown in the graph.

Returns: Nothing

=cut

sub genVPNGraph ($type, $graph, $time) {
    my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');
    my $vpn_db            = "${collector_rrd_dir}/${type}.rrd";
    my $vpn_name          = $type;
    $vpn_name =~ s/-vpn$//g;

    if (-e $vpn_db) {
        RRDs::graph(
            $graph,                                                #
            "--imgformat=${imagetype}",                            #
            "--start=-1${time}",                                   #
            "--height=${height}",                                  #
            "--width=${width}",                                    #
            "--lazy",                                              #
            "-l 0",                                                #
            "--alt-autoscale-max",                                 #
            "--title=TRAFFIC ON ${vpn_name}",                      #
            "--vertical-label=BANDWIDTH",                          #
            "DEF:in=${vpn_db}:in:AVERAGE",                         #
            "DEF:out=${vpn_db}:out:AVERAGE",                       #
            "CDEF:in_bytes=in,1024,*",                             #
            "CDEF:out_bytes=out,1024,*",                           #
            "CDEF:out_bytes_neg=out_bytes,-1,*",                   #
            "AREA:in_bytes#46b971:In ",                            #
            "LINE1:in_bytes#000000",                               #
            "GPRINT:in_bytes:LAST:Last\\:%5.1lf %sByte/sec",       #
            "GPRINT:in_bytes:MIN:Min\\:%5.1lf %sByte/sec",         #
            "GPRINT:in_bytes:AVERAGE:Avg\\:%5.1lf %sByte/sec",     #
            "GPRINT:in_bytes:MAX:Max\\:%5.1lf %sByte/sec\\n",      #
            "AREA:out_bytes_neg#595959:Out",                       #
            "LINE1:out_bytes_neg#000000",                          #
            "GPRINT:out_bytes:LAST:Last\\:%5.1lf %sByte/sec",      #
            "GPRINT:out_bytes:MIN:Min\\:%5.1lf %sByte/sec",        #
            "GPRINT:out_bytes:AVERAGE:Avg\\:%5.1lf %sByte/sec",    #
            "GPRINT:out_bytes:MAX:Max\\:%5.1lf %sByte/sec\\n",     #
            "HRULE:0#000000"                                       #
        );

        my $rrdError = RRDs::error;
        print "$0: unable to generate ${graph}: ${rrdError}\n" if ($rrdError);
    }

    return;
}

=pod

=head1 getGraphs2Show

Get list of graph names by type or all of them.

Parameters:

    graphtype - 'System', 'Network', 'Farm' or 'VPN'.

Returns: string list - List of graph names

=cut

#function that returns the graph list to show
sub getGraphs2Show ($graphtype) {
    my $collector_rrd_dir = &getGlobalConfiguration('collector_rrd_dir');
    my @dir_list;
    my @results = ();

    if (opendir(my $dir, $collector_rrd_dir)) {
        @dir_list = readdir($dir);
        closedir($dir);
    }
    else {
        log_error("Could not open directory '$collector_rrd_dir/': $!");
        return @results;
    }

    if ($graphtype eq 'System') {
        my @disk = grep { /^dev-.*$/ } @dir_list;
        for (@disk) { s/.rrd$//g }
        @results = ("cpu", @disk, "load", "mem", "memsw");
    }
    elsif ($graphtype eq 'Network') {
        @results = grep { /iface.rrd$/ } sort @dir_list;
        for (@results) { s/.rrd$//g }
    }
    elsif ($graphtype eq 'Farm') {
        @results = grep { /farm.rrd$/ } sort @dir_list;
        for (@results) { s/.rrd$//g }
    }
    elsif ($graphtype eq 'VPN') {
        @results = grep { /vpn.rrd$/ } sort @dir_list;
        for (@results) { s/.rrd$//g }
    }
    else {
        log_error("Graph type not supported.");
    }

    return @results;
}

1;

