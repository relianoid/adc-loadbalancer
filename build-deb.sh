#!/bin/bash
# Dependencies: rsync, fakeroot, dpkg-deb
set -Eeu

cd "$(dirname "${BASH_SOURCE[0]}")"

WORK_DIR="workdir"
rm -rf "$WORK_DIR"
mkdir "$WORK_DIR"

rsync --archive DEBIAN "$WORK_DIR/"
rsync --archive etc "$WORK_DIR/"
rsync --archive usr "$WORK_DIR/"

version=$(grep '^Version:' DEBIAN/control | awk '{print $2}')
package_name="relianoid_${version}_amd64.deb"

global_conf_template='usr/local/relianoid/share/global.conf.template'
sed -i "s/_VERSION_/$version/" "${WORK_DIR}/${global_conf_template}"

find "$WORK_DIR" -name .keep -exec rm {} \;

fakeroot dpkg-deb --build workdir "$package_name"
