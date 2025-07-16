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

if [ ! -f "/usr/local/relianoid/share/noid_ssl_cert.pem" ]; then
	echo "Default SSL certificate does not exist _/usr/local/relianoid/share/noid_ssl_cert.pem_"
	exit 1
fi

if [ ! -f "/usr/local/relianoid/config/certificates/noid_ssl_cert.key" ]; then
	cp /usr/local/relianoid/share/noid_ssl_cert.key /usr/local/relianoid/config/certificates/
fi
if [ ! -f "/usr/local/relianoid/config/certificates/noid_ssl_cert.pem" ]; then
	cp /usr/local/relianoid/share/noid_ssl_cert.pem /usr/local/relianoid/config/certificates/
fi

# Migrate cherokee default certificate
if [ -f "/usr/local/relianoid/app/cherokee/etc/cherokee/cherokee.conf" ] && [ "`grep zencert /usr/local/relianoid/app/cherokee/etc/cherokee/cherokee.conf`" != "" ]; then
	sed -i -e 's/zencert-c/noid_ssl_cert/g' /usr/local/relianoid/app/cherokee/etc/cherokee/cherokee.conf
	sed -i -e 's/zencert/noid_ssl_cert/g' /usr/local/relianoid/app/cherokee/etc/cherokee/cherokee.conf
fi

# Migrate HTTP/S farms default certificate
for i in $(find /usr/local/relianoid/config/ -name "*proxy.cfg");
do
	if [ "`grep zencert $i`" != "" ]; then
		sed -i -e 's/zencert.pem/noid_ssl_cert.pem/g' "$i"
	fi
done

# Finally, remove obsolete zencert
rm -rf /usr/local/zevenet/config/certificates/zencert-c.key /usr/local/zevenet/config/certificates/zencert.pem
