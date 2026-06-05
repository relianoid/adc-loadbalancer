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

clouddir="/usr/local/relianoid/share/cloud/azure"

cp $clouddir/rc.local /etc/rc.local
chmod +x /etc/rc.local

systemctl enable rc-local
systemctl start rc-local.service

cp $clouddir/configure_nics /etc/network/if-up.d/
chmod +x /etc/network/if-up.d/configure_nics

perl -MRelianoid::Config -e "setGlobalConfiguration('cloud_provider', 'azure')" >/dev/null
perl -MRelianoid::Config -e "setGlobalConfiguration('cloud_address_metadata', '169.254.169.254')" >/dev/null

echo "deb https://packages.microsoft.com/repos/microsoft-debian-bookworm-prod bookworm main" > /etc/apt/sources.list.d/microsoft-prod.list
cp $clouddir/microsoft.asc /etc/apt/trusted.gpg.d/microsoft.asc
cp $clouddir/azure-cli.sources /etc/apt/sources.list.d/

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y walinuxagent cloud-init azure-cli dnsmasq

systemctl enable walinuxagent
systemctl start walinuxagent

systemctl enable cloud-init

exit 0