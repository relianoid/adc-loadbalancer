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
clouddir="/usr/local/relianoid/share/cloud/azure"
cp $clouddir/rc.local /etc/rc.local
cp $clouddir/configure_nics /etc/network/if-up.d/

systemctl enable rc-local
systemctl start rc-local.service

# setup global variables
perl -MRelianoid::Config -e "setGlobalConfiguration('cloud_provider', 'azure')" >/dev/null
perl -MRelianoid::Config -E "setGlobalConfiguration('cloud_address_metadata', '169.254.169.254')" >/dev/null

# setup repository
echo "deb https://packages.microsoft.com/repos/microsoft-debian-bookworm-prod bookworm main" > /etc/apt/sources.list.d/microsoft-prod.list
cp $clouddir/microsoft.asc /etc/apt/trusted.gpg.d/microsoft.asc
cp $clouddir/azure-cli.sources /etc/apt/sources.list.d/

# install dependencies
dpkg=`dpkg -l waagent`
if [ $? -eq 1 ]; then
    echo "Azure detected: After the installation, please run:"
    echo "apt-get update && apt-get install cloud-init waagent azure-cli dnsmasq"
fi

exit 0
