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

sub setSnmpdStatus () {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my $snmpd_status = shift;
    my $return_code = -1;
    my $systemctl   = &getGlobalConfiguration('systemctl');
    my $updatercd   = &getGlobalConfiguration('updatercd');
    my $snmpd_srv   = &getGlobalConfiguration('snmpd_service');

    if ($snmpd_status eq 'true') {
        &zenlog("Starting snmp service", "info", "SYSTEM");
        &setSnmpdDefaultConfig();
        &logAndRun("$updatercd snmpd enable");

        if (-f $systemctl) {
            $return_code = &logAndRun("$systemctl start snmpd");
        }
        else {
            $return_code = &logAndRun("$snmpd_srv start");
        }
    }
    elsif ($snmpd_status eq 'false') {
        &zenlog("Stopping snmp service", "info", "SYSTEM");
        &logAndRun("$updatercd snmpd disable");

        if (-f $systemctl) {
            $return_code = &logAndRun("$systemctl stop snmpd");
        }
        else {
            $return_code = &logAndRun("$snmpd_srv stop");
        }
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
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my $pidof       = &getGlobalConfiguration('pidof');
    my $return_code = (&logAndRunCheck("$pidof snmpd")) ? 'false' : 'true';

    return $return_code;
}

=pod

=head1 setSnmpdLaunchConfig

Set configuration and disable the snmpd service.

Parameters:

    none

Returns:

    integer - 0 if success, error in another case.

=cut

sub setSnmpdLaunchConfig () {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my $snmp_conf = shift;
    my @config = ("/etc/default/snmpd", "/usr/lib/systemd/system/snmpd.service");
    my $changed = 0;

    require Tie::File;
    foreach my $file (@config) {
        tie my @config_file, 'Tie::File', $file;
		if (defined $snmp_conf->{trapsess} && $snmp_conf->{trapsess} eq "true" && grep ( /mteTrigger/, @config_file )) {
			s/ -smux,mteTrigger,mteTriggerConf// for @config_file;
			$changed = 1;
		}
		elsif ((! defined $snmp_conf->{trapsess} || $snmp_conf->{trapsess} eq "false") && ! grep ( /mteTrigger/, @config_file )) {
			s/ -I / -I -smux,mteTrigger,mteTriggerConf / for @config_file;
			$changed = 1;
		}

		if (!grep ( /LS4d /, @config_file )) {
			s/-L.*d /-LS4d / for @config_file;
			$changed = 1;
		}
		untie @config_file;
	}

	return &logAndRun("systemctl daemon-reload");
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
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

	my $default_snmp_conf = &setSnmpdDefaultConfig();
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
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

	my $snmp_config = &getSnmpdConfig();
	$snmp_config = &_setSnmpdDefaultConfig() if (! defined $snmp_config->{changed} || $snmp_config->{changed} != 1);
	&setSnmpdLaunchConfig($snmp_config);

	return $snmp_config;
}

=pod

=head1 _setSnmpdDefaultConfig

Set the default configuration of the SNMP service.

Parameters:

    none

Returns:

    scalar - Hash reference with SNMP default configuration.

=cut

sub _setSnmpdDefaultConfig () {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

	my $default_snmp_conf = &getSnmpdDefaultConfig();
	&_setSnmpdConfig($default_snmp_conf);
	return $default_snmp_conf;
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
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

	my $snmpd_conf = {
		proto => "udp",
		ip => "*",
		port => "161",
		community_mode => "rocommunity",
		community => "public",
		scope => "0.0.0.0/0",
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
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    require Tie::File;

    my $snmpdconfig_file = &getGlobalConfiguration('snmpdconfig_file');
    my $snmpd_conf;

    $snmpd_conf->{ status } = &getSnmpdStatus();

    tie my @config_file, 'Tie::File', $snmpdconfig_file;

    foreach my $line (@config_file) {
		next if ($line =~ /^\s*$/);
        if ($line =~ /^agentAddress /) {
			my (undef, $aline) = split(/\s+/, $line);
			if ($aline =~ /udp:|tcp:/) {
				($snmpd_conf->{proto}, $snmpd_conf->{ip}, $snmpd_conf->{port}) = split(/:/, $aline);
            } else {
				($snmpd_conf->{ip}, $snmpd_conf->{port}) = split(/:/, $aline);
			}
            $snmpd_conf->{ip} = '*' if ($snmpd_conf->{ip} eq '0.0.0.0');
        } elsif ($line =~ /^..community /) {
			($snmpd_conf->{community_mode}, $snmpd_conf->{community}, $snmpd_conf->{scope}) = split(/\s+/, $line);
		} elsif ($line =~ /^trapcommunity /) {
			(undef, $snmpd_conf->{trapcommunity}) = split(/\s+/, $line);
		} elsif ($line =~ /^authtrapenable /) {
			(undef, $snmpd_conf->{authtrapenable}) = split(/\s+/, $line);
		} elsif ($line =~ /^createuser /) {
            (undef, $snmpd_conf->{createuser_user}, $snmpd_conf->{createuser_auth}, $snmpd_conf->{createuser_auth_pass}, $snmpd_conf->{createuser_priv}, $snmpd_conf->{createuser_priv_pass}) = split(/\s+/, $line);
		} elsif ($line =~ /^iquerysecname /) {
			(undef, $snmpd_conf->{iquerysecname}) = split(/\s+/, $line);
		} elsif ($line =~ /^..user /) {
			($snmpd_conf->{user_mode}, $snmpd_conf->{user}) = split(/\s+/, $line);
		} elsif ($line =~ /^trapsink /) {
			(undef, $snmpd_conf->{trapsink_host}, $snmpd_conf->{trapsink_port}) = split(/\s+/, $line);
		} elsif ($line =~ /^trap2sink /) {
			(undef, $snmpd_conf->{trap2sink_host}) = split(/\s+/, $line);
        } elsif ($line =~ /^trapsess /) {
            $snmpd_conf->{trapsess} = 'true';
            my @trap_line = split(/\s+/, $line);
            my $i = 0;
            while ($i < (scalar @trap_line)) {
                if ($trap_line[$i] eq "-v") {
                    $i+=1;
                    $snmpd_conf->{trapsess_version} = $trap_line[$i];
                } elsif ($trap_line[$i] eq "-u") {
                    $i+=1;
					$snmpd_conf->{trapsess_user} = $trap_line[$i];
                } elsif ($trap_line[$i] eq "-e") {
                    $i+=1;
					$snmpd_conf->{trapsess_engine} = $trap_line[$i];
                } elsif ($trap_line[$i] eq "-a") {
                    $i+=1;
					$snmpd_conf->{trapsess_authproto} = $trap_line[$i];
                } elsif ($trap_line[$i] eq "-A") {
                    $i+=1;
					$snmpd_conf->{trapsess_authpass} = $trap_line[$i];
                } elsif ($trap_line[$i] eq "-x") {
                    $i+=1;
					$snmpd_conf->{trapsess_privproto} = $trap_line[$i];
                } elsif ($trap_line[$i] eq "-X") {
                    $i+=1;
					$snmpd_conf->{trapsess_privpass} = $trap_line[$i];
                } elsif ($i == (scalar @trap_line)-1) {
                    if ($trap_line[$i] =~ /:/) {
						($snmpd_conf->{trapsess_host}, $snmpd_conf->{trapsess_port}) = split(/:/, $trap_line[$i]);
                    } else {
						$snmpd_conf->{trapsess_host} = $trap_line[$i];
						$snmpd_conf->{trapsess_port} = '162';
                    }
                }
                $i+=1;
            }
		} elsif ($line =~ /^linkUpDownNotifications /) {
			(undef, $snmpd_conf->{notif_linkupdown}) = split(/\s+/, $line);
		} elsif ($line =~ /^defaultMonitors /) {
			(undef, $snmpd_conf->{notif_defmonitors}) = split(/\s+/, $line);
		} elsif ($line =~ /^load /) {
			(undef, $snmpd_conf->{load}) = split(/\s+/, $line);
		} elsif ($line =~ /^includeAllDisks /) {
			(undef, $snmpd_conf->{disks}) = split(/\s+/, $line);
		} elsif ($line =~ /^monitor /) {
			$snmpd_conf->{monitors} = () unless (defined $snmpd_conf->{monitors});
			$line =~ s/^monitor\s+//;
			push(@{ $snmpd_conf->{monitors} }, $line);
		} elsif ($line =~ /^#changed-by-relianoid/) {
			$snmpd_conf->{changed} = 1;
        }
    }

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

sub setSnmpdConfig () {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

	my $snmpd_conf = shift;
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

sub _setSnmpdConfig () {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my $snmpd_conf = shift;
    my $snmpdconfig_file = &getGlobalConfiguration('snmpdconfig_file');

    return -1 if ref $snmpd_conf ne 'HASH';

    my $ip = $snmpd_conf->{ip};
    $ip = '0.0.0.0' if ($snmpd_conf->{ip} eq '*'); 

    # scope has to be network range definition
    require NetAddr::IP;
    my $network = NetAddr::IP->new($snmpd_conf->{scope})->network();
    return -1 if ($network ne $snmpd_conf->{scope});

	require Relianoid::Lock;
	my $lock_file = &getLockFile( "snmpd_conf" );
	my $lock_fh = &openlock( $lock_file, 'w' );
	if (open my $config_file, '>', $snmpdconfig_file) {
		# example: agentAddress  udp:127.0.0.1:161
		# example: rocommunity public  0.0.0.0/0
		print $config_file "agentAddress $snmpd_conf->{proto}:$ip:$snmpd_conf->{port}\n" if (defined $snmpd_conf->{proto});
		print $config_file "agentAddress $ip:$snmpd_conf->{port}\n" if (!defined $snmpd_conf->{proto});
		print $config_file "$snmpd_conf->{community_mode} $snmpd_conf->{community} $snmpd_conf->{scope}\n" if (defined $snmpd_conf->{community_mode});
		print $config_file "trapcommunity $snmpd_conf->{trapcommunity}\n" if (defined $snmpd_conf->{trapcommunity});
		print $config_file "authtrapenable $snmpd_conf->{authtrapenable}\n" if (defined $snmpd_conf->{authtrapenable});
        print $config_file "createuser $snmpd_conf->{createuser_user} $snmpd_conf->{createuser_auth} $snmpd_conf->{createuser_auth_pass} $snmpd_conf->{createuser_priv} $snmpd_conf->{createuser_priv_pass}\n" if (defined $snmpd_conf->{createuser});
		print $config_file "iquerysecname $snmpd_conf->{iquerysecname}\n" if (defined $snmpd_conf->{iquerysecname});
		print $config_file "user_mode $snmpd_conf->{user}\n" if (defined $snmpd_conf->{user_mode});
		print $config_file "trapsink $snmpd_conf->{trapsink_host} $snmpd_conf->{trapsink_port}\n" if (defined $snmpd_conf->{trapsink});
		print $config_file "trap2sink $snmpd_conf->{trap2sink_host}\n" if (defined $snmpd_conf->{trap2sink});
		if (defined $snmpd_conf->{trapsess}) {
			print $config_file "trapsess ";
			print $config_file "-v $snmpd_conf->{trapsess_version} " if (defined $snmpd_conf->{trapsess_version});
			print $config_file "-u $snmpd_conf->{trapsess_user} " if (defined $snmpd_conf->{trapsess_user});
			print $config_file "-e $snmpd_conf->{trapsess_engine} " if (defined $snmpd_conf->{trapsess_engine});
			print $config_file "-a $snmpd_conf->{trapsess_authproto} " if (defined $snmpd_conf->{trapsess_authproto});
			print $config_file "-A $snmpd_conf->{trapsess_authpass} " if (defined $snmpd_conf->{trapsess_authpass});
			print $config_file "-x $snmpd_conf->{trapsess_privproto} " if (defined $snmpd_conf->{trapsess_privproto});
			print $config_file "-X $snmpd_conf->{trapsess_privpass} " if (defined $snmpd_conf->{trapsess_privpass});
			print $config_file "$snmpd_conf->{trapsess_host}:$snmpd_conf->{trapsess_port}" if (defined $snmpd_conf->{trapsess_host});
			print $config_file "\n";
		}
		print $config_file "linkUpDownNotifications $snmpd_conf->{notif_linkupdown}\n" if (defined $snmpd_conf->{notif_linkupdown});
		print $config_file "defaultMonitors $snmpd_conf->{notif_defmonitors}\n" if (defined $snmpd_conf->{notif_defmonitors});
		print $config_file "load $snmpd_conf->{load}\n" if (defined $snmpd_conf->{load});
		print $config_file "includeAllDisks $snmpd_conf->{disks}\n" if (defined $snmpd_conf->{disks});
		if (defined $snmpd_conf->{monitors}) {
			foreach my $monitor (@{ $snmpd_conf->{monitors} }) {
				print $config_file "monitor $monitor\n";
			}
		}
		print $config_file "\n#changed-by-relianoid\n";
		close $config_file;
	} else {
		&zenlog("Could not open $snmpdconfig_file: $!", "warning", "SYSTEM");
		return -1;
	}
	close $lock_fh;

    return 0;
}

=pod

=head1 sendSnmpTrap

Send trap and their varbinds.

Parameters:

    trap - Hash reference with SNMP trap configuration gathered in the
           notification details with snmp info included
           (refer to setSnmpContents()).
    snmp - Hash reference with SNMPd configuration
           (refer to getSnmpdConfig()).

Returns:

    integer - 0 on success, or -1 on failure.

=cut

sub sendSnmpTrap () {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my ($trap, $snmp) = @_;

    # snmptrap -v <snmp_version> -e <engine_id> -u <security_username> -a <authentication_protocal> -A <authentication_protocal_pass_phrase> -x <privacy_protocol> -X <privacy_protocol_pass_phrase> -l authPriv <destination_host> <uptime> <OID_or_MIB> <object> <value_type> <value>
    # ej. snmptrap -v 3 -e 0x090807060504030201 -u the_user_name -a SHA -A the_SHA_string -x AES -X the_AES_string -l authPriv localhost '' 1.3.6.1.4.1.8072.2.3.0.1 1.3.6.1.4.1.8072.2.3.2.1 i 123456
    my $cmd = &getGlobalConfiguration('snmptrap_cmd');
    if (! defined $cmd || $cmd eq "") {
        &zenlog("snmptrap command not found", "ERROR", "SYSTEM");
        return -1;
    }
    $cmd .= " -v $snmp->{trapsess_version}" if (defined $snmp->{trapsess_version});
    $cmd .= " -e $snmp->{trapsess_engine}" if (defined $snmp->{trapsess_engine});
    $cmd .= " -u $snmp->{trapsess_user}" if (defined $snmp->{trapsess_user});
    $cmd .= " -a $snmp->{createuser_auth}" if (defined $snmp->{createuser_auth});
    $cmd .= " -A $snmp->{createuser_auth_pass}" if (defined $snmp->{createuser_auth_pass});
    $cmd .= " -x $snmp->{createuser_priv}" if (defined $snmp->{createuser_priv});
    $cmd .= " -X $snmp->{createuser_priv_pass}" if (defined $snmp->{createuser_priv_pass});
    $cmd .= " -l authPriv $snmp->{trap_host} ''" if (defined $snmp->{trap_host});
    $cmd .= " $trap->{snmp_oid}" if (defined $trap->{snmp_oid});

    foreach my $var (@{ $trap->{snmp_varbinds}}) {
        $cmd .= " $var->{oid}" if (defined $var->{oid});
        if (defined $var->{type} && defined $var->{value}) {
            $cmd .= " s \'$var->{value}\'" if ($var->{type} eq "STRING");
            $cmd .= " i $var->{value}" if ($var->{type} eq "INTEGER");
        }
    }

    &zenlog("Sending Trap: $cmd", "INFO", "SYSTEM");
    my $error = &logAndRun($cmd);
    return $error;
}

=pod

=head1 translateSNMPConfigToApi

Translate the SNMP Config params to API params.

Parameters:

    config_ref - Array of snmp config params.

Returns:

    Hash ref - Translated params.

=cut

sub translateSNMPConfigToApi {
    &zenlog(__FILE__ . ":" . __LINE__ . ":" . (caller(0))[3] . "( @_ )", "debug", "PROFILING");

    my $config_ref = shift;

    if (not defined $config_ref) {
        return undef;
    }

    my %params = (
        'ip'        => 'ip',
        'community' => 'community',
        'port'      => 'port',
        'scope'     => 'scope',
        'status'    => 'status',
    );

    foreach my $key (keys %{$config_ref}) {
        if (not defined $params{$key}) {
            delete $config_ref->{$key};
        }
    }

    return $config_ref;
}

1;

