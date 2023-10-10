#!/bin/bash
###############################################################################
#
#    ZEVENET Software License
#    This file is part of the ZEVENET Load Balancer software package.
#
#    Copyright (C) 2014-today ZEVENET SL, Sevilla (Spain)
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

# Exit at the first error.
set -e

### VARIABLE ###
DATE=$(date +%y%m%d_%H%M%S)
arch="amd64"

### FUNCTIONS ###
exit_with_error() {
  echo "Error: $1"
  exit 1
}

function cleanup() {
        rm -rf build-context
}

function msg() {
        echo -e "\n####"
        echo -e "## ${1}"
        echo -e "####\n"
}

function die() {
        local bldred='\e[1;31m' # Red bold text
        local txtrst='\e[0m'    # Text Reset

        cleanup
        msg "${bldred}Error${txtrst} ${1}"
        exit 1
}

function print_usage() {
        echo "Usage: $0 <--devel> [--pre|--pro|--interactive]"
        echo ""
        echo "Optional Options:"
        echo "  Compilation:"
        echo "    --devel                 Do not compile perl"
        echo ""
        echo "  Version mode:"
        echo "    --pre                   Version Suitable for pre-production"
        echo "    --pro                   Version suitable for production"
        echo "    --interactive           Indicate the version manually"
        echo ""
        echo "Examples:"
        echo "  $0 --devel --pre"
	echo "  $0 --pre"
        exit
}

function interactiveVersion() {
        echo "Please enter the version. Example: 5.13.4"
        read interactive_mode
        if [ -z $interactive_mode ]; then
                echo "*** aborted ***"
                echo "The version has not been entered."
                exit 1
        else
                zevenet_version=$interactive_mode
        fi
}

### END FUNCTIONS ####

# Variables to store parameter values.
mode=""
version=""
devel="false"

# Cycle to process the received parameters.
while [ "$#" -gt 0 ]; do
        case "$1" in
        --devel)
                if [[ "$mode" == "" ]]; then
			[ $1 == "--devel" ] && devel="true" && mode="devel"
                else
                        exit_with_error "The 'Mode' of the parameter has already been previously specified."
                fi
                shift
        ;;
        --pre|--pro|--interactive)
                if [[ "$version" == "" ]]; then
                        version="$1"
                else
                        exit_with_error "The 'Version' of the parameter has already been previously specified."
                fi
                shift
        ;;
        *)
                exit_with_error "unknown parameter: $1"
        ;;
        esac
done

# Check that the version mode has been specified.
if [[ -z "$version" ]]; then
        echo "You must specify a version mode"
        echo ""
        print_usage
fi

# Get ZEVENET version.
if  [ $version != "--interactive" ]; then
        zevenet_version=`git describe --tags --abbrev=0 | sed 's|^v||'`
        if [ $? != 0 ]; then
                echo ""
                echo "Could not get the version automatically."
                echo "failed cmd: git describe --tags --abbrev=0 | sed 's|^v||'"
                echo ""
                interactiveVersion
        fi
else
        interactiveVersion
fi

# Increments the last digit of the current version of the project.
if [[ $version == "--pre" ]]; then
        suffix=`sed 's|.*-|-|;s|[0-9].*||' <<< $zevenet_version`
        last_digit=`sed -E 's|\-.*||;s|^.*\.||' <<< $zevenet_version`
        last_digit=$((last_digit+1))
        zevenet_version=`sed -E "s|\-.*||;s|\.[0-9]+$|\.${last_digit}|;s|\$.*|${suffix}|" <<< $zevenet_version`
fi

# Ensure we are in the correct directory.
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null && pwd )"
if [ "$BASE_DIR" == "/" ]; then
        BUILD_DIR="/build-pkg"
else
        BUILD_DIR="${BASE_DIR}/build-pkg"
fi

# Setup docker images.
cd "$BUILD_DIR"
msg "Setting up the docker environment..."
debian_versions=(buster)

# Check whether docker is running.
docker ps -q >/dev/null 2>&1 \
        || die ": it seems that docker is not working"

for version in "${debian_versions[@]}"; do
        echo -e "\n>> Building ${version} image:"

        dockerimg="zvn-ee-builder-${version}"

        # Ensure that docker build context exists.
        mkdir -p build-context

        # Build specific docker image.
        sed "s/#{version}/${version}/g" dockerfile-base > build-context/Dockerfile
        docker build \
                --build-arg host_uid="$(id -u)" \
                --build-arg host_gid="$(id -g)" \
                -t "$dockerimg" \
                build-context/ || die " building docker image"

        # Remove docker build context.
        cleanup

done

# Setup a clean environment.
msg "Setting up a clean environment..."

WORK_DIR="${BUILD_DIR}/workdir"
if [ -d "${WORK_DIR}" ]; then
        rm -rf ${WORK_DIR}
fi
mkdir ${WORK_DIR}
# Copy all the files in project to workdir, except build-pkg.
cd ${BASE_DIR}
if [ $BASE_DIR == "/" ];then
	TAR_file="${BUILD_DIR}/files.tar"
	TAR_file_tmp="${BUILD_DIR}/files.tmp"
		if [ -f "${TAR_file_tmp}" ]; then
        		rm ${TAR_file_tmp}
		fi
	for file in `git ls-tree --full-tree -r --name-only HEAD`; do
        	echo $file >> ${TAR_file_tmp}
	done
	tar cvf ${TAR_file} --files-from=${TAR_file_tmp} > /dev/null
	cd ${WORK_DIR}
	tar xvf ${TAR_file} > /dev/null
	rm -r ${TAR_file_tmp}
	rm -r ${TAR_file}
	rm -rf ${WORK_DIR}/build-pkg
else
	rsync -a --exclude $BASE_DIR * $WORK_DIR/
	rm -rf ${WORK_DIR}/build-pkg
fi
# Set version and package name.
cd ${WORK_DIR}
sed -i "s|Version\:.*|Version: ${zevenet_version}|" ${WORK_DIR}/DEBIAN/control
pkgname_prefix="zevenet_${zevenet_version}_${arch}"

if [[ "$devel" == "false" ]]; then
	pkgname=${pkgname_prefix}_${DATE}.deb
else
	pkgname=${pkgname_prefix}_${mode}_${DATE}.deb
fi

# Set version in global.conf tpl.
globalconftpl='usr/local/zevenet/share/global.conf.template'
version_string='$version="_VERSION_";'
sed -i "s/$version_string/\$version=\"$zevenet_version\";/" $globalconftpl


#### Package preparation ####
msg "Preparing package..."

# Remove .keep files.
find . -name .keep -exec rm {} \;

# Release or development.
if [[ $devel == "false" ]]; then
	msg "Removing warnings..."
	# Don't include API 3
	find -L usr/local/zevenet/bin \
			usr/share/perl5/Zevenet \
			usr/local/zevenet/www/zapi/v3.1 \
			usr/local/zevenet/www/zapi/v4.0 \
			-type f \
			-exec sed --follow-symlinks -i 's/^use warnings.*//' {} \;
fi

#### Generate package and clean up ####
msg "Generating .deb package..."
cd "$BUILD_DIR"

# Generate package using the most recent debian version.
docker run --rm -v "$(pwd)":/workdir \
        "$dockerimg" \
        fakeroot dpkg-deb --build workdir packages/"$pkgname" \
        || die " generating the package"

msg "Success: package ready"
