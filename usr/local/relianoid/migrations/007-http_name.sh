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

source /usr/local/relianoid/bin/load_global_conf
load_global_conf

for i in $(find /usr/local/relianoid/config/ -name "*_proxy.cfg" -or -name "*_pound.cfg");
do
	fname=`echo $i | cut -d"_" -f1 | cut -d"/" -f6`

	echo "Checking User directive in farm config file: $i"
	grep "^User.*" $i &>/dev/null
	if [[ $? != 0 ]];then
		echo "Adding directive 'User' to farm config file: $i"
		sed -i "/^##GLOBAL OPTIONS/ aUser\t\t\"root\"" $i
	fi

	echo "Checking Group directive in farm config file: $i"
	grep "^Group.*" $i &>/dev/null
	if [[ $? != 0 ]];then
		echo "Adding directive 'Group' to farm config file: $i"
		sed -i "/^User/ aGroup\t\t\"root\"" $i
	fi

	echo "Checking Name directive in farm config file: $i"
	grep "^Name.*" $i &>/dev/null
	if [[ $? != 0 ]];then
		echo "Adding directive 'Name' to farm config file: $i"
		sed -i "/^Group/ aName\t\t${fname}" $i
	fi

	echo "Checking Control directive in farm config file: $i"
	grep "^Control.*" $i &>/dev/null
	if [[ $? != 0 ]];then
		echo "Adding directive 'Control' to farm config file: $i"
		sed -i "/^ThreadModel/ aControl\t\t\"/tmp/${fname}_proxy.socket\"" $i
	fi

done
