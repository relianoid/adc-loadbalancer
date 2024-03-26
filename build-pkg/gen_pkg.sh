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

set -e

remove_build_context() {
    rm -rf build-context
}

msg() {
    echo " > ${1}"
}

die() {
    local BOLD_RED='\e[1;31m'
    local RESET_COLOR='\e[0m'

    remove_build_context
    msg "${BOLD_RED}Error${RESET_COLOR} ${1}"
    exit 1
}

print_usage() {
    echo "Usage: $0 [--force-version][--help]"
    echo ""
    echo "Options:"
    echo "    --force-version         Force a version number interactively"
    echo "    --help                  Show this message"
    exit
}

interactive_version() {
    msg "Enter a version. For example: 7.0.0"
    echo -n " > Version: "
    read interactive_mode
    if [ -z $interactive_mode ]; then
        echo "No version received. Quitting"
        exit 1
    fi
    relianoid_version=$interactive_mode
}

get_version() {
    grep '^Version:' ${BASE_DIR}/DEBIAN/control | awk '{print $2}'
}

force_version=''

while [ "$#" -gt 0 ]; do
    case "$1" in
    --help)
        print_usage
    ;;
    --force-version)
        force_version=1
        shift
    ;;
    *)
        echo "Error: Unknown parameter: $1"
    ;;
    esac
done

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null && pwd )"
BUILD_DIR="${BASE_DIR}/build-pkg"
WORK_DIR="${BUILD_DIR}/workdir"
if [ -d "${WORK_DIR}" ]; then
    rm -rf ${WORK_DIR}
fi
mkdir ${WORK_DIR}
rsync --archive $BASE_DIR/DEBIAN $WORK_DIR/
rsync --archive $BASE_DIR/etc $WORK_DIR/
rsync --archive $BASE_DIR/usr $WORK_DIR/
rsync --archive $BASE_DIR/license.txt $WORK_DIR/

# Get package version
if  [ -z $force_version ]; then
    relianoid_version=$(get_version)
else
    interactive_version
    sed -i "s|Version\:.*|Version: ${relianoid_version}|" ${WORK_DIR}/DEBIAN/control
fi

current_time=$(date +%y%m%d_%H%M%S)
package_name="relianoid_${relianoid_version}_amd64_${current_time}.deb"

# Set version in global.conf template
global_conf_template='usr/local/relianoid/share/global.conf.template'
version_string='$version="_VERSION_";'
sed -i "s/$version_string/\$version=\"$relianoid_version\";/" "${WORK_DIR}/${global_conf_template}"

msg "Preparing package..."

find ${WORK_DIR} -name .keep -exec rm {} \;

cd ${WORK_DIR}
msg "Removing warnings..."
find -L usr/local/relianoid \
    usr/share/perl5/Relianoid \
    usr/local/relianoid/www/zapi/v4.0 \
    -type f \
    -exec sed --follow-symlinks -i 's/^use warnings.*//' {} \;

cd - >/dev/null

cd "$BUILD_DIR"

msg "Setting up the docker environment..."

debian_version=bookworm
docker_image="relianoid-builder-${debian_version}"
# Ensure that docker build context exists.
mkdir -p build-context
# Build specific docker image.
sed "s/#{version}/${debian_version}/g" dockerfile-base > build-context/Dockerfile
docker ps -q >/dev/null 2>&1 \
    || die ": Failed running Docker command"

msg "Building image ${docker_image}"

docker build \
    --build-arg host_uid="$(id -u)" \
    --build-arg host_gid="$(id -g)" \
    -t "$docker_image" \
    build-context/ || die " building docker image"
remove_build_context

msg "Generating .deb package..."

docker run --rm --network none --volume "$(pwd)":/workdir "$docker_image" \
    fakeroot dpkg-deb --build workdir packages/${package_name} \
    || die " generating the package"

msg "Success: package ready"
