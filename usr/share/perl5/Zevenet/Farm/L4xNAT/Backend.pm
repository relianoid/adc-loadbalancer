#!/usr/bin/perl
###############################################################################
#
#    ZEVENET Software License
#    This file is part of the ZEVENET Load Balancer software package.
#
#    Copyright (C) 2014-today ZEVENET SL, Sevilla (Spain)
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

use Zevenet::Config;
use Zevenet::Nft;

my $configdir = &getGlobalConfiguration( 'configdir' );


=begin nd
Function: setL4FarmServer

	Edit a backend or add a new one if the id is not found

Parameters:
	farmname - Farm name
	id - Backend id
	rip - Backend IP
	port - Backend port
	weight - Backend weight. The backend with more weight will manage more connections
	priority - The priority of this backend (between 1 and 9). Higher priority backends will be used more often than lower priority ones
	maxconn - Maximum connections for the given backend

Returns:
	Integer - return 0 on success, -1 on NFTLB failure or -2 on IP duplicated.

Returns:
	Scalar - 0 on success or other value on failure
	FIXME: Stop returning -2 when IP duplicated, nftlb should do this
=cut

sub setL4FarmServer
{
	&zenlog( __FILE__ . q{:} . __LINE__ . q{:} . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my ( $farm_name, $ids, $ip, $port, $weight, $priority, $max_conns ) = @_;

	require Zevenet::Farm::L4xNAT::Config;
	require Zevenet::Farm::L4xNAT::Action;
	require Zevenet::Farm::Backend;
	require Zevenet::Netfilter;

	my $farm_filename = &getFarmFile( $farm_name );
	my $output        = 0;
	my $json          = qq();
	my $msg           = "setL4FarmServer << farm_name:$farm_name ids:$ids ";

	# load the configuration file first if the farm is down
	my $f_ref = &getL4FarmStruct( $farm_name );
	if ( $f_ref->{ status } ne "up" )
	{
		my $out = &loadL4FarmNlb( $farm_name );
		return $out if ( $out != 0 );
	}

	my $exists = &getFarmServer( $f_ref->{ servers }, $ids );

	my $rip  = $ip;
	my $mark = "0x0";

	if ( defined $port and $port ne "" )
	{
		if ( &ipversion( $ip ) == 4 )
		{
			$rip = "$ip\:$port";
		}
		elsif ( &ipversion( $ip ) == 6 )
		{
			$rip = "[$ip]\:$port";
		}

		if ( not defined $exists or ( defined $exists and $exists->{ port } ne $port ) )
		{
			$json .= qq(, "port" : "$port");
			$msg  .= "port:$port ";
		}
	}
	elsif ( defined $port and $port eq "" )
	{
		$json .= qq(, "port" : "$port");
		$msg  .= "port:$port ";
	}

	if (    defined $ip
		and $ip ne ""
		and ( not defined $exists or ( defined $exists and $exists->{ rip } ne $rip ) )
	  )
	{
		my $existrip = &getFarmServer( $f_ref->{ servers }, $rip, "rip" );
		return -2 if ( defined $existrip and ( $existrip->{ id } ne $ids ) );
		$json = qq(, "ip-addr" : "$ip") . $json;
		$msg .= "ip:$ip ";

		if ( not defined $exists )
		{
			$mark = &getNewMark( $farm_name );
			return -1 if ( not defined $mark or $mark eq "" );
			$json .= qq(, "mark" : "$mark");
			$msg  .= "mark:$mark ";
		}
		else
		{
			$mark = $exists->{ tag };
		}

		&setBackendRule( "add", $f_ref, $mark ) if ( $f_ref->{ status } eq "up" );

	}

	if (
		     defined $weight
		 and $weight ne ""
		 and ( not defined $exists
			   or ( defined $exists and $exists->{ weight } ne $weight ) )
	  )
	{
		$weight = 1 if ( $weight == 0 );
		$json .= qq(, "weight" : "$weight");
		$msg  .= "weight:$weight ";
	}

	if (
		     defined $priority
		 and $priority ne ""
		 and ( not defined $exists
			   or ( defined $exists and $exists->{ priority } ne $priority ) )
	  )
	{
		$priority = 1 if ( $priority == 0 );
		$json .= qq(, "priority" : "$priority");
		$msg  .= "priority:$priority ";
	}

	if (
		     defined $max_conns
		 and $max_conns ne ""
		 and ( not defined $exists
			   or ( defined $exists and $exists->{ max_conns } ne $max_conns ) )
	  )
	{
		$max_conns = 0 if ( $max_conns < 0 );
		$json .= qq(, "est-connlimit" : "$max_conns");
		$msg  .= "maxconns:$max_conns ";
	}

	if ( not defined $exists )
	{
		$json .= qq(, "state" : "up");
		$msg  .= "state:up ";
	}

	&zenlog( "$msg" ) if &debug;

	$output = &sendL4NlbCmd(
		{
		   farm   => $farm_name,
		   file   => "$configdir/$farm_filename",
		   method => "PUT",
		   body =>
			 qq({"farms" : [ { "name" : "$farm_name", "backends" : [ { "name" : "bck$ids"$json } ] } ] })
		}
	);

	# take care of floating interfaces without masquerading

	return $output;
}

=begin nd
Function: runL4FarmServerDelete

	Delete a backend from a l4 farm

Parameters:
	backend - Backend id
	farmname - Farm name

Returns:
	Scalar - 0 on success or other value on failure

=cut

sub runL4FarmServerDelete
{
	&zenlog( __FILE__ . q{:} . __LINE__ . q{:} . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my ( $ids, $farm_name ) = @_;

	require Zevenet::Farm::L4xNAT::Config;
	require Zevenet::Farm::L4xNAT::Action;
	require Zevenet::Netfilter;

	my $farm_filename = &getFarmFile( $farm_name );
	my $output        = 0;
	my $mark          = "0x0";

	# load the configuration file first if the farm is down
	my $f_ref = &getL4FarmStruct( $farm_name );

	$output = &sendL4NlbCmd(
							 {
							   farm    => $farm_name,
							   backend => "bck" . $ids,
							   file    => "$configdir/$farm_filename",
							   method  => "DELETE",
							 }
	);

	my $backend;
	foreach my $server ( @{ $f_ref->{ servers } } )
	{
		if ( $server->{ id } eq $ids )
		{
			$mark    = $server->{ tag };
			$backend = $server;
			last;
		}
	}

	### Flush conntrack
	&resetL4FarmBackendConntrackMark( $backend );

	&setBackendRule( "del", $f_ref, $mark );
	&delMarks( "", $mark );

	return $output;
}

=begin nd
Function: setL4FarmBackendsSessionsRemove

	Remove all the active sessions enabled to a backend

Parameters:
	farm_name - Farm name
	backend_ref - Hash ref of Backend 
	farm_mode - Farm Mode

Returns:
	Integer - 0 on success , 1 on failure

=cut

sub setL4FarmBackendsSessionsRemove
{
	&zenlog( __FILE__ . q{:} . __LINE__ . q{:} . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my ( $farm_name, $backend_ref, $farm_mode ) = @_;

	my $output = -1;
	if ( not defined $backend_ref )
	{
		&zenlog(
			"Warning removing sessions for backend id farm '$farm_name': Backend id not found",
			"warning", "lslb"
		);
		return $output;
	}

	my $table;
	my $value_check;
	my $value_regex;
	if ( defined $farm_mode and $farm_mode eq "dsr" )
	{
		$table = "netdev";
		my $ip_bin    = &getGlobalConfiguration( 'ip_bin' );
		my $mac       = &logAndRun( "$ip_bin neigh show $backend_ref->{ ip }" );
		my @mac_split = split ( ' ', $mac );
		$value_check = $mac_split[4];
		$value_regex = qr/([a-fA-F0-9:]{1,})/;
	}
	else
	{
		$table = "ip";
		require Zevenet::Net::Validate;
		if ( &ipversion( $backend_ref->{ ip } ) == 6 )
		{
			$table .= "6";
		}
		( $value_check = $backend_ref->{ tag } ) =~ s/0x//g;
		$value_regex = qr/0x0*(\d+)/;
	}

	my $nft_bin  = &getGlobalConfiguration( 'nft_bin' );
	my $map_name = "persist-$farm_name";
	my @persistmap =
	  @{ &logAndGet( "$nft_bin list map $table nftlb $map_name", "array" ) };
	my $data = 0;

	my $sessions;
	my $n_sessions_deleted;
	foreach my $line ( @persistmap )
	{

		$data = 1 if ( $line =~ /elements = / );
		next if ( not $data );

		my ( $key, $value ) =
		  ( $line =~ /,?\s+([\w\.\s\:]+) expires \w+ : $value_regex[\s,]/ );
		if ( $value eq $value_check )
		{
			$sessions .= " $key,";
			$n_sessions_deleted++;
		}

		last if ( $data and $line =~ /\}/ );
	}

	if ( defined $sessions )
	{
		chop $sessions;
		my $error = &logAndRun(
				"/usr/local/sbin/nft delete element $table nftlb $map_name { $sessions }" );
		if ( $error )
		{
			&zenlog(
				"Error removing '$n_sessions_deleted' sessions for backend id '$backend_ref->{ id }' in farm '$farm_name'",
				"error", "lslb"
			);
			$output = 1;
		}
		else
		{
			&zenlog(
				"Removing '$n_sessions_deleted' sessions for backend id '$backend_ref->{ id }' in farm '$farm_name'",
				"info", "lslb"
			);
			$output = 0;
		}
	}
	else
	{
		# no sessions found
		$output = 0;
	}

	return $output;
}

=begin nd
Function: setL4FarmBackendStatus

	Set backend status for an l4 farm and stops traffic to that backend when needed.

Parameters:
	farmname - Farm name
	backend - Backend id
	status - Backend status. The possible values are: "up", "down", "maintenance" or "fgDOWN".
	cutmode - "cut" to force the traffic stop for such backend
Returns:
	$error_ref: $error_ref->{ code } - 0 on success, 1 on failure changing status,
				2 on failure removing sessions, 3 on failure removing connections,
				4 on failure removing sessions and connections.
				$error_ref->{ desc } - error message.


=cut

sub setL4FarmBackendStatus
{
	&zenlog( __FILE__ . q{:} . __LINE__ . q{:} . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my ( $farm_name, $backend, $status, $cutmode ) = @_;

	require Zevenet::Farm::L4xNAT::Config;
	require Zevenet::Farm::L4xNAT::Action;

	my $error_ref->{ code } = -1;
	my $farm                = &getL4FarmStruct( $farm_name );
	my $farm_filename       = $farm->{ filename };
	my @backends;
	my @bks_prio_status;
	my @bks_updated_prio_status;
	my $output;
	my $msg;
	$status = 'off'  if ( $status eq "maintenance" );
	$status = 'down' if ( $status eq "fgDOWN" );

#the following actions are only needed if a high priority backend turns up after being down/off and
#a lower priority backend(s) turned active during the time the other backends was down/off
	if ( $status eq 'up' and @{ $$farm{ servers } } > 1 )
	{
		my $i = 0;
		my $bk_index;
		foreach my $server ( @{ $$farm{ servers } } )
		{
			my $bk;
			$bk_index = $i if $backend == $server->{ id };
			if ( $server->{ status } ne "up" )
			{
				$bk->{ status } = "down";
			}
			else
			{
				$bk->{ status } = $server->{ status };
			}
			$bk->{ priority } = $server->{ priority };
			push ( @backends, $bk );
			$i++;
		}
		require Zevenet::Farm::Backend;
		@bks_prio_status = @{ &getPriorityAlgorithmStatus( \@backends )->{ status } };
		$backends[$bk_index]->{ status } = $status;
		@bks_updated_prio_status =
		  @{ &getPriorityAlgorithmStatus( \@backends )->{ status } };
	}

	$output =
	  &sendL4NlbCmd(
		{
		   farm   => $farm_name,
		   file   => "$configdir/$farm_filename",
		   method => "PUT",
		   body =>
			 qq({"farms" : [ { "name" : "$farm_name", "backends" : [ { "name" : "bck$backend", "state" : "$status" } ] } ] })
		}
	  );

	if ( $output )
	{
		$msg =
		  "Status of backend $backend in farm '$farm_name' was not changed to $status";
		&zenlog( $msg, "error", "LSLB" );
		$error_ref->{ code } = 1;
		$error_ref->{ desc } = $msg;
		return $error_ref;
	}
	else
	{
		$msg = "Status of backend $backend in farm '$farm_name' was changed to $status";
		&zenlog( $msg, "info", "LSLB" );
		$error_ref->{ code } = 0;
		$error_ref->{ desc } = $msg;
	}

#compare priority status of all backends and delete sessions and connections of backends
#that have had their priority status changed from true to false.
	my $i = 0;
	foreach my $bk ( @bks_updated_prio_status )
	{
		if ( $bk ne $bks_prio_status[$i] )
		{
			if ( @{ $farm->{ servers } }[$i]->{ status } eq 'up' )
			{
				if ( $farm->{ persist } ne '' )
				{
					# delete backend session
					$output =
					  &setL4FarmBackendsSessionsRemove( $farm_name,
														@{ $farm->{ servers } }[$i],
														$farm->{ mode } );
					if ( $output )
					{
						$error_ref->{ code } = 2;
					}
				}

				# remove conntrack
				$output = &resetL4FarmBackendConntrackMark( @{ $farm->{ servers } }[$i] );
				if ( $output )
				{
					$msg = "Connections for unused backends in farm '$farm_name' were not deleted";
					$error_ref->{ code } = 3;
					$error_ref->{ desc } = $msg;
				}

				if ( $farm->{ persist } ne '' )
				{
					# delete backend session again in case new connections are created
					$output =
					  &setL4FarmBackendsSessionsRemove( $farm_name,
														@{ $farm->{ servers } }[$i],
														$farm->{ mode } );
					if ( $output )
					{
						if ( $error_ref->{ code } == 3 )
						{
							$msg =
							  "Connections and sessions of unused backends in farm '$farm_name' were not deleted";
							$error_ref->{ code } = 4;
							$error_ref->{ desc } = $msg;
						}
						else
						{
							$msg = "Sessions for unused backends in farm '$farm_name' were not deleted";
							$error_ref->{ code } = 2;
							$error_ref->{ desc } = $msg;
						}
					}
					else
					{
						$error_ref->{ code } = 0 if $error_ref->{ code } == 2;
					}
				}
			}
		}
		$i++;
	}
	if ( $status ne "up" and $cutmode eq "cut" )
	{

		my $server;

		# get backend with id $backend
		foreach my $srv ( @{ $$farm{ servers } } )
		{
			if ( $srv->{ 'id' } == $backend )
			{
				$server = $srv;
				last;
			}
		}

		if ( $farm->{ persist } ne '' )
		{
			#delete backend session
			$output =
			  &setL4FarmBackendsSessionsRemove( $farm_name, $server, $farm->{ mode } );
			if ( $output )
			{
				$error_ref->{ code } = 2;
			}
		}

		# remove conntrack
		$output = &resetL4FarmBackendConntrackMark( $server );
		if ( $output )
		{
			$msg =
			  "Connections for backend $server->{ ip }:$server->{ port } in farm '$farm_name' were not deleted";
			$error_ref->{ code } = 3;
			$error_ref->{ desc } = $msg;
		}

		if ( $farm->{ persist } ne '' )
		{
			# delete backend session again in case new connections are created
			$output =
			  &setL4FarmBackendsSessionsRemove( $farm_name, $server, $farm->{ mode } );
			if ( $output )
			{
				if ( $error_ref->{ code } == 3 )
				{
					$msg =
					  "Error deleting connections and sessions on backend $server->{ ip }:$server->{ port } in farm '$farm_name'";
					$error_ref->{ code } = 4;
					$error_ref->{ desc } = $msg;
				}
				else
				{
					$msg =
					  "Sessions for backend $server->{ ip }:$server->{ port } in farm '$farm_name' were not deleted";
					$error_ref->{ code } = 2;
					$error_ref->{ desc } = $msg;
				}
			}
			else
			{
				$error_ref->{ code } = 0 if $error_ref->{ code } == 2;
			}
		}
	}
	if ( $farm->{ lbalg } eq 'leastconn' )
	{
		require Zevenet::Farm::L4xNAT::L4sd;
		&sendL4sdSignal();
	}

	#~ TODO
	#~ my $stopping_fg = ( $caller =~ /runFarmGuardianStop/ );
	#~ if ( $fg_enabled eq 'true' and not $stopping_fg )
	#~ {
	#~ if ( $0 !~ /farmguardian/ and $fg_pid > 0 )
	#~ {
	#~ kill 'CONT' => $fg_pid;
	#~ }
	#~ }

	return $error_ref;
}

=begin nd
Function: getL4FarmServers

	 Get all backends and their configuration

Parameters:
	farmname - Farm name

Returns:
	Array - array of hash refs of backend struct

=cut

sub getL4FarmServers
{
	&zenlog( __FILE__ . q{:} . __LINE__ . q{:} . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $farm_name = shift;

	my $farm_filename = &getFarmFile( $farm_name );

	open my $fd, '<', "$configdir/$farm_filename";
	chomp ( my @content = <$fd> );
	close $fd;

	return &_getL4FarmParseServers( \@content );
}

=begin nd
Function: _getL4FarmParseServers

	Return the list of backends with all data about a backend in a l4 farm

Parameters:
	config - plain text server list

Returns:
	backends array - array of backends structure
		\%backend = { $id, $alias, $family, $ip, $port, $tag, $weight, $priority, $status, $rip = $ip, $max_conns }

=cut

sub _getL4FarmParseServers
{
	&zenlog( __FILE__ . q{:} . __LINE__ . q{:} . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $config = shift;
	my $stage  = 0;
	my $server;
	my @servers;

	require Zevenet::Farm::L4xNAT::Config;
	my $fproto = &_getL4ParseFarmConfig( 'proto', undef, $config );

	foreach my $line ( @{ $config } )
	{
		if ( $line =~ /\"farms\"/ )
		{
			$stage = 1;
		}

		# do not go to the next level if empty
		if ( $line =~ /\"backends\"/ and $line !~ /\[\],/ )
		{
			$stage = 2;
		}

		if ( $stage == 2 and $line =~ /\{/ )
		{
			$stage = 3;
			undef $server;
		}

		if ( $stage == 3 and $line =~ /\}/ )
		{
			$stage = 2;
			push ( @servers, $server );
		}

		if ( $stage == 2 and $line =~ /\]/ )
		{
			last;
		}

		if ( $stage == 3 and $line =~ /\"name\"/ )
		{
			my @l = split /"/, $line;
			my $index = $l[3];
			$index =~ s/bck//;
			$server->{ id }        = $index + 0;
			$server->{ port }      = undef;
			$server->{ tag }       = "0x0";
			$server->{ max_conns } = 0;
		}

		if ( $stage == 3 and $line =~ /\"ip-addr\"/ )
		{
			my @l = split /"/, $line;
			$server->{ ip }  = $l[3];
			$server->{ rip } = $l[3];
		}

		if ( $stage == 3 and $line =~ /\"source-addr\"/ )
		{
			my @l = split /"/, $line;
			$server->{ sourceip } = $l[3];
		}

		if ( $stage == 3 and $line =~ /\"port\"/ )
		{
			my @l = split /"/, $line;
			$server->{ port } = $l[3];

			require Zevenet::Net::Validate;
			if ( $server->{ port } ne '' and $fproto ne 'all' )
			{
				if ( &ipversion( $server->{ rip } ) == 4 )
				{
					$server->{ rip } = "$server->{ip}\:$server->{port}";
				}
				elsif ( &ipversion( $server->{ rip } ) == 6 )
				{
					$server->{ rip } = "[$server->{ip}]\:$server->{port}";
				}
			}
		}

		if ( $stage == 3 and $line =~ /\"weight\"/ )
		{
			my @l = split /"/, $line;
			$server->{ weight } = $l[3] + 0;
		}

		if ( $stage == 3 and $line =~ /\"priority\"/ )
		{
			my @l = split /"/, $line;
			$server->{ priority } = $l[3] + 0;
		}

		if ( $stage == 3 and $line =~ /\"mark\"/ )
		{
			my @l = split /"/, $line;
			$server->{ tag } = $l[3];
		}

		if ( $stage == 3 and $line =~ /\"est-connlimit\"/ )
		{
			my @l = split /"/, $line;
			$server->{ max_conns } = $l[3] + 0;
		}

		if ( $stage == 3 and $line =~ /\"state\"/ )
		{
			my @l = split /"/, $line;
			$server->{ status } = $l[3];
			$server->{ status } = "undefined" if ( $server->{ status } eq "config_error" );
			$server->{ status } = "maintenance" if ( $server->{ status } eq "off" );
			$server->{ status } = "fgDOWN" if ( $server->{ status } eq "down" );
			$server->{ status } = "up" if ( $server->{ status } eq "available" );
		}
	}

	return \@servers;
}

=begin nd
Function: getL4ServerWithLowestPriority

	Look for backend with the lowest priority

Parameters:
	farm - Farm hash ref. It is a hash with all information about the farm

Returns:
	hash ref - reference to the selected server for prio algorithm

=cut

sub getL4ServerWithLowestPriority
{
	&zenlog( __FILE__ . q{:} . __LINE__ . q{:} . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $farm = shift;

	my $prio_server;

	foreach my $server ( @{ $$farm{ servers } } )
	{
		if ( $$server{ status } eq 'up' )
		{
			# find the lowest priority server
			$prio_server = $server if not defined $prio_server;
			$prio_server = $server if $$prio_server{ priority } > $$server{ priority };
		}
	}

	return $prio_server;
}

=begin nd
Function: getL4BackendsWeightProbability

	Get probability for every backend

Parameters:
	farm - Farm hash ref. It is a hash with all information about the farm

Returns:
	none - .

=cut

sub getL4BackendsWeightProbability
{
	&zenlog( __FILE__ . q{:} . __LINE__ . q{:} . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $farm = shift;

	my $weight_sum = 0;

	&doL4FarmProbability( $farm );

	foreach my $server ( @{ $$farm{ servers } } )
	{
		# only calculate probability for the servers running
		if ( $$server{ status } eq 'up' )
		{
			$weight_sum += $$server{ weight };
			$$server{ prob } = $weight_sum / $$farm{ prob };
		}
		else
		{
			$$server{ prob } = 0;
		}
	}
	return;
}

=begin nd
Function: resetL4FarmBackendConntrackMark

	Reset Connection tracking for a given backend

Parameters:
	server - Backend hash reference. It uses the backend unique mark in order to deletes the conntrack entries.

Returns:
	scalar - 0 if deleted, 1 if not deleted

=cut

sub resetL4FarmBackendConntrackMark
{
	&zenlog( __FILE__ . q{:} . __LINE__ . q{:} . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $server = shift;

	my $conntrack = &getGlobalConfiguration( 'conntrack' );
	my $cmd       = "$conntrack -D -m $server->{ tag }/0x7fffffff";

	&zenlog( "running: $cmd" ) if &debug();

	# return_code = 0 -> deleted
	# return_code = 1 -> not found/deleted
	my $return_code = &logAndRunCheck( "$cmd" );

	#check if error in return_code is because connections were not found
	if ( $return_code )
	{
		require Zevenet::Net::ConnStats;
		my $params           = { mark => "$server->{ tag }/0x7fffffff" };
		my $conntrack_params = &getConntrackParams( $params );
		my $conns            = &getConntrackCount( $conntrack_params );

		#if connections are not found, no error
		$return_code = 0 if $conns == 0;
	}

	if ( &debug() )
	{
		if ( $return_code )
		{
			&zenlog( "Connection tracking for " . $server->{ ip } . " not removed." );
		}
		else
		{
			&zenlog( "Connection tracking for " . $server->{ ip } . " removed." );
		}
	}

	return $return_code;
}

=begin nd
Function: getL4FarmBackendAvailableID

	Get next available backend ID

Parameters:
	farmname - farm name

Returns:
	integer - .

=cut

sub getL4FarmBackendAvailableID
{
	&zenlog( __FILE__ . q{:} . __LINE__ . q{:} . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $farmname = shift;

	require Zevenet::Farm::Backend;

	my $backends  = &getL4FarmServers( $farmname );
	my $nbackends = $#{ $backends } + 1;

	for ( my $id = 0 ; $id < $nbackends ; $id++ )
	{
		my $exists = &getFarmServer( $backends, $id );
		return $id if ( not $exists );
	}

	return $nbackends;
}

=begin nd
Function: getL4ServerByMark

	Obtain the backend id from the mark

Parameters:
	servers_ref - reference to the servers array
	mark - backend mark to discover the id

Returns:
	integer - > 0 if successful, -1 if error.

=cut

sub getL4ServerByMark
{
	&zenlog( __FILE__ . q{:} . __LINE__ . q{:} . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my $servers_ref = shift;
	my $mark        = shift;

	( my $tag = $mark ) =~ s/0x.0*/0x/g;

	foreach my $server ( @{ $servers_ref } )
	{
		if ( $server->{ tag } eq $tag )
		{
			return $server->{ id };
		}
	}

	return -1;
}

=begin nd
Function: getL4FarmPriorities

	Get the list of the backends priorities in a L4 farm

Parameters:
	farmname - Farm name

Returns:
	Array Ref - it returns an array ref of priority values

=cut

sub getL4FarmPriorities    # ( $farmname )
{
	&zenlog( __FILE__ . q{:} . __LINE__ . q{:} . ( caller ( 0 ) )[3] . "( @_ )",
			 "debug", "PROFILING" );
	my ( $farmname ) = shift;
	my @priorities;
	my $backends = &getL4FarmServers( $farmname );
	foreach my $backend ( @{ $backends } )
	{
		if ( defined $backend->{ priority } )
		{
			push @priorities, $backend->{ priority };
		}
		else
		{
			push @priorities, 1;
		}

	}
	return \@priorities;
}

1;

