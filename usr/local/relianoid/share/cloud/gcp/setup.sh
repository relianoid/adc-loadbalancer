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
clouddir="/usr/local/relianoid/share/cloud/gcp"
cp $clouddir/rc.local /etc/rc.local
cp $clouddir/configure_nics /etc/network/if-up.d/

systemctl enable rc-local
systemctl start rc-local.service

# setup global variables
perl -MRelianoid::Config -e "setGlobalConfiguration('cloud_provider', 'gcp')" >/dev/null
perl -MRelianoid::Config -E "setGlobalConfiguration('cloud_address_metadata', 'metadata.google.internal')" >/dev/null

# repositories
cp $clouddir/cloud.google.gpg /usr/share/keyrings/
cp $clouddir/google-cloud-sdk.list /etc/apt/sources.list.d/

# install dependencies
dpkg=`dpkg -l google-guest-agent`
if [ $? -eq 1 ]; then
    echo "GCP detected: After the installation, please run:"
    echo "apt-get update && apt-get install -y cloud-init google-guest-agent google-cloud-sdk"
fi

exit 0
google-cloud-sdk.list
cloud.google.gpg
