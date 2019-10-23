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
# $Id: x-compile.sh 16434 2019-09-01 15:36:06Z NiLuJe $
#
# kate: syntax bash;
#

## Using CrossTool-NG (http://crosstool-ng.org/)

CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_ROOT="${CUR_DIR}/build"
DEFAULT_GIT_REPO="https://github.com/crosstool-ng/crosstool-ng.git"

Build_CT-NG() {
	echo "[*] Building CrossTool-NG . . ."
	ct_ng_git_repo="$1"
	shift
	ct_ng_commit="$1"
	shift
	tc_target="$1"
	PARALLEL_JOBS=$(($(getconf _NPROCESSORS_ONLN 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || echo 0) + 1))
	echo "[-] ct-ng git repo: ${ct_ng_git_repo}"
	echo "[-] ct-ng commit hash: ${ct_ng_commit}"
	echo "[-] compiling with ${PARALLEL_JOBS} parallel jobs"
	echo "[-] toolchain target: ${tc_target}"

	[ ! -d "${BUILD_ROOT}" ] && mkdir -p "${BUILD_ROOT}"
	pushd "${BUILD_ROOT}"
		if [ ! -d CT-NG ]; then
			git clone "${ct_ng_git_repo}" CT-NG
		fi
		pushd CT-NG
			git remote rm origin
			git remote add origin "${ct_ng_git_repo}"
			git fetch origin
			git checkout "${ct_ng_commit}"
			git clean -fxdq
			./bootstrap
			[ ! -d "${BUILD_ROOT}/CT_NG_BUILD" ] && mkdir -p "${BUILD_ROOT}/CT_NG_BUILD"
			./configure --prefix="${BUILD_ROOT}/CT_NG_BUILD"
			make -j${PARALLEL_JOBS}
			make install
			export PATH="${PATH}:${BUILD_ROOT}/CT_NG_BUILD/bin"
		popd
		# extract platform name from target tuple
		tmp_str="${tc_target#*-}"
		TC_BUILD_DIR="${tmp_str%%-*}"
		[ ! -d "${TC_BUILD_DIR}" ] && mkdir -p "${TC_BUILD_DIR}"
		pushd "${TC_BUILD_DIR}"
			ct-ng distclean

			unset CFLAGS CXXFLAGS LDFLAGS
			ct-ng "${tc_target}"
			ct-ng oldconfig
			ct-ng updatetools
			nice ct-ng build
			echo "[INFO ]  ================================================================="
			echo "[INFO ]  Build done. Please add $HOME/x-tools/${tc_target}/bin to your PATH."
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
	nickel
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
		# NOTE: See x-compile.sh for why we're staying away from GCC 8 & 9 for now (TL;DR: neon perf regressions).
		Build_CT-NG \
			https://github.com/NiLuJe/crosstool-ng.git \
			b437f2d5350e255d67bc5e86dc5efc1d9d10eea1 \
			"arm-${1}-linux-gnueabihf"
		;;
	nickel)
		Build_CT-NG \
			https://github.com/NiLuJe/crosstool-ng.git \
			b437f2d5350e255d67bc5e86dc5efc1d9d10eea1 \
			"arm-${1}-linux-gnueabihf"
		;;
	kindlepw2)
		Build_CT-NG \
			https://github.com/NiLuJe/crosstool-ng.git \
			b437f2d5350e255d67bc5e86dc5efc1d9d10eea1 \
			"arm-${1}-linux-gnueabi"
		;;
	kindle5)
		Build_CT-NG \
			https://github.com/NiLuJe/crosstool-ng.git \
			b437f2d5350e255d67bc5e86dc5efc1d9d10eea1 \
			"arm-${1}-linux-gnueabi"
		;;
	kindle)
		# NOTE: Don't swap away from the 1.23-kindle branch,
		#       this TC currently fails to build on 1.24-kindle...
		Build_CT-NG \
			https://github.com/NiLuJe/crosstool-ng.git \
			b437f2d5350e255d67bc5e86dc5efc1d9d10eea1 \
			"arm-${1}-linux-gnueabi"
		;;
	cervantes)
		Build_CT-NG \
			https://github.com/NiLuJe/crosstool-ng.git \
			b437f2d5350e255d67bc5e86dc5efc1d9d10eea1 \
			"arm-${1}-linux-gnueabi"
		;;
	*)
		echo "[!] $1 not supported!"
		echo "${HELP_MSG}"
		exit 1
		;;
esac
