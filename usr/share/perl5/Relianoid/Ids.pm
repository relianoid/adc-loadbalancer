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
use Config::Tiny;

my $eload = eval { require Relianoid::ELoad; };

# TODO
# ipds-rbl-domains
# waf-ruleset
# waf-files

# string to use when a branch of the id tree finishes
my $FIN = undef;

=pod

=head1 Module

Relianoid::Ids

=cut

=pod

=head1 getIdsTree

=cut

sub getIdsTree () {
    require Relianoid::Farm::Core;
    require Relianoid::FarmGuardian;
    require Relianoid::Net::Interface;
    require Relianoid::Certificate;
    require Relianoid::Backup;
    require Relianoid::System::Log;

    my $l4_default_srv_tag = "default_service";

    my $tree = $FIN;
    $tree->{farms} = $FIN;

    for my $type ('https', 'http', 'l4xnat', 'gslb', 'datalink') {
        my @farms = &getFarmsByType($type);

        # add farm
        for my $f (@farms) {
            require Relianoid::Farm::Service;
            $tree->{farms}{$f}{services} = $FIN;

            # add srv
            my @srv = ($type =~ /http|gslb/) ? &getFarmServices($f) : ($l4_default_srv_tag);

            for my $s (@srv) {
                require Relianoid::Farm::Backend;

                $tree->{farms}{$f}{services}{$s}{backends} = $FIN;

                # add bk
                my $bks = &getFarmServerIds($f, $s);

                for my $b (@{$bks}) {
                    $tree->{farms}{$f}{services}{$s}{backends}{$b} = $FIN;
                }

                my $fg = &getFGFarm($f, ($type =~ /datalink|l4xnat/) ? undef : $s);

                $tree->{farms}{$f}{services}{$s}{fg}{$fg} = $FIN if ($fg ne '');
            }

            # add certificates
            if ($type =~ /http/) {
                my @cnames;
                if ($eload) {
                    @cnames = &eload(module => 'Relianoid::EE::Farm::HTTP::HTTPS::Ext', func => 'getFarmCertificatesSNI', args => [$f],);
                }
                else {
                    require Relianoid::Farm::HTTP::HTTPS;
                    @cnames = (&getFarmCertificate($f));
                }
                $tree->{farms}{$f}{certificates} = &addIdsArrays(\@cnames);
            }

            if ($eload) {
                # add zones
                if ($type eq 'gslb') {
                    my @zones = &eload(module => 'Relianoid::EE::Farm::GSLB::Zone', func => 'getGSLBFarmZones', args => [$f],);
                    $tree->{farms}{$f}{zones} = &addIdsArrays(\@zones);
                }

                # add bl
                my @bl = &eload(module => 'Relianoid::EE::IPDS::Blacklist::Core', func => 'listBLByFarm', args => [$f],);

                $tree->{farms}{$f}{ipds}{blacklists} = &addIdsArrays(\@bl);

                # add dos
                my @dos = &eload(module => 'Relianoid::EE::IPDS::DoS::Core', func => 'listDOSByFarm', args => [$f],);
                $tree->{farms}{$f}{ipds}{dos} = &addIdsArrays(\@dos);

                # add rbl
                my @rbl = &eload(module => 'Relianoid::EE::IPDS::RBL::Core', func => 'listRBLByFarm', args => [$f],);
                $tree->{farms}{$f}{ipds}{rbl} = &addIdsArrays(\@rbl);

                #add waf
                if ($type =~ /http/) {
                    my @waf = &eload(module => 'Relianoid::EE::IPDS::WAF::Core', func => 'listWAFByFarm', args => [$f],);
                    $tree->{farms}{$f}{ipds}{waf} = &addIdsArrays(\@waf);
                }
            }
        }
    }

    # add fg
    my @fg = &getFGList();
    $tree->{farmguardians} = &addIdsArrays(\@fg);

    # add ssl certs
    my @certs = &getCertFiles();
    $tree->{certificates} = &addIdsArrays(\@certs);

    # add interfaces
    my @if_list = ('nic', 'vlan', 'virtual');
    push @if_list, 'bond' if ($eload);

    for my $type (@if_list) {
        my $if_key = ($type eq 'bond') ? 'bonding' : $type;
        $tree->{interfaces}{$if_key} = $FIN;

        my @list = &getInterfaceTypeList($type);

        for my $if (@list) {
            $tree->{interfaces}{$if_key}{ $if->{name} } = $FIN;
        }
    }

    # add routing
    require Relianoid::Net::Route;
    my @routing_table = listRoutingTablesNames();
    $tree->{routing}{tables} = &addIdsArrays(\@routing_table);

    if ($eload) {
        # add floating interfaces
        my $float = &eload(module => 'Relianoid::EE::Net::Floating', func => 'getFloatingList',);
        $tree->{interfaces}{floating} = &addIdsArrays($float);

        # add ipds rules
        $tree->{ipds} = &eload(module => 'Relianoid::EE::IPDS::Core', func => 'getIPDSIds',);

        # add rbac
        my @users  = &eload(module => 'Relianoid::EE::RBAC::User::Core',   func => 'getRBACUserList',);
        my @groups = &eload(module => 'Relianoid::EE::RBAC::Group::Core',  func => 'getRBACGroupList',);
        my @roles  = &eload(module => 'Relianoid::EE::RBAC::Role::Config', func => 'getRBACRolesList',);
        $tree->{rbac}{users}  = &addIdsArrays(\@users);
        $tree->{rbac}{roles}  = &addIdsArrays(\@roles);
        $tree->{rbac}{groups} = &addIdsArrays(\@groups);

        for my $g (@groups) {
            my $g_cfg = &eload(module => 'Relianoid::EE::RBAC::Group::Core', func => 'getRBACGroupObject', args => [$g]);

            $tree->{rbac}{groups}{$g}{users}      = &addIdsArrays($g_cfg->{users});
            $tree->{rbac}{groups}{$g}{farms}      = &addIdsArrays($g_cfg->{farms});
            $tree->{rbac}{groups}{$g}{interfaces} = &addIdsArrays($g_cfg->{interfaces});
        }

        # add aliases
        my $alias_bck_ref = &eload(module => 'Relianoid::EE::Alias', func => 'getAlias', args => ['backend'],);
        my $alias_if_ref  = &eload(module => 'Relianoid::EE::Alias', func => 'getAlias', args => ['interface'],);
        $tree->{aliases}{backends}   = &addIdsKeys($alias_bck_ref);
        $tree->{aliases}{interfaces} = &addIdsKeys($alias_if_ref);
    }

    # add backups
    my $backups = &getBackup();
    for my $b (@{$backups}) {
        $tree->{system}{backup}{ $b->{name} } = $FIN;
    }

    # add logs
    my $logs = &getLogs();
    $tree->{system}{logs} = $FIN;
    for my $l (@{$logs}) {
        $tree->{system}{logs}{ $l->{file} } = $FIN;
    }

    return $tree;
}

=pod

=head1 addIdsKeys

=cut

sub addIdsKeys ($hash_ref) {
    my @arr_keys = keys %{$hash_ref};
    return &addIdsArrays(\@arr_keys);
}

=pod

=head1 addIdsArrays

=cut

sub addIdsArrays ($arr) {
    my $out = {};

    for my $it (@{$arr}) {
        $out->{$it} = $FIN;
    }

    return (!keys %{$out}) ? undef : $out;
}

1;

