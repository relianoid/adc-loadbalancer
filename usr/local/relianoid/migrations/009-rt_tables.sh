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

rttables_base_dir="/etc/iproute2"
rttables_old="$rttables_base_dir/rt_tables"
rttables_new_dir="$rttables_base_dir/rt_tables.d"
rttables_new_file="$rttables_new_dir/20-relianoid.conf"
rttables_tpl="/usr/local/relianoid/share/rt_tables.template"

if [ -f "$rttables_old" ]; then
    mkdir -p "$rttables_new_dir"
    mv "$rttables_old" "$rttables_new_file"
fi
