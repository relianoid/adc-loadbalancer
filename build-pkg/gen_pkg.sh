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
    echo -e " > ${1}"
}

die() {
    local BOLD_RED='\e[1;31m'
    local RESET_COLOR='\e[0m'

    remove_build_context
    msg "${BOLD_RED}Error${RESET_COLOR} ${1}"
    exit 1
}

print_usage() {
    echo "Usage: $(basename "$0") [--rc|--prod][--help]"
    echo ""
    echo "Options:"
    echo "    --force-version         Force a version number interactively"
    echo "    --help                  Show this message"
    echo ""
    echo "By default the version in DEBIAN/control is used."
    echo "By default every version will have the suffix ~devDATE."
    echo ""
    echo "    [--dev]          Developement version by default. Example: 7.5.0~dev20260224T1133"
    echo "    --rc             Set version as release candidate. Example: 7.5.0~rc20260224T1133"
    echo "    --prod           Set version as final release. Example: 7.5.0"
    echo ""
}

get_version() {
    grep '^Version:' "${BASE_DIR}/DEBIAN/control" | awk '{print $2}'
}

version_sufix="dev" # default version sufix

while [ "$#" -gt 0 ]; do
    case "$1" in
    -h|--help)
        print_usage
        exit
    ;;
    --rc)
        version_sufix="rc"
        shift
    ;;
    --prod)
        version_sufix=""
        shift
    ;;
    *)
        die "Panic: Unknown parameter: $1"
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

# Get RELIANOID version.
relianoid_version=$(get_version)

if [ "$version_sufix" ]; then
    relianoid_version=$relianoid_version~$version_sufix$(date -u +%Y%m%dT%H%M)
    sed -i "s|Version\:.*|Version: ${relianoid_version}|" "${WORK_DIR}/DEBIAN/control"
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
    usr/local/relianoid/www/api/v4.0 \
    -type f \
    -exec sed --follow-symlinks -i 's/^use warnings.*//' {} \;

cd - >/dev/null

cd "$BUILD_DIR"

container=docker
container_args=""
if which podman; then
    container=podman
    container_args="--userns=keep-id"
# else
#     container_args="--user $(id -u):$(id -g)"
fi

msg "Setting up $container environment..."

debian_version=trixie-slim
docker_image="relianoid-builder-${debian_version}:latest"
userID=0
groupID=0
    # --build-arg host_uid="$userID" \
    # --build-arg host_gid="$groupID" \

# Ensure that docker build context exists.
mkdir -p build-context

# Build specific docker image.
sed "s/#{version}/${debian_version}/g" dockerfile-base > build-context/Dockerfile

$container ps -q >/dev/null 2>&1 \
    || die ": Failed running $container command"

msg "Building image ${docker_image}"

    # --build-arg host_uid="$(id -u)" \
    # --build-arg host_gid="$(id -g)" \
$container build \
    --network host \
    --build-arg host_uid="$(id -u)" \
    --build-arg host_gid="$(id -g)" \
    -t "$docker_image" \
    build-context/ || die " building $container image"
remove_build_context

msg "Generating .deb package..."

# --ulimit nofile=1024:1024
# is a workaround to:
# faked-sysv may appear stuck or consume 100% CPU on Debian due to a known bug 
# where the daemon enters a tight loop closing high-numbered file descriptors, 
# especially under high file descriptor limits.

    # -u "$userID:$groupID" \
$container run --rm \
    $container_args \
    --network none \
    --volume "$(pwd)":/workdir \
    --ulimit nofile=1024:1024 \
    "$docker_image" \
    fakeroot dpkg-deb --build workdir packages/${package_name} \
    || die " generating the package"

msg "Success: package ready"
