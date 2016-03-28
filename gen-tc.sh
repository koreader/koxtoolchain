#!/bin/bash -e
#
# adapted from NiLuJe's build script:
# http://www.mobileread.com/forums/showthread.php?t=88004
#
# =================== original header ====================
#
# Kindle cross toolchain & lib/bin/util build script
#
# $Id: x-compile.sh 12265 2015-08-20 15:24:44Z NiLuJe $
#
# kate: syntax bash;
#

## Using CrossTool-NG (http://crosstool-ng.org/)

CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_ROOT=${CUR_DIR}/build

Build_CT-NG() {
	echo "[*] Building CrossTool-NG . . ."
	cfg_path=$1
	echo "[-] ct-ng config path: ${cfg_path}"

	[ ! -d ${BUILD_ROOT} ] && mkdir -p ${BUILD_ROOT}
	pushd ${BUILD_ROOT}
		if [ ! -d CT-NG ]; then
			git clone git@github.com:crosstool-ng/crosstool-ng.git CT-NG
		fi
		pushd CT-NG
			git fetch
			git checkout crosstool-ng-1.22.0
			./bootstrap
			[ ! -d ${BUILD_ROOT}/CT_NG_BUILD ] && mkdir -p ${BUILD_ROOT}/CT_NG_BUILD
			./configure --prefix=${BUILD_ROOT}/CT_NG_BUILD
			make
			make install
			export PATH="${PATH}:${BUILD_ROOT}/CT_NG_BUILD/bin"
		popd
		cfg_name=$(basename ${cfg_path})
		# extract platform from config name
		tmp_str=${cfg_name#ct-ng-}
		TC_BUILD_DIR=${tmp_str%*-config}
		[ ! -d ${TC_BUILD_DIR} ] && mkdir -p ${TC_BUILD_DIR}
		pushd ${TC_BUILD_DIR}
			ct-ng distclean
			rm -rf build.log config .config .config.2 .config.old config.gen \
				.build/arm-kindle-linux-gnueabi .build/arm-kindle5-linux-gnueabi \
				.build/arm-kindlepw2-linux-gnueabi .build/arm-kobo-linux-gnueabi \
				.build/src .build/tools .build/tarballs/gcc-linaro-*.tar.xz

			unset CFLAGS CXXFLAGS LDFLAGS

			cp ${cfg_path} .config
			ct-ng oldconfig
			# ct-ng menuconfig
			nice ct-ng build
		popd
	popd
}


HELP_MSG="
usage: $0 PLATFORM

Supported platforms:

	kindle
"

if [ $# -lt 1 ]; then
	echo "Missing argument"
	echo "${HELP_MSG}"
	exit 1
fi

case $1 in
	-h)
		echo "${HELP_MSG}"
		exit 0
		;;
	kindle)
		Build_CT-NG ${CUR_DIR}/configs/ct-ng-kindle-config
		;;
	*)
		echo "[!] $1 not supported!"
		echo "${HELP_MSG}"
		exit 1
		;;
esac
