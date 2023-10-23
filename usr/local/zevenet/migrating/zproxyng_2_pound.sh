#!/usr/bin/bash

source /usr/local/zevenet/bin/load_global_conf
load_global_conf

name="Name"
nfmark="NfMark"

for i in $(find /usr/local/zevenet/config/ -name "*_proxy.cfg" -or -name "*_pound.cfg");
do
	echo "Checking Name and NfMark directive in farm config file: $i"
	grep "^\s*Name\s*\"" $i &>/dev/null
	if [[ $? == 0 ]];then
		echo "Remove directive 'Name' to farm config file: $i"
		fname=`echo $i | cut -d"_" -f1 | cut -d"/" -f6`
		sed -i "/^\s*Name\s*\"/d" "$i"
	fi

	grep "^\s*NfMark\s*" $i &>/dev/null
	if [[ $? == 0 ]];then
		echo "Remove directive 'NfMark' to farm config file: $i"
		fname=`echo $i | cut -d"_" -f1 | cut -d"/" -f6`
		sed -i "/^\s*NfMark\s*/d" "$i"
	fi

done
