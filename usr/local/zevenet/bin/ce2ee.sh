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
#
# This script performs the migration from
# RELIANOID or ZEVENET Community Edition
# to RELIANOID Enterprise Edition.
#
# It requires an installation ISO file provided from
# https://www.relianoid.com/campaigns/migrate-to-enterprise/
#

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

if [ -z "$1" ]; then
    echo "Error: Please detail a Input cannot be empty."
    exit 1
fi

# 1. Create the dir /mnt/iso and mount the ISO file into it
ISO_DIR="/opt"
ISO_FILE="$1"
MOUNT_DIR="/mnt/iso"

if ! [[ "$ISO_FILE" =~ ^[A-Za-z0-9._%+-]+\.iso$ ]]; then
    echo "Error: Not a valid ISO file."
    exit 1
fi

if [ ! -d "$ISO_DIR" ]; then
    mkdir -p /opt
fi

if [ ! -d "$MOUNT_DIR" ]; then
    mkdir -p "$MOUNT_DIR"
fi

if [ ! -f "$ISO_DIR/$ISO_FILE" ]; then
    echo "Error: ISO file do not exist."
    exit 1
fi

mount -o loop "$ISO_DIR/$ISO_FILE" "$MOUNT_DIR" 2> /dev/null
if [ ! -f "$MOUNT_DIR/README.txt" ]; then
    echo "Failed to mount the ISO file."
    exit 1
fi

# 2. Comment Debian official apt sources in /etc/apt/sources.list
sed -i 's/^deb/#deb/' /etc/apt/sources.list
echo "" > /etc/apt/sources.list.d/zevenet.list

# 3. Add an apt deb entry pointing to the mounted folder /mnt/iso with the distro buster and directory main
echo "deb file:$MOUNT_DIR buster main" >> /etc/apt/sources.list.d/zevenet.list

# 4. Perform an apt update
apt update

# 5. Perform an unattended apt upgrade
#sed -i 's/.*conf_force_conffold.*/conf_force_conffold=YES/g' /etc/ucf.conf
# prepare grub-pc unattended update
#debconf-show grub-pc > /tmp/grub-pc.debconf
DISK=`fdisk -l | grep Disk | head -1 | awk -F' ' '{ printf $2}' | tr -d ':'`
#sed -i -r "s#.*grub\-pc\/install_devices\:.*#* grub\-pc\/install_devices\: $DISK#g" /tmp/grub-pc.debconf
if [ -e "$DISK" ]; then
    echo "grub-pc grub-pc/install_devices multiselect $DISK" > /tmp/grub-pc.debconf
    debconf-set-selections /tmp/grub-pc.debconf
    rm /tmp/grub-pc.debconf
fi

DEBIAN_FRONTEND=noninteractive apt install -y conntrackd ethtool expect gdnsd health-checks keepalived libauthen-simple-ldap-perl libconvert-asn1-perl libcrypt-blowfish-perl libcrypt-cbc-perl libcurses-perl libcurses-ui-perl libdata-structure-util-perl libdigest-bubblebabble-perl libdigest-hmac-perl libdigest-md5-file-perl libdotconf0 libdrm-common libdrm2 libdumbnet1 libfindbin-libs-perl libgssapi-perl libhiredis0.14 libipset11 libjemalloc2 libldns2 liblinux-inotify2-perl libltdl7 liblua5.1-0 libmaxminddb0 libmodsecurity libmspack0 libnet-dns-perl libnet-dns-sec-perl libnet-ifconfig-wrapper-perl libnet-ip-perl libnet-ldap-perl libnet-libidn-perl libnet-sip-perl libnetfilter-cthelper0 libnetfilter-queue1 libnl-3-200 libnl-genl-3-200 libodbc1 libproc-find-perl libre2-5 libstrongswan libstrongswan-standard-plugins libtcl8.6 libterm-readkey-perl libunwind8 liburcu6 libxmlsec1 libxmlsec1-openssl libxslt1.1 libyajl2 linux-headers-4.19.118-z6000 linux-image-4.19.118-z6000 lua-bitop lua-cjson mariadb-common msodbcsql17 mssql-tools netcat-openbsd netplug odbcinst odbcinst1debian2 open-vm-tools packetbl ppp qemu-guest-agent redis-tools rsync sec ssyncd ssyncd-pound strongswan-charon strongswan-libcharon strongswan-starter tcl-expect tcl8.6 unixodbc xe-guest-utilities xl2tpd
DEBIAN_FRONTEND=noninteractive apt upgrade -y
DEBIAN_FRONTEND=noninteractive apt install -y zevenet-ipds

# Unmount the ISO file after the upgrade
umount "$MOUNT_DIR"

# Clean up
rmdir "$MOUNT_DIR"

echo "RELIANOID CE successfully migrated to Enterprise. Welcome to the Site Reliability Experience!"
echo "Please, reboot the system to apply the upgrade."
