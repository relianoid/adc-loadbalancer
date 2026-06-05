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

truncate -s 0 /etc/machine-id
rm -rf /var/lib/cloud/*
rm -rf /tmp/*
rm -rf /var/tmp/*

# clean root artifacts (do not wipe root directory)
rm -rf /root/.ssh/*
rm -f /root/.bash_history
rm -f /root/.wget-hsts

# Properly lock root
passwd -l root

# remove non-default users completely
for user in $(ls /home); do
    if [ "$user" = "azureuser" ] || [ "$user" = "debian" ]; then
        rm -f /home/$user/.bash_history
        rm -f /home/$user/.ssh/authorized_keys
        su -c "history -c" $user
    else
        userdel -r $user 2>/dev/null
    fi
done

# ensure skeleton exists for new users
mkdir -p /etc/skel
chmod 755 /etc/skel

apt clean
history -c
