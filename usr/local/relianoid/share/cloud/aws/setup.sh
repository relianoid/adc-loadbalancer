#!/bin/bash
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

# setup rc.local
dir="/usr/local/relianoid/share/cloud/aws"
cp $dir/rc.local /etc/rc.local

# setup dhcp interfaces
SHARE_DIR="/usr/local/relianoid/share"
CHECK_NIC_DHCP="check-nic-dhcp"
if [ -f "$SHARE_DIR/$CHECK_NIC_DHCP" ]; then
	NET_CONFIG_DIR="/etc/network/if-up.d"
	cp $SHARE_DIR/$CHECK_NIC_DHCP $NET_CONFIG_DIR/
	$NET_CONFIG_DIR/$CHECK_NIC_DHCP
fi

# setup global variables
perl -MRelianoid::Config -E "setGlobalConfiguration('cloud_provider', 'aws')" >/dev/null
perl -MRelianoid::Config -E "setGlobalConfiguration('cloud_address_metadata', '169.254.169.254')" >/dev/null
perl -MRelianoid::Config -E "
	&setGlobalConfiguration('netcat_bin', '$aws_netcat_bin');
	&setGlobalConfiguration('cat_bin', '$aws_cat_bin');
	&setGlobalConfiguration('lsmod', '$aws_lsmod');
	&setGlobalConfiguration('modprobe', '$aws_modprobe');
	&setGlobalConfiguration('poweroff_bin', '$aws_poweroff_bin');
	&setGlobalConfiguration('reboot_bin', '$aws_reboot_bin');
	&setGlobalConfiguration('dhcp_bin', '$aws_dhcp_bin');
	&setGlobalConfiguration('ifconfig_bin', '$aws_ifconfig_bin');
	&setGlobalConfiguration('fdisk_bin', '$aws_fdisk_bin');
	&setGlobalConfiguration('date', '$aws_date_bin');
	&setGlobalConfiguration('cut_bin', '$aws_cut_bin');"
