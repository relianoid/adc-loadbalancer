#!/bin/sh
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

set -eu

DEBIAN_SNMPD_SERVICE="snmpd.service"
DEBIAN_SNMPD_SERVICE_PATH="/usr/lib/systemd/system/$DEBIAN_SNMPD_SERVICE"
RELIANOID_SNMPD_SERVICE="relianoid-snmpd.service"
RELIANOID_SNMPD_SERVICE_PATH="/etc/systemd/system/$RELIANOID_SNMPD_SERVICE"
RELIANOID_SNMPD_SERVICE_TEMPLATE="/usr/local/relianoid/share/$RELIANOID_SNMPD_SERVICE"

# if systemctl is-enabled --quiet $DEBIAN_SNMPD_SERVICE; then
if [ ! -f $RELIANOID_SNMPD_SERVICE_PATH ]; then
    cp $RELIANOID_SNMPD_SERVICE_TEMPLATE $RELIANOID_SNMPD_SERVICE_PATH

    # configure systemd snmpd service
    if ! grep --quiet ' -I -smux,mteTrigger,mteTriggerConf' $DEBIAN_SNMPD_SERVICE_PATH; then
        sed -i 's/ -I -smux,mteTrigger,mteTriggerConf//' $RELIANOID_SNMPD_SERVICE_PATH
    fi
    # configure logging
    if ! grep --quiet '\-LS6d ' $RELIANOID_SNMPD_SERVICE_PATH; then
        sed -i -E 's/-L[^[:space:]]+ /-LS6d /' $RELIANOID_SNMPD_SERVICE_PATH
    fi

    # replace service
    if systemctl is-enabled --quiet $DEBIAN_SNMPD_SERVICE; then
        systemctl disable --now $DEBIAN_SNMPD_SERVICE
        systemctl daemon-reload
        systemctl enable --now $RELIANOID_SNMPD_SERVICE
    fi
fi
