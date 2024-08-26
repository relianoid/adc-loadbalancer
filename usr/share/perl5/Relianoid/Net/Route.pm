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
use Relianoid::Core;

my $eload = eval { require Relianoid::ELoad };

my $ip_bin = &getGlobalConfiguration('ip_bin');

=pod

=head1 Module

Relianoid::Net::Route

=cut

=pod

=head1 writeRoutes

It sets a routing table id and name pair in rt_tables file.

Only required setting up a routed interface. Complemented in delIf()

Parameters:

    if_name - network interface name.

Returns:

    none

=cut

# create table route identification, complemented in delIf()
sub writeRoutes ($if_name) {
    my $rttables = &getGlobalConfiguration('rttables');

    &log_debug("Creating table 'table_$if_name'");

    open my $fh, '<', $rttables;
    my @contents = <$fh>;
    close $fh;

    # the table is already in the file, nothig to do
    if (grep { /^...\ttable_$if_name$/ } @contents) {
        return;
    }

    my $found = "false";
    my $rtnumber;

    # Find next table number available
    for (my $i = 200 ; $i < 1000 && $found eq "false" ; $i++) {
        next if (grep { /^$i\t/ } @contents);
        $found    = "true";
        $rtnumber = $i;
    }

    if ($found eq "true") {
        open(my $fh, ">>", $rttables);
        print $fh "$rtnumber\ttable_$if_name\n";
        close $fh;

        &log_info("Created the table ID 'table_$if_name'", "network");
    }

    return;
}

=pod

=head1 deleteRoutesTable

It removes the a routing table id and name pair from the rt_tables file.

Parameters:

    if_name - network interface name.

Returns:

    none

=cut

sub deleteRoutesTable ($if_name) {
    my $rttables = &getGlobalConfiguration('rttables');

    open my $route_table_in, '<', $rttables;
    my @contents = <$route_table_in>;
    close $route_table_in;

    @contents = grep { !/\ttable_$if_name\n/ } @contents;

    open my $route_table_out, '>', $rttables;
    for my $table (@contents) {
        print $route_table_out $table;
    }
    close $route_table_out;
    return;
}

=pod

=head1 applyRoutingCmd

It creates the command to add a routing entry in a table.

Depend on the passed parameter, it can delete, add or replace the route

Parameters:

    action - it is the action to apply: add, replace or del
    if_ref - network interface hash reference
    table - it is the routing table where the entry will be added

Returns:

    Integer - Error code, it is 0 on success or another value on

TODO:

    use the 'buildRouteCmd' function

=cut

sub applyRoutingCmd ($action, $if_ref, $table) {
    use NetAddr::IP;
    my $routeparams = &getGlobalConfiguration('routeparams');
    my $ip_local    = NetAddr::IP->new($$if_ref{addr}, $$if_ref{mask});
    my $net_local   = $ip_local->network();

    &log_debug("addlocalnet: $action route for $$if_ref{name} in table $table", "NETWORK")
      if &debug();

    my $ip_cmd =
      "$ip_bin -$$if_ref{ip_v} route $action $net_local dev $$if_ref{name} src $$if_ref{addr} table $table $routeparams";

    my $err = &logAndRun($ip_cmd);
    return $err;
}

=pod

=head1 addlocalnet

Set routes to interface subnet into interface routing tables and fills the interface table.

Parameters:

    if_ref - network interface hash reference.

Returns:

    void - .

See Also:

    Only used here: <applyRoutes>

=cut

sub addlocalnet ($if_ref) {
    &log_debug("addlocalnet( name: $$if_ref{name}, addr: $$if_ref{addr}, mask: $$if_ref{mask} )", "NETWORK")
      if &debug();

    # Get network
    use NetAddr::IP;
    my $ip_local  = NetAddr::IP->new($$if_ref{addr}, $$if_ref{mask});
    my $net_local = $ip_local->network();

    # Add or replace local net to all tables
    my @links = ('main', &getLinkNameList());

    my @isolates = ();
    if ($eload) {
        @isolates = &eload(
            module => 'Relianoid::EE::Net::Routing',
            func   => 'getRoutingIsolate',
            args   => [ $$if_ref{name} ],
        );
    }

    # filling the other tables
    for my $link (@links) {
        my $skip_route = 0;
        next if $link eq 'lo';
        next if $link eq 'cl_maintenance';

        my $table = ($link eq 'main') ? 'main' : "table_$link";

        if (grep { /^(?:\*|$table)$/ } @isolates) {
            $skip_route = 1;
        }
        elsif ($link ne 'main') {
            my $iface = &getInterfaceConfig($link);

            # ignores interfaces down or not configured
            next if defined $iface->{status} and $iface->{status} ne 'up';
            next if not defined $iface->{addr};

            #if duplicated network, next
            my $ip_table        = NetAddr::IP->new($$iface{addr}, $$iface{mask});
            my $net_local_table = $ip_table->network();

            if ($net_local_table eq $net_local && $$if_ref{name} ne $link) {
                &log_error(
                    "The network $net_local of dev $$if_ref{name} is the same than the network for $link, route is not going to be applied in table $table",
                    "network"
                );
                $skip_route = 1;
            }
        }

        if (!$skip_route) {
            &applyRoutingCmd('replace', $if_ref, $table);
        }

        if ($eload) {
            &eload(
                module => 'Relianoid::EE::Net::Routing',
                func   => 'applyRoutingTableByIface',
                args   => [ $table, $$if_ref{name} ],
            );
        }
    }

    # filling the own table
    my @ifaces = @{ &getConfigInterfaceList() };
    for my $iface (@ifaces) {
        next if $iface->{name} eq $if_ref->{name};
        my $iface_sys = &getSystemInterface($iface->{name});
        use Relianoid::Net::Core;

        next if $iface_sys->{status} ne 'up';
        next if $iface->{type} eq 'virtual';
        next if defined $iface->{is_slave} and $iface->{is_slave} eq 'true';    # Is in bonding iface
        next if (!defined $iface->{addr} || length $iface->{addr} == 0);        # IP addr doesn't exist
        next if (!&isIp($iface));

        # do not import the iface route if it is isolate
        my @isolates = ();
        if ($eload) {
            @isolates = &eload(
                module => 'Relianoid::EE::Net::Routing',
                func   => 'getRoutingIsolate',
                args   => [ $$iface{name} ],
            );
        }
        next if (grep { /^(?:\*|table_$$if_ref{name})$/ } @isolates);

        &log_debug("addlocalnet: into current interface: name $$iface{name} type $$iface{type}", "NETWORK");

        #if duplicated network, next
        my $ip    = NetAddr::IP->new($$iface{addr}, $$iface{mask});
        my $net   = $ip->network();
        my $table = "table_$$if_ref{name}";

        if ($net eq $net_local && $$iface{name} ne $$if_ref{name}) {
            &log_error(
                "The network $net of dev $$iface{name} is the same than the network for $$if_ref{name}, the route is not going to be applied in table $table",
                "network"
            );
            next;
        }

        &applyRoutingCmd('replace', $iface, $table);
    }

    if ($eload) {
        &eload(
            module => 'Relianoid::EE::Net::Routing',
            func   => 'applyRoutingCustom',
            args   => [ 'add', "table_$$if_ref{name}" ],
        );
    }

    require Relianoid::Net::Core;
    &setRuleIPtoTable($$if_ref{name}, $$if_ref{addr}, "add");

    return;
}

=pod

=head1 isRoute

Checks if any of the routes applied to the system matchs according to the input parameters.
It receives the ip route command line options and it checks the system. 
Example. "src 1.1.12.5 dev eth3 table table_eth3".

Parameters:

    route      - command line options for the "ip route list" command.
    ip_version - version used for the ip command. If this parameter is not used, 
                the command will be executed without this flag

Returns:

    Integer - It returns 1 if any applied rule matchs, or 0 if not

=cut

sub isRoute ($route, $ipv = undef) {
    $ipv = $ipv ? "-$ipv" : '';

    my $exists = 1;
    my $ip_cmd = "$ip_bin $ipv route list $route";
    my $out    = &logAndGet("$ip_cmd");

    if ($out eq '') {
        $exists = 0;
    }
    else {
        require Relianoid::Validate;
        my $ip_re = &getValidFormat('ipv4v6');
        $exists = 0
          if ($exists && $route !~ /src $ip_re/ && $out =~ /src $ip_re/);
    }

    if (&debug() > 1) {
        my $msg = ($exists) ? "(Already exists)" : "(Not found)";
        $msg .= " $ip_cmd";
        &log_debug($msg, "net");
    }

    return $exists;
}

=pod

=head1 existRoute

Checks if any of the paths applied to the system has same properties to the input.
It receives the ip route command line options and it checks the system. Example. "src 1.1.12.5 dev eth3 table table_eth3".

Parameters:

    route - command line options for the "ip route list" command.
    via   - 1 to check via
    src   - 1 to check via

Returns:

    Integer - It returns 1 if any applied rule matchs, or 0 if not

=cut

sub existRoute ($route, $via, $src) {
    require Relianoid::Validate;

    my $ip_re = &getValidFormat('ipv4v6');

    $route =~ s/via ($ip_re)// if not $via;
    $route =~ s/src ($ip_re)// if not $src;

    my $ip_cmd = "$ip_bin route list $route";
    my $out    = &logAndGet("$ip_cmd");

    my $exist = ($out eq '') ? 0 : 1;

    return $exist;
}

=pod

=head1 buildRuleCmd

It creates the command line for a routing directive.

Parameters:

    action - it is the action to apply, 'add' to create a new routing entry, 'del' to delete the requested routing entry or 'undef' to create the parameters wihout adding the 'ip route <action>'
    conf - It is a hash referece with the parameters expected to build the command. The options are:

        ip_v : is the ip version for the route
        priority : is the priority which the route will be execute. Lower priority will be executed before
        not : is the NOT logical operator
        from : is the source address or networking segment from is comming the request
        to : is the destination address or networking segment the request is comming to
        fwmark : is the traffic mark of the packet
        lookup : is the routing table where is going to be added the route

Returns:

    String - It is the command line string to execute in the system

=cut

sub buildRuleCmd ($action, $conf) {
    my $cmd = "";
    my $ipv = (exists $conf->{ip_v}) ? "-$conf->{ip_v}" : "";

    # ip rule { add | del } [ priority PRIO ] [ not ] from IP/NETMASK [ to IP/NETMASK ] [ fwmark FW_MARK ] lookup TABLE_ID
    $cmd .= "$ip_bin $ipv rule $action" if (defined $action);
    if (    (defined $action and $action ne 'list')
        and (exists $conf->{priority} and $conf->{priority} =~ /\d/))
    {
        $cmd .= " priority $conf->{priority} ";
    }
    $cmd .= " not" if (exists $conf->{not} and $conf->{not} eq 'true');
    $cmd .= " from $conf->{from}";
    $cmd .= " to $conf->{to}"
      if (exists $conf->{to} && $conf->{to} ne "");
    $cmd .= " fwmark $conf->{fwmark}"
      if (exists $conf->{fwmark} && $conf->{fwmark} ne "");
    $cmd .= " lookup $conf->{table}";

    return $cmd;
}

=pod

=head1 isRule

Check if routing rule for the given table, from or fwmark exists.

Parameters:

    conf - Rule hash reference.

Returns:

    scalar - number of times the rule was found. True if found.

Todo:

    Rules for Datalink farms are included.

=cut

sub isRule ($conf) {
    my $ipv  = (exists $conf->{ip_v}) ? "-$conf->{ip_v}" : "";
    my $cmd  = "$ip_bin $ipv rule list";
    my $rule = "";
    $rule .= " not" if (exists $conf->{not} and $conf->{not} eq 'true');
    my ($net, $netmask) = split /\//, $conf->{from};
    if (defined $netmask
        and ($netmask eq "32" or $netmask eq "255.255.255.255"))
    {
        $rule .= " from $net";
    }
    else {
        $rule .= " from $conf->{from}";
    }
    $rule .= " to $conf->{to}"
      if (exists $conf->{to} && $conf->{to} ne "");
    $rule .= " fwmark $conf->{fwmark}"
      if (exists $conf->{fwmark} && $conf->{fwmark} ne "");
    $rule .= " lookup $conf->{table}";
    $rule =~ s/^\s+//;
    $rule =~ s/\s+$//;

    my @out = @{ &logAndGet($cmd, 'array') };
    chomp @out;

    my $exist = (grep { /^\d+:\s*$rule\s*$/ } @out) ? 1 : 0;

    if (&debug() > 1) {
        my $msg = ($exist) ? "(Already existed)" : "(Not found)";
        $msg .= " $cmd";
        &log_debug($msg, "net");
    }

    return $exist;
}

=pod

=head1 applyRule

Add or delete the rule according to the given parameters.

Parameters:

    action - "add" to create a new rule or "del" to remove it.
    rule - Rule hash reference.

Returns:

    integer - ip command return code.

Bugs:

    Rules for Datalink farms are included.

=cut

sub applyRule ($action, $rule) {
    return -1 if ($rule->{table} eq "");

    if ($action eq 'add' and ((!defined $rule->{priority}) || $rule->{priority} eq '')) {
        $rule->{priority} = &genRoutingRulesPrio($rule->{type});
    }

    my $cmd    = &buildRuleCmd($action, $rule);
    my $output = &logAndRun("$cmd");

    return $output;
}

=pod

=head1 genRoutingRulesPrio

Create a priority according to the type of route is going to be created

Parameters:

    Type - type of route, the possible values are:

        'iface' for the default interface routes,
        'l4xnat' for the l4xnat backend routes,
        'http or https' for the L7 backend routes,
        'farm-datalink' for the rules applied by datalink farms,
        'user' for the customized routes created for the user,
        'vpn' for the routes applied by vpn connections

Returns:

    Integer - Priority for the route

=cut

sub genRoutingRulesPrio ($type) {
    # The maximun priority value in the system is '32766'
    my $farmL4       = &getGlobalConfiguration('routingRulePrioFarmL4');
    my $farmDatalink = &getGlobalConfiguration('routingRulePrioFarmDatalink');
    my $userInit     = &getGlobalConfiguration('routingRulePrioUserMin');
    my $userEnd      = &getGlobalConfiguration('routingRulePrioUserMax') + 1;
    my $ifacesInit   = &getGlobalConfiguration('routingRulePrioIfaces');

    my $min;
    my $max;

    # l4xnat farm rules
    if ($type eq 'l4xnat' || $type eq 'http' || $type eq 'https') {
        $min = $farmL4;
        $max = $farmDatalink;
    }

    # datalink farm rules
    elsif ($type eq 'farm-datalink') {
        $min = $farmDatalink;
        $max = $userInit;
    }

    # custom rules
    elsif ($type eq 'user') {
        $min = $userInit;
        $max = $userEnd;
    }

    # iface rules
    else {
        return $ifacesInit;
    }

    if ($eload) {
        # vpn rules
        my $vpn = &getGlobalConfiguration('routingRulePrioVPN');
        if ($type eq 'vpn') {
            $min = $vpn;
            $max = $farmL4;
        }
    }

    my $prio;
    my $prioList = &listRoutingRulesPrio();
    for ($prio = $max - 1 ; $prio >= $min ; $prio--) {
        last if (!grep { $prio eq $_ } @{$prioList});
    }

    return $prio;
}

=pod

=head1 listRoutingRulesPrio

List the priority of the rules that are currently applied in the system

Parameters:

    None

Returns:

    Array ref - list of priorities

=cut

sub listRoutingRulesPrio () {
    my $rules = &listRoutingRules();
    my @list;

    for my $r (@{$rules}) {
        push @list, $r->{priority};
    }

    @list = sort @list;
    return \@list;
}

=pod

=head1 getRuleFromIface

It returns a object with the routing parameters that are needed for creating the default route of an interface.

Parameters:

    Interface - name of the interace

Returns:

    Hash ref

    {
        table => "table_eth3",  # table where creating the entry
        type => 'iface',        # type of route rule
        from => 15.255.25.2/24, # networking segement of the interface
    }

=cut

sub getRuleFromIface ($if_ref) {
    my $from = "";
    if (defined($if_ref->{net}) && $if_ref->{net} ne '') {
        $from =
          ($if_ref->{mask} =~ /^\d$/)
          ? "$if_ref->{net}/$if_ref->{mask}"
          : NetAddr::IP->new($if_ref->{net}, $if_ref->{mask})->cidr();
    }

    my $rule = {
        table => "table_$if_ref->{name}",
        type  => 'iface',
        from  => $from,
        ip_v  => $if_ref->{ip_v}
    };

    return $rule;
}

=pod

=head1 setRule

Check and then apply action to add or delete the rule according to the parameters.

Parameters:

    action - "add" to create a new rule or "del" to remove it.
    rule - Rule hash reference

Returns:

    integer - ip command return code.

Bugs:

    Rules for Datalink farms are included.

=cut

sub setRule ($action, $rule) {
    my $output = 0;

    if (!defined($rule->{from}) || $rule->{from} eq '') {
        return 0;
    }
    if ($action !~ /^add$|^del$/) {
        return -1;
    }
    if (defined $rule->{fwmark} && $rule->{fwmark} =~ /^0x0$/) {
        return -1;
    }

    my $isrule = &isRule($rule);

    &log_debug("action '$action' and the rule exist=$isrule", "net");

    if ($action eq "add" && $isrule == 0) {
        &applyRule($action, $rule);
        $output = &isRule($rule) ? 0 : 1;
    }
    elsif ($action eq "del" && $isrule != 0) {
        &applyRule($action, $rule);
        $output = &isRule($rule);
    }

    return $output;
}

=pod

=head1 applyRoutes

Apply routes for interface or default gateway.

For "local" table set route for interface.
For "global" table set route for default gateway and save the default
gateway in global configuration file.

Parameters:

    table - "local" for interface routes or "global" for default gateway route.
    if_ref - network interface hash reference.
    gateway - Default gateway. Only required if table parameter is "global".

Returns:

    integer - ip command return code.

See Also:

    <delRoutes>

=cut

sub applyRoutes ($table, $if_ref, $gateway = undef) {
    my $if_announce = "";
    my $status      = 0;

    # do not add routes if the inteface is down
    my $if_sys = &getSystemInterface($$if_ref{name});
    if ($$if_sys{status} ne 'up') {
        return 0;
    }
    if ($$if_ref{ip_v} != 4 and $$if_ref{ip_v} != 6) {
        return 0;
    }

    unless ($$if_ref{net}) {
        require Relianoid::Net::Interface;
        $$if_ref{net} =
          &getAddressNetwork($$if_ref{addr}, $$if_ref{mask}, $$if_ref{ip_v});
    }

    # not virtual interface
    if (!defined $$if_ref{vini} || $$if_ref{vini} eq '') {
        if ($table eq "local") {
            my $gateway = $$if_ref{gateway} // '';
            &log_info("Applying $table routes in stack IPv$$if_ref{ip_v} to $$if_ref{name} with gateway \"${gateway}\"", "NETWORK");

            &addlocalnet($if_ref);

            if ($$if_ref{gateway}) {
                my $routeparams = &getGlobalConfiguration('routeparams');
                my $ip_cmd =
                  "$ip_bin -$$if_ref{ip_v} route replace default via $$if_ref{gateway} dev $$if_ref{name} table table_$$if_ref{name} $routeparams";
                $status = &logAndRun("$ip_cmd");
            }

            my $rule = &getRuleFromIface($if_ref);
            $status = &setRule("add", $rule);
        }
        else {
            # Apply routes on the global table
            if ($gateway) {
                my $routeparams = &getGlobalConfiguration('routeparams');

                my $action = "replace";
                my $system_default_gw;
                if ($$if_ref{ip_v} == 4) {
                    $system_default_gw = &getDefaultGW();
                }
                elsif ($$if_ref{ip_v} == 6) {
                    $system_default_gw = &getIPv6DefaultGW();
                }

                if (not $system_default_gw) {
                    $action = "add";
                }

                if (&existRoute("default via $gateway dev $$if_ref{name}", 1, 0)) {
                    &log_info("Gateway \"$gateway\" is already applied in $table routes in stack IPv$$if_ref{ip_v}", "NETWORK");
                }
                else {
                    &log_info("Applying $table routes in stack IPv$$if_ref{ip_v} with gateway \"$gateway\"", "NETWORK");
                    my $ip_cmd = "$ip_bin -$$if_ref{ip_v} route $action default via $gateway dev $$if_ref{name} $routeparams";
                    $status = &logAndRun("$ip_cmd");
                }
                if ($$if_ref{ip_v} == 6) {
                    &setGlobalConfiguration('defaultgw6',   $gateway);
                    &setGlobalConfiguration('defaultgwif6', $$if_ref{name});
                }
                else {
                    &setGlobalConfiguration('defaultgw',   $gateway);
                    &setGlobalConfiguration('defaultgwif', $$if_ref{name});
                }
            }
        }
        $if_announce = $$if_ref{name};
    }

    # virtual interface
    else {
        my ($toif) = split(/:/, $$if_ref{name});

        my $rule = &getRuleFromIface($if_ref);
        $rule->{table} = "table_$toif";
        $status        = &setRule("add", $rule);
        $if_announce   = $toif;
    }

    # not send garps to network if node is backup or it is in maintenance
    eval {
        if ($eload) {
            my $cl_status = &eload(
                module => 'Relianoid::EE::Cluster',
                func   => 'getClusterNodeStatus',
                args   => [],
            );
            my $cl_maintenance = &eload(
                module => 'Relianoid::EE::Cluster',
                func   => 'getClMaintenanceManual',
                args   => [],
            );

            if (($cl_status and $cl_status ne "backup") and $cl_maintenance ne "true") {
                require Relianoid::Net::Util;
                &log_info("Announcing garp $if_announce and $$if_ref{addr} ");
                &sendGArp($if_announce, $$if_ref{addr});
            }
        }
    };

    return $status;
}

=pod

=head1 delRoutes

Delete routes for interface or default gateway.

For "local" table remove route for interface.
For "global" table remove route for default gateway and removes the
default gateway in global configuration file.

Parameters:

    table - "local" for interface routes or "global" for default gateway route.
    if_ref - network interface hash reference.

Returns:

    integer - ip command return code.

See Also:

    <applyRoutes>

=cut

sub delRoutes ($table, $if_ref) {
    unless ($$if_ref{ip_v}) {
        croak("IP version stack required");
    }

    my $status = 0;

    &log_info("Deleting $table routes for IPv$$if_ref{ip_v} in interface $$if_ref{name}", "NETWORK");

    if (!defined $$if_ref{vini} || $$if_ref{vini} eq '') {
        #an interface is going to be deleted, delete the rule of the IP first
        require Relianoid::Net::Core;
        &setRuleIPtoTable($$if_ref{name}, $$if_ref{addr}, "del");

        if ($table eq "local") {
            # exists if the tables does not exist
            if (!grep { /^table_$if_ref->{name}/ } &listRoutingTablesNames()) {
                &log_debug2("The table table_$if_ref->{name} was not flushed because it was not found", "net");
                return 0;
            }

            my $ip_cmd = "$ip_bin -$$if_ref{ip_v} route flush table table_$$if_ref{name}";

            my ($errno, $out_ref, $err_ref) = &run3($ip_cmd);
            if ($errno == 2 and not @{$out_ref}) {
                if (    grep { /FIB table does not exist./ } @{$err_ref}
                    and grep { /terminated/ } @{$err_ref})
                {
                    $errno = 0;
                }
            }
            $status = $errno;

            if ($status) {
                &log_error("running: $ip_cmd",     "SYSTEM");
                &log_error("out: @{$out_ref}",     "SYSTEM") if @{$out_ref};
                &log_error("err: @{$err_ref}",     "SYSTEM") if @{$err_ref};
                &log_error("last command failed!", "SYSTEM");
            }
            else {
                &log_debug("running: $ip_cmd", "SYSTEM");
                &log_debug2("out: @{$out_ref}", "SYSTEM") if @{$out_ref};
                &log_debug2("err: @{$err_ref}", "SYSTEM") if @{$err_ref};
            }

            my $rule = &getRuleFromIface($if_ref);
            $status = &setRule("del", $rule);
            return $status;
        }
        else {
            # Delete routes on the global table
            my $ip_cmd = "$ip_bin -$$if_ref{ip_v} route del default";
            $status = &logAndRun("$ip_cmd");

            if ($status == 0) {
                if ($$if_ref{ip_v} == 6) {
                    &setGlobalConfiguration('defaultgw6',   '');
                    &setGlobalConfiguration('defaultgwif6', '');
                }
                else {
                    &setGlobalConfiguration('defaultgw',   '');
                    &setGlobalConfiguration('defaultgwif', '');
                }
            }

            return $status;
        }
    }

    return $status;
}

=pod

=head1 getDefaultGW

Get system or interface default gateway.

Parameters:

    if - interface name. Optional.

Returns:

    scalar - Gateway IP address.

See Also:

    <getIfDefaultGW>

=cut

# get default gw for interface
sub getDefaultGW ($if_name = undef) {
    my $gw;
    my @routes = ();

    if ($if_name) {
        my $routed_if = $if_name;
        if ($if_name =~ /\:/) {
            my @iface = split(/\:/, $routed_if);
            $routed_if = $iface[0];
        }

        open(my $fh, '<', &getGlobalConfiguration('rttables'));

        if (grep { /^...\ttable_${routed_if}$/ } <$fh>) {
            @routes = @{ &logAndGet("${ip_bin} route list table table_${routed_if}", "array") };
        }

        close $fh;
    }
    else {
        @routes = @{ &logAndGet("$ip_bin route list", "array") };
    }

    if (my @default_gw = grep { /^default/ } @routes) {
        my @line = split(/ /, $default_gw[0]);
        $gw = $line[2];
    }

    return $gw;
}

=pod

=head1 getIPv6DefaultGW

Get system IPv6 default gateway.

Parameters:

    none - .

Returns:

    scalar - IPv6 default gateway address.

See Also:

    <getDefaultGW>, <getIPv6IfDefaultGW>

=cut

sub getIPv6DefaultGW () {
    my @routes = @{ &logAndGet("$ip_bin -6 route list", "array") };
    my ($default_line) = grep { /^default/ } @routes;

    my $default_gw;
    if ($default_line) {
        $default_gw = (split(' ', $default_line))[2];
    }

    return $default_gw;
}

=pod

=head1 getIPv6IfDefaultGW

Get network interface to IPv6 default gateway.

Parameters:

    none - .

Returns:

    scalar - Interface to IPv6 default gateway.

See Also:

    <getIPv6DefaultGW>, <getIfDefaultGW>

=cut

sub getIPv6IfDefaultGW () {
    my @routes = @{ &logAndGet("$ip_bin -6 route list", "array") };
    my ($default_line) = grep { /^default/ } @routes;

    my $if_default_gw;
    if ($default_line) {
        $if_default_gw = (split(' ', $default_line))[4];
    }

    return $if_default_gw;
}

=pod

=head1 getIfDefaultGW

Get network interface to default gateway.

Parameters:

    none - .

Returns:

    scalar - Interface to default gateway address.

See Also:

    <getDefaultGW>, <getIPv6IfDefaultGW>

=cut

# get interface for default gw
sub getIfDefaultGW () {
    my $if_name;
    my @routes = @{ &logAndGet("$ip_bin route list", "array") };
    if (my @defgw = grep { /^default/ } @routes) {
        my @line = split(/ /, $defgw[0]);
        $if_name = $line[4];
    }

    return $if_name;
}

=pod

=head1 configureDefaultGW

Setup the configured default gateway (for IPv4 and IPv6).

Parameters:

    none

Returns:

    none

See Also:

    relianoid

=cut

sub configureDefaultGW () {
    my $defaultgw    = &getGlobalConfiguration('defaultgw');
    my $defaultgwif  = &getGlobalConfiguration('defaultgwif');
    my $defaultgw6   = &getGlobalConfiguration('defaultgw6');
    my $defaultgwif6 = &getGlobalConfiguration('defaultgwif6');

    # input: global variables $defaultgw and $defaultgwif
    if ($defaultgw && $defaultgwif) {
        my $if_ref = &getInterfaceConfig($defaultgwif, 4);
        if ($if_ref) {
            &applyRoutes("global", $if_ref, $defaultgw);
        }
    }

    # input: global variables $$defaultgw6 and $defaultgwif6
    if ($defaultgw6 && $defaultgwif6) {
        my $if_ref = &getInterfaceConfig($defaultgwif6, 6);
        if ($if_ref) {
            &applyRoutes("global", $if_ref, $defaultgw6);
        }
    }
    return;
}

=pod

=head1 listRoutingTablesNames

It lists the system routing tables by its nickname

Parameters:

    none

Returns:

    Array - List of routing tables in the system

=cut

sub listRoutingTablesNames () {
    my $rttables   = &getGlobalConfiguration('rttables');
    my @list       = ();
    my @exceptions = ('local', 'default', 'unspec');

    require Relianoid::Lock;
    my $fh = &openlock($rttables, 'r');
    chomp(my @rttables_lines = <$fh>);
    close $fh;

    for my $line (@rttables_lines) {
        next if ($line =~ /^\s*#/);

        if ($line =~ /\d+\s+([\w\-\.]+)/) {
            my $name = $1;
            next if grep { $name eq $_ } @exceptions;
            push @list, $name;
        }
    }

    return @list;
}

=pod

=head1 listRoutingRulesSys

It returns a list of the routing rules from the system.

Parameters:

    filter - filter hash reference for matching rules. No filter means all rules.

Returns:

    Array ref - list of routing rules

=cut

sub listRoutingRulesSys ($filter = undef) {
    my $filter_param;
    my @rules = ();

    if (defined $filter) {
        my @filter_params = keys %{$filter};
        $filter_param = $filter_params[0];
    }

    # get data
    my $cmd  = "$ip_bin -j -p rule list";
    my $data = &logAndGet($cmd);

    require JSON;

    my $dec_data = eval { JSON::decode_json($data); };
    if ($@) {
        &log_error("Decoding json: $@", "net");
        $dec_data = [];
    }

    # filter data
    for my $r (@{$dec_data}) {
        if (   (not defined $filter)
            or ($filter->{$filter_param} eq $r->{$filter_param}))
        {
            my $type = (exists $r->{fwmask}) ? 'farm' : 'system';

            $r->{from} = $r->{src};
            $r->{from} .= "/$r->{srclen}" if exists($r->{srclen});

            delete $r->{src};
            delete $r->{srclen};

            $r->{to} = $r->{dst}        if exists($r->{dst});
            $r->{to} .= "/$r->{dstlen}" if exists($r->{dstlen});

            delete $r->{dst};
            delete $r->{dstlen};

            $r->{type} = $type;
            $r->{not}  = 'true' if (exists $r->{not});
            push @rules, $r;
        }
    }

    return \@rules;
}

=pod

=head1 listRoutingRules

It returns a list of the routing rules. These rules are the resulting list of
join the system administred and the created by the user.

Parameters:

    none

Returns:

    Array ref - list of routing rules

=cut

sub listRoutingRules () {
    my @rules_conf = ();

    if ($eload) {
        @rules_conf = @{ &eload(module => 'Relianoid::EE::Net::Routing', func => 'listRoutingRulesConf', args => [],) };
    }

    my @priorities = ();

    for my $r (@rules_conf) {
        push @priorities, $r->{priority};
    }

    for my $sys (@{ &listRoutingRulesSys() }) {
        if (!grep { $sys->{priority} eq $_ } @priorities) {
            push @rules_conf, $sys;
        }
    }

    return \@rules_conf;
}

=pod

=head1 getRoutingOutgoing

It gets the output interface in the system

Only used for floating interfaces in getFloatingSourceAddr()

Parameters:

    ip - IP address
    mark - Optional mark. For example: '0xX'

Returns:

    Hash ref - $route_ref

Variable: $route_ref

    Hash ref that maps the route info

    $ref->{in}{ip}       - dest ip address
    $ref->{in}{mark}     - mark.
    $ref->{out}{ifname}  - Interface name for output.
    $ref->{out}{srcaddr} - IP address for output.
    $ref->{out}{table}   - Route Table name used
    $ref->{out}{custom}  - Custom route

=cut

sub getRoutingOutgoing ($ip, $mark = undef) {
    my $outgoing_ref;
    $outgoing_ref->{in}{ip}       = $ip;
    $outgoing_ref->{in}{mark}     = "";
    $outgoing_ref->{out}{ifname}  = "";
    $outgoing_ref->{out}{srcaddr} = "";
    $outgoing_ref->{out}{table}   = "";
    $outgoing_ref->{out}{custom}  = "";

    my $mark_option = "";
    if ($mark) {
        $outgoing_ref->{in}{mark} = $mark;
        $mark_option = "mark $mark";
    }

    my $cmd  = "$ip_bin -o -d route get $ip $mark_option";
    my $data = &logAndGet($cmd);

    require Relianoid::Validate;
    my $ip_re = &getValidFormat("ip_addr");

    if ($data =~ /^.* \Q$ip\E (?:via .* )?dev (.*) table (.*) src ($ip_re)(?: $mark_option)? uid (.*)/) {
        my $iface      = $1;
        my $table      = $2;
        my $sourceaddr = $3;
        my $custom     = $4;

        if ($iface eq "lo") {
            my $cmd  = "$ip_bin -o -d route list table $table type local";
            my $data = &logAndGet($cmd, "array");
            for my $route_local (@{$data}) {
                if ($route_local =~ /^local \Q$ip\E dev (.*) proto .* src .*/) {
                    $iface = $1;
                    last;
                }
            }
            $outgoing_ref->{out}{custom} = "false";
        }
        else {
            my $route_params = &getGlobalConfiguration('routeparams');
            if ($custom =~ $route_params) {
                $outgoing_ref->{out}{custom} = "false";
            }
            else {
                $outgoing_ref->{out}{custom} = "true";
            }
        }

        $outgoing_ref->{out}{ifname}  = $iface;
        $outgoing_ref->{out}{table}   = $table;
        $outgoing_ref->{out}{srcaddr} = $sourceaddr;
    }

    return $outgoing_ref;
}

1;
