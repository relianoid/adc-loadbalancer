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

rm -rf /usr/local/relianoid/config/if_*
systemctl stop rsyslog
systemctl stop cron
if [ -f "/usr/local/relianoid/www/activation-cert.pem" ]; then
    rm /usr/local/relianoid/www/activation-cert.pem
fi
rm -rf /var/log/*
rm -rf /usr/local/relianoid/var/noid-collector/rrd/*
rm -rf /etc/apt/apt.conf
rm -rf /root/.ssh/*
rm -rf /root/*
rm /root/.bash_history
passwd -d root
sed -i "s/^root\:.*/root:*LOCK*:14600::::::/g" /etc/shadow
for user in `ls /home/`; do
	if [ "$user" == "azureuser" ]; then
		rm -rf /home/$user/*
		rm -rf /home/$user/.ssh/*
		rm /home/$user/.bash_history
		su -c "history -c" $user
	else
		rm -rf /home/$user/
	fi
fi
touch /etc/firstbootsetpw
apt clean
history -c
