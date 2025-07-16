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

use Relianoid::HTTP;

=pod

=head1 Module

Relianoid::API40::Routes

=cut

my $PATH_INFO      = $ENV{PATH_INFO};
my $REQUEST_METHOD = $ENV{REQUEST_METHOD};

if ($PATH_INFO =~ qr{^/ids$}) {
    require Relianoid::HTTP::Controllers::API::Ids;

    GET qr{^/ids$} => \&list_ids_controller;
}

require Relianoid::Validate;

if ($PATH_INFO =~ qr{^/certificates/letsencryptz?}) {
    require Relianoid::HTTP::Controllers::API::Letsencrypt;

    my $le_cert_re = &getValidFormat('le_certificate_name');

    GET qr{^/certificates/letsencryptz?/config$} => \&get_le_conf_controller;    #  GET config
    PUT qr{^/certificates/letsencryptz?/config$} => \&set_le_conf_controller;    #  Modify config

    GET qr{^/certificates/letsencryptz?$} => \&list_le_cert_controller;          #  List certificates
    POST qr{^/certificates/letsencryptz?$} => \&add_le_cert_controller;          #  Create certificate

    GET qr{^/certificates/letsencryptz?/($le_cert_re)$} => \&get_le_cert_controller;          #  GET certificate
    DELETE qr{^/certificates/letsencryptz?/($le_cert_re)$} => \&delete_le_cert_controller;    #  DELETE certificate
    PUT qr{^/certificates/letsencryptz?/($le_cert_re)$} => \&set_le_cert_controller;          #  Modify certificate

    POST qr{^/certificates/letsencryptz?/($le_cert_re)/actions$} => \&actions_le_cert_controller;  #  LE certificate actions
}

# SSL certificates
if ($PATH_INFO =~ qr{^/certificates}) {
    require Relianoid::HTTP::Controllers::API::Certificate;

    my $cert_name_re = &getValidFormat('certificate_name');

    GET qr{^/certificates$}                      => \&list_certificates_controller;       #  GET List SSL certificates
    GET qr{^/certificates/($cert_name_re)/info$} => \&get_certificate_info_controller;    #  GET SSL certificate information
    GET qr{^/certificates/($cert_name_re)$}      => \&download_certificate_controller;    #  Download SSL certificate
    POST qr{^/certificates$}     => \&create_csr_controller;                              #  Create CSR certificates
    POST qr{^/certificates/pem$} => \&create_certificate_controller;                      #  POST certificates

    if ($PATH_INFO !~ qr{^/certificates/letsencryptz?-wildcard$}) {
        POST qr{^/certificates/($cert_name_re)$} => \&upload_certificate_controller;      #  POST certificates
    }

    DELETE qr{^/certificates/($cert_name_re)$} => \&delete_certificate_controller;        #  DELETE certificate
}

my $farm_re    = &getValidFormat('farm_name');
my $service_re = &getValidFormat('service');
my $be_re      = &getValidFormat('backend');

if ($PATH_INFO =~ qr{^/farms/$farm_re/certificates}) {
    require Relianoid::HTTP::Controllers::API::Certificate;

    my $cert_pem_re = &getValidFormat('cert_pem');

    POST qr{^/farms/($farm_re)/certificates$} => \&add_farm_certificate_controller;
    DELETE qr{^/farms/($farm_re)/certificates/($cert_pem_re)$} => \&delete_farm_certificate_controller;
}

if (   $PATH_INFO =~ qr{^/monitoring/fg}
    or $PATH_INFO =~ qr{^/farms/$farm_re(?:/services/$service_re)?/fg})
{
    require Relianoid::HTTP::Controllers::API::Farm::Guardian;

    my $fg_name_re = &getValidFormat('fg_name');

    POST qr{^/farms/($farm_re)/services/($service_re)/fg$} => \&add_fg_to_farm_controller;
    POST qr{^/farms/($farm_re)/fg$}                        => \&add_fg_to_farm_controller;
    DELETE qr{^/farms/($farm_re)/services/($service_re)/fg/($fg_name_re)$} => \&delete_fg_from_farm_controller;
    DELETE qr{^/farms/($farm_re)/fg/($fg_name_re)$}                        => \&delete_fg_from_farm_controller;

    GET qr{^/monitoring/fg$} => \&list_farmguardian_controller;
    POST qr{^/monitoring/fg$} => \&create_farmguardian_controller;
    GET qr{^/monitoring/fg/($fg_name_re)$} => \&get_farmguardian_controller;
    PUT qr{^/monitoring/fg/($fg_name_re)$} => \&modify_farmguardian_controller;
    DELETE qr{^/monitoring/fg/($fg_name_re)$} => \&delete_farmguardian_controller;
}

if ($PATH_INFO =~ qr{^/farms/$farm_re/actions}) {
    require Relianoid::HTTP::Controllers::API::Farm::Action;

    PUT qr{^/farms/($farm_re)/actions$} => \&actions_farm_controller;
}

if ($PATH_INFO =~ qr{^/farms/$farm_re.*/backends/$be_re/maintenance}) {
    require Relianoid::HTTP::Controllers::API::Farm::Action;

    PUT qr{^/farms/($farm_re)/services/($service_re)/backends/($be_re)/maintenance$} =>
      \&set_service_backend_maintenance_controller;    #  (HTTP only)

    PUT qr{^/farms/($farm_re)/backends/($be_re)/maintenance$} => \&set_backend_maintenance_controller;    #  (L4xNAT only)
}

if ($PATH_INFO =~ qr{^/farms/$farm_re(?:/services/$service_re)?/backends}) {
    require Relianoid::HTTP::Controllers::API::Farm::Backend;

    GET qr{^/farms/($farm_re)/backends$} => \&list_farm_backends_controller;
    POST qr{^/farms/($farm_re)/backends$} => \&add_farm_backend_controller;
    PUT qr{^/farms/($farm_re)/backends/($be_re)$} => \&modify_farm_backend_controller;
    DELETE qr{^/farms/($farm_re)/backends/($be_re)$} => \&delete_farm_backend_controller;

    GET qr{^/farms/($farm_re)/services/($service_re)/backends$} => \&list_service_backends_controller;
    POST qr{^/farms/($farm_re)/services/($service_re)/backends$} => \&add_service_backend_controller;
    PUT qr{^/farms/($farm_re)/services/($service_re)/backends/($be_re)$} => \&modify_service_backends_controller;
    DELETE qr{^/farms/($farm_re)/services/($service_re)/backends/($be_re)$} => \&delete_service_backend_controller;
}

if ($PATH_INFO =~ qr{^/farms/$farm_re/services}) {
    require Relianoid::HTTP::Controllers::API::Farm::Service;

    POST qr{^/farms/($farm_re)/services$} => \&add_farm_service_controller;
    GET qr{^/farms/($farm_re)/services/($service_re)$} => \&get_farm_service_controller;
    PUT qr{^/farms/($farm_re)/services/($service_re)$} => \&modify_farm_service_controller;
    DELETE qr{^/farms/($farm_re)/services/($service_re)$} => \&delete_farm_service_controller;
}

if ($PATH_INFO =~ qr{^/farms}) {
    if ($REQUEST_METHOD eq 'GET') {
        require Relianoid::HTTP::Controllers::API::Farm::Get;

        GET qr{^/farms$} => \&list_farms_controller;

        GET qr{^/farms/modules/summary$} => \&get_farm_modules_controller;
        GET qr{^/farms/modules/lslb$}    => \&list_lslb_controller;
        GET qr{^/farms/modules/dslb$}    => \&list_dslb_controller;

        GET qr{^/farms/($farm_re)$}         => \&get_farm_controller;
        GET qr{^/farms/($farm_re)/status$}  => \&get_farm_status_controller;
        GET qr{^/farms/($farm_re)/summary$} => \&get_farm_summary_controller;
    }

    if ($REQUEST_METHOD eq 'POST') {
        require Relianoid::HTTP::Controllers::API::Farm::Post;
        POST qr{^/farms$} => \&add_farm_controller;
    }

    if ($REQUEST_METHOD eq 'PUT') {
        require Relianoid::HTTP::Controllers::API::Farm::Put;
        PUT qr{^/farms/($farm_re)$} => \&modify_farm_controller;
    }

    if ($REQUEST_METHOD eq 'DELETE') {
        require Relianoid::HTTP::Controllers::API::Farm::Delete;
        DELETE qr{^/farms/($farm_re)$} => \&delete_farm_controller;
    }
}

# Network Interfaces
my $nic_re  = &getValidFormat('nic_interface');
my $bond_re = &getValidFormat('bond_interface');
my $vlan_re = &getValidFormat('vlan_interface');

if ($PATH_INFO =~ qr{^/interfaces/nic}) {
    require Relianoid::HTTP::Controllers::API::Interface::NIC;

    GET qr{^/interfaces/nic$}           => \&list_nic_controller;
    GET qr{^/interfaces/nic/($nic_re)$} => \&get_nic_controller;
    PUT qr{^/interfaces/nic/($nic_re)$} => \&modify_nic_controller;
    DELETE qr{^/interfaces/nic/($nic_re)$} => \&delete_nic_controller;
    POST qr{^/interfaces/nic/($nic_re)/actions$} => \&actions_nic_controller;
}

if ($PATH_INFO =~ qr{^/interfaces/vlan}) {
    require Relianoid::HTTP::Controllers::API::Interface::VLAN;

    GET qr{^/interfaces/vlan$} => \&list_vlan_controller;
    POST qr{^/interfaces/vlan$} => \&add_vlan_controller;
    GET qr{^/interfaces/vlan/($vlan_re)$} => \&get_vlan_controller;
    PUT qr{^/interfaces/vlan/($vlan_re)$} => \&modify_vlan_controller;
    DELETE qr{^/interfaces/vlan/($vlan_re)$} => \&delete_vlan_controller;
    POST qr{^/interfaces/vlan/($vlan_re)/actions$} => \&actions_vlan_controller;
}

if ($PATH_INFO =~ qr{^/interfaces/virtual}) {
    require Relianoid::HTTP::Controllers::API::Interface::Virtual;

    GET qr{^/interfaces/virtual$} => \&list_virtual_controller;
    POST qr{^/interfaces/virtual$} => \&add_virtual_controller;

    my $virtual_re = &getValidFormat('virt_interface');

    GET qr{^/interfaces/virtual/($virtual_re)$} => \&get_virtual_controller;
    PUT qr{^/interfaces/virtual/($virtual_re)$} => \&modify_virtual_controller;
    DELETE qr{^/interfaces/virtual/($virtual_re)$} => \&delete_virtual_controller;
    POST qr{^/interfaces/virtual/($virtual_re)/actions$} => \&actions_virtual_controller;
}

if ($PATH_INFO =~ qr{^/interfaces/gateway/ipv(?:[46])$}) {
    require Relianoid::HTTP::Controllers::API::Interface::Gateway;

    GET qr{^/interfaces/gateway/ipv([46])$} => \&get_gateway_controller;
    PUT qr{^/interfaces/gateway/ipv([46])$} => \&modify_gateway_controller;
    DELETE qr{^/interfaces/gateway/ipv([46])$} => \&delete_gateway_controller;
}

if ($PATH_INFO =~ qr{^/interfaces$}) {
    require Relianoid::HTTP::Controllers::API::Interface::Generic;

    GET qr{^/interfaces$} => \&list_interfaces_controller;
}

# Statistics
if ($PATH_INFO =~ qr{^/stats}) {
    require Relianoid::HTTP::Controllers::API::Stats;

    GET qr{^/stats$}                => \&get_stats_controller;
    GET qr{^/stats/system/network$} => \&get_stats_network_controller;

    GET qr{^/stats/farms$}                     => \&list_farms_stats_controller;
    GET qr{^/stats/farms/($farm_re)$}          => \&get_farm_stats_controller;
    GET qr{^/stats/farms/($farm_re)/backends$} => \&get_farm_stats_controller;

    # Fixed: make 'service' or 'services' valid requests for compatibility with previous bug.
    GET qr{^/stats/farms/($farm_re)/services?/($service_re)/backends$} => \&get_farm_stats_controller;
}

# Graphs
if ($PATH_INFO =~ qr{^/graphs}) {
    require Relianoid::HTTP::Controllers::API::Graph;

    my $frequency_re = &getValidFormat('graphs_frequency');
    my $rrd_re       = &getValidFormat('rrd_time');

    GET qr{^/graphs$} => \&list_graphs_controller;

    GET qr{^/graphs/system$} => \&list_sys_graphs_controller;

    GET qr{^/graphs/system/(cpu)$}  => \&get_sys_graphs_controller;
    GET qr{^/graphs/system/(load)$} => \&get_sys_graphs_controller;
    GET qr{^/graphs/system/(ram)$}  => \&get_sys_graphs_controller;
    GET qr{^/graphs/system/(swap)$} => \&get_sys_graphs_controller;

    GET qr{^/graphs/system/(cpu)/($frequency_re)$}  => \&get_sys_graphs_freq_controller;
    GET qr{^/graphs/system/(load)/($frequency_re)$} => \&get_sys_graphs_freq_controller;
    GET qr{^/graphs/system/(ram)/($frequency_re)$}  => \&get_sys_graphs_freq_controller;
    GET qr{^/graphs/system/(swap)/($frequency_re)$} => \&get_sys_graphs_freq_controller;

    GET qr{^/graphs/system/(cpu)/custom/start/($rrd_re)/end/($rrd_re)$}  => \&get_sys_graphs_interval_controller;
    GET qr{^/graphs/system/(load)/custom/start/($rrd_re)/end/($rrd_re)$} => \&get_sys_graphs_interval_controller;
    GET qr{^/graphs/system/(ram)/custom/start/($rrd_re)/end/($rrd_re)$}  => \&get_sys_graphs_interval_controller;
    GET qr{^/graphs/system/(swap)/custom/start/($rrd_re)/end/($rrd_re)$} => \&get_sys_graphs_interval_controller;

    # $disk_re includes 'root' at the beginning
    my $disk_re = &getValidFormat('mount_point');

    GET qr{^/graphs/system/disk$}                                                 => \&list_disks_graphs_controller;
    GET qr{^/graphs/system/disk/($disk_re)/custom/start/($rrd_re)/end/($rrd_re)$} => \&get_disk_graphs_interval_controller;
    GET qr{^/graphs/system/disk/($disk_re)/($frequency_re)$}                      => \&get_disk_graphs_freq_controller;
    GET qr{^/graphs/system/disk/($disk_re)$}                                      => \&get_disk_graphs_controller;

    GET qr{^/graphs/interfaces$}                                    => \&list_iface_graphs_controller;
    GET qr{^/graphs/interfaces/($nic_re|$vlan_re)$}                 => \&get_iface_graphs_controller;
    GET qr{^/graphs/interfaces/($nic_re|$vlan_re)/($frequency_re)$} => \&get_iface_graphs_frec_controller;
    GET qr{^/graphs/interfaces/($nic_re|$vlan_re)/custom/start/($rrd_re)/end/($rrd_re)$} =>
      \&get_iface_graphs_interval_controller;

    GET qr{^/graphs/farms$}                                                 => \&list_farm_graphs_controller;
    GET qr{^/graphs/farms/($farm_re)$}                                      => \&get_farm_graphs_controller;
    GET qr{^/graphs/farms/($farm_re)/($frequency_re)$}                      => \&get_farm_graphs_frec_controller;
    GET qr{^/graphs/farms/($farm_re)/custom/start/($rrd_re)/end/($rrd_re)$} => \&get_farm_graphs_interval_controller;
}

# System
if ($PATH_INFO =~ qr{^/system/dns}) {
    require Relianoid::HTTP::Controllers::API::System::Service::DNS;

    GET qr{^/system/dns$} => \&get_dns_controller;
    POST qr{^/system/dns$} => \&set_dns_controller;
}

if ($ENV{PATH_INFO} =~ qr{^/system/proxy}) {
    require Relianoid::HTTP::Controllers::API::System::Service::Proxy;

    GET qr{^/system/proxy$} => \&get_proxy_controller;
    POST qr{^/system/proxy$} => \&set_proxy_controller;
}

if ($PATH_INFO =~ qr{^/system/snmp}) {
    require Relianoid::HTTP::Controllers::API::System::Service::SNMP;

    GET qr{^/system/snmp$} => \&get_snmp_controller;
    POST qr{^/system/snmp$} => \&set_snmp_controller;
}

if ($PATH_INFO =~ qr{^/system/ntp}) {
    require Relianoid::HTTP::Controllers::API::System::Service::NTP;

    GET qr{^/system/ntp$} => \&get_ntp_controller;
    POST qr{^/system/ntp$} => \&set_ntp_controller;
}

if ($PATH_INFO =~ qr{^/system/users}) {
    require Relianoid::HTTP::Controllers::API::System::User;

    GET qr{^/system/users$} => \&get_system_user_controller;     #  GET users
    POST qr{^/system/users$} => \&set_system_user_controller;    #  POST users
}

if ($PATH_INFO =~ qr{^/system/log}) {
    require Relianoid::HTTP::Controllers::API::System::Log;

    GET qr{^/system/logs$} => \&list_logs_controller;

    my $logs_re = &getValidFormat('log');
    GET qr{^/system/logs/($logs_re)$} => \&download_logs_controller;

    GET qr{^/system/logs/($logs_re)/lines/(\d+)$} => \&show_logs_controller;
}

if ($PATH_INFO =~ qr{^/system/backup}) {
    require Relianoid::HTTP::Controllers::API::System::Backup;

    GET qr{^/system/backup$} => \&list_backups_controller;      #  GET list backups
    POST qr{^/system/backup$} => \&create_backup_controller;    #  POST create backups

    GET qr{^/system/backup/(.+)$} => \&download_backup_controller;            #  GET download backups
    PUT qr{^/system/backup/(.+)$} => \&upload_backup_controller;              #  PUT  upload backups
    DELETE qr{^/system/backup/(.+)$} => \&delete_backup_controller;           #  DELETE  backups
    POST qr{^/system/backup/(.+)/actions$} => \&restore_backup_controller;    #  POST  restore backups
}

if ($PATH_INFO =~ qr{^/system/(?:version|info|license|support|supportsave|language|packages)}) {
    require Relianoid::HTTP::Controllers::API::System::Info;

    GET qr{^/system/version$}     => \&get_version_controller;
    GET qr{^/system/info$}        => \&get_system_info_controller;
    GET qr{^/system/support$}     => \&get_support_file_controller;
    GET qr{^/system/supportsave$} => \&get_support_file_controller;
    # Using a non-capturing group as support(?:save)? to avoid repeating the 
    # call to get_support_file_controller will send a count of matches to 
    # get_support_file_controller, but this function accepts no arguments.
    # This repetition can be removed when the compatibility with
    # /system/supportsave is droped.

    my $license_re = &getValidFormat('license_format');
    GET qr{^/system/license/($license_re)$} => \&get_license_controller;

    GET qr{^/system/language$} => \&get_language_controller;
    POST qr{^/system/language$} => \&set_language_controller;

    GET qr{^/system/packages$} => \&get_packages_info_controller;
}

if ($PATH_INFO =~ qr{/ciphers$}) {
    require Relianoid::HTTP::Controllers::API::Certificate;

    GET qr{^/ciphers$} => \&get_ciphers_controller;
}

if ($PATH_INFO =~ qr{^/farms/$farm_re/(?:addheader|headremove|addresponseheader|removeresponseheader)(:?/\d+)?$}) {
    require Relianoid::HTTP::Controllers::API::Farm::HTTP;

    POST qr{^/farms/($farm_re)/addheader$} => \&add_addheader_controller;
    PUT qr{^/farms/($farm_re)/addheader/(\d+)$} => \&modify_addheader_controller;
    DELETE qr{^/farms/($farm_re)/addheader/(\d+)$} => \&del_addheader_controller;

    POST qr{^/farms/($farm_re)/headremove$} => \&add_headremove_controller;
    PUT qr{^/farms/($farm_re)/headremove/(\d+)$} => \&modify_headremove_controller;
    DELETE qr{^/farms/($farm_re)/headremove/(\d+)$} => \&del_headremove_controller;

    POST qr{^/farms/($farm_re)/addresponseheader$} => \&add_addResHeader_controller;
    PUT qr{^/farms/($farm_re)/addresponseheader/(\d+)$} => \&modify_addResHeader_controller;
    DELETE qr{^/farms/($farm_re)/addresponseheader/(\d+)$} => \&del_addResHeader_controller;
    POST qr{^/farms/($farm_re)/removeresponseheader$} => \&add_delResHeader_controller;
    PUT qr{^/farms/($farm_re)/removeresponseheader/(\d+)$} => \&modify_delResHeader_controller;
    DELETE qr{^/farms/($farm_re)/removeresponseheader/(\d+)$} => \&del_delResHeader_controller;
}

if ($ENV{PATH_INFO} =~ qr{^/vpns}) {
    require Relianoid::HTTP::Controllers::API::VPN::Core;
    my $vpn_re  = &getValidFormat('vpn_name');
    my $user_re = &getValidFormat('vpn_user');

    GET qr{^/vpns$},                 \&list_vpn_controller;
    GET qr{^/vpns/modules/summary$}, \&list_vpn_bymodule_controller;

    POST qr{^/vpns$}, \&add_vpn_controller;
    GET qr{^/vpns/($vpn_re)$}, \&get_vpn_controller;
    DELETE qr{^/vpns/($vpn_re)$}, \&delete_vpn_controller;
    PUT qr{^/vpns/($vpn_re)$}, \&modify_vpn_controller;
    POST qr{^/vpns/($vpn_re)/actions$}, \&actions_vpn_controller;

    if ($ENV{PATH_INFO} =~ qr{^/vpns/($vpn_re)/users}) {
        require Relianoid::HTTP::Controllers::API::VPN::User;

        POST qr{^/vpns/($vpn_re)/users$}, \&add_vpn_user_controller;
        DELETE qr{^/vpns/($vpn_re)/users/($user_re)$}, \&delete_vpn_user_controller;
        PUT qr{^/vpns/($vpn_re)/users/($user_re)$}, \&modify_vpn_user_controller;
    }

    if ($ENV{PATH_INFO} =~ qr{^/vpns/modules/(zss|site_to_site)$}) {
        require Relianoid::HTTP::Controllers::API::VPN::SiteToSite;

        GET qr{^/vpns/modules/(zss|site_to_site)$}, \&list_vpn_site_to_site_controller;
    }

    if ($ENV{PATH_INFO} =~ qr{^/vpns/modules/(ztn|tunnel)$}) {
        require Relianoid::HTTP::Controllers::API::VPN::Tunnel;

        GET qr{^/vpns/modules/(ztn|tunnel)$}, \&list_vpn_tunnel_controller;
    }

    # if ($ENV{PATH_INFO} =~ qr{^/vpns/modules/(zrs|remote_access)$}) {
    #     require Relianoid::HTTP::Controllers::API::VPN::RemoteAccess;

    #     GET qr{^/vpns/modules/(zrs|remote_access)$}, \&list_vpn_remote_site_controller;
    # }
}

##### Load modules dynamically #######################################
my $routes_path = &getGlobalConfiguration('lib_dir') . '/API40/Routes';
opendir(my $dir, $routes_path);

for my $file (readdir $dir) {
    next if $file !~ /\w\.pm$/;

    my $module = "$routes_path/$file";

    unless (eval { require $module; }) {
        &log_debug2("Error loading module: $module", "SYSTEM");
        &log_error($@, "SYSTEM");
        die $@;
    }
}

1;
