#!/usr/bin/bash

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

SNMPD_CONF='/etc/snmp/snmpd.conf'
RELIANOID_SNMPD_CONF='/etc/snmp/snmpd.conf.d/50-relianoid.conf'

# snmpd install or update may overwrite /etc/snmp/snmpd.conf with a template.
# Wipe snmpd.conf template, to avoid preserving example conf on the next step.
if [ -f "$SNMPD_CONF" ] && grep -q "example configuration" $SNMPD_CONF; then
    echo "includeDir /etc/snmp/snmpd.conf.d" > /etc/snmp/snmpd.conf
fi

# Migrate old config to new $RELIANOID_SNMPD_CONF
if [ -f "$SNMPD_CONF" ] && [ ! -s "$RELIANOID_SNMPD_CONF" ]; then
    # Allow non-matching grep commands
    set +e
    {
        grep -i '^[[:space:]]*#\?[[:space:]]*agentAddress\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*..community\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*trapcommunity\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*authtrapenable\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*createuser\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*iquerysecname\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*..user\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*trapsink\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*trap2sink\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*trapsess\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*linkUpDownNotifications\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*defaultMonitors\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*load\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*includeAllDisks\b' $SNMPD_CONF
        grep -i '^[[:space:]]*#\?[[:space:]]*monitor\b' $SNMPD_CONF
    } >> $RELIANOID_SNMPD_CONF
    set -e
    # Wipe /etc/snmp/snmpd.conf after migrating old config
    echo "includeDir /etc/snmp/snmpd.conf.d" > $SNMPD_CONF
fi

# Add snmpd arguments when the service is ran
perl -MRelianoid::SNMP -E "&setSnmpdDefaultConfig();"

# Install default $RELIANOID_SNMPD_CONF on new installs
if [ ! -s "$RELIANOID_SNMPD_CONF" ]; then
    perl -MRelianoid::SNMP -E "&setSnmpdFactoryReset();"
fi
