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

use Relianoid::Log;
use Relianoid::Config;

=pod

=head1 Module

Relianoid::SNMP

=cut

=pod

=head1 setSnmpdStatus

Start or stop the SNMP service.

Parameters:

    snmpd_status - 'true' to start, or 'stop' to stop the SNMP service.

Returns:

    scalar - 0 on success, non-zero on failure.

=cut

sub setSnmpdStatus ($snmpd_status) {
    my $return_code = -1;
    my $systemctl   = &getGlobalConfiguration('systemctl');
    my $snmpd_srv   = &getGlobalConfiguration('snmpd_service');

    if ($snmpd_status eq 'true') {
        &zenlog("Starting snmp service", "info", "SYSTEM");
        &logAndRun("$systemctl enable $snmpd_srv");
        $return_code = &logAndRun("$systemctl start $snmpd_srv");
    }
    elsif ($snmpd_status eq 'false') {
        &zenlog("Stopping snmp service", "info", "SYSTEM");
        &logAndRun("$systemctl disable $snmpd_srv");
        $return_code = &logAndRun("$systemctl stop $snmpd_srv");
    }
    else {
        &zenlog("SNMP requested state is invalid", "warning", "SYSTEM");
        return -1;
    }

    return $return_code;
}

=pod

=head1 getSnmpdStatus

Get if the SNMP service is running.

Parameters:

    none

Returns:

    string - Boolean. 'true' if it is running, or 'false' if it is not running.

=cut

sub getSnmpdStatus () {
    my $pidof       = &getGlobalConfiguration('pidof');
    my $return_code = (&logAndRunCheck("$pidof snmpd")) ? 'false' : 'true';

    return $return_code;
}

=pod

=head1 setSnmpdLaunchConfig

Set configuration and disable the snmpd service.

Parameters:

    snmp_conf - Configuration for SNMP

Returns:

    integer - 0 if success, error in another case.

=cut

sub setSnmpdLaunchConfig ($snmp_conf) {
    my @config  = ("/etc/default/snmpd", "/usr/lib/systemd/system/snmpd.service");
    my $changed = 0;

    require Tie::File;
    for my $file (@config) {
        tie my @config_file, 'Tie::File', $file;
        if (   defined $snmp_conf->{trapsess}
            && $snmp_conf->{trapsess} eq "true"
            && grep { /mteTrigger/ } @config_file)
        {
            s/ -I -smux,mteTrigger,mteTriggerConf// for @config_file;
            $changed = 1;
        }
        elsif ((!defined $snmp_conf->{trapsess} || $snmp_conf->{trapsess} eq "false")
            && !grep { /mteTrigger/ } @config_file)
        {
            s/ -f / -I -smux,mteTrigger,mteTriggerConf -f / for @config_file;
            $changed = 1;
        }

        if (!grep { /LS6d / } @config_file) {
            s/-L[^\s]+ /-LS6d / for @config_file;
            $changed = 1;
        }
        untie @config_file;
    }

    if ($changed) {
        my $systemctl = &getGlobalConfiguration('systemctl');
        return &logAndRun("$systemctl daemon-reload");
    }

    return 0;
}

=pod

=head1 setSnmpdFactoryReset

Set default configuration and disable the snmpd service.

Parameters:

    none

Returns:

    integer - 0 on success, or -1 on failure.

=cut

sub setSnmpdFactoryReset () {
    my $default_snmp_conf = &getSnmpdDefaultConfig();
    my $snmpdconfig_file  = &getGlobalConfiguration('snmpdconfig_file');
    unlink($snmpdconfig_file);
    &_setSnmpdConfig($default_snmp_conf);
    &setSnmpdLaunchConfig($default_snmp_conf);
    return &setSnmpdStatus("false");
}

=pod

=head1 setSnmpdDefaultConfig

Apply default SNMP config if it was not changed by this service
before. Then, reload the service generators.

Parameters:

    none

Returns:

    scalar - Hash reference with SNMP default configuration.

=cut

sub setSnmpdDefaultConfig () {
    my $snmp_config = &getSnmpdConfig();
    if ($snmp_config->{changed} == 0) {
        $snmp_config = &setSnmpdFactoryReset();
    }
    else {
        &setSnmpdLaunchConfig($snmp_config);
    }

    return $snmp_config;
}

=pod

=head1 getSnmpdDefaultConfig

Get the default configuration of the SNMP service.

Parameters:

    none

Returns:

    scalar - Hash reference with SNMP default configuration.

		$snmpd_conf = {
				proto # agentAddress line
				ip
				port
				community # community line
				community_mode
				scope
			};

=cut

sub getSnmpdDefaultConfig () {
    my $snmpd_conf = {
        proto          => "udp",
        ip             => "*",
        port           => "161",
        community_mode => "rocommunity",
        community      => "public",
        scope          => "0.0.0.0/0",
    };

    return $snmpd_conf;
}

=pod

=head1 getSnmpdConfig

Get the configuration of the SNMP service according to the
snmpd.conf file.

Parameters:

    none

Returns:

    scalar - Hash reference with SNMP configuration.

		$snmpd_conf = {
					   status
					   proto # agentAddress line
					   ip
					   port
					   community # community line
					   community_mode
					   scope
					   authtrapenable # authtrapenable line
					   createuser_user # createuser line
					   createuser_auth
					   createuser_auth_pass
					   createuser_priv
					   createuser_priv_pass
					   iquerysecname # iquerysecname line
					   user_mode # xxuser line
					   user
					   trapsink_host # trapsink line
					   trapsink_port
					   trap2sink_host # trap2sink
					   trapsess_version # trapsess line
					   trapsess_user
					   trapsess_engine
					   trapsess_authproto
					   trapsess_authpass
					   trapsess_privproto
					   trapsess_privpass
					   trapsess_host
					   trapsess_port
					   notif_linkupdown
					   notif_defmonitors
					   load
					   disks
					   monitors # array with monitors configuration
					   changed # 1 if changed by relianoid
		}; 

=cut

sub getSnmpdConfig () {
    require Tie::File;

    my $snmpdconfig_file = &getGlobalConfiguration('snmpdconfig_file');
    my $snmpd_conf;

    $snmpd_conf->{status}  = &getSnmpdStatus();
    $snmpd_conf->{changed} = 1;

    tie my @config_file, 'Tie::File', $snmpdconfig_file;

    for my $line (@config_file) {
        next if ($line =~ /^\s*$/);
        $snmpd_conf->{changed} = 0
          if ($line =~ /^(# EXAMPLE.conf|# An example configuration file)/);
        next if ($line =~ /^\s*#/);
        chomp($line);
        if ($line =~ /^\s*agentAddress\s+/) {
            my (undef, $aline) = split(/\s+/, $line);
            if ($aline =~ /udp:|tcp:/) {
                ($snmpd_conf->{proto}, $snmpd_conf->{ip}, $snmpd_conf->{port}) = split(/:/, $aline);
            }
            else {
                ($snmpd_conf->{ip}, $snmpd_conf->{port}) = split(/:/, $aline);
            }
            $snmpd_conf->{ip} = '*' if ($snmpd_conf->{ip} eq '0.0.0.0');
        }
        elsif ($line =~ /^..community\s+/) {
            ($snmpd_conf->{community_mode}, $snmpd_conf->{community}, $snmpd_conf->{scope}) =
              split(/\s+/, $line);
            $snmpd_conf->{scope} = "0.0.0.0/0" if ($snmpd_conf->{scope} =~ /default/);
        }
        elsif ($line =~ /^trapcommunity\s+/) {
            (undef, $snmpd_conf->{trapcommunity}) = split(/\s+/, $line);
        }
        elsif ($line =~ /^authtrapenable\s+/) {
            (undef, $snmpd_conf->{authtrapenable}) = split(/\s+/, $line);
        }
        elsif ($line =~ /^createuser\s+/) {
            (
                undef,                               $snmpd_conf->{createuser_user}, $snmpd_conf->{createuser_auth},
                $snmpd_conf->{createuser_auth_pass}, $snmpd_conf->{createuser_priv}, $snmpd_conf->{createuser_priv_pass}
            ) = split(/\s+/, $line);
        }
        elsif ($line =~ /^iquerysecname\s+/) {
            (undef, $snmpd_conf->{iquerysecname}) = split(/\s+/, $line);
        }
        elsif ($line =~ /^..user\s+/) {
            ($snmpd_conf->{user_mode}, $snmpd_conf->{user}) = split(/\s+/, $line);
        }
        elsif ($line =~ /^trapsink\s+/) {
            (undef, $snmpd_conf->{trapsink_host}, $snmpd_conf->{trapsink_port}) =
              split(/\s+/, $line);
        }
        elsif ($line =~ /^trap2sink\s+/) {
            (undef, $snmpd_conf->{trap2sink_host}) = split(/\s+/, $line);
        }
        elsif ($line =~ /^trapsess\s+/) {
            $snmpd_conf->{trapsess} = 'true';
            my @trap_line = split(/\s+/, $line);
            my $i         = 0;
            while ($i < (scalar @trap_line)) {
                if ($trap_line[$i] eq "-v") {
                    $i += 1;
                    $snmpd_conf->{trapsess_version} = $trap_line[$i];
                }
                elsif ($trap_line[$i] eq "-u") {
                    $i += 1;
                    $snmpd_conf->{trapsess_user} = $trap_line[$i];
                }
                elsif ($trap_line[$i] eq "-e") {
                    $i += 1;
                    $snmpd_conf->{trapsess_engine} = $trap_line[$i];
                }
                elsif ($trap_line[$i] eq "-a") {
                    $i += 1;
                    $snmpd_conf->{trapsess_authproto} = $trap_line[$i];
                }
                elsif ($trap_line[$i] eq "-A") {
                    $i += 1;
                    $snmpd_conf->{trapsess_authpass} = $trap_line[$i];
                }
                elsif ($trap_line[$i] eq "-x") {
                    $i += 1;
                    $snmpd_conf->{trapsess_privproto} = $trap_line[$i];
                }
                elsif ($trap_line[$i] eq "-X") {
                    $i += 1;
                    $snmpd_conf->{trapsess_privpass} = $trap_line[$i];
                }
                elsif ($i == (scalar @trap_line) - 1) {
                    if ($trap_line[$i] =~ /:/) {
                        ($snmpd_conf->{trapsess_host}, $snmpd_conf->{trapsess_port}) =
                          split(/:/, $trap_line[$i]);
                    }
                    else {
                        $snmpd_conf->{trapsess_host} = $trap_line[$i];
                        $snmpd_conf->{trapsess_port} = '162';
                    }
                }
                $i += 1;
            }
        }
        elsif ($line =~ /^linkUpDownNotifications\s+/) {
            (undef, $snmpd_conf->{notif_linkupdown}) = split(/\s+/, $line);
        }
        elsif ($line =~ /^defaultMonitors\s+/) {
            (undef, $snmpd_conf->{notif_defmonitors}) = split(/\s+/, $line);
        }
        elsif ($line =~ /^load\s+/) {
            (undef, $snmpd_conf->{load}) = split(/\s+/, $line);
        }
        elsif ($line =~ /^includeAllDisks\s+/) {
            (undef, $snmpd_conf->{disks}) = split(/\s+/, $line);
        }
        elsif ($line =~ /^monitor\s+/) {
            $snmpd_conf->{monitors} = () unless (defined $snmpd_conf->{monitors});
            (my $newline = $line) =~ s/^monitor\s+//;
            push(@{ $snmpd_conf->{monitors} }, $newline);
        }
    }

    $snmpd_conf->{ip}   = "*"   if (not defined $snmpd_conf->{ip});
    $snmpd_conf->{port} = "161" if (not defined $snmpd_conf->{port});

    untie @config_file;
    return $snmpd_conf;
}

=pod

=head1 setSnmpdConfig

Apply SNMP configuration and reload services.

Parameters:

    snmpd_conf - Hash reference with SNMP configuration.

Returns:

    integer - 0 on success, or -1 on failure.

=cut

sub setSnmpdConfig ($snmpd_conf) {
    &_setSnmpdConfig($snmpd_conf);
    &setSnmpdLaunchConfig($snmpd_conf);

    return 0;
}

=pod

=head1 _setSnmpdConfig

Store SNMP configuration.

Parameters:

    snmpd_conf - Hash reference with SNMP configuration.

Returns:

    integer - 0 on success, or -1 on failure.

=cut

sub _setSnmpdConfig ($snmpd_conf) {
    my $snmpdconfig_file = &getGlobalConfiguration('snmpdconfig_file');
    my $default_index    = 0;                                             # line to insert the configuration

    return -1 if ref $snmpd_conf ne 'HASH';

    my $ip = $snmpd_conf->{ip};
    $ip = '0.0.0.0' if ($snmpd_conf->{ip} eq '*');

    # scope has to be network range definition
    require NetAddr::IP;
    my $network = NetAddr::IP->new($snmpd_conf->{scope})->network();
    return -1 if ($network ne $snmpd_conf->{scope});

    require Relianoid::Lock;
    my @contents;
    my $lock_file = &getLockFile("snmpd_conf");
    my $lock_fh   = &openlock($lock_file, 'w');

    if (open my $config_file, '<', $snmpdconfig_file) {
        @contents = <$config_file>;
        close $config_file;
        close $lock_fh;

        @contents = grep { !/^agentAddress/ } @contents;
        @contents = grep { !/^..community/ } @contents             if (defined $snmpd_conf->{community_mode});
        @contents = grep { !/^trapcommunity/ } @contents           if (defined $snmpd_conf->{trapcommunity});
        @contents = grep { !/^authtrapenable/ } @contents          if (defined $snmpd_conf->{authtrapenable});
        @contents = grep { !/^createuser/ } @contents              if (defined $snmpd_conf->{createuser_user});
        @contents = grep { !/^iquerysecname/ } @contents           if (defined $snmpd_conf->{iquerysecname});
        @contents = grep { !/^..user/ } @contents                  if (defined $snmpd_conf->{user_mode});
        @contents = grep { !/^trapsink/ } @contents                if (defined $snmpd_conf->{trapsink});
        @contents = grep { !/^trap2sink/ } @contents               if (defined $snmpd_conf->{trap2sink});
        @contents = grep { !/^trapsess/ } @contents                if (defined $snmpd_conf->{trapsess});
        @contents = grep { !/^linkUpDownNotifications/ } @contents if (defined $snmpd_conf->{notif_linkupdown});
        @contents = grep { !/^defaultMonitors/ } @contents         if (defined $snmpd_conf->{notif_defmonitors});
        @contents = grep { !/^load/ } @contents                    if (defined $snmpd_conf->{load});
        @contents = grep { !/^includeAllDisks/ } @contents         if (defined $snmpd_conf->{disks});
        @contents = grep { !/^monitor/ } @contents                 if (defined $snmpd_conf->{monitors});
    }
    else {
        close $lock_fh;
    }

    my $index = $default_index;
    if (defined $snmpd_conf->{proto}) {
        splice @contents, $index, 0, "agentAddress $snmpd_conf->{proto}:$ip:$snmpd_conf->{port}\n";
        $index++;
    }
    else {
        splice @contents, $index, 0, "agentAddress $ip:$snmpd_conf->{port}\n";
        $index++;
    }

    if (defined $snmpd_conf->{community_mode} and $snmpd_conf->{community} and $snmpd_conf->{scope}) {
        splice @contents, $index, 0, "$snmpd_conf->{community_mode} $snmpd_conf->{community} $snmpd_conf->{scope}\n";
        $index++;
    }

    if (defined $snmpd_conf->{trapcommunity}) {
        splice @contents, $index, 0, "trapcommunity $snmpd_conf->{trapcommunity}\n";
        $index++;
    }

    if (defined $snmpd_conf->{authtrapenable}) {
        splice @contents, $index, 0, "authtrapenable $snmpd_conf->{authtrapenable}\n";
        $index++;
    }

    if (defined $snmpd_conf->{createuser_user}) {
        my $line = "createuser $snmpd_conf->{createuser_user}";
        $line .= " $snmpd_conf->{createuser_auth}"      if ($snmpd_conf->{createuser_auth});
        $line .= " $snmpd_conf->{createuser_auth_pass}" if ($snmpd_conf->{createuser_auth_pass});
        $line .= " $snmpd_conf->{createuser_priv}"      if ($snmpd_conf->{createuser_priv});
        $line .= " $snmpd_conf->{createuser_priv_pass}" if ($snmpd_conf->{createuser_priv_pass});
        $line .= "\n";
        splice @contents, $index, 0, "$line";
        $index++;

        if (defined $snmpd_conf->{user_mode}) {
            splice @contents, $index, 0, "$snmpd_conf->{user_mode} $snmpd_conf->{createuser_user}\n";
            $index++;
        }
    }

    if (defined $snmpd_conf->{iquerysecname}) {
        splice @contents, $index, 0, "iquerysecname $snmpd_conf->{iquerysecname}\n";
        $index++;
    }

    if (defined $snmpd_conf->{trapsink}) {
        splice @contents, $index, 0, "trapsink $snmpd_conf->{trapsink}\n";
        $index++;
    }

    if (defined $snmpd_conf->{trap2sink}) {
        splice @contents, $index, 0, "trap2sink $snmpd_conf->{trap2sink}\n";
        $index++;
    }

    if (defined $snmpd_conf->{trapsess}) {
        my $line = "trapsess ";
        $line .= "-v $snmpd_conf->{trapsess_version} "   if ($snmpd_conf->{trapsess_version});
        $line .= "-u $snmpd_conf->{trapsess_user} "      if ($snmpd_conf->{trapsess_user});
        $line .= "-e $snmpd_conf->{trapsess_engine} "    if ($snmpd_conf->{trapsess_engine});
        $line .= "-a $snmpd_conf->{trapsess_authproto} " if ($snmpd_conf->{trapsess_authproto});
        $line .= "-A $snmpd_conf->{trapsess_authpass} "  if ($snmpd_conf->{trapsess_authpass});
        $line .= "-x $snmpd_conf->{trapsess_privproto} " if ($snmpd_conf->{trapsess_privproto});
        $line .= "-X $snmpd_conf->{trapsess_privpass} "  if ($snmpd_conf->{trapsess_privpass});
        $line .= "$snmpd_conf->{trapsess_host}"          if ($snmpd_conf->{trapsess_host});
        $line .= ":$snmpd_conf->{trapsess_port}"         if ($snmpd_conf->{trapsess_port});
        $line .= "\n";
        splice @contents, $index, 0, "$line";
        $index++;
    }

    if (defined $snmpd_conf->{notif_linkupdown}) {
        splice @contents, $index, 0, "linkUpDownNotifications $snmpd_conf->{notif_linkupdown}\n";
        $index++;
    }

    if (defined $snmpd_conf->{notif_defmonitors}) {
        splice @contents, $index, 0, "defaultMonitors $snmpd_conf->{notif_defmonitors}\n";
        $index++;
    }

    if (defined $snmpd_conf->{load}) {
        splice @contents, $index, 0, "load $snmpd_conf->{load}\n";
        $index++;
    }

    if (defined $snmpd_conf->{disks}) {
        splice @contents, $index, 0, "includeAllDisks $snmpd_conf->{disks}\n";
        $index++;
    }

    if (defined $snmpd_conf->{monitors}) {
        for my $monitor (@{ $snmpd_conf->{monitors} }) {
            splice @contents, $index, 0, "monitor $monitor\n";
            $index++;
        }
    }

    $lock_fh = &openlock($lock_file, 'w');

    if (open my $config_file, '>', $snmpdconfig_file) {
        print $config_file @contents;
        close $config_file;
        close $lock_fh;
    }
    else {
        close $lock_fh;
        &zenlog("Could not open ${snmpdconfig_file}: $!", "warning", "SYSTEM");
        return -1;
    }

    return 0;
}

=pod

=head1 translateSNMPConfigToApi

Translate the SNMP Config params to API params.

Parameters:

    config_ref - Array of snmp config params.

Returns:

    Hash ref - Translated params.

=cut

sub translateSNMPConfigToApi ($config_ref) {
    my %params = (
        'ip'        => 'ip',
        'community' => 'community',
        'port'      => 'port',
        'scope'     => 'scope',
        'status'    => 'status',
    );

    for my $key (keys %{$config_ref}) {
        if (not defined $params{$key}) {
            delete $config_ref->{$key};
        }
    }

    return $config_ref;
}

1;

