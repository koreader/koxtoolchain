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
DEFAULT_GIT_REPO="https://github.com/crosstool-ng/crosstool-ng.git"

Build_CT-NG() {
	echo "[*] Building CrossTool-NG . . ."
	ct_ng_git_repo=$1
	shift
	ct_ng_commit=$1
	shift
	cfg_path=$1
	PARALLEL_JOBS=$(expr `grep -c ^processor /proc/cpuinfo` + 1)
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
			rm -rf build.log config .config .config.2 .config.old config.gen \
				.build/arm-kindle-linux-gnueabi .build/arm-kindle5-linux-gnueabi \
				.build/arm-kindlepw2-linux-gnueabi .build/arm-kobo-linux-gnueabi \
				.build/src .build/tools .build/tarballs/gcc-linaro-*.tar.xz

			unset CFLAGS CXXFLAGS LDFLAGS
			cp ${cfg_path} .config
			echo "CT_PARALLEL_JOBS=${PARALLEL_JOBS}" >> .config
			ct-ng oldconfig
			# ct-ng menuconfig
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

build_kobo_ct() {
	[ ! -d ${BUILD_ROOT}/downloads ] && mkdir -p ${BUILD_ROOT}/downloads
	CUSTOM_KERNEL_TARBALL=${BUILD_ROOT}/downloads/kobo-linux-2.6.35.3.tar.bz2
	if [ ! -f ${CUSTOM_KERNEL_TARBALL} ]; then
		echo "Fetching kernel source from Kobo github repo..."
		curl -k https://raw.githubusercontent.com/kobolabs/Kobo-Reader/master/hw/imx507-aurah2o/linux-2.6.35.3.tar.bz2 \
			> ${CUSTOM_KERNEL_TARBALL}
	fi
	expected_md5='fc5cc4a95ca363a2a98e726151bc6933'
	checksum=`md5sum ${CUSTOM_KERNEL_TARBALL} | awk '{print $1}'`
	if [ ${checksum} != ${expected_md5} ]; then
		echo "Wrong checksum for kernel source, abort!"
		echo "md5(${CUSTOM_KERNEL_TARBALL}) should be: '${expected_md5}', got: '${checksum}'"
		exit 1
	fi
	[ ! -d ${BUILD_ROOT}/tmp ] && mkdir -p ${BUILD_ROOT}/tmp
	tmp_cfg=${BUILD_ROOT}/tmp/ct-ng-kobo-config
	cp ${CUR_DIR}/configs/ct-ng-kobo-config ${tmp_cfg}
	echo "CT_KERNEL_LINUX_CUSTOM_LOCATION=\"${CUSTOM_KERNEL_TARBALL}\"" >> ${tmp_cfg}
	Build_CT-NG ${DEFAULT_GIT_REPO} crosstool-ng-1.22.0 ${tmp_cfg}
	rm ${tmp_cfg}
}


HELP_MSG="
usage: $0 PLATFORM

Supported platforms:

	kindle
	kobo
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
		build_kobo_ct
		;;
	kindle)
		Build_CT-NG \
			https://github.com/NiLuJe/crosstool-ng.git \
			kindle \
			${CUR_DIR}/configs/ct-ng-kindle-config
		;;
	*)
		echo "[!] $1 not supported!"
		echo "${HELP_MSG}"
		exit 1
		;;
esac
