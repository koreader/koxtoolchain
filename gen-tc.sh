#!/bin/bash -e
#
# adapted from NiLuJe's build script:
# http://www.mobileread.com/forums/showthread.php?t=88004
# (live copy: http://trac.ak-team.com/trac/browser/niluje/Configs/trunk/Kindle/Misc/x-compile.sh)
#
# =================== original header ====================
#
# Kindle cross toolchain & lib/bin/util build script
#
# $Id: x-compile.sh 15482 2018-10-17 15:48:55Z NiLuJe $
#
# kate: syntax bash;
#

## Using CrossTool-NG (http://crosstool-ng.org/)

CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_ROOT=${CUR_DIR}/build
DEFAULT_GIT_REPO="https://github.com/crosstool-ng/crosstool-ng.git"

Build_CT-NG() {
	echo "[*] Building CrossTool-NG . . ."
	ct_ng_git_repo=$1
	shift
	ct_ng_commit=$1
	shift
	cfg_path=$1
	PARALLEL_JOBS=$(($(getconf _NPROCESSORS_ONLN 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || echo 0) + 1))
	echo "[-] ct-ng git repo: ${ct_ng_git_repo}"
	echo "[-] ct-ng commit hash: ${ct_ng_commit}"
	echo "[-] ct-ng config path: ${cfg_path}"
	echo "[-] compiling with ${PARALLEL_JOBS} parallel jobs"

	[ ! -d ${BUILD_ROOT} ] && mkdir -p ${BUILD_ROOT}
	pushd ${BUILD_ROOT}
		if [ ! -d CT-NG ]; then
			git clone ${ct_ng_git_repo} CT-NG
		fi
		pushd CT-NG
			git remote rm origin
			git remote add origin ${ct_ng_git_repo}
			git fetch origin
			git checkout ${ct_ng_commit}
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

			unset CFLAGS CXXFLAGS LDFLAGS
			cp ${cfg_path} .config
			echo "CT_PARALLEL_JOBS=${PARALLEL_JOBS}" >> .config
			ct-ng oldconfig
			# ct-ng menuconfig
			ct-ng updatetools
			nice ct-ng build
			pushd .build
				tc_prefix=$(ls -d arm-*)
			popd
			echo "[INFO ]  ================================================================="
			echo "[INFO ]  Build done. Please add $HOME/x-tools/${tc_prefix}/bin to your PATH."
			echo "[INFO ]  ================================================================="
		popd
	popd
}

HELP_MSG="
usage: $0 PLATFORM

Supported platforms:

	kindle
	kindle5
	kindlepw2
	kobo
	cervantes
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
	kobo)
		Build_CT-NG \
			https://github.com/NiLuJe/crosstool-ng.git \
			8b1358a286d2df3deb71d6f041ad2064b555fa43 \
			${CUR_DIR}/configs/ct-ng-kobo-config
		;;
	kindlepw2)
		Build_CT-NG \
			https://github.com/NiLuJe/crosstool-ng.git \
			8b1358a286d2df3deb71d6f041ad2064b555fa43 \
			${CUR_DIR}/configs/ct-ng-kindlepw2-config
		;;
	kindle5)
		Build_CT-NG \
			https://github.com/NiLuJe/crosstool-ng.git \
			8b1358a286d2df3deb71d6f041ad2064b555fa43 \
			${CUR_DIR}/configs/ct-ng-kindle5-config
		;;
	kindle)
		Build_CT-NG \
			https://github.com/NiLuJe/crosstool-ng.git \
			8b1358a286d2df3deb71d6f041ad2064b555fa43 \
			${CUR_DIR}/configs/ct-ng-kindle-config
		;;
	cervantes)
		Build_CT-NG \
			https://github.com/NiLuJe/crosstool-ng.git \
			8b1358a286d2df3deb71d6f041ad2064b555fa43 \
			${CUR_DIR}/configs/ct-ng-cervantes-config
		;;
	*)
		echo "[!] $1 not supported!"
		echo "${HELP_MSG}"
		exit 1
		;;
esac
