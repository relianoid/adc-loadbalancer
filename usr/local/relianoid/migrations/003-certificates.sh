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

# Migrate certificates files to new directory
mv /usr/local/relianoid/config/{*.pem,*.csr,*.key} /usr/local/relianoid/config/certificates/ 2>/dev/null

# Migrate certificate of farm config file
for i in $(find /usr/local/relianoid/config/ -name "*_proxy.cfg" -o -name "*_pound.cfg");
do
	if grep 'Cert \"\/usr\/local\/relianoid\/config\/\w.*\.pem' $i | grep -qv certificates; then
		echo "Migrating certificate directory of config file"
		sed -i -e 's/Cert \"\/usr\/local\/relianoid\/config/Cert \"\/usr\/local\/relianoid\/config\/certificates/' $i
	fi
done

# Migrate http server certificate
http_conf="/usr/local/relianoid/app/cherokee/etc/cherokee/cherokee.conf"

grep -E "/usr/local/relianoid/config/[^\/]+.pem" $http_conf
if [ $? -eq 0 ]; then
	echo "Migrating certificate of http server"
	perl -E '
use strict;
use Tie::File;
tie my @fh, "Tie::File", "/usr/local/relianoid/app/cherokee/etc/cherokee/cherokee.conf";
for my $line (@fh)
{
	if ($line =~ m"/usr/local/relianoid/config/[^/]+\.(pem|csr|key)" )
	{

		unless( $line =~ s"/usr/local/relianoid/config"/usr/local/relianoid/config/certificates"m)
		{
			say "Error modifying: >$line<";
		}
		say "migrated $line";
	}
}
close @fh;
	'
fi

# verify that the ssl cert configured in cherokee really exists
CERT_PATH="/usr/local/relianoid/config/certificates"
CERT_FILE=`grep -r "vserver.*ssl_certificate_file = " $http_conf | awk -F' ' '{ print $3 }'`
if [ ! -f "$CERT_FILE" ]; then
	CERT_NAME=`basename $CERT_FILE`
	CERT_OFFICIAL_FILE="$CERT_PATH/$CERT_NAME"
	if [ -f "$CERT_OFFICIAL_FILE" ]; then
		cp "$CERT_OFFICIAL_FILE" "/usr/local/relianoid/app/cherokee/etc/cherokee/$CERT_NAME"
		sed -i "s/vserver.*ssl_certificate_file .*/vserver\!1\!ssl_certificate_file = \/usr\/local\/relianoid\/app\/cherokee\/etc\/cherokee\/$CERT_NAME/g" $http_conf
		sed -i "s/vserver.*ssl_certificate_key_file .*/vserver\!1\!ssl_certificate_key_file = \/usr\/local\/relianoid\/app\/cherokee\/etc\/cherokee\/$CERT_NAME/g" $http_conf
	else
		echo "Cert file missing, cannot be found: $CERT_FILE"
	fi
fi
