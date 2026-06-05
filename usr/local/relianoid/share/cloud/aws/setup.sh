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

dir="/usr/local/relianoid/share/cloud/aws"

cp $dir/rc.local /etc/rc.local
chmod +x /etc/rc.local

systemctl enable rc-local
systemctl start rc-local.service

SHARE_DIR="/usr/local/relianoid/share"
CHECK_NIC_DHCP="check-nic-dhcp"

if [ -f "$SHARE_DIR/$CHECK_NIC_DHCP" ]; then
        NET_CONFIG_DIR="/etc/network/if-up.d"
        cp $SHARE_DIR/$CHECK_NIC_DHCP $NET_CONFIG_DIR/
        chmod +x $NET_CONFIG_DIR/$CHECK_NIC_DHCP
        $NET_CONFIG_DIR/$CHECK_NIC_DHCP
fi

perl -MRelianoid::Config -E "setGlobalConfiguration('cloud_provider', 'aws')" >/dev/null
perl -MRelianoid::Config -E "setGlobalConfiguration('cloud_address_metadata', '169.254.169.254')" >/dev/null

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y cloud-init

systemctl enable cloud-init

exit 0