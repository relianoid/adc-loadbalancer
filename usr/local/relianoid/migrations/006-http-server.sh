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

set -e

CHEROKEE_DIR="/usr/local/relianoid/app/cherokee"
CHEROKEE_CONF="$CHEROKEE_DIR/etc/cherokee/cherokee.conf"
LIGHTTPD_DIR="/usr/local/relianoid/app/lighttpd"
LIGHTTPD_CONF="$LIGHTTPD_DIR/lighttpd.conf"
LIGHTTPD_CONF_TEMPLATE="/usr/local/relianoid/share/lighttpd.conf"

[ -f "$LIGHTTPD_CONF" ] && exit 0

mkdir -p "$LIGHTTPD_DIR"
cp "$LIGHTTPD_CONF_TEMPLATE" "$LIGHTTPD_CONF"

[ ! -f "$CHEROKEE_CONF" ] && exit 0

# Upgrading from bookworm ##################################

if [ -f "/usr/share/perl5/Relianoid/ELoad.pm" ]; then
    perl -MRelianoid::ELoad -e 'eload(module => "Relianoid::EE::Server::HTTP::Migration", func => "run")'
fi

# EE and CE upgrade to trixie
if systemctl is-enabled --quiet cherokee.service; then
    systemctl disable --quiet cherokee.service  --now
    systemctl daemon-reload
    sleep 5
    systemctl enable --quiet lighttpd.service --now

    # remove cherokee files
    # rm -rf "$CHEROKEE_DIR"
    rm -f "/var/log/cherokee-error.log*"
    rm -f "/var/log/cherokee-access.log*"
fi



