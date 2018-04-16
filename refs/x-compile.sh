#!/bin/bash -e
#
# Kindle cross toolchain & lib/bin/util build script
#
# $Id: x-compile.sh 14796 2018-04-14 15:22:18Z NiLuJe $
#
# kate: syntax bash;
#
##

## Using CrossTool-NG (http://crosstool-ng.org/)
SVN_ROOT="${HOME}/SVN"
## Remember where we are...
SCRIPTS_BASE_DIR="$(readlink -f "${BASH_SOURCE%/*}")"

# Setup xz multi-threading...
export XZ_DEFAULTS="-T 0"
# Speaking of multi-threading, we're using lbzip2 for tar.bz2 files.
# Note that we cannot use the -u flag (despite its potential advantages),
# because the Kindles bundle a truly abysmally old busybox version, one which
# doesn't handle multi-stream bz2 files, like the ones produces by pbzip2 or
# lbzip2 -u...
# FWIW, that's been supported since busybox 1.17.4, but the Kindles use 1.17.1...
# NOTE: That said, even without the -u switch, past a certain archive size (?!),
# it *still* upsets the Kindle's prehistoric busybox version... So avoid lbzip2
# when creating tarballs that will directly be processed on the device... :/

## Version comparison (req. coreutils 7) [cf. https://stackoverflow.com/questions/4023830]
is_ver_gte()
{
	[ "${1}" = "$(echo -e "${1}\n${2}" | sort -V | tail -n1)" ]
}

## Make the window title useful when running this through tmux...
pkgIndex="0"
update_title_info()
{
	# Get package name from the current directory, because I'm lazy ;)
	pkgName="${PWD##*/}"
	# Increment package counter...
	pkgIndex="$((pkgIndex + 1))"
	# Get number of packages by counting the amount of calls to this very function in the script... Not 100% accurate because of the branching...
	[[ -z ${pkgCount} ]] && pkgCount="$(grep -c '^[[:blank:]]*update_title_info$' "${SCRIPTS_BASE_DIR}/x-compile.sh")"

	# Set the panel name to something short & useful
	myPanelTitle="X-TC ${KINDLE_TC}"
	echo -e '\033k'${myPanelTitle}'\033\\'
	# Set the window title to a longer description of what we're doing...
	myWindowTitle="Building ${pkgName} for ${KINDLE_TC} (${pkgIndex} of ~${pkgCount})"
	echo -e '\033]2;'${myWindowTitle}'\007'
}

## Install/Setup CrossTool-NG
Build_CT-NG() {
	echo "* Building CrossTool-NG . . ."
	echo ""
	cd ${HOME}/Kindle
	mkdir -p CrossTool
	cd CrossTool

	# Remove previous CT-NG install...
	rm -rf bin CT-NG lib share

	mkdir -p CT-NG
	cd CT-NG
	# Pull our own CT-NG branch, which includes a few tweaks needed to support truly old glibc & kernel versions...
	git clone -b 1.23-kindle https://github.com/NiLuJe/crosstool-ng.git .
	# This also often includes the latest Linaro GCC versions...
	# But, more generally,
	# This includes the Make-3.82 patch to Glibc 2.9 too, because it fails to build in softfp with make 3.81... -_-" [Cf. http://lists.gnu.org/archive/html/help-make/2012-02/msg00025.html]
	# Along with glibc patches to make the version checks more relaxed (i.e., imported from the most recent glibc release) and not die on newer make/gcc/binutils...
	# Also backports https://sourceware.org/git/?p=glibc.git;a=commit;h=07037eeb43ca1e0ac2802e3a1492cecf869c63c6 to glibc 2.15, so that it actually builds...
	# And https://sourceware.org/git/?p=glibc.git;a=commit;h=3857022a761ea7251f8e5c0e45d382ebc3e34cf9, too...
	# NOTE: We *can* use glibc 2.16.0 instead of eglibc 2_15 for the KOBO TC, because eglibc is dead, it's not supported in ct-ng anymore, and glibc 2.15 is terrible (besides the aforementioned build fixes needed, there's the mostly unfixable rpc mess to contend with)
	# NOTE: Or, we can use glibc 2.15, patched to the tip of the 2.15 branch (https://sourceware.org/git/?p=glibc.git;a=shortlog;h=refs/heads/release/2.15/master), which includes sunrpc support, plus the eventual needed fixes (https://sourceware.org/git/?p=glibc.git&a=search&h=HEAD&st=commit&s=sunrpc).
	#       Cherry-picked commits:
	#       * https://sourceware.org/git/?p=glibc.git;a=commit;h=3857022a761ea7251f8e5c0e45d382ebc3e34cf9
	#       * https://sourceware.org/git/?p=glibc.git;a=commit;h=07037eeb43ca1e0ac2802e3a1492cecf869c63c6
	#       * https://sourceware.org/git/?p=glibc.git;a=commit;h=07c58f8f3501329340bf3c69a347f7c8fdcbe528
	#       * https://sourceware.org/git/?p=glibc.git;a=commit;h=fb21f89b75d0152aa42efb6b620843799a4cd76b
	# NOTE: Don't forget to backport https://sourceware.org/git/?p=glibc.git;a=commit;h=175cef4163dd60f95106cfd5f593b8a4e09d02c9 in glibc-ports to fix build w/ GCC 5
	# NOTE: We also still currently need to backport https://git.linaro.org/toolchain/gcc.git/commitdiff/a26dad6a5955ed8574efc8d149faca3963a48d46 in Linaro GCC (ISL-0.15 handling for Graphite)...
	# NOTE: The glibc 2.15 stuff currently doesn't apply to the 1.23-kindle branch, since upstream appears to have massaged glibc 2.15 into submission for the 1.23.0 release, which this branch is based on ;).

	# FIXME: Something is very, very wrong with my Linaro 2016.01 builds: everything segfaults on start (in __libc_csu_init).
	# FIXME: Progress! With the 2016.02 & 2016.03 snapshots, as well as the 2016.02 release, it SIGILLs (in _init/call_gmon_start)...
	# FIXME: Building the PW2 TC against glibc 2.19, on the other hand, results in working binaries... WTF?! (5.3 2016.03 snapshot)
	# NOTE: Joy? The issue appears to be fixed in Linaro GCC 5.3 2016.04 snapshot! :)

	./bootstrap
	./configure --prefix=${HOME}/Kindle/CrossTool
	make
	make install
	export PATH="${PATH}:${HOME}/Kindle/CrossTool/bin"

	cd ..
	mkdir -p TC_Kindle
	cd TC_Kindle

	# We need a clean set of *FLAGS, or shit happens...
	unset CFLAGS CXXFLAGS LDFLAGS

	## And then build every TC one after the other...
	for my_tc in kindle kindle5 kindlepw2 kobo ; do
		echo ""
		echo "* Building the ${my_tc} ToolChain . . ."
		echo ""

		# Start by removing the old TC...
		[[ -d "${HOME}/x-tools/_arm-${my_tc}-linux-gnueabi" ]] && chmod -R u+w ${HOME}/x-tools/_arm-${my_tc}-linux-gnueabi && rm -rf ${HOME}/x-tools/_arm-${my_tc}-linux-gnueabi
		# Then backup the current one...
		[[ -d "${HOME}/x-tools/arm-${my_tc}-linux-gnueabi" ]] && mv ${HOME}/x-tools/{,_}arm-${my_tc}-linux-gnueabi

		# Clean the WD manually (clean & distclean are both a little bit too enthusiastic)
		rm -rf build.log config .config.2 .config.old config.gen .build/arm-kindle-linux-gnueabi .build/arm-kindle5-linux-gnueabi .build/arm-kindlepw2-linux-gnueabi .build/arm-kobo-linux-gnueabi .build/src .build/tools

		# Get the current config for this TC...
		cp ${SVN_ROOT}/Configs/trunk/Kindle/Misc/ct-ng-${my_tc}-config .config

		# And fire away!
		ct-ng oldconfig
		#ct-ng menuconfig

		ct-ng updatetools

		nice ct-ng build
	done

	## Config Hints:
	cat << EOF > /dev/null

	CT-NG Config Overview:

	* Paths >
	EXPERIMENTAL: [*]
	Parallel jobs: 3

	* Target >
	Arch: arm
	Use the MMU
	Endianness: Little endian
	Bitness: 32-bit
	Instruction set: arm
	Arch level: armv6j	|	armv7-a
	CPU: arm1136jf-s	|	cortex-a8	|	cortex-a9	# NOTE: Prefer setting CPU instead of Arch & Tune.
	Tune: arm1136jf-s	|	cortex-a8	|	cortex-a9
	FPU: vfp		|	neon or vfpv3
	Floating point: softfp				# NOTE: Can't use hardf anymore, it requires the linux-armhf loader. Amazon never used interwork, and it's not as useful anymore with Thumb2. K5: I'm not sure Amazon defaults to Thumb2, but AFAICT we can use it safely.
	CFLAGS:		# Be very fucking conservative here, so, leave them empty to use the defaults (-O2 -pipe).... And, FWIW, don't use -ffast-math or -Ofast here, '#error "glibc must not be compiled with -ffast-math"' ;).
	LDFLAGS:
	Default instruction set mode:	arm	|	thumb
	Use EABI: [*]

	* TC >
	Tuple's vendor: kindle	|	kindle5		|	kindlepw2

	* OS >
	Target: linux
	Kernel: 2.6.27.62	|	2.6.32.71	|	3.0.101		# [Or use the -lab126 tarball from Kindle Source Code packages, but you'll need to patch it. (sed -e 's/getline/get_line/g' -i scripts/unifdef.c)]

	* Binary >
	Format: ELF
	Binutils: 2.26.1
	Linkers to enable: ld, gold
	Enable threaded gold: [*]
	Add ld wrapper: [*]
	Enable support for plugins: [*]

	* C Compiler >
	Type: gcc
	Linaro: [*]
	Version: linaro-snapshot-5.2-2015.11-2
	Additional Lang: C++
	Link lstdc++ statically
	Disable GRAPHITE	# NOTE: Linaro disables it, apparently lacks a proper maintener since ~2013... cf. https://git.linaro.org/toolchain/abe.git/blob/HEAD:/config/gcc.conf#l20
	Enable LTO
	Opt gcc libs for size [ ]	# -Os is evil?
	Use __cxa_atexit
	<M> sjlj
	<M> 128-bit long doubles
	Linker hash-style: Default	|	gnu

	* C library >
	Type: glibc	# NOTE: K5, PW2 & KOBO actually use eglibc, but that's been dropped from ct-ng, and it's ABI compatible, so we use mainline glibc instead
	Version: 2.9	|	2.12.2	# NOTE: The ports addon for this glibc version has never been released. Gentoo used the one from 2.12.1. I rolled a tarball manually from https://sourceware.org/git/?p=glibc-ports.git;a=shortlog;h=refs/heads/release/2.12/master (except from the 2.12.2 tag, not the branch).
	Threading: nptl
	Minimum supported kernel version: 2.6.22	|	2.6.31		|	3.0.35

EOF
	##

	# NOTE: Be aware that FW 5.6.5 moved to eglibc 2_19 (still softfp, though...). But since we want to keep backwards compatibility, keep using 2.12.2...
	# NOTE: Recap of my adventures in trying to use Linaro's ABE (https://wiki.linaro.org/ABE) to look into the GCC 5.3 issues w/ Linaro 5.3 2016.01/2016.02/2016.03...
	#	For some reason, trying to specify a linux & gmp version is b0rked, and prevents ABE from actually building & installing these components, which obviously breaks everything...
	#	NOTE: An URL pointing to a tarball is NOT supported, so, that at least explains the gmp failure... Using gmp=file:///usr/portage/distfiles/gmp-6.1.0.tar.xz instead should work, on the other hand... but suprise... it doesn't! :/
	#		In fact, file:// support doesn't seem to be implemented at all.. :?
	# ../ABE/abe.sh --target arm-linux-gnueabi --set languages=c,c++,lto --set cpu=cortex-a9 --set libc=eglibc --set linker=ld gcc=gcc.git~linaro/gcc-5-branch eglibc=eglibc.git~eglibc-2_19 binutils=binutils-gdb.git~binutils-2_26-branch gdb=binutils-gdb.git~gdb-7.11-branch linux=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git~linux-3.0.y gmp=https://gmplib.org/download/gmp/gmp-6.1.0.tar.bz2 --build all
	# ... And eglibc_2.19 is borked, too... (https://sourceware.org/ml/libc-alpha/2014-12/msg00105.html). YAY. Let's try w/ glibc instead...
	# ../ABE/abe.sh --target arm-linux-gnueabi --set languages=c,c++,lto --set cpu=cortex-a9 --set libc=glibc --set linker=ld gcc=gcc.git~linaro/gcc-5-branch glibc=glibc.git~release/2.19/master binutils=binutils-gdb.git~binutils-2_26-branch gdb=binutils-gdb.git~gdb-7.11-branch --build all
	# ... And it needs the nptl backports from 2.20 to build on ARM... >_<" (find_exidx.c:(.text+0x36c): undefined reference to `libgcc_s_resume')
	# NOTE: On the other hand, a build against glibc 2.20 works... And the resulting binaries do, too... ARGH -_-".
	#	Although when using --tarbin, it uses a broken default sysroot, for some unfathomable reason... In which case you need to pass --sysroot to GCC, or symlink the sysroot, I guess? cf. https://git.linaro.org/toolchain/abe.git/blob/HEAD:/config/gcc.conf#l170
	# NOTE: This relates to the various issues I encountered with these sets of Linaro snapshots, which were fixed in 2016.04 ;).
}

## Choose your TC!
case ${1} in
	k2 | K2 | k3 | K3 )
		KINDLE_TC="K3"
	;;
	k4 | K4 | k5 | K5 )
		KINDLE_TC="K5"
	;;
	pw2 | PW2 )
		KINDLE_TC="PW2"
	;;
	kobo | Kobo | KOBO )
		KINDLE_TC="KOBO"
	;;
	# Or build them?
	tc )
		Build_CT-NG
		# And exit happy now :)
		exit 0
	;;
	* )
		echo "You must choose a ToolChain! (k3, k5, pw2 or kobo)"
		echo "Or, alternatively, ask to build them (tc)"
		exit 1
	;;
esac

## NOTE: Reminder of the various stuff I had to install on a fresh Gentoo box...
#
# For the packaging scripts:
#	cave resolve -x lbzip2 pigz
#	cave resolve dev-perl/File-MimeInfo -x
#	cave resolve -x kindletool
#	cave resolve -x svn2cl
#	cave resolve -x rar
#	cave resolve p7zip rar python-swiftclient python-keystoneclient
#
# For... something:
#	cave resolve -1 ragel gobject-introspection-common -x
#
# For OpenSSH & co:
#	mkdir -p /mnt/onboard/.niluje/usbnet && mkdir -p /mnt/us/usbnet && chown -cvR niluje:users /mnt/us && chown -cvR niluje:users /mnt/onboard
#
# For Python (set main Python interpreter to 2.7):
#	eselect python set 1
#
# For Python 3rd party modules:
#	cave resolve -x distutilscross
#
# For FC:
#	cave resolve -x dev-python/lxml (for fontconfig)
#
# To fetch everything:
#	cave resolve -1 -z -f -x sys-libs/zlib expat freetype harfbuzz fontconfig coreutils dropbear rsync busybox dev-libs/openssl:0.9.8 dev-libs/openssl:0 openssh ncurses htop lsof protobuf mosh libarchive gmp nettle libpng libjpeg-turbo imagemagick bzip2 dev-libs/libffi sys-libs/readline icu sqlite dev-lang/python:2.7 dev-libs/glib sys-fs/fuse elfutils file nano libpcre zsh mit-krb5 libtirpc xz-utils libevent tmux gdb --uninstalls-may-break '*/*'
#	OR
#	emerge -1 -f sys-libs/zlib expat freetype harfbuzz fontconfig coreutils dropbear rsync busybox dev-libs/openssl:0.9.8 dev-libs/openssl:0 openssh ncurses htop lsof protobuf mosh libarchive gmp nettle libpng libjpeg-turbo imagemagick bzip2 dev-libs/libffi sys-libs/readline icu sqlite dev-lang/python:2.7 dev-libs/glib sys-fs/fuse elfutils file nano libpcre zsh mit-krb5 libtirpc xz-utils libevent tmux gdb
#
##

## Setup our env to use the right TC
echo "* Setting environment up . . ."
echo ""

## Setup parallellization... Shamelessly stolen from crosstool-ng ;).
AUTO_JOBS=$(($(getconf _NPROCESSORS_ONLN 2> /dev/null || echo 0) + 1))
JOBSFLAGS="-j${AUTO_JOBS}"

case ${KINDLE_TC} in
	K3 )
		ARCH_FLAGS="-march=armv6j -mtune=arm1136jf-s -mfpu=vfp -mfloat-abi=softfp"
		CROSS_TC="arm-kindle-linux-gnueabi"
		TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"

		# Export it for our CMakeCross TC file
		export CROSS_TC
		export TC_BUILD_DIR

		export CROSS_PREFIX="${CROSS_TC}-"
		export PATH="${HOME}/x-tools/${CROSS_TC}/bin:${PATH}"

		## NOTE: See http://gcc.gnu.org/gcc-4.7/changes.html & http://comments.gmane.org/gmane.linux.linaro.devel/12115 & http://comments.gmane.org/gmane.linux.ports.arm.kernel/117863
		## But, basically, if you want to build a Kernel, backport https://github.com/mirrors/linux/commit/8428e84d42179c2a00f5f6450866e70d802d1d05 [it's not in FW 2.5.8/3.4/4.1.0/5.1.2],
		## or build your Kernel with -mno-unaligned-access
		## You might also want to backport https://github.com/mirrors/linux/commit/088c01f1e39dbe93a13e0b00f4532ed8b79d35f4 if you intend to roll your own Kernel.
		## For those interested, basically, if your kernel has this: https://github.com/mirrors/linux/commit/baa745a3378046ca1c5477495df6ccbec7690428 then you're safe in userland.
		## (That's the commit merged in 2.6.28 that the GCC docs refer to).
		## It's in FW 3.x/4.x/5.x, so we're good on *some* Kindles. However, it's *NOT* in FW 2.x, and the trap handler defaults to ignoring unaligned access faults.
		## I haven't seen any *actual* issues yet, but the counter does increment...
		## So, to be on the safe side, let's use -mno-unaligned-access on the K3 TC, to avoid going kablooey in weird & interesting ways on FW 2.x... ;)
		## And again, if you roll your own kernel with this TC, this may also be of interest to you: https://bugs.launchpad.net/linaro-toolchain-binaries/+bug/1186218/comments/7
		if is_ver_gte "$(${CROSS_TC}-gcc -dumpversion)" "4.7" ; then
			ARM_NO_UNALIGNED_ACCESS="-mno-unaligned-access"
		fi

		## NOTE: The new libstdc++ ABI might cause some issues if not handled on GCC >= 5.1 (cf. https://gcc.gnu.org/onlinedocs/libstdc++/manual/using_dual_abi.html), so, disable it...
		if is_ver_gte "$(${CROSS_TC}-gcc -dumpversion)" "5.1" ; then
			LEGACY_GLIBCXX_ABI="-D_GLIBCXX_USE_CXX11_ABI=0"
			## NOTE: Like the FORTIFY stuff, this should *really* be in CPPFLAGS, but we have to contend with broken buildsystems that don't honor CPPFLAGS... So we go with the more ubiquitous CFLAGS instead ;/.
		fi

		## NOTE: When linking dynamically, disable GCC 4.3/Glibc 2.8 fortify & stack-smashing protection support to avoid pulling symbols requiring GLIBC_2.8 or GCC_4.3
		BASE_CFLAGS="-O2 -ffast-math ${ARCH_FLAGS} ${ARM_NO_UNALIGNED_ACCESS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin -fno-stack-protector -U_FORTIFY_SOURCE"
		NOLTO_CFLAGS="-O2 -ffast-math ${ARCH_FLAGS} ${ARM_NO_UNALIGNED_ACCESS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -fno-stack-protector -U_FORTIFY_SOURCE"

		## NOTE: And here comes another string of compatibility related tweaks...
		# We don't have mkostemp on Glibc 2.5... ;) (fontconfig)
		export ac_cv_func_mkostemp=no
		# Avoid pulling __isoc99_sscanf@GLIBC_2.7 (dropbear, libjpeg-turbo, fuse, sshfs, zsh)
		BASE_CPPFLAGS="-D_GNU_SOURCE"
		# utimensat's only available since Glibc 2.6, so we can't use it (rsync, libarchive)
		export ac_cv_func_utimensat=no
		# Avoid pulling stuff from glibc 2.6... (libarchive, xz-utils)
		export ac_cv_func_futimens=no
		# Avoid pulling stuff from GLIBC_2.7 & 2.9 (glib, gdb)
		export glib_cv_eventfd=no
		export ac_cv_func_pipe2=no
		# Avoid pulling stuff from GLIBC_2.9, 2.8 & 2.7 (libevent)
		export ac_cv_func_epoll_create1=no
		export ac_cv_func_timerfd_create=no
		export ac_cv_header_sys_timerfd_h=no
		export ac_cv_func_eventfd=no
		export ac_cv_header_sys_eventfd_h=no


		## NOTE: Check if LTO still horribly breaks some stuff...
		## NOTE: See https://gcc.gnu.org/gcc-4.9/changes.html for the notes about building LTO-enabled static libraries... (gcc-ar/gcc-ranlib)
		## NOTE: And see https://gcc.gnu.org/gcc-5/changes.html to rejoice because we don't have to care about broken build-systems with mismatched compile/link time flags anymore :).
		export AR="${CROSS_TC}-gcc-ar"
		export RANLIB="${CROSS_TC}-gcc-ranlib"
		export NM="${CROSS_TC}-gcc-nm"
		## NOTE: Also, BOLO for packages thant link with $(CC) $(LDFLAGS) (ie. without CFLAGS). This is BAD. One (dirty) workaround if you can't fix the package is to append CFLAGS to the end of LDFLAGS... :/
		## NOTE: ... although GCC 5 should handle this in a transparent & sane manner, so, yay :).
		#BASE_CFLAGS="${NOLTO_CFLAGS}"
		export CFLAGS="${BASE_CFLAGS}"
		export CXXFLAGS="${BASE_CFLAGS}"
		# NOTE: Use -isystem instead of -I to make sure GMP doesn't do crazy stuff... (FIXME: -idirafter sounds more correct for our use-case, though...)
		BASE_CPPFLAGS="${BASE_CPPFLAGS} -isystem${TC_BUILD_DIR}/include"
		export CPPFLAGS="${BASE_CPPFLAGS}"
		BASE_LDFLAGS="-L${TC_BUILD_DIR}/lib -Wl,-O1 -Wl,--as-needed"
		# NOTE: Dirty LTO workaround (cf. earlier). All hell might break loose if we tweak CFLAGS for some packages...
		#BASE_LDFLAGS="${BASE_CFLAGS} ${BASE_LDFLAGS}"
		export LDFLAGS="${BASE_LDFLAGS}"

		# NOTE: Use the gold linker
		export CTNG_LD_IS="gold"

		## NOTE: We jump through terrible hoops to counteract libtool's stripping of 'unknown' or 'harmful' FLAGS... (cf. https://www.gnu.org/software/libtool/manual/html_node/Stripped-link-flags.html)
		## That's a questionable behavior that is bound to screw up LTO in fun and interesting ways, at the very least on the performance aspect of things...
		## Store those in the right format here, and apply patches or tricks to anything using libtool, because of course it's a syntax that gcc doesn't know about, so we can't simply put it in the global LDFLAGS.... -_-".
		## And since autotools being autotools, it's used in various completely idiosyncratic ways, we can't always rely on simply overriding AM_LDFLAGS...
		## NOTE: Hopefully, GCC 5's smarter LTO handling means we don't have to care about that anymore... :).
		export XC_LINKTOOL_CFLAGS="-Wc,-ffast-math -Wc,-fomit-frame-pointer -Wc,-frename-registers -Wc,-fweb"

		BASE_HACKDIR="${SVN_ROOT}/Configs/trunk/Kindle/Hacks"

		BASE_PKG_CONFIG_PATH="${TC_BUILD_DIR}/lib/pkgconfig"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_DIR=
		export PKG_CONFIG_PATH="${BASE_PKG_CONFIG_PATH}"
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"

		DEVICE_USERSTORE="/mnt/us"
	;;
	K5 )
		ARCH_FLAGS="-march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=softfp -mthumb"
		CROSS_TC="arm-kindle5-linux-gnueabi"
		TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"

		# Export it for our CMakeCross TC file
		export CROSS_TC
		export TC_BUILD_DIR

		export CROSS_PREFIX="${CROSS_TC}-"
		export PATH="${HOME}/x-tools/${CROSS_TC}/bin:${PATH}"

		## NOTE: The new libstdc++ ABI might cause some issues if not handled on GCC >= 5.1 (cf. https://gcc.gnu.org/onlinedocs/libstdc++/manual/using_dual_abi.html), so, disable it...
		if is_ver_gte "$(${CROSS_TC}-gcc -dumpversion)" "5.1" ; then
			LEGACY_GLIBCXX_ABI="-D_GLIBCXX_USE_CXX11_ABI=0"
			## NOTE: Like the FORTIFY stuff, this should *really* be in CPPFLAGS, but we have to contend with broken buildsystems that don't honor CPPFLAGS... So we go with the more ubiquitous CFLAGS instead ;/.
		fi

		BASE_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin"
		NOLTO_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb"
		## NOTE: Check if LTO still horribly breaks some stuff...
		## NOTE: See https://gcc.gnu.org/gcc-4.9/changes.html for the notes about building LTO-enabled static libraries... (gcc-ar/gcc-ranlib)
		## NOTE: And see https://gcc.gnu.org/gcc-5/changes.html to rejoice because we don't have to care about broken build-systems with mismatched compile/link time flags anymore :).
		export AR="${CROSS_TC}-gcc-ar"
		export RANLIB="${CROSS_TC}-gcc-ranlib"
		export NM="${CROSS_TC}-gcc-nm"
		## NOTE: Also, BOLO for packages thant link with $(CC) $(LDFLAGS) (ie. without CFLAGS). This is BAD. One (dirty) workaround if you can't fix the package is to append CFLAGS to the end of LDFLAGS... :/
		## NOTE: ... although GCC 5 should handle this in a transparent & sane manner, so, yay :).
		#BASE_CFLAGS="${NOLTO_CFLAGS}"
		export CFLAGS="${BASE_CFLAGS}"
		export CXXFLAGS="${BASE_CFLAGS}"
		# NOTE: Use -isystem instead of -I to make sure GMP doesn't do crazy stuff... (FIXME: -idirafter sounds more correct for our use-case, though...)
		BASE_CPPFLAGS="-isystem${TC_BUILD_DIR}/include"
		export CPPFLAGS="${BASE_CPPFLAGS}"
		BASE_LDFLAGS="-L${TC_BUILD_DIR}/lib -Wl,-O1 -Wl,--as-needed"
		# NOTE: Dirty LTO workaround (cf. earlier). All hell might break loose if we tweak CFLAGS for some packages...
		#BASE_LDFLAGS="${BASE_CFLAGS} ${BASE_LDFLAGS}"
		export LDFLAGS="${BASE_LDFLAGS}"

		# NOTE: Use the gold linker
		export CTNG_LD_IS="gold"

		## NOTE: We jump through terrible hoops to counteract libtool's stripping of 'unknown' or 'harmful' FLAGS... (cf. https://www.gnu.org/software/libtool/manual/html_node/Stripped-link-flags.html)
		## That's a questionable behavior that is bound to screw up LTO in fun and interesting ways, at the very least on the performance aspect of things...
		## Store those in the right format here, and apply patches or tricks to anything using libtool, because of course it's a syntax that gcc doesn't know about, so we can't simply put it in the global LDFLAGS.... -_-".
		## And since autotools being autotools, it's used in various completely idiosyncratic ways, we can't always rely on simply overriding AM_LDFLAGS...
		## NOTE: Hopefully, GCC 5's smarter LTO handling means we don't have to care about that anymore... :).
		export XC_LINKTOOL_CFLAGS="-Wc,-ffast-math -Wc,-fomit-frame-pointer -Wc,-frename-registers -Wc,-fweb"

		BASE_HACKDIR="${SVN_ROOT}/Configs/trunk/Kindle/Touch_Hacks"

		BASE_PKG_CONFIG_PATH="${TC_BUILD_DIR}/lib/pkgconfig"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_DIR=
		export PKG_CONFIG_PATH="${BASE_PKG_CONFIG_PATH}"
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"

		DEVICE_USERSTORE="/mnt/us"
	;;
	PW2 )
		ARCH_FLAGS="-march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=softfp -mthumb"
		CROSS_TC="arm-kindlepw2-linux-gnueabi"
		TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"

		# Export it for our CMakeCross TC file
		export CROSS_TC
		export TC_BUILD_DIR

		export CROSS_PREFIX="${CROSS_TC}-"
		export PATH="${HOME}/x-tools/${CROSS_TC}/bin:${PATH}"

		## NOTE: The new libstdc++ ABI might cause some issues if not handled on GCC >= 5.1 (cf. https://gcc.gnu.org/onlinedocs/libstdc++/manual/using_dual_abi.html), so, disable it...
		if is_ver_gte "$(${CROSS_TC}-gcc -dumpversion)" "5.1" ; then
			LEGACY_GLIBCXX_ABI="-D_GLIBCXX_USE_CXX11_ABI=0"
			## NOTE: Like the FORTIFY stuff, this should *really* be in CPPFLAGS, but we have to contend with broken buildsystems that don't honor CPPFLAGS... So we go with the more ubiquitous CFLAGS instead ;/.
		fi

		BASE_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin"
		NOLTO_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb"

		## FIXME: Crazy compat flags if the TC has been built against glibc 2.19...
		##	Why would we do that? Because since FW 5.6.5, that's actually the glibc version used, and, more importantly,
		##	it was part of an experiment: with the apparently broken Linaro 5.3 snapshots from 2016.01 to 2016.3, a TC built against glibc 2.19 would work, instead of silently generating broken code...
		## NOTE: The root issue was fixed in Linaro 5.3 2016.04, which makes that whole experiment an archeological relic ;).
		if [[ -f "${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/lib/libc-2.19.so" ]] ; then
			echo "!!"
			echo "!! ENABLING GLIBC 2.19 -> GLIBC 2.12 COMPAT FLAGS! !!"
			echo "!!"
			# __<math>_finite@GLIBC_2.15 on ScreenSavers/src/linkss/lib/libpng16.so.16 & ScreenSavers/src/linkss/bin/convert & USBNetwork/src/usbnet/bin/htop
			BASE_CFLAGS="${BASE_CFLAGS} -fno-finite-math-only"
			NOLTO_CFLAGS="${NOLTO_CFLAGS} -fno-finite-math-only"
			# getauxval@GLIBC_2.16 on USBNetwork/src/usbnet/lib/libcrypto.so.1.0.0
			KINDLE_TC_IS_GLIBC_219="true"
			# __fdelt_chk@GLIBC_2.15 on USBNetwork/src/usbnet/bin/mosh-* & OpenSSH
			# __poll_chk@GLIBC_2.16 on OpenSSH
			# NOTE: Requires killing FORTIFY_SOURCE... We do it on site w/ a KINDLE_TC_IS_GLIBC_219 check.
			# FIXME: Don't forget to kill those stray checks if I ever get rid of this monstrosity...
			# clock_gettime@GLIBC_2.17 on USBNetwork/src/usbnet/bin/mosh-* & OpenSSH & USBNetwork/src/usbnet/bin/sshfs
			# NOTE: This one is particular in that the function existed, it was just in librt instead of libc ;).
			export ac_cv_search_clock_gettime="-lrt"
			# setns@GLIBC_2.14 on GDB
			export ac_cv_func_setns="no"
		fi

		## NOTE: Check if LTO still horribly breaks some stuff...
		## NOTE: See https://gcc.gnu.org/gcc-4.9/changes.html for the notes about building LTO-enabled static libraries... (gcc-ar/gcc-ranlib)
		## NOTE: And see https://gcc.gnu.org/gcc-5/changes.html to rejoice because we don't have to care about broken build-systems with mismatched compile/link time flags anymore :).
		export AR="${CROSS_TC}-gcc-ar"
		export RANLIB="${CROSS_TC}-gcc-ranlib"
		export NM="${CROSS_TC}-gcc-nm"
		## NOTE: Also, BOLO for packages thant link with $(CC) $(LDFLAGS) (ie. without CFLAGS). This is BAD. One (dirty) workaround if you can't fix the package is to append CFLAGS to the end of LDFLAGS... :/
		## NOTE: ... although GCC 5 should handle this in a transparent & sane manner, so, yay :).
		#BASE_CFLAGS="${NOLTO_CFLAGS}"
		export CFLAGS="${BASE_CFLAGS}"
		export CXXFLAGS="${BASE_CFLAGS}"
		# NOTE: Use -isystem instead of -I to make sure GMP doesn't do crazy stuff... (FIXME: -idirafter sounds more correct for our use-case, though...)
		BASE_CPPFLAGS="-isystem${TC_BUILD_DIR}/include"
		export CPPFLAGS="${BASE_CPPFLAGS}"
		BASE_LDFLAGS="-L${TC_BUILD_DIR}/lib -Wl,-O1 -Wl,--as-needed"
		# NOTE: Dirty LTO workaround (cf. earlier). All hell might break loose if we tweak CFLAGS for some packages...
		#BASE_LDFLAGS="${BASE_CFLAGS} ${BASE_LDFLAGS}"
		export LDFLAGS="${BASE_LDFLAGS}"

		# NOTE: Use the gold linker
		export CTNG_LD_IS="gold"

		## NOTE: We jump through terrible hoops to counteract libtool's stripping of 'unknown' or 'harmful' FLAGS... (cf. https://www.gnu.org/software/libtool/manual/html_node/Stripped-link-flags.html)
		## That's a questionable behavior that is bound to screw up LTO in fun and interesting ways, at the very least on the performance aspect of things...
		## Store those in the right format here, and apply patches or tricks to anything using libtool, because of course it's a syntax that gcc doesn't know about, so we can't simply put it in the global LDFLAGS.... -_-".
		## And since autotools being autotools, it's used in various completely idiosyncratic ways, we can't always rely on simply overriding AM_LDFLAGS...
		## NOTE: Hopefully, GCC 5's smarter LTO handling means we don't have to care about that anymore... :).
		export XC_LINKTOOL_CFLAGS="-Wc,-ffast-math -Wc,-fomit-frame-pointer -Wc,-frename-registers -Wc,-fweb"

		BASE_HACKDIR="${SVN_ROOT}/Configs/trunk/Kindle/PW2_Hacks"

		BASE_PKG_CONFIG_PATH="${TC_BUILD_DIR}/lib/pkgconfig"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_DIR=
		export PKG_CONFIG_PATH="${BASE_PKG_CONFIG_PATH}"
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"

		DEVICE_USERSTORE="/mnt/us"
	;;
	KOBO )
		ARCH_FLAGS="-march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -mthumb"
		CROSS_TC="arm-kobo-linux-gnueabi"
		TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"

		# Export it for our CMakeCross TC file
		export CROSS_TC
		export TC_BUILD_DIR

		export CROSS_PREFIX="${CROSS_TC}-"
		export PATH="${HOME}/x-tools/${CROSS_TC}/bin:${PATH}"

		## NOTE: The new libstdc++ ABI might cause some issues if not handled on GCC >= 5.1 (cf. https://gcc.gnu.org/onlinedocs/libstdc++/manual/using_dual_abi.html), so, disable it...
		if is_ver_gte "$(${CROSS_TC}-gcc -dumpversion)" "5.1" ; then
			LEGACY_GLIBCXX_ABI="-D_GLIBCXX_USE_CXX11_ABI=0"
			## NOTE: Like the FORTIFY stuff, this should *really* be in CPPFLAGS, but we have to contend with broken buildsystems that don't honor CPPFLAGS... So we go with the more ubiquitous CFLAGS instead ;/.
		fi

		BASE_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin"
		NOLTO_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb"
		## NOTE: Check if LTO still horribly breaks some stuff...
		## NOTE: See https://gcc.gnu.org/gcc-4.9/changes.html for the notes about building LTO-enabled static libraries... (gcc-ar/gcc-ranlib)
		## NOTE: And see https://gcc.gnu.org/gcc-5/changes.html to rejoice because we don't have to care about broken build-systems with mismatched compile/link time flags anymore :).
		export AR="${CROSS_TC}-gcc-ar"
		export RANLIB="${CROSS_TC}-gcc-ranlib"
		export NM="${CROSS_TC}-gcc-nm"
		## NOTE: Also, BOLO for packages thant link with $(CC) $(LDFLAGS) (ie. without CFLAGS). This is BAD. One (dirty) workaround if you can't fix the package is to append CFLAGS to the end of LDFLAGS... :/
		## NOTE: ... although GCC 5 should handle this in a transparent & sane manner, so, yay :).
		#BASE_CFLAGS="${NOLTO_CFLAGS}"
		export CFLAGS="${BASE_CFLAGS}"
		export CXXFLAGS="${BASE_CFLAGS}"
		# NOTE: Use -isystem instead of -I to make sure GMP doesn't do crazy stuff... (FIXME: -idirafter sounds more correct for our use-case, though...)
		BASE_CPPFLAGS="-isystem${TC_BUILD_DIR}/include"
		export CPPFLAGS="${BASE_CPPFLAGS}"
		BASE_LDFLAGS="-L${TC_BUILD_DIR}/lib -Wl,-O1 -Wl,--as-needed"
		# NOTE: Dirty LTO workaround (cf. earlier). All hell might break loose if we tweak CFLAGS for some packages...
		#BASE_LDFLAGS="${BASE_CFLAGS} ${BASE_LDFLAGS}"
		export LDFLAGS="${BASE_LDFLAGS}"

		# NOTE: Use the gold linker
		export CTNG_LD_IS="gold"

		## NOTE: We jump through terrible hoops to counteract libtool's stripping of 'unknown' or 'harmful' FLAGS... (cf. https://www.gnu.org/software/libtool/manual/html_node/Stripped-link-flags.html)
		## That's a questionable behavior that is bound to screw up LTO in fun and interesting ways, at the very least on the performance aspect of things...
		## Store those in the right format here, and apply patches or tricks to anything using libtool, because of course it's a syntax that gcc doesn't know about, so we can't simply put it in the global LDFLAGS.... -_-".
		## And since autotools being autotools, it's used in various completely idiosyncratic ways, we can't always rely on simply overriding AM_LDFLAGS...
		## NOTE: Hopefully, GCC 5's smarter LTO handling means we don't have to care about that anymore... :).
		export XC_LINKTOOL_CFLAGS="-Wc,-ffast-math -Wc,-fomit-frame-pointer -Wc,-frename-registers -Wc,-fweb"

		BASE_HACKDIR="${SVN_ROOT}/Configs/trunk/Kindle/Kobo_Hacks"

		BASE_PKG_CONFIG_PATH="${TC_BUILD_DIR}/lib/pkgconfig"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_DIR=
		export PKG_CONFIG_PATH="${BASE_PKG_CONFIG_PATH}"
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"

		# Kobos are finnicky as hell, so take some more precautions...
		# On the vfat partition, don't use the .kobo folder, since it might go poof with no warning in case of troubles...
		DEVICE_ONBOARD_USERSTORE="/mnt/onboard/.niluje"
		# And we'll let dropbear live in the internal memory to avoid any potential interaction with USBMS...
		DEVICE_INTERNAL_USERSTORE="/usr/local/niluje"
		DEVICE_USERSTORE="${DEVICE_ONBOARD_USERSTORE}"
	;;
	* )
		echo "Unknown TC: ${KINDLE_TC} !"
		exit 1
	;;
esac

## NOTE: Some misc autotools hacks for undetectable stuff when cross-compiling...
# Of course mmap() is sane...
# NOTE: FT depends on this for platform-specific I/O & memory code. In particular, that means CLOEXEC handling. Check that this doesn't backfires on the K2? where the kernel is probably too old to support CLOEXEC...
export ac_cv_func_mmap_fixed_mapped=yes

## Quick'n dirty env setup only handling... Don't forget to *source* this script (and not simply run it) when using this feature ;).
if [[ "${2}" == "env" ]] ; then
	# We just want the env setup for this TC... :)
	echo "* Environment has been set up for the ${KINDLE_TC} TC, enjoy :)"

	# Handle some KOReader specifics...
	if [[ "${3}" == "ko" ]] ; then
		echo "* Enabling KOReader quirks :)"
		# The Makefile gets the TC's triplet from CHOST
		export CHOST="${CROSS_TC}"
		# We don't want to pull any of our own libs through pkg-config
		unset PKG_CONFIG_DIR
		unset PKG_CONFIG_PATH
		unset PKG_CONFIG_LIBDIR
		# We also don't want to look at or pick up our own custom sysroot, for fear of an API/ABI mismatch somewhere...
		export CPPFLAGS="${CPPFLAGS/-isystem${TC_BUILD_DIR}\/include/}"
		export LDFLAGS="${LDFLAGS/-L${TC_BUILD_DIR}\/lib /}"
		# NOTE: Play it safe, and disable LTO. Using it properly would need more invasive buildsystem tweaks.
		BASE_CFLAGS="${NOLTO_CFLAGS}"
		export CFLAGS="${BASE_CFLAGS}"
		export CXXFLAGS="${BASE_CFLAGS}"
		# NOTE: In the same vein, disable gold too...
		unset CTNG_LD_IS
		# NOTE: And we want to link to libstdc++ statically...
		export LDFLAGS="${LDFLAGS} -static-libstdc++"

		# FIXME: Go back to GCC 4.9 for now, as CRe mysteriously breaks when built w/ Linaro GCC 5.2 2015.11-2...
		#export PATH="${PATH/${CROSS_TC}/gcc49_${CROSS_TC}}"
		# FIXME: Oh, joy. It also segfaults w/ Linaro GCC 4.9 2016.02...
	fi

	# And return happy now :)
	return 0

fi

## Get to our build dir
mkdir -p "${TC_BUILD_DIR}"
cd "${TC_BUILD_DIR}"

## And start building stuff!

## FT & FC for Fonts
echo "* Building zlib . . ."
echo ""
ZLIB_SOVER="1.2.11"
tar -I pigz -xvf /usr/portage/distfiles/zlib-1.2.11.tar.gz
cd zlib-1.2.11
update_title_info
# On ARMv7, apply a few patches w/ hand-crafted SIMD ASM (from https://github.com/kaffeemonster/zlib & https://bugzilla.mozilla.org/show_bug.cgi?id=462796)
#if [[ "${KINDLE_TC}" != "K3" ]] ; then
#	# NOTE: So far, results on the workflows I care about (fbgrab & ImageMagick) are mostly inexistant in terms of performance gain, so...
#	#       Not really feeling heartbroken at them not having landed upstream in nearly 3 years...
#	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/zlib-1.2.8-simd.patch
#fi
./configure --shared --prefix=${TC_BUILD_DIR}
make ${JOBSFLAGS}
make install
sed -i -r 's:\<(O[FN])\>:_Z_\1:g' ${TC_BUILD_DIR}/include/z*.h
# Install the shared libs for USBNet & ScreenSavers
cp ../lib/libz.so.${ZLIB_SOVER} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libz.so.${ZLIB_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libz.so.${ZLIB_SOVER%%.*}
cp ../lib/libz.so.${ZLIB_SOVER} ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libz.so.${ZLIB_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libz.so.${ZLIB_SOVER%%.*}
# And also for MRInstaller...
if [[ "${KINDLE_TC}" != "KOBO" ]] ; then
	cp ../lib/libz.so.${ZLIB_SOVER} ${BASE_HACKDIR}/../KUAL/MRInstaller/extensions/MRInstaller/lib/${KINDLE_TC}/libz.so.${ZLIB_SOVER%%.*}
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/../KUAL/MRInstaller/extensions/MRInstaller/lib/${KINDLE_TC}/libz.so.${ZLIB_SOVER%%.*}
fi

echo "* Building expat . . ."
echo ""
cd ..
EXPAT_SOVER="1.6.2"
tar -I lbzip2 -xvf /usr/portage/distfiles/expat-2.2.0.tar.bz2
cd expat-2.2.0
patch -p2 < /usr/portage/dev-libs/expat/files/expat-2.1.1-CVE-2016-0718-regression.patch
update_title_info
# Fix Makefile for LTO...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/expat-fix-Makefile-for-lto.patch
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes
make ${JOBSFLAGS}
make install

## NOTE: This is called from a function because we need to do two sets of builds in the same TC run to handle a weird, but critical issue with GCC 5 on the K4...
Build_FreeType_Stack() {
	## HarfBuzz for FT's authinter
	# Funnily enough, it depends on freetype too...
	FT_VER="2.7_p20161001"
	FT_SOVER="6.12.6"
	echo "* Building freetype (for harfbuzz) . . ."
	echo ""
	cd ..
	rm -rf freetype2 freetype2-demos
	tar -xvJf /usr/portage/distfiles/freetype-${FT_VER}.tar.xz
	cd freetype2
	update_title_info
	# Fix Makefile for LTO...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-fix-Makefile-for-lto.patch
	## minimal
	sh autogen.sh
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-bzip2 --without-harfbuzz --without-png
	make ${JOBSFLAGS}
	make install

	echo "* Building harfbuzz . . ."
	echo ""
	cd ..
	rm -rf harfbuzz
	HB_SOVER="0.10302.0"
	tar -xvJf /usr/portage/distfiles/harfbuzz-1.3.2_p20161004.tar.xz
	cd harfbuzz
	update_title_info
	env NOCONFIGURE="true" sh autogen.sh
	# Make sure libtool doesn't eat any our of our CFLAGS when linking...
	export AM_LDFLAGS="${XC_LINKTOOL_CFLAGS}"
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-coretext --without-uniscribe --without-cairo --without-glib --without-gobject --without-graphite2 --without-icu --disable-introspection --with-freetype
	make ${JOBSFLAGS} V=1
	make install
	unset AM_LDFLAGS
	# Install the shared version, to avoid the circular dep FT -> HB -> FT...
	cp ../lib/libharfbuzz.so.${HB_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libharfbuzz.so.${HB_SOVER%%.*}
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libharfbuzz.so.${HB_SOVER%%.*}
	# We also need it for the K5 ScreenSavers hack, because the pinfo support relies on it, and Amazon's FT build is evil (it segfaults since FW 5.6.1)...
	if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] ; then
		cp ../lib/libharfbuzz.so.${HB_SOVER} ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libharfbuzz.so.${HB_SOVER%%.*}
		${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libharfbuzz.so.${HB_SOVER%%.*}
	fi

	## FIXME: Should we link against a static libz for perf/stability? (So far, no issues, and no symbol versioning mishap either, but then again, it's only used for compressed PCF font AFAIR).
	echo "* Building freetype . . ."
	echo ""
	# Add an rpath to find libharfbuzz (look in /var/local first for the K5 family...). Keep the screensavers hack in there, too, IM relies on us...
	export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=/var/local/linkfonts/lib -Wl,-rpath=${DEVICE_USERSTORE}/linkfonts/lib -Wl,-rpath=${DEVICE_USERSTORE}/linkss/lib"
	## Autohint
	cd ..
	rm -rf freetype2
	tar -xvJf /usr/portage/distfiles/freetype-${FT_VER}.tar.xz
	cd freetype2
	update_title_info
	# Fix Makefile for LTO...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-fix-Makefile-for-lto.patch
	## Always force autohinter (Like on the K2)
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-2.4.9-kindle-force-autohint.patch
	#patch -p1 < /usr/portage/media-libs/freetype/files/freetype-2.7-enable-valid.patch
	## NOTE: Let's try to break everything! AA to 16 shades of grey intead of 256. Completely destroys the rendering on my box, doesn't seem to have any effect on my K5 :?.
	#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-kindle-num_grays-16.patch
	sh autogen.sh
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-bzip2 --with-harfbuzz --without-png
	make ${JOBSFLAGS}
	make install
	cp ../lib/libfreetype.so.${FT_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/autohint/libfreetype.so
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/autohint/libfreetype.so
	## Light
	cd ..
	rm -rf freetype2
	tar -xvJf /usr/portage/distfiles/freetype-${FT_VER}.tar.xz
	cd freetype2
	# Fix Makefile for LTO...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-fix-Makefile-for-lto.patch
	## Always force light grey hinting (light hinting implicitly forces autohint) unless we asked for monochrome rendering (ie. in some popups & address bars, if we don't take this into account, these all render garbled glyphs)
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-2.4.9-kindle-force-light.patch
	## Let's try the experimental autofit warper too, since it's only enabled with LIGHT :)
	sed -e 's/module->warping           = 0;/module->warping           = 1;/' -i src/autofit/afmodule.c
	#patch -p1 < /usr/portage/media-libs/freetype/files/freetype-2.7-enable-valid.patch
	#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-kindle-num_grays-16.patch
	sh autogen.sh
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-bzip2 --with-harfbuzz --without-png
	make ${JOBSFLAGS}
	make install
	cp ../lib/libfreetype.so.${FT_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/light/libfreetype.so
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/light/libfreetype.so
	## SPR
	cd ..
	rm -rf freetype2
	tar -xvJf /usr/portage/distfiles/freetype-${FT_VER}.tar.xz
	cd freetype2
	# Fix Makefile for LTO...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-fix-Makefile-for-lto.patch
	## Always force grey hinting (bci implicitly takes precedence over autohint)
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-2.4.9-kindle-force-bci.patch
	#patch -p1 < /usr/portage/media-libs/freetype/files/freetype-2.7-enable-valid.patch
	#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-kindle-num_grays-16.patch
	## Enable the v38 native hinter...
	sed -e "/#define FT_CONFIG_OPTION_SUBPIXEL_RENDERING/a #define FT_CONFIG_OPTION_SUBPIXEL_RENDERING" -i include/freetype/config/ftoption.h
	# NOTE: cf. http://git.savannah.gnu.org/cgit/freetype/freetype2.git/commit/?id=596157365aeff6bb842fe741f8cf322890a952fe
	#	The original default value for TT_CONFIG_OPTION_SUBPIXEL_HINTING suits us just fine :)
	sed -i -e "/^#define TT_CONFIG_OPTION_SUBPIXEL_HINTING[[:blank:]]*/ { s:^:/* :; s:$: */: }" include/freetype/config/ftoption.h
	sed -i -e "/#define TT_CONFIG_OPTION_SUBPIXEL_HINTING[[:blank:]]*2/a #define TT_CONFIG_OPTION_SUBPIXEL_HINTING 2" include/freetype/config/ftoption.h
	## Haha. LCD filter. Hahahahahaha.
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-2.6.2-spr-fir-filter-weight-to-gibson-coeff.patch
	sh autogen.sh
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-bzip2 --with-harfbuzz --without-png
	make ${JOBSFLAGS}
	make install
	cp ../lib/libfreetype.so.${FT_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/spr/libfreetype.so
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/spr/libfreetype.so
	## BCI
	cd ..
	rm -rf freetype2
	tar -xvJf /usr/portage/distfiles/freetype-${FT_VER}.tar.xz
	cd freetype2
	# Fix Makefile for LTO...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-fix-Makefile-for-lto.patch
	## Always force grey hinting (bci implicitly takes precedence over autohint)
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-2.4.9-kindle-force-bci.patch
	#patch -p1 < /usr/portage/media-libs/freetype/files/freetype-2.7-enable-valid.patch
	#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-kindle-num_grays-16.patch
	sh autogen.sh
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-bzip2 --with-harfbuzz --without-png
	make ${JOBSFLAGS}
	make install
	cp ../lib/libfreetype.so.${FT_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/bci/libfreetype.so
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/bci/libfreetype.so
	# As with harfbuzz, we need it for the K5 ScreenSavers hack, because the pinfo support relies on it, and Amazon's FT build is evil (it segfaults since FW 5.6.1)...
	if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] ; then
		cp ../lib/libfreetype.so.${FT_SOVER} ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libfreetype.so.${FT_SOVER%%.*}
		${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libfreetype.so.${FT_SOVER%%.*}
	fi
	# fc-scan will also need it in the Fonts hack...
	cp ../lib/libfreetype.so.${FT_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libfreetype.so.${FT_SOVER%%.*}
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libfreetype.so.${FT_SOVER%%.*}

	## Build ftbench
	echo "* Building ftbench . . ."
	echo ""
	cd ..
	cd freetype2-demos
	# Fix Makefile for LTO...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-demos-fix-Makefile-for-lto.patch
	## We only care about ftbench
	sed -e 's/  EXES := ftbench \\/  EXES := ftbench/' -i Makefile
	sed -e 's/          ftdump  \\/#          ftdump  \\/' -i Makefile
	sed -e 's/          ftlint/#          ftlint/' -i Makefile
	sed -e 's/  EXES += ftdiff   \\/#  EXES += ftdiff   \\/' -i Makefile
	sed -e 's/          ftgamma  \\/#          ftgamma  \\/' -i Makefile
	sed -e 's/          ftgrid   \\/#          ftgrid   \\/' -i Makefile
	sed -e 's/          ftmulti  \\/#          ftmulti  \\/' -i Makefile
	sed -e 's/          ftstring \\/#          ftstring \\/' -i Makefile
	sed -e 's/          ftview/#          ftview/' -i Makefile
	make ${JOBSFLAGS}
	${CROSS_TC}-strip --strip-unneeded bin/.libs/ftbench
	cp bin/.libs/ftbench ftbench
	export LDFLAGS="${BASE_LDFLAGS}"
}

## FIXME: Apparently, when using an FT override built with GCC 5 (at least Linaro 5.2 2015.09), the framework will crash and fail to start on legacy devices (<= K4), which is bad.
##        To avoid breaking stuff, use an older GCC 4.9 (Linaro 2015.06) TC, at least for the K3 & K5 builds.
##        AFAICT, it appears to work fine on anything running FW 5.x, though (even a Kindle Touch), so don't do anything special with the PW2 builds.
if [[ "${KINDLE_TC}" == "K3" ]] || [[ "${KINDLE_TC}" == "K5" ]] ; then
	temp_nogcc5="true"
	export PATH="${PATH/${CROSS_TC}/gcc49_${CROSS_TC}}"
fi

## NOTE: Since the issue doesn't appear to affect FW 5.x, we'll do two sets of build for the K5 TC: One with GCC 4.9 for the K4, and one with the current TC for everything else.
##       We start with the K4 binaries, in order to leave consistent stuff (TC-wise) in our WD...
if [[ "${temp_nogcc5}" == "true" ]] && [[ "${KINDLE_TC}" == "K5" ]] ; then
	# We want the binaries to go in a different target directory, of course ;).
	BASE_HACKDIR="${BASE_HACKDIR/Touch_Hacks/K4_Hacks}"
fi

# De eeeeet!
Build_FreeType_Stack

## NOTE: Reset to our up to date toolchain, if need be.
if [[ "${temp_nogcc5}" == "true" ]] ; then
	unset temp_nogcc5
	export PATH="${PATH/gcc49_${CROSS_TC}/${CROSS_TC}}"

	## And for the K5 TC, do a second, proper build :).
	if [[ "${KINDLE_TC}" == "K5" ]] ; then
		BASE_HACKDIR="${BASE_HACKDIR/K4_Hacks/Touch_Hacks}"
		Build_FreeType_Stack
	fi
fi

## Build FC
echo "* Building fontconfig . . ."
echo ""
FC_SOVER="1.9.2"
FC_VER="2.12.1_p20160911"
cd ..
tar -xvJf /usr/portage/distfiles/fontconfig-${FC_VER}.tar.xz
cd fontconfig
update_title_info
# Fix Makefile for LTO...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/fontconfig-fix-Makefile-for-lto.patch
patch -p1 < /usr/portage/media-libs/fontconfig/files/fontconfig-2.11.93-latin-update.patch
patch -p1 < /usr/portage/media-libs/fontconfig/files/fontconfig-2.10.2-docbook.patch
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/fontconfig-2.10.0-do-not-deprecate-dotfile.patch
# NOTE: Pick-up our own expat via rpath, we're using expat 2.1.0, the Kindle is using 2.0.0 (and it's not in the tree anymore). Same from FT & HB.
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/linkfonts/lib"
sh autogen.sh --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=no --disable-docs --disable-docbook --localstatedir=/var --with-templatedir=/etc/fonts/conf.avail --with-baseconfigdir=/etc/fonts --with-xmldir=/etc/fonts --with-arch=arm --with-expat=${TC_BUILD_DIR}
make ${JOBSFLAGS} V=1
make install-exec
make install-pkgconfigDATA
cp ../lib/libfontconfig.so.${FC_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libfontconfig.so.${FC_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libfontconfig.so.${FC_SOVER%%.*}
cp ../lib/libexpat.so.${EXPAT_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libexpat.so.${EXPAT_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libexpat.so.${EXPAT_SOVER%%.*}
cp ../lib/libz.so.${ZLIB_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libz.so.${ZLIB_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libz.so.${ZLIB_SOVER%%.*}
## FIXME: Keep a copy of the shared version, to check if it behaves...
cp ../bin/fc-scan ${BASE_HACKDIR}/Fonts/src/linkfonts/bin/shared_fc-scan
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/bin/shared_fc-scan

## FIXME: And then build it statically (at least as far as libfontconfig is concerned) for fc-scan,
## because for some unknown and baffling reason, linking it dynamically leaves us with a binary that loops forever,
## which horribly breaks the boot on legacy devices when the KF8 support is enabled in the fonts hack...
cd ..
rm -rf fontconfig
tar -xvJf /usr/portage/distfiles/fontconfig-${FC_VER}.tar.xz
cd fontconfig
update_title_info
# Fix Makefile for LTO...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/fontconfig-fix-Makefile-for-lto.patch
patch -p1 < /usr/portage/media-libs/fontconfig/files/fontconfig-2.11.93-latin-update.patch
patch -p1 < /usr/portage/media-libs/fontconfig/files/fontconfig-2.10.2-docbook.patch
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/fontconfig-2.10.0-do-not-deprecate-dotfile.patch
# Needed to properly link FT...
export PKG_CONFIG="pkg-config --static"
sh autogen.sh --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=no --enable-static=yes --disable-docs --disable-docbook --localstatedir=/var --with-templatedir=/etc/fonts/conf.avail --with-baseconfigdir=/etc/fonts --with-xmldir=/etc/fonts --with-arch=arm --with-expat=${TC_BUILD_DIR}
make ${JOBSFLAGS} V=1
make install-exec
make install-pkgconfigDATA
${CROSS_TC}-strip --strip-unneeded ../bin/fc-scan
cp ../bin/fc-scan ${BASE_HACKDIR}/Fonts/src/linkfonts/bin/fc-scan
if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	${CROSS_TC}-strip --strip-unneeded ../bin/fc-list
	cp ../bin/fc-list ${BASE_HACKDIR}/Fonts/src/linkfonts/bin/fc-list
fi
export LDFLAGS="${BASE_LDFLAGS}"
unset PKG_CONFIG

## Coreutils for SS
echo "* Building coreutils . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/coreutils-8.25.tar.xz
cd coreutils-8.25
update_title_info
tar xvJf /usr/portage/distfiles/coreutils-8.25-patches-1.0.tar.xz
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	## Dirty hack to avoid pulling the __sched_cpucount@GLIBC_2.6 symbol from <sched.h> in sort.c (through lib/nproc.c), since we only have glibc 2.5 on the target. (Needed since coreutils 8.6)
	sed -e "s/CPU_COUNT/GLIBC_26_CPU_COUNT/g" -i lib/nproc.c
fi
rm -f patch/000_all_coreutils-i18n.patch patch/001_all_coreutils-gen-progress-bar.patch
for patchfile in patch/*.patch ; do
	if [ "${patchfile}" == "patch/050_all_coreutils-primes.patch" ] ; then
		patch -p0 < ${patchfile}
	else
		patch -p1 < ${patchfile}
	fi
done
# Avoid (re)generating manpages...
for my_man in man/*.x ; do
	touch ${my_man/%x/1}
done
export fu_cv_sys_stat_statfs2_bsize=yes
export gl_cv_func_realpath_works=yes
export gl_cv_func_fstatat_zero_flag=yes
export gl_cv_func_mknod_works=yes
export gl_cv_func_working_mkstemp=yes
# Some cross compilation tweaks lifted from http://cross-lfs.org/view/svn/x86_64-64/temp-system/coreutils.html
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-acl --disable-xattr --disable-libcap --enable-install-program=hostname
make ${JOBSFLAGS} V=1
make install
unset fu_cv_sys_stat_statfs2_bsize
unset gl_cv_func_realpath_works
unset gl_cv_func_fstatat_zero_flag
unset gl_cv_func_mknod_works
unset gl_cv_func_working_mkstemp
${CROSS_TC}-strip --strip-unneeded ../bin/sort
cp ../bin/sort ${BASE_HACKDIR}/ScreenSavers/src/linkss/bin/sort
${CROSS_TC}-strip --strip-unneeded ../bin/dircolors
cp ../bin/dircolors ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/dircolors

## SSHD, rsync, telnetd, sftp for USBNet
# We build libtommath & libtomcrypt ourselves in an attempt to avoid the performance regressions on ARM of the stable releases... FWIW, it's still there :/.
echo "* Building libtommath . . ."
echo ""
cd ..
rm -rf libtommath
until git clone https://github.com/libtom/libtommath.git -b develop libtommath ; do
	rm -rf libtommath
	sleep 15
done
cd libtommath
update_title_info
export CFLAGS="${CPPFLAGS} ${BASE_CFLAGS}"
sed -i -e '/CFLAGS += -O3 -funroll-loops/d' makefile.include
sed -i -e 's/-O3//g' etc/makefile
sed -i -e 's/-funroll-loops//g' etc/makefile
make ${JOBSFLAGS} CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" INCPATH=${TC_BUILD_DIR}/include LIBPATH=${TC_BUILD_DIR}/lib
make ${JOBSFLAGS} CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" INCPATH=${TC_BUILD_DIR}/include LIBPATH=${TC_BUILD_DIR}/lib INSTALL_USER=$(id -u) INSTALL_GROUP=$(id -g) install
export CFLAGS="${BASE_CFLAGS}"

echo "* Building libtomcrypt . . ."
echo ""
cd ..
rm -rf libtomcrypt
git clone https://github.com/libtom/libtomcrypt.git -b develop libtomcrypt
cd libtomcrypt
update_title_info
# Enable the math descriptors for dropbear's ECC support
export CFLAGS="${CPPFLAGS} -DUSE_LTM -DLTM_DESC ${BASE_CFLAGS}"
sed -i -e '/CFLAGS += -O3 -funroll-loops/d' makefile.include
# GCC doesn't like the name 'B0' for a variable, make it longer. (Breaks dropbear build later on)
sed -i -e 's/B0/SB0/g' src/encauth/ccm/ccm_memory_ex.c src/headers/tomcrypt_mac.h
make ${JOBSFLAGS} CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm"
make ${JOBSFLAGS} CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" INCPATH=${TC_BUILD_DIR}/include LIBPATH=${TC_BUILD_DIR}/lib DATAPATH=${TC_BUILD_DIR}/share INSTALL_USER=$(id -u) INSTALL_GROUP=$(id -g) NODOCS=true install
export CFLAGS="${BASE_CFLAGS}"

echo "* Building dropbear . . ."
echo ""
cd ..
tar -I lbzip2 -xvf /usr/portage/distfiles/dropbear-2016.74.tar.bz2
cd dropbear-2016.74
update_title_info
# NOTE: As mentioned earlier, on Kobos, let dropbear live in the internal memory to avoid trouble...
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	DEVICE_USERSTORE="${DEVICE_INTERNAL_USERSTORE}"
fi
# Update to latest git...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2016.74-upstream-catchup.patch
# Gentoo patches/tweaks
patch -p0 < /usr/portage/net-misc/dropbear/files/dropbear-0.46-dbscp.patch
sed -i -e "/SFTPSERVER_PATH/s:\".*\":\"${DEVICE_USERSTORE}/usbnet/libexec/sftp-server\":" default_options.h.in default_options.h
sed -i -e '/pam_start/s:sshd:dropbear:' svr-authpam.c
sed -i -e "/DSS_PRIV_FILENAME/s:\".*\":\"${DEVICE_USERSTORE}/usbnet/etc/dropbear_dss_host_key\":" -e "/RSA_PRIV_FILENAME/s:\".*\":\"${DEVICE_USERSTORE}/usbnet/etc/dropbear_rsa_host_key\":" -e "/ECDSA_PRIV_FILENAME/s:\".*\":\"${DEVICE_USERSTORE}/usbnet/etc/dropbear_ecdsa_host_key\":" default_options.h.in default_options.h
sed -e 's%#define DROPBEAR_X11FWD 1%#define DROPBEAR_X11FWD 0%' -i default_options.h.in default_options.h
sed -i -e "/DROPBEAR_PIDFILE/s:\".*\":\"${DEVICE_USERSTORE}/usbnet/run/sshd.pid\":" default_options.h.in default_options.h
# This only affects the bundled libtom, but disable it anyway
sed -e 's%#define DROPBEAR_SMALL_CODE 1%#define DROPBEAR_SMALL_CODE 0%' -i default_options.h.in default_options.h
# Moar crypto!
sed -e 's%/\*#define DROPBEAR_BLOWFISH\*/%#define DROPBEAR_BLOWFISH 1%' -i default_options.h.in default_options.h
# Ensure we have a full path, like with telnet, on Kobo devices, since ash doesn't take care of it for us...
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	sed -e '/DEFAULT_PATH/s:".*":"/sbin\:/usr/sbin\:/bin\:/usr/bin":' -i default_options.h.in default_options.h
fi
# Show /etc/issue (on Kindle only)
if [[ "${KINDLE_TC}" != "KOBO" ]] ; then
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2016.73-kindle-show-issue.patch
fi
# No passwd...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2016.73-kindle-nopasswd-hack.patch
# Pubkeys in ${DEVICE_USERSTORE}/usbnet/etc/authorized_keys & with perms checks curbed a bit
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2016.73-kindle-pubkey-hack.patch
# Make sure the linking with 'system' libtom* is done properly (libtomcrypt depends on libtommath, so we need to end up with -ltomcrypt -ltommath, not the other way around)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2016.73-fix-system-libtom.patch
# Fix the Makefile so that LTO flags aren't dropped in the linking stage...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-fix-Makefile-for-lto.patch
# Kill bundled libtom, we're using our own, from the latest develop branch
rm -rf libtomcrypt libtommath
# Fix userstore path on Kobos...
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	sed -e "s#/mnt/us#${DEVICE_USERSTORE}#g" -i svr-authpubkey.c
	# And the logs, we're on a Kobo, not a Kindle ;)
	sed -e "s#Kindle#Kobo#g" -i svr-authpasswd.c
fi
autoreconf -fi
# We now ship our own shared zlib, so let's use it
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-lastlog --enable-zlib --enable-openpty --enable-shadow --enable-syslog --disable-bundled-libtom
make ${JOBSFLAGS} MULTI=1 PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp"
export LDFLAGS="${BASE_LDFLAGS}"
${CROSS_TC}-strip --strip-unneeded dropbearmulti
cp dropbearmulti ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/dropbearmulti
# NOTE: ... and switch back to the usual userstore for everything else ;).
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	DEVICE_USERSTORE="${DEVICE_ONBOARD_USERSTORE}"
fi

# Build a speciifc version for the Rescue Pack, too, with a slightly different config...
if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] ; then
	echo "* Building dropbear (diags) . . ."
	echo ""
	cd ..
	rm -rf dropbear-2016.74
	tar -I lbzip2 -xvf /usr/portage/distfiles/dropbear-2016.74.tar.bz2
	cd dropbear-2016.74
	update_title_info
	# Update to latest git...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2016.74-upstream-catchup.patch
	# Gentoo patches/tweaks
	patch -p0 < /usr/portage/net-misc/dropbear/files/dropbear-0.46-dbscp.patch
	sed -i -e "/SFTPSERVER_PATH/s:\".*\":\"${DEVICE_USERSTORE}/usbnet/libexec/sftp-server\":" default_options.h.in default_options.h
	sed -i -e '/pam_start/s:sshd:dropbear:' svr-authpam.c
	sed -e 's%#define DROPBEAR_X11FWD 1%#define DROPBEAR_X11FWD 0%' -i default_options.h.in default_options.h
	# This only affects the bundled libtom, but disable it anyway
	sed -e 's%#define DROPBEAR_SMALL_CODE 1%#define DROPBEAR_SMALL_CODE 0%' -i default_options.h.in default_options.h
	# Moar crypto!
	sed -e 's%/\*#define DROPBEAR_BLOWFISH\*/%#define DROPBEAR_BLOWFISH 1%' -i default_options.h.in default_options.h
	# More diags specific tweaks
	sed -e '/_PATH_SSH_PROGRAM/s:".*":"/usr/local/bin/dbclient":' -i default_options.h.in default_options.h
	sed -e '/DEFAULT_PATH/s:".*":"/usr/local/bin\:/usr/bin\:/bin":' -i default_options.h.in default_options.h
	# Show /etc/issue
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2016.73-kindle-show-issue.patch
	# No passwd...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2016.73-kindle-nopasswd-hack.patch
	# Pubkeys in ${DEVICE_USERSTORE}/usbnet/etc/authorized_keys & with perms checks curbed a bit
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2016.73-kindle-pubkey-hack.patch
	# Make sure the linking with 'system' libtom* is done properly (libtomcrypt depends on libtommath, so we need to end up with -ltomcrypt -ltommath, not the other way around)
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2016.73-fix-system-libtom.patch
	# Enable the no password mode by default
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2016.73-kindle-nopasswd-hack-as-default.patch
	# Fix the Makefile so that LTO flags aren't dropped in the linking stage...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-fix-Makefile-for-lto.patch
	# Kill bundled libtom, we're using our own, from the latest develop branch
	rm -rf libtomcrypt libtommath
	autoreconf -fi
	# Build that one against a static zlib...
	for db_dep in libz.so libz.so.${ZLIB_SOVER%%.*} libz.so.${ZLIB_SOVER} ; do mv -v ../lib/${db_dep} ../lib/_${db_dep} ; done
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-lastlog --enable-zlib --enable-openpty --enable-shadow --enable-syslog --disable-bundled-libtom
	make ${JOBSFLAGS} MULTI=1 PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp"
	for db_dep in libz.so libz.so.${ZLIB_SOVER%%.*} libz.so.${ZLIB_SOVER} ; do mv -v ../lib/_${db_dep} ../lib/${db_dep} ; done
	${CROSS_TC}-strip --strip-unneeded dropbearmulti
	cp dropbearmulti ${BASE_HACKDIR}/RescuePack/src/dropbearmulti
fi

echo "* Building rsync . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/rsync-3.1.2.tar.gz
cd rsync-3.1.2
update_title_info
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-acl-support --disable-xattr-support --disable-ipv6 --disable-debug
make ${JOBSFLAGS}
make install
${CROSS_TC}-strip --strip-unneeded ../bin/rsync
cp ../bin/rsync ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/rsync

# NOTE: Glibc 2.15 is the in-between release when SunRPC support was obsoleted, but the --enable-obsolete-rpc configure switch only appeared in glibc 2.16.0...
# Since libtirpc is both a huge PITA and potentially not ready to be a drop-in replacement, we use glibc 2.16.0, that saves everyone a lot of hassle.
if [[ "${KINDLE_TC}" == "KOBO" ]] && [[ "${USE_TIRPC}" == "true" ]] ; then
	# Unfortunetaly, libtirpc is terrible. 0.3.0 currently requires the kerberos headers, even when building without GSS support... -_-"
	echo "* Building MIT Kerberos V . . ."
	echo ""
	tar -xvf /usr/portage/distfiles/krb5-1.13.1-signed.tar
	tar -xvzf krb5-1.13.1.tar.gz
	cd krb5-1.13.1
	patch -p0 < /usr/portage/app-crypt/mit-krb5/files/mit-krb5-1.12_warn_cflags.patch
	patch -p1 < /usr/portage/app-crypt/mit-krb5/files/mit-krb5-config_LDFLAGS.patch
	cd src
	autoreconf -fi
	export CFLAGS="${BASE_CFLAGS} -fno-strict-aliasing -fno-strict-overflow"
	env WARN_CFLAGS="set" LIBS="-lm" ac_cv_header_keyutils_h=no krb5_cv_attr_constructor_destructor=yes ac_cv_func_regcomp=yes ac_cv_printf_positional=yes ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static=yes --enable-shared=no --without-ldap --without-tcl --disable-pkinit --without-hesiod --enable-dns-for-realm --enable-kdc-lookaside-cache --disable-rpath
	make ${JOBSFLAGS}
	make install
	export CFLAGS="${BASE_CFLAGS}"
	cd ..
	cd ..

	# FIXME: Someone will have to explain that one to me. This is supposed to one day replace glibc's rpc support, which isn't built by default anymore... and yet it requires the glibc's rpc headers at build time. WTF?!
	# At least I'm not alone to have noticed... but nobody seems to care. (cf. http://sourceforge.net/p/libtirpc/bugs/25/, which is roughly 4 years old).
	# Work that shit around by siphoning the headers from our K5 TC, which is the closest match...
	mkdir -p include/rpcsvc
	cp -v ${HOME}/x-tools/arm-kindle5-linux-gnueabi/arm-kindle5-linux-gnueabi/sysroot/usr/include/rpcsvc/nis.h include/rpcsvc/
	cp -v ${HOME}/x-tools/arm-kindle5-linux-gnueabi/arm-kindle5-linux-gnueabi/sysroot/usr/include/rpcsvc/nis_tags.h include/rpcsvc/
	cp -v ${HOME}/x-tools/arm-kindle5-linux-gnueabi/arm-kindle5-linux-gnueabi/sysroot/usr/include/rpcsvc/nislib.h include/rpcsvc/

	echo "* Building TI-RPC . . ."
	# FIXME: For added fun, linking this w/ LTO fucks it up silently (broken pmap_* symbols)... (Linaro GCC 4.9 2015.04-1 & Linaro binutils 2.25.0-2015.01-2)
	if [[ "${CFLAGS}" != "${NOLTO_CFLAGS}" ]] ; then
		temp_nolto="true"
		export CFLAGS="${NOLTO_CFLAGS}"
	fi
	echo ""
	tar -I lbzip2 -xvf /usr/portage/distfiles/libtirpc-0.3.0.tar.bz2
	cd libtirpc-0.3.0
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static=yes --enable-shared=no --disable-ipv6 --disable-gssapi
	make ${JOBSFLAGS} V=1
	make install
	cd ..
	# NOTE: Re-enable LTO if need be
	if [[ "${temp_nolto}" == "true" ]] ; then
		unset temp_nolto
		export CFLAGS="${BASE_CFLAGS}"
	fi
fi

echo "* Building busybox . . ."
echo ""
# FIXME: Currently fails to link w/ gold (internal error in do_print_to_mapfile)... (Linaro GCC 5.2 2015.09 & binutils 2.25.1)
#if [[ "${CTNG_LD_IS}" == "gold" ]] ; then
#	temp_nogold="true"
#	unset CTNG_LD_IS
#fi
cd ..
tar -I lbzip2 -xvf /usr/portage/distfiles/busybox-1.24.2.tar.bz2
cd busybox-1.24.2
update_title_info
export CROSS_COMPILE="${CROSS_TC}-"
#export CFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
#export CXXFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
patch -p1 < /usr/portage/sys-apps/busybox/files/busybox-1.19.0-bb.patch
patch -p1 < /usr/portage/sys-apps/busybox/files/busybox-1.24.1-trylink-ldflags.patch
for patchfile in /usr/portage/sys-apps/busybox/files/busybox-1.24.2-*.patch ; do
	patch -p1 < ${patchfile}
done
cp /usr/portage/sys-apps/busybox/files/ginit.c init/
sed -i -r -e 's:[[:space:]]?-(Werror|Os|falign-(functions|jumps|loops|labels)=1|fomit-frame-pointer)\>::g' Makefile.flags
#sed -i '/bbsh/s:^//::' include/applets.h
sed -i '/^#error Aborting compilation./d' applets/applets.c
sed -i 's:-Wl,--gc-sections::' Makefile
sed -i 's:-static-libgcc::' Makefile.flags
# Print issue & auth as root without pass over telnet...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/busybox-1.22.1-kindle-nopasswd-hack.patch
# Look for ash profile & history in usbnet/etc
sed -e "s#hp = concat_path_file(hp, \".profile\");#hp = concat_path_file(\"${DEVICE_USERSTORE}/usbnet/etc\", \".profile\");#" -i shell/ash.c
sed -e "s#hp = concat_path_file(hp, \".ash_history\");#hp = concat_path_file(\"${DEVICE_USERSTORE}/usbnet/etc\", \".ash_history\");#" -i shell/ash.c

make allnoconfig
sleep 5
## Busybox config...
cat << EOF

	* General >
	Show applet usage messages
	Enable locale
	Support Unicode [w/o libc routines]
	Use sendfile system call
	devpts
	utmp
	wtmp
	SUID (solo)
	exec prefers applets

	* Tuning >
	MD5: 0
	SHA3: 0
	faster /proc
	Use CLOCK_MONOTONIC
	ioctl names
	Command line editing [w/o vi-style; Save history on shell exit]

	* Apllets > Archival >
	bunzip2

	* Applets > Coreutils > Common >
	Support verbose options (usually -v) for various applets

	* Applets > Debian Utilities >
	start-stop-daemon

	* Applets > Login/Password >
	shadow passwords
	login (solo)

	* Applets > Networking >
	ftpd
	httpd
	inetd
	telnetd

	* Applets > Shell >
	ash	[w/o Idle timeout; Check for new mail; Optimize for size]
	cttyhack
	Alias sh & bash to ash
	POSIX math
	Hide message...
	Use HISTFILESIZE

EOF
#make menuconfig
cp -v ${SVN_ROOT}/Configs/trunk/Kindle/Misc/busybox-1.24.1-config .config
make oldconfig
sleep 5
# NOTE: Remember, we jumped through a billion of shitty hoops to maybe use TI RPC on Kobo?
if [[ "${KINDLE_TC}" == "KOBO" ]] && [[ "${USE_TIRPC}" == "true" ]] ; then
	export CPPFLAGS="${BASE_CPPFLAGS} -I${TC_BUILD_DIR}/include/tirpc"
	sed -re 's/^(CONFIG_EXTRA_LDLIBS=)(.*?)/\1"tirpc pthread"/' -i .config
fi
make ${JOBSFLAGS} AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1
if [[ "${KINDLE_TC}" == "KOBO" ]] && [[ "${USE_TIRPC}" == "true" ]] ; then
	export CPPFLAGS="${BASE_CPPFLAGS}"
fi
cp busybox ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/busybox
# And now for Gandalf...
if [[ "${KINDLE_TC}" == "K5" || "${KINDLE_TC}" == "PW2" ]] ; then
	make distclean
	make allnoconfig
	sleep 5
	## Busybox config...
	cat << EOF

		* General >
		Show applet usage messages (solo)
		Use sendfile system call
		devpts
		utmp
		wtmp
		SUID (solo)
		exec prefers applets

		* Tuning >
		MD5: 0
		SHA3: 0
		faster /proc
		Use CLOCK_MONOTONIC
		ioctl names

		* Coreutils > Common >
		Support verbose options (usually -v) for various applets

		* Applets > Login/Password >
		shadow passwords
		su (solo)

EOF
	#make menuconfig
	cp -v ${SVN_ROOT}/Configs/trunk/Kindle/Misc/busybox-1.24.1-gandalf-config .config
	make oldconfig
	sleep 5
	make ${JOBSFLAGS} AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1
	cp busybox ${BASE_HACKDIR}/DevCerts/src/install/gandalf
fi
# NOTE: Re-enable gold if need be
if [[ "${temp_nogold}" == "true" ]] ; then
	unset temp_nogold
	export CTNG_LD_IS="gold"
fi

if [[ "${KINDLE_TC}" == "K3" ]] ; then
	echo "* Building OpenSSL 0.9.8 . . ."
	echo ""
	cd ..
	tar -I pigz -xvf /usr/portage/distfiles/openssl-0.9.8zh.tar.gz
	cd openssl-0.9.8zh
	update_title_info
	#export CFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
	#export CXXFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
	export LDFLAGS="${BASE_LDFLAGS} -Wa,--noexecstack"
	# NOTE: Avoid pulling __isoc99_sscanf@GLIBC_2.7 w/ the K3 TC... We use CFLAGS because the buildsystem doesn't honor CPPFLAGS...
	export CFLAGS="${CPPFLAGS} -D_GNU_SOURCE ${BASE_CFLAGS}"
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-0.9.8e-bsd-sparc64.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-0.9.8h-ldflags.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-0.9.8m-binutils.patch
	sed -i -e '/DIRS/s: fips : :g' -e '/^MANSUFFIX/s:=.*:=ssl:' -e "/^MAKEDEPPROG/s:=.*:=${CROSS_TC}-gcc:" -e '/^install:/s:install_docs::' Makefile{,.org}
	sed -i '/^SET_X/s:=.*:=set -x:' Makefile.shared
	sed -i 's/expr.*MAKEDEPEND.*;/true;/' util/domd
	cp /usr/portage/dev-libs/openssl/files/gentoo.config-0.9.8 gentoo.config
	chmod a+rx gentoo.config
	sed -i '1s,^:$,#!/usr/bin/perl,' Configure
	sed -i '/^"debug-ben-debug-64"/d' Configure
	sed -i '/^"debug-steve/d' Configure
	#./Configure linux-generic32 -DL_ENDIAN ${BASE_CFLAGS} -fno-strict-aliasing enable-camellia enable-mdc2 enable-tlsext enable-zlib --prefix=${TC_BUILD_DIR} --openssldir=${TC_BUILD_DIR}/etc/ssl shared threads
	./Configure linux-generic32 -DL_ENDIAN ${CFLAGS} enable-camellia enable-ec enable-idea enable-mdc2 enable-rc5 enable-tlsext enable-zlib --prefix=${TC_BUILD_DIR} --openssldir=${TC_BUILD_DIR}/etc/ssl shared threads
	grep '^CFLAG=' Makefile | LC_ALL=C sed -e 's:^CFLAG=::' -e 's:-ffast-math ::g' -e 's:-fomit-frame-pointer ::g' -e 's:-O[0-9] ::g' -e 's:-march=[-a-z0-9]* ::g' -e 's:-mcpu=[-a-z0-9]* ::g' -e 's:-m[a-z0-9]* ::g' > x-compile-tmp
	CFLAG="$(< x-compile-tmp)"
	sed -i -e "/^CFLAG/s:=.*:=${CFLAG} ${CFLAGS}:" -e "/^SHARED_LDFLAGS=/s:$: ${LDFLAGS}:" Makefile
	make -j1 AR="${CROSS_TC}-gcc-ar r" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" depend
	make -j1 AR="${CROSS_TC}-gcc-ar r" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" build_libs
	make -j1 AR="${CROSS_TC}-gcc-ar r" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" install

	# Copy it for the USBNet rpath...
	for ssl_lib in libcrypto.so.0.9.8 libssl.so.0.9.8 ; do
		cp -f ../lib/${ssl_lib} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
		chmod -cvR ug+w ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
		${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
	done
	export CFLAGS="${BASE_CFLAGS}"
	export LDFLAGS="${BASE_LDFLAGS}"
elif [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	# NOTE: We build & link it statically for K4/K5 because KT 5.1.0 move from openssl-0.9.8 to openssl-1...
	echo "* Building OpenSSL 1 . . ."
	echo ""
	cd ..
	tar -I pigz -xvf /usr/portage/distfiles/openssl-1.0.2j.tar.gz
	cd openssl-1.0.2j
	update_title_info
	export CPPFLAGS="${BASE_CPPFLAGS} -DOPENSSL_NO_BUF_FREELISTS"
	#export CFLAGS="${CPPFLAGS} ${BASE_CFLAGS} -fno-strict-aliasing"
	export CFLAGS="${CPPFLAGS} ${BASE_CFLAGS}"
	#export CXXFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
	export LDFLAGS="${BASE_LDFLAGS} -Wa,--noexecstack"
	rm -f Makefile
	patch -p0 < /usr/portage/dev-libs/openssl/files/openssl-1.0.0a-ldflags.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.2i-parallel-build.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.2a-parallel-obj-headers.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.2a-parallel-install-dirs.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.2a-parallel-symlinking.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.2-ipv6.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.2a-x32-asm.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.1p-default-source.patch
	# FIXME: Periodically check if the Kernel has been tweaked, and we can use the PMCCNTR in userland.
	# FIXME: When Amazon ported FW 5.4.x to the PW1, they apparently helpfully backported this regression too, so apply that to K5 builds, too...
	# NOTE: Since OpenSSL 1.0.2, there's also the crypto ARMv8 stuff, but that of course will never happen for us, so we can just ditch it.
	# NOTE: Appears to be okay on Kobo... Or at least it doesn't spam dmesg ;).
	if [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "K5" ]] ; then
		patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/openssl-1.0.2-nerf-armv7_tick_armv8-armcaps.patch
	fi
	# NOTE: getauxval appeared in glibc 2.16, but we can't pick it up on Kobo, since those run eglibc 2_15... Nerf it (if we're using glibc 2.16).
	# FIXME: Same deal for the PW2-against-glibc-2.19 ...
	if [[ "${KINDLE_TC_IS_GLIBC_219}" == "true" ]] ; then
		sed -e 's/extern unsigned long getauxval(unsigned long type) __attribute__ ((weak));/static unsigned long (*getauxval) (unsigned long) = NULL;/' -i crypto/armcap.c
	fi
	#if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	#	sed -e 's/extern unsigned long getauxval(unsigned long type) __attribute__ ((weak));/static unsigned long (*getauxval) (unsigned long) = NULL;/' -i crypto/armcap.c
	#	# NOTE: This chucks the constructor attribute out the window, which may not be desirable...
	#	#sed -e 's/# if defined(__GNUC__) && __GNUC__>=2/#if 0/' -i crypto/armcap.c
	#	# NOTE: That might also do the job, but I'm less convinced of the soundness of it in this particular instance...
	#	#export LDFLAGS="${LDFLAGS} -Wl,--defsym,getauxval=getauxval"
	#fi
	sed -i -e '/DIRS/s: fips : :g' -e '/^MANSUFFIX/s:=.*:=ssl:' -e "/^MAKEDEPPROG/s:=.*:=${CROSS_TC}-gcc:" -e '/^install:/s:install_docs::' Makefile.org
	sed -i '/^SET_X/s:=.*:=set -x:' Makefile.shared
	cp /usr/portage/dev-libs/openssl/files/gentoo.config-1.0.2 gentoo.config
	chmod a+rx gentoo.config
	sed -i '1s,^:$,#!/usr/bin/perl,' Configure
	sed -i '/stty -icanon min 0 time 50; read waste/d' config
	#unset CROSS_COMPILE
	# We need it to be PIC, or mosh fails to link (not an issue anymore, now that we use a shared lib)
	#./Configure linux-armv4 -DL_ENDIAN ${BASE_CFLAGS} -fno-strict-aliasing enable-camellia enable-mdc2 enable-tlsext enable-zlib --prefix=${TC_BUILD_DIR} --openssldir=${TC_BUILD_DIR}/etc/ssl shared threads
	./Configure linux-armv4 -DL_ENDIAN ${CFLAGS} enable-camellia enable-ec enable-idea enable-mdc2 enable-rc5 enable-tlsext enable-asm enable-zlib --prefix=${TC_BUILD_DIR} --openssldir=${TC_BUILD_DIR}/etc/ssl shared threads
	grep '^CFLAG=' Makefile | LC_ALL=C sed -e 's:^CFLAG=::' -e 's:-ffast-math ::g' -e 's:-fomit-frame-pointer ::g' -e 's:-O[0-9] ::g' -e 's:-march=[-a-z0-9]* ::g' -e 's:-mcpu=[-a-z0-9]* ::g' -e 's:-m[a-z0-9]* ::g' > x-compile-tmp
	CFLAG="$(< x-compile-tmp)"
	sed -i -e "/^CFLAG/s:=.*:=${CFLAG} ${CFLAGS}:" -e "/^SHARED_LDFLAGS=/s:$: ${LDFLAGS}:" Makefile
	make -j1 AR="${CROSS_TC}-gcc-ar r" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" depend
	make -j1 AR="${CROSS_TC}-gcc-ar r" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" all
	make -j1 AR="${CROSS_TC}-gcc-ar r" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" rehash
	make -j1 AR="${CROSS_TC}-gcc-ar r" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" install
	# If we want to only link statically because FW 5.1 moved to OpenSSL 1 while FW 5.0 was on OpenSSL 0.9.8...
	#rm -fv ../lib/engines/lib*.so ../lib/libcrypto.so ../lib/libcrypto.so.1.0.0 ../lib/libssl.so ../lib/libssl.so.1.0.0

	# Copy it for the USBNet rpath...
	for ssl_lib in libcrypto.so.1.0.0 libssl.so.1.0.0 ; do
		cp -f ../lib/${ssl_lib} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
		chmod -cvR ug+w ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
		${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
	done
	export CPPFLAGS="${BASE_CPPFLAGS}"
	export CFLAGS="${BASE_CFLAGS}"
	export LDFLAGS="${BASE_LDFLAGS}"
fi

echo "* Building OpenSSH . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/openssh-7.3p1.tar.gz
cd openssh-7.3p1
update_title_info
# NOTE: On the PW2 (Cortex A9), OpenSSH will throw a SIGILL at boot & connect (logged as an 'undefined instruction' in dmesg).
# This is 'normal', a part of OpenSSL's capabilities tests, and it is handled properly.
# (FWIW, it's the _armv7_tick check that fails, apparently because that feature isn't enabled for userland by the kernel for this specific CPU...
# cf. http://neocontra.blogspot.fr/2013/05/user-mode-performance-counters-for.html)
# NOTE: We've silenced the warning for now with an OpenSSL patch.
#
# NOTE: LTO used to break sshd on the K3 (at least) (openssh-6.0p1/GCC Linaro 4.7.2012.06)
export CFLAGS="${BASE_CFLAGS}"
export CXXFLAGS="${BASE_CFLAGS}"
# Setup an RPATH for OpenSSL....
# Needed on the K5 because of the 0.9.8 -> 1.0.0 switch,
# and needed on the K3, because OpenSSH (client) segfaults during the hostkey exchange with Amazon's bundled OpenSSL lib (on FW 2.x at least)
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
# Why, oh why are you finding ar in a weird way?
export ac_cv_path_AR=${CROSS_TC}-gcc-ar
sed -i -e '/_PATH_XAUTH/s:/usr/X11R6/bin/xauth:/usr/bin/xauth:' pathnames.h
sed -i '/^AuthorizedKeysFile/s:^:#:' sshd_config
patch -p1 < /usr/portage/net-misc/openssh/files/openssh-7.3_p1-GSSAPI-dns.patch
patch -p1 < /usr/portage/net-misc/openssh/files/openssh-6.7_p1-openssl-ignore-status.patch
# Pubkeys in ${DEVICE_USERSTORE}/usbnet/etc/authorized_keys & with perms checks curbed a bit
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/openssh-7.2p1-kindle-pubkey-hack.patch
# Curb some more permission checks to avoid dying horribly on FW >= 5.3.9...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/openssh-7.2p1-kindle-perm-hack.patch
# Fix Makefile to actually make use of LTO ;).
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/openssh-fix-Makefile-for-lto.patch
sed -i -e "s:-lcrypto:$(pkg-config --libs ../lib/pkgconfig/openssl.pc):" configure{,.ac}
sed -i -e 's:^PATH=/:#PATH=/:' configure{,.ac}
# Tweak a whole lot of paths to suit our needs...
# NOTE: This is particularly ugly, but the code handles $HOME from the passwd db itself, so, gotta trick it... Use a decent amount of .. to handle people with custom HOMEdirs
sed -e "s#~/\.ssh#${DEVICE_USERSTORE}/usbnet/etc/dot\.ssh#g" -i pathnames.h
sed -e "s#\"\.ssh#\"../../../../../..${DEVICE_USERSTORE}/usbnet/etc/dot\.ssh#g" -i pathnames.h
# Fix userstore path on Kobos...
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	sed -e "s#/mnt/us#${DEVICE_USERSTORE}#g" -i auth.c
	# NOTE: poll_chk appeared in glibc 2.16, but we can't pull that in since Kobos run eglibc 2_15... We have to pull the full fortify support to get rid of this one if we're using glibc 2.16... Not too torn up about that one, since we don't actually really use OpenSSH there anyway ;p.
	#export CFLAGS="${BASE_CFLAGS} -fno-stack-protector -U_FORTIFY_SOURCE"
	# Since it introduces an alias and a new symbol, no amount of defsym trickery can help, AFAICT...
	#export LDFLAGS="${LDFLAGS} -Wl,--defsym,__poll_chk=poll@GLIBC_2.4"	# <- Not even a valid syntax, wheee, and using simply poll fails to resolve it :?
fi
if [[ "${KINDLE_TC}" == "K3" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] || [[ "${KINDLE_TC_IS_GLIBC_219}" == "true" ]] ; then
	# OpenSSH >= 6.0 wants to build with stack-protection & _FORTIFY_SOURCE=2 but we can't on these devices...
	sed -i -e 's:-D_FORTIFY_SOURCE=2::' configure{,.ac}
	autoreconf -fi
fi
if [[ "${KINDLE_TC}" == "K3" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	## Easier to just fake it now than edit a bunch of defines later... (Only useful for sshd, you don't have to bother with it if you're just interested in sftp-server)
	if [[ -d "${DEVICE_USERSTORE}/usbnet" ]] ; then
		./configure --prefix=${DEVICE_USERSTORE}/usbnet --with-pid-dir=${DEVICE_USERSTORE}/usbnet/run --with-privsep-path=${DEVICE_USERSTORE}/usbnet/empty --host=${CROSS_TC} --with-ldflags="${LDFLAGS}" --disable-etc-default-login --disable-lastlog --with-openssl --with-md5-passwords --with-ssl-engine --disable-strip --without-stackprotect
	else
		./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --with-ldflags="${LDFLAGS}" --disable-etc-default-login --disable-lastlog --with-openssl --with-md5-passwords --with-ssl-engine --disable-strip --without-stackprotect
	fi
elif [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] ; then
	if [[ -d "${DEVICE_USERSTORE}/usbnet" ]] ; then
		./configure --prefix=${DEVICE_USERSTORE}/usbnet --with-pid-dir=${DEVICE_USERSTORE}/usbnet/run --with-privsep-path=${DEVICE_USERSTORE}/usbnet/empty --host=${CROSS_TC} --with-ldflags="${LDFLAGS}" --disable-etc-default-login --disable-lastlog --with-openssl --with-md5-passwords --with-ssl-engine --disable-strip
	else
		./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --with-ldflags="${LDFLAGS}" --disable-etc-default-login --disable-lastlog --with-openssl --with-md5-passwords --with-ssl-engine --disable-strip
	fi
fi
make ${JOBSFLAGS}
if [[ -d "${DEVICE_USERSTORE}/usbnet" ]] ; then
	# Make sure it's clean before install...
	rm -rf ${DEVICE_USERSTORE}/usbnet/bin ${DEVICE_USERSTORE}/usbnet/empty ${DEVICE_USERSTORE}/usbnet/etc ${DEVICE_USERSTORE}/usbnet/libexec ${DEVICE_USERSTORE}/usbnet/sbin ${DEVICE_USERSTORE}/usbnet/share
fi
make install-nokeys
if [[ -d "${DEVICE_USERSTORE}/usbnet" ]] ; then
	for file in ${DEVICE_USERSTORE}/usbnet/bin/* ${DEVICE_USERSTORE}/usbnet/sbin/* ${DEVICE_USERSTORE}/usbnet/libexec/* ; do
		if [[ "${file}" != "${DEVICE_USERSTORE}/usbnet/bin/slogin" ]] ; then
			${CROSS_TC}-strip --strip-unneeded ${file}
			cp ${file} ${BASE_HACKDIR}/USBNetwork/src/usbnet/${file#${DEVICE_USERSTORE}/usbnet/*}
		fi
	done
	cp ${DEVICE_USERSTORE}/usbnet/etc/moduli ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/moduli
	cp ${DEVICE_USERSTORE}/usbnet/etc/sshd_config  ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/sshd_config
	# NOTE: Enable aggressive KeepAlive behavior, see if it helps on FW 2.x and/or over WiFi...
	sed -e 's/#ClientAliveInterval 0/# Kindle tweaks: enable aggressive KeepAlive\nClientAliveInterval 15/' -i ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/sshd_config
	sed -e 's/#ClientAliveCountMax 3/ClientAliveCountMax 3/' -i ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/sshd_config
	# Also, we kind of *need* root login here... ;D
	sed -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' -i ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/sshd_config
	sed -e 's/#PermitRootLogin no/PermitRootLogin yes/' -i ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/sshd_config
	cp ${DEVICE_USERSTORE}/usbnet/etc/ssh_config  ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/ssh_config
	# Do the same for the client...
	sed -e '/# configuration file, and defaults at the end./s/$/\n\n# Kindle tweaks: enable aggressive KeepAlive\nServerAliveInterval 15\nServerAliveCountMax 3/' -i ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/ssh_config
else
	cp ../libexec/sftp-server ${BASE_HACKDIR}/USBNetwork/src/usbnet/libexec/sftp-server
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/libexec/sftp-server
fi
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	export CFLAGS="${BASE_CFLAGS}"
fi
unset ac_cv_path_AR
export LDFLAGS="${BASE_LDFLAGS}"

## ncurses & htop for USBNet
echo "* Building ncurses (narrowc) . . ."
echo ""
NCURSES_SOVER="6.0"
cd ..
tar -I pigz -xvf /usr/portage/distfiles/ncurses-6.0.tar.gz
cd ncurses-6.0
update_title_info
export CFLAGS="${BASE_CFLAGS}"
export CXXFLAGS="${BASE_CFLAGS}"
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-gfbsd.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-5.7-nongnu.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-rxvt-unicode-9.15.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-pkg-config.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-5.9-gcc-5.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-ticlib.patch
sed -i -e '/^PKG_CONFIG_LIBDIR/s:=.*:=$(libdir)/pkgconfig:' misc/Makefile.in
unset TERMINFO
export CPPFLAGS="${BASE_CPPFLAGS} -D_GNU_SOURCE"
# NOTE: cross-compile fun times, build tic for our host, in case we're not running the same ncurses version...
export CBUILD="$(uname -m)-pc-linux-gnu"
mkdir -p ${CBUILD}
cd ${CBUILD}
env CHOST=${CBUILD} CFLAGS="-O2 -pipe -march=native" CXXFLAGS="-O2 -pipe -march=native" LDFLAGS="-Wl,--as-needed -static" CPPFLAGS="-D_GNU_SOURCE" CC="gcc" CXX="g++" AR="ar" RANLIB="ranlib" NM="nm" LD="ld" ../configure --{build,host}=${CBUILD} --without-shared --with-normal
# NOTE: use our host's tic
MY_BASE_PATH="${PATH}"
export PATH="${TC_BUILD_DIR}/ncurses-6.0/${CBUILD}/progs:${PATH}"
export TIC_PATH="${TC_BUILD_DIR}/ncurses-6.0/${CBUILD}/progs/tic"
cd ..
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --with-terminfo-dirs="${DEVICE_USERSTORE}/usbnet/etc/terminfo:/etc/terminfo:/usr/share/terminfo" --with-pkg-config-libdir="${TC_BUILD_DIR}/lib/pkgconfig" --enable-pc-files --with-shared --without-hashed-db --without-ada --without-cxx --without-cxx-binding --without-debug --without-profile --without-gpm --disable-termcap --enable-symlinks --with-rcs-ids --with-manpage-format=normal --enable-const --enable-colorfgbg --enable-hard-tabs --enable-echo --with-progs --disable-widec --without-pthread --without-reentrant
# NOTE: Build our hosts's tic
cd ${CBUILD}
make -j1 sources
rm -f misc/pc-files
make ${JOBSFLAGS} -C progs tic
cd ..
make -j1 sources
rm -f misc/pc-files
make ${JOBSFLAGS}
make install
unset TIC_PATH
export PATH="${MY_BASE_PATH}"
unset CBUILD
export CPPFLAGS="${BASE_CPPFLAGS}"
# Kobo doesn't ship ncurses at all, but we always need it anyway, since 6.0 changed the sover ;)
cp ../lib/libncurses.so.${NCURSES_SOVER} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libncurses.so.${NCURSES_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libncurses.so.${NCURSES_SOVER%%.*}
# We then do a widechar build, which is actually mostly the one we'll be relying on
echo "* Building ncurses (widec) . . ."
echo ""
cd ..
rm -rf ncurses-6.0
tar -I pigz -xvf /usr/portage/distfiles/ncurses-6.0.tar.gz
cd ncurses-6.0
update_title_info
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-gfbsd.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-5.7-nongnu.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-rxvt-unicode-9.15.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-pkg-config.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-5.9-gcc-5.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-ticlib.patch
sed -i -e '/^PKG_CONFIG_LIBDIR/s:=.*:=$(libdir)/pkgconfig:' misc/Makefile.in
export CPPFLAGS="${BASE_CPPFLAGS} -D_GNU_SOURCE"
# NOTE: cross-compile fun times, build tic for our host, in case we're not running the same ncurses version...
export CBUILD="$(uname -m)-pc-linux-gnu"
mkdir -p ${CBUILD}
cd ${CBUILD}
env CHOST=${CBUILD} CFLAGS="-O2 -pipe -march=native" CXXFLAGS="-O2 -pipe -march=native" LDFLAGS="-Wl,--as-needed -static" CPPFLAGS="-D_GNU_SOURCE" CC="gcc" CXX="g++" AR="ar" RANLIB="ranlib" NM="nm" LD="ld" ../configure --{build,host}=${CBUILD} --without-shared --with-normal
# NOTE: use our host's tic
MY_BASE_PATH="${PATH}"
export PATH="${TC_BUILD_DIR}/ncurses-6.0/${CBUILD}/progs:${PATH}"
export TIC_PATH="${TC_BUILD_DIR}/ncurses-6.0/${CBUILD}/progs/tic"
cd ..
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --with-terminfo-dirs="${DEVICE_USERSTORE}/usbnet/etc/terminfo:/etc/terminfo:/usr/share/terminfo" --with-pkg-config-libdir="${TC_BUILD_DIR}/lib/pkgconfig" --enable-pc-files --with-shared --without-hashed-db --without-ada --without-cxx --without-cxx-binding --without-debug --without-profile --without-gpm --disable-termcap --enable-symlinks --with-rcs-ids --with-manpage-format=normal --enable-const --enable-colorfgbg --enable-hard-tabs --enable-echo --with-progs --enable-widec --without-pthread --without-reentrant --includedir="${TC_BUILD_DIR}/include/ncursesw"
# NOTE: Build our hosts's tic
cd ${CBUILD}
make -j1 sources
rm -f misc/pc-files
make ${JOBSFLAGS} -C progs tic
cd ..
make -j1 sources
rm -f misc/pc-files
make ${JOBSFLAGS}
make install
unset TIC_PATH
export PATH="${MY_BASE_PATH}"
unset CBUILD
export CPPFLAGS="${BASE_CPPFLAGS}"
cp ../lib/libncursesw.so.${NCURSES_SOVER} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libncursesw.so.${NCURSES_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libncursesw.so.${NCURSES_SOVER%%.*}
# Update termcap DB...
if [[ "${KINDLE_TC}" != "PW2" ]] ; then
	for termdb in $(find ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/terminfo -type f) ; do
		termdb_file="${termdb##*/}"
		termdb_dir="${termdb_file:0:1}"
		cp -v "../share/terminfo/${termdb_dir}/${termdb_file}" "${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/terminfo/${termdb_dir}/${termdb_file}"
	done
fi

echo "* Building htop . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/htop-2.0.2.tar.gz
cd htop-2.0.2
update_title_info
# FIXME: Currently fails to build w/ LTO (ICE)... (K5 TC, Linaro GCC 5.2 2015.09 & binutils 2.25.1)
#if [[ "${CFLAGS}" != "${NOLTO_CFLAGS}" ]] ; then
#	temp_nolto="true"
#	export CFLAGS="${NOLTO_CFLAGS}"
#fi
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/htop-2.0.2-to-HEAD.patch
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/htop-1.0.3-kindle-tweaks.patch
# Kobo doesn't ship ncurses... Some Kindles don't ship ncursesw either, so always use our own.
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
# Fix userstore path on Kobos...
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	sed -e "s#/mnt/us#${DEVICE_USERSTORE}#g" -i htop.c
fi
autoreconf -fi
export ac_cv_func_malloc_0_nonnull=yes
export ac_cv_func_realloc_0_nonnull=yes
export ac_cv_file__proc_meminfo=yes
export ac_cv_file__proc_stat=yes
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-unicode --enable-taskstats
make ${JOBSFLAGS}
make install
${CROSS_TC}-strip --strip-unneeded ../bin/htop
unset ac_cv_func_malloc_0_nonnull
unset ac_cv_func_realloc_0_nonnull
unset ac_cv_file__proc_meminfo
unset ac_cv_file__proc_stat
cp ../bin/htop ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/htop
export LDFLAGS="${BASE_LDFLAGS}"
# NOTE: Re-enable LTO if need be
if [[ "${temp_nolto}" == "true" ]] ; then
	unset temp_nolto
	export CFLAGS="${BASE_CFLAGS}"
fi

## lsof for USBNet
echo "* Building lsof . . ."
echo ""
cd ..
tar -I lbzip2 -xvf /usr/portage/distfiles/lsof_4.89.tar.bz2
cd lsof_4.89
tar -xvf lsof_4.89_src.tar
cd lsof_4.89_src
update_title_info
touch .neverInv
patch -p1 < /usr/portage/sys-process/lsof/files/lsof-4.85-cross.patch
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	LSOF_CC="${CROSS_TC}-gcc" LSOF_AR="${CROSS_TC}-gcc-ar rc" LSOF_RANLIB="${CROSS_TC}-gcc-ranlib" LSOF_NM="${CROSS_TC}-gcc-nm" LSOF_CFGF="${CFLAGS} ${CPPFLAGS}" LSOF_CFGL="${CFLAGS} ${LDFLAGS}" LSOF_ARCH="armv6l" LSOF_INCLUDE="${TC_BUILD_DIR}/include" LINUX_CLIB="-DGLIBCV=2" LINUX_HASSELINUX="N" ./Configure -n linux
elif [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	LSOF_CC="${CROSS_TC}-gcc" LSOF_AR="${CROSS_TC}-gcc-ar rc" LSOF_RANLIB="${CROSS_TC}-gcc-ranlib" LSOF_NM="${CROSS_TC}-gcc-nm" LSOF_CFGF="${CFLAGS} ${CPPFLAGS}" LSOF_CFGL="${CFLAGS} ${LDFLAGS}" LSOF_ARCH="armv7-a" LSOF_INCLUDE="${TC_BUILD_DIR}/include" LINUX_CLIB="-DGLIBCV=2" LINUX_HASSELINUX="N" ./Configure -n linux
fi
make ${JOBSFLAGS} DEBUG="" all
${CROSS_TC}-strip --strip-unneeded lsof
cp lsof ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/lsof
cd ..

## shlock for Fonts & SS
echo "* Building shlock . . ."
echo ""
cd ..
mkdir shlock
cd shlock
update_title_info
wget http://gitweb.dragonflybsd.org/dragonfly.git/blob_plain/HEAD:/usr.bin/shlock/shlock.c -O shlock.c
## BSD -> LINUX
patch -p0 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/shlock-DFBSD-to-GNU.patch
${CROSS_TC}-gcc shlock.c ${BASE_CFLAGS} ${BASE_LDFLAGS} -o shlock
${CROSS_TC}-strip --strip-unneeded shlock
cp shlock ${BASE_HACKDIR}/Fonts/src/linkfonts/bin/shlock
cp shlock ${BASE_HACKDIR}/ScreenSavers/src/linkss/bin/shlock

## protobuf (mosh dep) [You need to have the exact same version installed on your box...]
echo "* Building protobuf . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/protobuf-3.0.0_beta3_p1.tar.gz
cd protobuf-3.0.0-beta-3.1
update_title_info
patch -p1 < /usr/portage/dev-libs/protobuf/files/protobuf-2.5.0-emacs-24.4.patch
patch -p1 < /usr/portage/dev-libs/protobuf/files/protobuf-2.6.1-protoc-cmdline.patch
patch -p1 < /usr/portage/dev-libs/protobuf/files/protobuf-3.0.0_beta2-disable-local-gmock.patch
export CXXFLAGS="${BASE_CFLAGS} -DGOOGLE_PROTOBUF_NO_RTTI"
autoreconf -fi
## NOTE: The host *must* be running the exact same version (for protoc)
if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	# Needs to be PIC on K5, or mosh throws a fit (reloc against a local symbol, as always)
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static=yes --enable-shared=no --with-zlib --with-protoc=/usr/bin/protoc --with-pic
elif [[ "${KINDLE_TC}" == "K3" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static=yes --enable-shared=no --with-zlib --with-protoc=/usr/bin/protoc
fi
make ${JOBSFLAGS}
make install
export CXXFLAGS="${BASE_CFLAGS}"

## mosh for USBNet
echo "* Building mosh . . ."
echo ""
cd ..
# Link libstdc++ statically, because the bundled one is friggin' ancient (especially on the K3, but the one on the K5 is still too old) (and we pull GLIBCXX_3.4.10 / CXXABI_ARM_1.3.3 / GLIBCXX_3.4.15)
# The K5 handles: <= GLIBCXX_3.4.14 / CXXABI_1.3.4 / CXXABI_ARM_1.3.3
# Also, setup an RPATH for OpenSSL....
export LDFLAGS="${BASE_LDFLAGS} -static-libstdc++ -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
tar -I pigz -xvf /usr/portage/distfiles/mosh-1.2.5.tar.gz
cd mosh-1.2.5
update_title_info
patch -p1 < /usr/portage/net-misc/mosh/files/mosh-1.2.5-git-version.patch
./autogen.sh
if [[ "${KINDLE_TC}" == "K3" ]] || [[ "${KINDLE_TC_IS_GLIBC_219}" == "true" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-client --enable-server --disable-hardening
elif [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-client --enable-server --enable-hardening
fi
make ${JOBSFLAGS} V=1
make install
export LDFLAGS="${BASE_LDFLAGS}"
${CROSS_TC}-strip --strip-unneeded ../bin/mosh-server
cp ../bin/mosh-server ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/mosh-server
${CROSS_TC}-strip --strip-unneeded ../bin/mosh-client
cp ../bin/mosh-client ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/mosh-client

## libarchive (kindletool dep) [No zlib symbol versioning issues either]
echo "* Building libarchive . . ."
echo ""
cd ..
tar -xvJf /usr/portage/distfiles/libarchive-3.3.2_p20171030.tar.xz
cd libarchive
update_title_info
# Kill -Werror, git master doesn't always build with it...
sed -e 's/-Werror //' -i ./Makefile.am
./build/autogen.sh
export ac_cv_header_ext2fs_ext2_fs_h=0
# We now ship our own shared zlib, so let's use it
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --disable-xattr --disable-acl --with-zlib --without-bz2lib --without-lzmadec --without-iconv --without-lzma --without-nettle --without-openssl --without-expat --without-xml2 --without-lz4
make ${JOBSFLAGS} V=1
make install
export LDFLAGS="${BASE_LDFLAGS}"
unset ac_cv_header_ext2fs_ext2_fs_h

## GMP (kindletool dep)
echo "* Building GMP . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/gmp-6.1.2.tar.xz
cd gmp-6.1.2
update_title_info
autoreconf -fi
libtoolize
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	env MPN_PATH="arm/v6 arm/v5 arm generic" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-assembly --enable-static --disable-shared --disable-cxx
elif [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	env MPN_PATH="arm/neon mpn/arm/v7a/cora8 arm/v6t2 arm/v6 arm/v5 arm generic" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-assembly --enable-static --disable-shared --disable-cxx
elif [[ "${KINDLE_TC}" == "PW2" ]] ; then
	env MPN_PATH="arm/neon mpn/arm/v7a/cora9 arm/v6t2 arm/v6 arm/v5 arm generic" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-assembly --enable-static --disable-shared --disable-cxx
fi
make ${JOBSFLAGS}
make install

## Nettle (kindletool dep)
echo "* Building nettle . . ."
echo ""
cd ..
if [[ "${USE_STABLE_NETTLE}" == "true" ]] ; then
	tar -I pigz -xvf /usr/portage/distfiles/nettle-2.7.1.tar.gz
	cd nettle-2.7.1
	# Breaks the tools build if we don't build the shared libs at all, which is precisely what we do ;).
	#patch -p1 < /usr/portage/dev-libs/nettle/files/nettle-2.7-shared.patch
	sed -e '/CFLAGS=/s: -ggdb3::' -e 's/solaris\*)/sunldsolaris*)/' -i configure.ac
	sed -i '/SUBDIRS/s/testsuite examples//' Makefile.in
	autoreconf -fi
	if [[ "${KINDLE_TC}" == "K3" ]] ; then
		env ac_cv_host="armv6j-kindle-linux-gnueabi" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --disable-arm-neon
	elif [[ "${KINDLE_TC}" == "K5" ]] ; then
		env ac_cv_host="armv7l-kindle5-linux-gnueabi" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --enable-arm-neon
	elif [[ "${KINDLE_TC}" == "PW2" ]] ; then
		env ac_cv_host="armv7l-kindlepw2-linux-gnueabi" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --enable-arm-neon
	elif [[ "${KINDLE_TC}" == "KOBO" ]] ; then
		env ac_cv_host="armv7l-kobo-linux-gnueabi" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --enable-arm-neon
	fi
	make ${JOBSFLAGS}
	make install
else
	# Build from git to benefit from the more x86_64 friendly API changes
	rm -rf nettle-git
	until git clone https://git.lysator.liu.se/nettle/nettle.git nettle-git ; do
		rm -rf nettle-git
		sleep 15
	done
	cd nettle-git
	update_title_info
	sed -e '/CFLAGS=/s: -ggdb3::' -e 's/solaris\*)/sunldsolaris*)/' -i configure.ac
	sed -i '/SUBDIRS/s/testsuite examples//' Makefile.in
	sh ./.bootstrap
	if [[ "${KINDLE_TC}" == "K3" ]] ; then
		env ac_cv_host="armv6j-kindle-linux-gnueabi" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --disable-arm-neon
	elif [[ "${KINDLE_TC}" == "K5" ]] ; then
		env ac_cv_host="armv7l-kindle5-linux-gnueabi" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --enable-arm-neon
	elif [[ "${KINDLE_TC}" == "PW2" ]] ; then
		env ac_cv_host="armv7l-kindlepw2-linux-gnueabi" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --enable-arm-neon
	elif [[ "${KINDLE_TC}" == "KOBO" ]] ; then
		env ac_cv_host="armv7l-kobo-linux-gnueabi" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --enable-arm-neon
	fi
	make ${JOBSFLAGS}
	make install
fi

## KindleTool for USBNet
echo "* Building KindleTool . . ."
echo ""
cd ..
rm -rf KindleTool
until git clone https://github.com/NiLuJe/KindleTool.git ; do
	rm -rf KindleTool
	sleep 15
done
cd KindleTool
update_title_info
export KT_NO_USERATHOST_TAG="true"
export CFLAGS="${BASE_CFLAGS} -DKT_USERATHOST='\"niluje@ajulutsikael\"'"
# Setup an RPATH for OpenSSL on the K5....
# Keep it K5 only, because on the K3, so far we haven't had any issues with KindleTool, and we use it in the JailBreak, too, so an rpath isn't the way to go
#if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
#	export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
#fi
# We now ship our own shared zlib, so let's (optionally) use it
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
make ${JOBSFLAGS} kindle
export LDFLAGS="${BASE_LDFLAGS}"
unset KT_NO_USERATHOST_TAG
export CFLAGS="${BASE_CFLAGS}"
#if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
#	export LDFLAGS="${BASE_LDFLAGS}"
#fi
cp KindleTool/Kindle/kindletool ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/kindletool
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	cp KindleTool/Kindle/kindletool ${BASE_HACKDIR}/Jailbreak/src/linkjail/bin/kindletool
fi
# MRInstaller needs us, too
if [[ "${KINDLE_TC}" != "KOBO" ]] ; then
	cp KindleTool/Kindle/kindletool ${BASE_HACKDIR}/../KUAL/MRInstaller/extensions/MRInstaller/bin/${KINDLE_TC}/kindletool
	# Package the binaries in a tarball...
	tar --show-transformed-names --owner 0 --group 0 --transform "s,^${SVN_ROOT#*/}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/,,S" -I pigz -cvf ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/data/mrpi-${KINDLE_TC}.tar.gz ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/lib/${KINDLE_TC} ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/bin/${KINDLE_TC}
	# Clear extra binaries...
	rm -f ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/lib/${KINDLE_TC}/* ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/bin/${KINDLE_TC}/*
fi

## Build the little USBNet helper...
echo "* Building USBNet helper . . ."
echo ""
cd ..
mkdir -p usbnet_helper
cd usbnet_helper
update_title_info
${CROSS_TC}-gcc ${SVN_ROOT}/Configs/trunk/Kindle/Hacks/USBNetwork/src/kindle_usbnet_addr.c ${BASE_CFLAGS} ${BASE_LDFLAGS} -o kindle_usbnet_addr
${CROSS_TC}-strip --strip-unneeded kindle_usbnet_addr
cp kindle_usbnet_addr ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/kindle_usbnet_addr

## libpng for ImageMagick
echo "* Building libpng . . ."
echo ""
cd ..
LIBPNG_SOVER="16.34.0"
tar xvJf /usr/portage/distfiles/libpng-1.6.34.tar.xz
cd libpng-1.6.34
update_title_info
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/libpng-fix-Makefile-for-lto.patch
autoreconf -fi
# Pull our own zlib, to avoid symbol versioning issues (and enjoy better PNG compression perf)...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/linkss/lib -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --enable-shared --enable-arm-neon=yes
else
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --enable-shared
fi
make ${JOBSFLAGS}
make install
export LDFLAGS="${BASE_LDFLAGS}"
# Install shared libs...
cp ../lib/libpng16.so.${LIBPNG_SOVER} ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libpng16.so.${LIBPNG_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libpng16.so.${LIBPNG_SOVER%%.*}
# USBNet too for fbgrab...
cp ../lib/libpng16.so.${LIBPNG_SOVER} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libpng16.so.${LIBPNG_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libpng16.so.${LIBPNG_SOVER%%.*}

## libjpg-turbo for ImageMagick
echo "* Building libjpeg-turbo . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/libjpeg-turbo-1.5.1.tar.gz
cd libjpeg-turbo-1.5.1
update_title_info
patch -p1 < /usr/portage/media-libs/libjpeg-turbo/files/libjpeg-turbo-1.2.0-x32.patch
autoreconf -fi
if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --with-mem-srcdst --without-java
else
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --with-mem-srcdst --without-java --without-simd
fi
make ${JOBSFLAGS} V=1
make install

## ImageMagick for ScreenSavers
echo "* Building ImageMagick . . ."
echo ""
cd ..
# FWIW, you can pretty much use the same configure line for GraphicsMagick, although the ScreenSavers hack won't work with it.
# It doesn't appear to need the quantize patch though, it consumes a 'normal' amount of memory by default.
tar xvJf /usr/portage/distfiles/ImageMagick-6.9.6-0.tar.xz
cd ImageMagick-6.9.6-0
update_title_info
# Use the same codepath as on iPhone devices to nerf the 65MB alloc of the dither code... (We also use a quantum-depth of 8 to keep the memory usage down)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/ImageMagick-6.8.6-5-nerf-dither-mem-alloc.patch
# Pull our own zlib to avoid symbol versioning issues...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/linkss/lib"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --without-magick-plus-plus --disable-openmp --disable-deprecated --disable-installed --disable-hdri --disable-opencl --disable-largefile --with-threads --without-modules --with-quantum-depth=8 --without-perl --without-bzlib --without-x --with-zlib --without-autotrace --without-dps --without-djvu --without-fftw --without-fpx --without-fontconfig --with-freetype --without-gslib --without-gvc --without-jbig --with-jpeg --without-openjp2 --without-lcms --without-lcms2 --without-lqr --without-lzma --without-mupdf --without-openexr --without-pango --with-png --without-rsvg --without-tiff --without-webp --without-corefonts --without-wmf --without-xml
make ${JOBSFLAGS} V=1
make install
export LDFLAGS="${BASE_LDFLAGS}"
${CROSS_TC}-strip --strip-unneeded ../bin/convert
cp ../bin/convert ${BASE_HACKDIR}/ScreenSavers/src/linkss/bin/convert
cp -f ../etc/ImageMagick-6/* ${BASE_HACKDIR}/ScreenSavers/src/linkss/etc/ImageMagick-6/

## bzip2 for Python
echo "* Building bzip2 . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/bzip2-1.0.6.tar.gz
cd bzip2-1.0.6
update_title_info
patch -p0 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.4-makefile-CFLAGS.patch
patch -p0 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.6-saneso.patch
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.4-man-links.patch
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.6-progress.patch
patch -p0 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.3-no-test.patch
patch -p0 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.4-POSIX-shell.patch
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.6-mingw.patch
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/bzip2-fix-Makefile-for-lto.patch
sed -i -e 's:\$(PREFIX)/man:\$(PREFIX)/share/man:g' -e 's:ln -s -f $(PREFIX)/bin/:ln -s :' -e 's:$(PREFIX)/lib:$(PREFIX)/$(LIBDIR):g' Makefile
make ${JOBSFLAGS} CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" ${JOBSFLAGS} -f Makefile-libbz2_so all
export CFLAGS="${BASE_CFLAGS} -static"
make ${JOBSFLAGS} CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" ${JOBSFLAGS} all
export CFLAGS="${BASE_CFLAGS}"
make PREFIX="${TC_BUILD_DIR}" LIBDIR="lib" install

## libffi for Python
echo "* Building libffi . . ."
echo ""
FFI_SOVER="6.0.4"
cd ..
tar -I pigz -xvf /usr/portage/distfiles/libffi-3.2.1.tar.gz
cd libffi-3.2.1
update_title_info
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/libffi-fix-Makefile-for-lto.patch
autoreconf -fi
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared
make ${JOBSFLAGS}
make install

## ICU for SQLite
# NOTE: This works perfectly well, but with a caveat: libicudata is massive, meaning we end up with oversized packages. Besides, Amazon doesn't seem to rely on it directly through libsqlite3...
# Only do it on the K5/PW2 packages, where the size is much more manageable ;).
if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	SQLITE_WITH_ICU="true"
fi
if [[ "${SQLITE_WITH_ICU}" == "true" ]] ; then
	echo "* Building ICU . . ."
	echo ""
	ICU_SOVER="57.1"
	cd ..
	tar -I pigz -xvf /usr/portage/distfiles/icu4c-57_1-src.tgz
	cd icu/source
	update_title_info
	sed -i -e "s/#define U_DISABLE_RENAMING 0/#define U_DISABLE_RENAMING 1/" common/unicode/uconfig.h
	sed -i -e "s:LDFLAGSICUDT=-nodefaultlibs -nostdlib:LDFLAGSICUDT=:" config/mh-linux
	sed -i -e 's:icudefs.mk:icudefs.mk Doxyfile:' configure.ac
	autoreconf -fi
	# Cross-Compile fun...
	mkdir ../../icu-host
	cd ../../icu-host
	env CFLAGS="" CXXFLAGS="" ASFLAGS="" LDFLAGS="" CC="gcc" CXX="g++" AR="ar" RANLIB="ranlib" NM="nm" LD="ld" ../icu/source/configure --disable-renaming --disable-debug --disable-samples --enable-static
	# NOTE: Don't care about verbose output for the host build ;).
	make ${JOBSFLAGS}
	cd -
	# ICU tries to use clang by default
	export CC="${CROSS_TC}-gcc"
	export CXX="${CROSS_TC}-g++"
	export LD="${CROSS_TC}-ld"
	# Use C++11
	export CXXFLAGS="${BASE_CFLAGS} -std=gnu++11"
	# Setup our Python rpath, plus a static lstdc++, since we pull CXXABI_1.3.8, which is too new for even the K5...
	export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/python/lib -static-libstdc++"
	# Huh. Why this only shows up w/ LTO is a mystery...
	export ac_cv_c_bigendian=no
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --disable-renaming --disable-samples --disable-debug --with-cross-build="${TC_BUILD_DIR}/icu-host"
	make ${JOBSFLAGS} VERBOSE=1
	make install
	unset ac_cv_c_bigendian
	export LDFLAGS="${BASE_LDFLAGS}"
	export CXXFLAGS="${BASE_CFLAGS}"
	unset LD
	unset CXX
	unset CC
	cd ..
fi

## Readline for SQLite & Python
echo "* Building Readline . . ."
echo ""
READLINE_SOVER="6.3"
READLINE_PATCHLVL="8"
cd ..
tar -I pigz -xvf /usr/portage/distfiles/readline-${READLINE_SOVER}.tar.gz
cd readline-${READLINE_SOVER}
update_title_info
for patch in $(seq 1 ${READLINE_PATCHLVL}) ; do
	patch_file="readline${READLINE_SOVER//.}-$(printf "%03d" ${patch})"
	patch -p0 < /usr/portage/distfiles/${patch_file}
done
patch -p0 < /usr/portage/sys-libs/readline/files/readline-5.0-no_rpath.patch
patch -p1 < /usr/portage/sys-libs/readline/files/readline-6.2-rlfe-tgoto.patch
patch -p1 < /usr/portage/sys-libs/readline/files/readline-6.3-fix-long-prompt-vi-search.patch
patch -p2 < /usr/portage/sys-libs/readline/files/readline-6.3-read-eof.patch
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/readline-fix-Makefile-for-lto.patch
ncurses_libs="$(pkg-config ncurses --libs)"
sed -e "/^SHLIB_LIBS=/s:=.*:='${ncurses_libs}':" -i support/shobj-conf
sed -e "/^[[:space:]]*LIBS=.-lncurses/s:-lncurses:${ncurses_libs}:" -i examples/rlfe/configure
unset ncurses_libs
sed -e '/objformat/s:if .*; then:if true; then:' -i support/shobj-conf
ln -s ../.. examples/rlfe/readline
export CPPFLAGS="${BASE_CPPFLAGS} -D_GNU_SOURCE -Dxrealloc=_rl_realloc -Dxmalloc=_rl_malloc -Dxfree=_rl_free"
export ac_cv_prog_AR=${CROSS_TC}-gcc-ar
export ac_cv_prog_RANLIB=${CROSS_TC}-gcc-ranlib
export ac_cv_prog_NM=${CROSS_TC}-gcc-nm
export bash_cv_termcap_lib=ncurses
export bash_cv_func_sigsetjmp='present'
export bash_cv_func_ctype_nonascii='yes'
export bash_cv_wcwidth_broken='no'
# Setup an rpath to make sure it won't pick-up a weird ncurses lib...
export LDFLAGS="${BASE_LDFLAGS} -L. -Wl,-rpath=${DEVICE_USERSTORE}/python/lib"
# NOTE: Never honor INPUTRC env var, always use our own. The Kindle sets this, and the system one has some weird bindings that make Python & SQLite's CLI flash in some instances.
sed -e "s#sh_get_env_value (\"INPUTRC\");#\"${DEVICE_USERSTORE}/usbnet/etc/inputrc\";#" -i bind.c
# And ship Gentoo's inputrc, which is pretty tame & sane.
cp -f /etc/inputrc ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/inputrc
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --cache-file="${PWD}/config.cache" --with-curses
# Never try to use /etc/inputrc, even as a last resort
sed -e "s#\"/etc/inputrc\"#\"${DEVICE_USERSTORE}/usbnet/etc/inputrc\";#" -i rlconf.h
make ${JOBSFLAGS}
make install
export LDFLAGS="${BASE_LDFLAGS}"
unset bash_cv_wcwidth_broken
unset bash_cv_func_ctype_nonascii
unset bash_cv_func_sigsetjmp
unset bash_cv_termcap_lib
unset ac_cv_prog_NM
unset ac_cv_prog_RANLIB
unset ac_cv_prog_AR
export CPPFLAGS="${BASE_CPPFLAGS}"

## SQLite3, amalgam
echo "* Building SQLite3 . . ."
echo ""
SQLITE_SOVER="0.8.6"
SQLITE_VER="3140200"
cd ..
#wget https://sqlite.org/2015/sqlite-autoconf-${SQLITE_VER}.tar.gz -O sqlite-autoconf-${SQLITE_VER}.tar.gz
#tar -I pigz -xvf sqlite-autoconf-${SQLITE_VER}.tar.gz
tar -I pigz -xvf /usr/portage/distfiles/sqlite-autoconf-${SQLITE_VER}.tar.gz
cd sqlite-autoconf-${SQLITE_VER}
update_title_info
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/sqlite-fix-Makefile-for-lto.patch
# Enable some extra features...
export CPPFLAGS="${BASE_CPPFLAGS} -DNDEBUG -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_RTREE -DSQLITE_SOUNDEX -DSQLITE_ENABLE_UNLOCK_NOTIFY"
if [[ "${SQLITE_WITH_ICU}" == "true" ]] ; then
	export CPPFLAGS="${CPPFLAGS} -DSQLITE_ENABLE_ICU"
	# Need to tweak that a bit to link properly against ICU...
	sed -e "s/LIBS = @LIBS@/& -licui18n -licuuc/" -i Makefile.in
fi
# Setup our Python rpath.
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/python/lib"
# SQLite doesn't want to be built w/ -ffast-math...
export CFLAGS="${BASE_CFLAGS/-ffast-math /}"
# NOTE: We need a static lib on Kobos for KFMon :).
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --enable-shared --enable-threadsafe --enable-dynamic-extensions --enable-readline --enable-fts5 --enable-json1
else
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --enable-threadsafe --enable-dynamic-extensions --enable-readline --enable-fts5 --enable-json1
fi
# FIXME: libtool is sometimes being stupid w/ parallel make... Since it's an agglo anyway, we're not losing much by disabling parallel make...
make -j1
make install
export CFLAGS="${BASE_CFLAGS}"
export LDFLAGS="${BASE_LDFLAGS}"
export CPPFLAGS="${BASE_CPPFLAGS}"

## Python for ScreenSavers
PYTHON_CUR_VER="2.7.12"
echo "* Building Python . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/Python-${PYTHON_CUR_VER}.tar.xz
cd Python-${PYTHON_CUR_VER}
update_title_info
rm -fr Modules/expat
rm -fr Modules/_ctypes/libffi*
rm -fr Modules/zlib
tar xvJf /usr/portage/distfiles/python-gentoo-patches-${PYTHON_CUR_VER}-0.tar.xz
# NOTE: The ebuild blacklists '*_regenerate_platform-specific_modules.patch' when cross-compiling, which is a good idea if the host's python version doesn't match...
# I'm still using 2.7 as default, so I can get away with keeping it enabled.
for patchfile in patches/* ; do
	# Try to detect if we need p0 or p1...
	if grep 'diff --git' "${patchfile}" &>/dev/null ; then
		echo "Applying ${patchfile} w/ p1 . . ."
		patch -p1 < ${patchfile}
	else
		echo "Applying ${patchfile} w/ p0 . . ."
		patch -p0 < ${patchfile}
	fi
done
# Adapted from Gentoo's 2.7.3 cross-compile patchset. There's some fairly ugly and unportable hacks in there, because for the life of me I can't figure out how the cross-compile support merged in 2.7.4 is supposed to take care of some stuff... (namely, pgen & install)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/python-2.7.12-cross-compile.patch
# Gentoo Patches...
patch -p1 < /usr/portage/dev-lang/python/files/python-2.7.9-ncurses-pkg-config.patch
patch -p1 < /usr/portage/dev-lang/python/files/python-2.7.10-cross-compile-warn-test.patch
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/python-fix-Makefile-for-lto.patch
sed -i -e "s:@@GENTOO_LIBDIR@@:lib:g" Lib/distutils/command/install.py Lib/distutils/sysconfig.py Lib/site.py Lib/sysconfig.py Lib/test/test_site.py Makefile.pre.in Modules/Setup.dist Modules/getpath.c setup.py
# Fix building against a static OpenSSL... (depends on zlib)
sed -e "s/\['ssl', 'crypto'\]/\['ssl', 'crypto', 'z'\]/g" -i setup.py
if [[ "${SQLITE_WITH_ICU}" == "true" ]] ; then
	# Make sure SQLite picks up ICU properly...
	sed -e 's/\["sqlite3",\]/\["sqlite3", "icui18n", "icuuc",\]/g' -i setup.py
fi
# Bzip2 needs to be PIC (compile/link time match w/ LTO)
sed -e "s/bz2_extra_link_args = ()/bz2_extra_link_args = ('-fPIC',)/" -i setup.py
# Fix building with Python 3 as the default Python interpreter...
sed -e 's#python$EXE#python2$EXE#' -i Lib/plat-linux2/regen
autoreconf -fi

# Note that curses needs ncursesw, which doesn't ship on every Kindle, so we ship our own. Same deal for readline.
export PYTHON_DISABLE_MODULES="dbm _bsddb gdbm _tkinter"
export CFLAGS="${BASE_CFLAGS} -fwrapv"
# Apparently, we need -I here, or Python cannot find any our our stuff...
export CPPFLAGS="${BASE_CPPFLAGS/-isystem/-I}"

# How fun is it to cross-compile stuff? >_<"
# NOTE: We're following the Gentoo ebuild, so, set the vars up the Gentoo way
# What we're building on
export CBUILD="$(uname -m)-pc-linux-gnu"
# What we're building for
export CHOST="${CROSS_TC}"
mkdir -p {${CBUILD},${CHOST}}
cd ${CBUILD}
OPT="-O1" CFLAGS="" CPPFLAGS="" LDFLAGS="" CC="" AR="" RANLIB="" NM="" ../configure --{build,host}=${CBUILD}
cd ..

# The configure script assumes it's buggy when cross-compiling.
export ac_cv_buggy_getaddrinfo=no
export ac_cv_have_long_long_format=yes
export ac_cv_file__dev_ptmx=yes
export ac_cv_file__dev_ptc=no
# Would probably need a custom zoneinfo directory...
#export ac_cv_working_tzset=yes
export _PYTHON_HOST_PLATFORM="linux-arm"
export PYTHON_FOR_BUILD="./hostpython"
export PGEN_FOR_BUILD="./Parser/hostpgen"
export CC="${CROSS_TC}-gcc"
export CXX="${CROSS_TC}-g++"
# Huh. For some reason, adding --static here breaks it... (Well, it's not useful here anyway, but, still...)
export ac_cv_path_PKG_CONFIG="pkg-config"
# Setup an rpath since we use a shared libpython to be able to build third-party modules...
export LDFLAGS="${BASE_LDFLAGS} -L. -Wl,-rpath=${DEVICE_USERSTORE}/python/lib"
# FIXME: Currently fails to build w/ LTO (bad instruction: fldcw [sp,#6] & fnstcw [sp,#6])... (Linaro GCC 5.2 2015.09 & binutils 2.25.1)
#        Those are x86 instructions, so, WTH?
#if [[ "${CFLAGS}" != "${NOLTO_CFLAGS}" ]] ; then
#	temp_nolto="true"
#	export CFLAGS="${NOLTO_CFLAGS}"
#fi
cd ${CHOST}
# NOTE: Enable the shared library to be able to compile third-party C modules...
OPT="" ../configure --prefix=${TC_BUILD_DIR}/python --build=${CBUILD} --host=${CROSS_TC} --enable-static --enable-shared --with-fpectl --disable-ipv6 --with-threads --enable-unicode=ucs4 --with-computed-gotos --with-libc="" --enable-loadable-sqlite-extensions --with-system-expat --with-system-ffi
# More cross-compile hackery...
sed -i -e '1iHOSTPYTHONPATH = ./hostpythonpath' -e '/^PYTHON_FOR_BUILD/s:=.*:= ./hostpython:' -e '/^PGEN_FOR_BUILD/s:=.*:= ./Parser/hostpgen:' Makefile{.pre,}
cd ..

cd ${CBUILD}
# Disable as many modules as possible -- but we need a few to install.
PYTHON_DISABLE_MODULES=$(sed -n "/Extension('/{s:^.*Extension('::;s:'.*::;p}" ../setup.py | egrep -v '(unicodedata|time|cStringIO|_struct|binascii)') PYTHON_DISABLE_SSL="1" SYSROOT= make ${JOBSFLAGS}
ln python ../${CHOST}/hostpython
ln Parser/pgen ../${CHOST}/Parser/hostpgen
ln -s ../${CBUILD}/build/lib.*/ ../${CHOST}/hostpythonpath
cd ..

# Fallback to a sane PYTHONHOME, so we don't necessarily have to set PYTHONHOME in our env...
# NOTE: We only patch the CHOST build, because this fallback is Kindle-centric, and would break the build if used for the CBUILD Python ;)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/python-2.7.5-kindle-pythonhome-fallback.patch
# Fix userstore path on Kobos...
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	sed -e "s#/mnt/us#${DEVICE_USERSTORE}#g" -i Python/pythonrun.c
fi
cd ${CHOST}
# Hardcode PYTHONHOME so we don't have to tweak our env... (NOTE: Now handled in a slightly more elegant/compatible way in a patch)
#sed -e 's#static char \*default_home = NULL;#static char \*default_home = "/mnt/us/python";#' -i ../Python/pythonrun.c
make ${JOBSFLAGS}
make altinstall
cd ..

# NOTE: Re-enable LTO if need be
if [[ "${temp_nolto}" == "true" ]] ; then
	unset temp_nolto
	export CFLAGS="${BASE_CFLAGS}"
fi
export LDFLAGS="${BASE_LDFLAGS}"
unset ac_cv_path_PKG_CONFIG
unset CXX
unset CC
unset PGEN_FOR_BUILD
unset PYTHON_FOR_BUILD
unset _PYTHON_HOST_PLATFORM
unset ac_cv_file__dev_ptc
unset ac_cv_file__dev_ptmx
unset ac_cv_have_long_long_format
unset ac_cv_buggy_getaddrinfo
#unset ac_cv_working_tzset
unset CHOST
unset CBUILD
export CPPFLAGS="${BASE_CPPFLAGS}"
export CFLAGS="${BASE_CFLAGS}"
unset PYTHON_DISABLE_MODULES

# Bundle some third-party modules...
cd ..
## NOTE: Usig the host's real Python install is hackish, but our hostpython might not have enough modules built to handle everything... Here's how it should have been called, though:
# env PYTHONPATH="${TC_BUILD_DIR}/Python-${PYTHON_CUR_VER}/${CROSS_TC}/hostpythonpath" ../Python-${PYTHON_CUR_VER}/${CROSS_TC}/hostpython
## Requests
rm -rf requests
until git clone https://github.com/kennethreitz/requests.git ; do
	rm -rf requests
	sleep 15
done
cd requests
update_title_info
python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --install-lib=lib/python2.7/site-packages --no-compile
cd ..
## Unidecode
rm -rf unidecode
if git clone http://www.tablix.org/~avian/git/unidecode.git ; then
	cd unidecode
else
	# NOTE: If domain is down, use the latest PyPi release...
	rm -rf Unidecode-0.04.19
	wget https://pypi.python.org/packages/source/U/Unidecode/Unidecode-0.04.19.tar.gz
	tar -I pigz -xvf Unidecode-0.04.19.tar.gz
	cd Unidecode-0.04.19
fi
update_title_info
python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --install-lib=lib/python2.7/site-packages --no-compile
cd ..
## pycparser for CFFI
rm -rf pycparser
until git clone https://github.com/eliben/pycparser.git ; do
	rm -rf pycparser
	sleep 15
done
cd pycparser
update_title_info
python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --install-lib=lib/python2.7/site-packages --no-compile
cd ..
## CFFI
rm -rf cffi
hg clone https://bitbucket.org/cffi/cffi
cd cffi
update_title_info
# NOTE: This is hackish. If the host's Python doesn't exactly match, here be dragons.
# We're using https://pypi.python.org/pypi/distutilscross to soften some of the sillyness, but it's still a pile of dominoes waiting to fall...
#env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" CFLAGS="${BASE_CFLAGS} -I${TC_BUILD_DIR}/python/include/python2.7" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --no-compile
env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/python" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py build -x
env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/python" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --install-lib=lib/python2.7/site-packages --no-compile
cd ..
## SimpleJSON
rm -rf simplejson
until git clone https://github.com/simplejson/simplejson.git ; do
	rm -rf simplejson
	sleep 15
done
cd simplejson
update_title_info
#env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" CFLAGS="${BASE_CFLAGS} -I${TC_BUILD_DIR}/python/include/python2.7" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --no-compile
env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/python" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py build -x
env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/python" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --install-lib=lib/python2.7/site-packages --no-compile
cd ..

cd Python-${PYTHON_CUR_VER}

# Don't forget libffi ;)
cp ../lib/libffi.so.${FFI_SOVER} ../python/lib/libffi.so.${FFI_SOVER%%.*}
# We're gonna need our shared libs... (expat because the one on the Kindle is too old, zlib to avoid symbol versioning issues, ncursesw & readline for the CLI)
cp ../lib/libexpat.so.${EXPAT_SOVER} ../python/lib/libexpat.so.${EXPAT_SOVER%%.*}
cp ../lib/libz.so.${ZLIB_SOVER} ../python/lib/libz.so.${ZLIB_SOVER%%.*}
cp ../lib/libncurses.so.${NCURSES_SOVER} ../python/lib/libncurses.so.${NCURSES_SOVER%%.*}
cp ../lib/libncursesw.so.${NCURSES_SOVER} ../python/lib/libncursesw.so.${NCURSES_SOVER%%.*}
cp ../lib/libpanel.so.${NCURSES_SOVER} ../python/lib/libpanel.so.${NCURSES_SOVER%%.*}
cp ../lib/libpanelw.so.${NCURSES_SOVER} ../python/lib/libpanelw.so.${NCURSES_SOVER%%.*}
cp ../lib/libreadline.so.${READLINE_SOVER} ../python/lib/libreadline.so.${READLINE_SOVER%%.*}
chmod -cvR ug+w ../python/lib/libreadline.so.${READLINE_SOVER%%.*}
# And OpenSSL because of the 0.9.8/1.0.0 switcheroo...
if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	for my_lib in libcrypto.so.1.0.0 libssl.so.1.0.0 ; do
		cp ../lib/${my_lib} ../python/lib/${my_lib}
		chmod -cvR ug+w ../python/lib/${my_lib}
	done
else
	for my_lib in libcrypto.so.0.9.8 libssl.so.0.9.8 ; do
		cp ../lib/${my_lib} ../python/lib/${my_lib}
		chmod -cvR ug+w ../python/lib/${my_lib}
	done
fi
if [[ "${SQLITE_WITH_ICU}" == "true" ]] ; then
	# We're going to need our ICU shared libs...
	for my_icu_lib in libicudata libicui18n libicuuc ; do
		cp ../lib/${my_icu_lib}.so.${ICU_SOVER} ../python/lib/${my_icu_lib}.so.${ICU_SOVER%%.*}
	done
fi
# And SQLite, too...
cp ../lib/libsqlite3.so.${SQLITE_SOVER} ../python/lib/libsqlite3.so.${SQLITE_SOVER%%.*}
# Keep our own sqlite3 CLI, for shit'n giggles
cp ../bin/sqlite3 ../python/bin/sqlite3

# And now, clean it up, to try to end up with the smallest install package possible...
sed -e "s/\(LDFLAGS=\).*/\1/" -i "../python/lib/python2.7/config/Makefile"
# First, strip...
chmod a+w ../python/lib/libpython2.7.a
${CROSS_TC}-strip --strip-unneeded ../python/lib/libpython2.7.a
chmod a-w ../python/lib/libpython2.7.a
chmod a+w ../python/lib/libpython2.7.so.1.0
find ../python -name '*.so*' -exec ${CROSS_TC}-strip --strip-unneeded {} +
chmod a-w ../python/lib/libpython2.7.so.1.0
${CROSS_TC}-strip --strip-unneeded ../python/bin/python2.7 ../python/bin/sqlite3
# Assume we're only ever going to need the shared libpython...
rm -rf ../python/lib/libpython2.7.a
# The DT_NEEDED entries all appear to point to the shared library w/ the full sover, kill the short symlink, since we can't use it on vfat as-is...
rm -rf ../python/lib/libpython2.7.so
# Next, kill a bunch of stuff we don't care about...
rm -rf ../python/lib/pkgconfig ../python/share
# Kill the symlinks we can't use on vfat anyway...
find ../python -type l -delete
# And now, do the same cleanup as the Gentoo ebuild...
rm -rf ../python/lib/python2.7/{bsddb,dbhash.py,test/test_bsddb*}
rm -rf ../usr/bin/idle2.7 ../python/lib/python2.7/{idlelib,lib-tk}
rm -f ../python/lib/python2.7/distutils/command/wininst-*.exe
# And the big one, kill bytecode (we'll rebuild it during install on the Kindle)
while read -d $'\0' -r file; do
	files+=("${file}")
done < <(find "../python" "(" -name "*.py[co]" -o -name "*\$py.class" ")" -type f -print0)
if [[ "${#files[@]}" -gt 0 ]]; then
	echo "Deleting byte-compiled Python modules needlessly generated by build system:"
	for file in "${files[@]}"; do
		echo " ${file}"
		rm -f "${file}"

		if [[ "${file%/*}" == *"/__pycache__" ]]; then
			rmdir "${file%/*}" 2> /dev/null
		fi
	done
fi

if [[ -d "../python/lib/python2.7/site-packages" ]]; then
	find "../python/lib/python2.7/site-packages" "(" -name "*.c" -o -name "*.h" -o -name "*.la" ")" -type f -print0 | xargs -0 rm -f
fi
unset file files
# Fix some shebangs to use the target prefix, not the one from my host...
sed -e "s#${TC_BUILD_DIR}/#${DEVICE_USERSTORE}/#" -i ../python/bin/idle ../python/bin/smtpd.py ../python/bin/python2.7-config ../python/bin/pydoc ../python/bin/2to3
# And finally, build our shiny tarball
cd ..
tar -cvJf python.tar.xz python
cp -f python.tar.xz ${BASE_HACKDIR}/Python/src/python.tar.xz
cd -
# NOTE: Might need to use the terminfo DB from usbnet to make the interpreter UI useful: export TERMINFO=${DEVICE_USERSTORE}/usbnet/etc/terminfo

## inotify-tools for ScreenSavers on the K2/3/4
echo "* Building inotify-tools . . ."
echo ""
cd ..
rm -rf inotify-tools
until git clone https://github.com/rvoicilas/inotify-tools.git ; do
	rm -rf inotify-tools
	sleep 15
done
cd inotify-tools
update_title_info
# Kill -Werror, it whines about _GNU_SOURCE on the K3...
sed -e 's/-Wall -Werror/-Wall/' -i src/Makefile.am
./autogen.sh
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared
make ${JOBSFLAGS}
make install
${CROSS_TC}-strip --strip-unneeded ../bin/inotifywait
cp ../bin/inotifywait ${BASE_HACKDIR}/ScreenSavers/src/linkss/bin/inotifywait

## Building libpcre for zsh (& glib)
echo "* Building libpcre . . ."
echo ""
cd ..
tar -I lbzip2 -xvf /usr/portage/distfiles/pcre-8.39.tar.bz2
cd pcre-8.39
update_title_info
echo "Libs.private: @PTHREAD_CFLAGS@" >> libpcrecpp.pc.in
sed -e "s:-lpcre ::" -i libpcrecpp.pc.in
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/pcre-fix-Makefile-for-lto.patch
autoreconf -fi
libtoolize
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared --enable-static --with-match-limit-recursion=8192 --disable-cpp --enable-jit --enable-utf --enable-unicode-properties --enable-pcre8
make ${JOBSFLAGS} V=1
make install
export LDFLAGS="${BASE_LDFLAGS}"
cp ../lib/libpcre.so.1.2.7 ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libpcre.so.1
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libpcre.so.1
cp ../lib/libpcreposix.so.0.0.4 ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libpcreposix.so.0
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libpcreposix.so.0

## sshfs for USBNet (Build it at the end, I don't want glib to be automagically pulled by something earlier...)
#
# Depends on glib
echo "* Building glib . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/glib-2.48.0.tar.xz
cd glib-2.48.0
update_title_info
sed -i -e 's/ tests//' {.,gio,glib}/Makefile.am
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/glib-fix-Makefile-for-lto.patch
autoreconf -fi
# Cf. https://developer.gnome.org/glib/stable/glib-cross-compiling.html
export glib_cv_stack_grows=no
export glib_cv_uscore=yes
export ac_cv_func_posix_getpwuid_r=yes
export ac_cv_func_posix_getgrgid_r=yes
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --disable-libelf --disable-selinux --disable-compile-warnings --with-pcre=system --with-threads=posix
make ${JOBSFLAGS} V=1
make install
unset glib_cv_stack_grows glib_cv_uscore ac_cv_func_posix_getpwuid_r c_cv_func_posix_getgrgid_r

# And of course FUSE ;)
echo "* Building fuse . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/fuse-2.9.7.tar.gz
cd fuse-2.9.7
update_title_info
patch -p1 < /usr/portage/sys-fs/fuse/files/fuse-2.9.3-kernel-types.patch
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} INIT_D_PATH=${TC_BUILD_DIR}/etc/init.d MOUNT_FUSE_PATH=${TC_BUILD_DIR}/sbin UDEV_RULES_PATH=${TC_BUILD_DIR}/etc/udev/rules.d --enable-shared=no --enable-static=yes --disable-example
make ${JOBSFLAGS} V=1
make install

# And finally sshfs
echo "* Building sshfs . . ."
echo ""
cd ..
rm -rf sshfs
until git clone https://github.com/libfuse/sshfs.git ; do
	rm -rf sshfs
	sleep 15
done
cd sshfs
update_title_info
# We don't have ssh in $PATH, call our own
sed -e "s#ssh_add_arg(\"ssh\");#ssh_add_arg(\"${DEVICE_USERSTORE}/usbnet/bin/ssh\");#" -i ./sshfs.c
# Same for sftp-server
sed -e "s#\"/usr/lib/sftp-server\"#\"${DEVICE_USERSTORE}/usbnet/libexec/sftp-server\"#" -i ./sshfs.c
autoreconf -fi
# Static libfuse...
env PKG_CONFIG="pkg-config --static" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-sshnodelay
make ${JOBSFLAGS}
make install
${CROSS_TC}-strip --strip-unneeded ../bin/sshfs
cp ../bin/sshfs ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/sshfs


# Build gawk for KUAL
echo "* Building gawk . . ."
echo ""
cd ..
rm -rf gawk
until git clone git://git.savannah.gnu.org/gawk.git ; do
	rm -rf gawk
	sleep 15
done
cd gawk
update_title_info
./bootstrap.sh
# LTO makefile compat...
# NOTE: sed -e 's/--mode=link $(CCLD) $(AM_CFLAGS) $(CFLAGS)/--mode=link $(CCLD) $(AM_CFLAGS) $(CFLAGS) $(XC_LINKTOOL_CFLAGS)/g' -i extension/Makefile.in
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/gawk-fix-Makefile-for-lto.patch
sed -i -e '/^LN =/s:=.*:= $(LN_S):' -e '/install-exec-hook:/s|$|\nfoo:|' Makefile.in doc/Makefile.in
sed -i '/^pty1:$/s|$|\n_pty1:|' test/Makefile.in
# Awful hack to allow closing stdout, so that we don't block KUAL on cache hits...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/gawk-4.1.0-allow-closing-stdout.patch
export ac_cv_libsigsegv=no
# Setup an rpath for the extensions...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/extensions/gawk/lib/gawk"
# FIXME: I'm guessing the old glibc somehow doesn't play nice with GCC, and stddef.h gets confused, but this is *very* weird.
# So, here goes an ugly workaround to get a ptrdiff_t typedef on time...
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	export CPPFLAGS="${BASE_CPPFLAGS} -D__need_ptrdiff_t"
fi
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-nls --without-readline
# Don't call the just-built binary...
sed -e 's#../gawk$(EXEEXT)#gawk#' -i extension/Makefile
make ${JOBSFLAGS}
make install
unset ac_cv_libsigsegv
export LDFLAGS="${BASE_LDFLAGS}"
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	export CPPFLAGS="${BASE_CPPFLAGS}"
fi
${CROSS_TC}-strip --strip-unneeded ../bin/gawk
${CROSS_TC}-strip --strip-unneeded ../lib/gawk/*.so
# Bundle it up...
tar -I pigz -cvf gawk-${KINDLE_TC}.tar.gz ../lib/gawk/*.so ../bin/gawk
# Chuck it w/ USBNet on Kobo...
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	cp gawk-${KINDLE_TC}.tar.gz ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/
else
	cp gawk-${KINDLE_TC}.tar.gz ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/gawk/extensions/gawk/data/
fi

# Build FBGrab
echo "* Building fbgrab . . ."
echo ""
cd ..
cp -av ${SVN_ROOT}/Configs/trunk/Kindle/Misc/FBGrab FBGrab
cd FBGrab
update_title_info
# Pull our own zlib to avoid symbol versioning issues (and enjoy better PNG compression perf)...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
make ${JOBSFLAGS} CC=${CROSS_TC}-gcc
${CROSS_TC}-strip --strip-unneeded fbgrab
cp fbgrab ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/fbgrab
export LDFLAGS="${BASE_LDFLAGS}"

# strace & ltrace
# FIXME: Craps out w/ Linaro GCC 5.3 2016.01/2016.02/2016.03 on Thumb2 TCs (i.e., everything except K3)
#	(selected processor does not support ARM mode cbnz) w/ Linaro GCC 5.3 2016.03 & binutils 2.26
# NOTE: Has been fixed by FSF right after the 2016.03 release. Meaning it works w/ >= 2016.04 :)
if is_ver_gte "$(${CROSS_TC}-gcc -dumpversion)" "5.3" && [[ "$(${CROSS_TC}-gcc -v 2>&1 | tail -n 1 | sed -re "s/^(gcc version)([[:blank:]])([[:digit:]\.]*)([[:blank:]])([[:digit:]]*)(.*?)$/\5/")" -lt "20160412" ]] ; then
	echo "* Skipping libunwind, it's currently broken w/ GCC 5.3 older than 2016.04 . . ."
	echo ""
else
	# libunwind for strace
	echo "* Building libunwind . . ."
	echo ""
	UNWIND_SOVER="8.0.1"
	cd ..
	rm -rf libunwind
	# Go with git because the latest release is ancient
	until git clone git://git.savannah.gnu.org/libunwind.git libunwind ; do
		rm -rf libunwind
		sleep 15
	done
	cd libunwind
	update_title_info
	# LTO makefile compat...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/libunwind-fix-Makefile-for-lto.patch
	env NOCONFIGURE=1 ./autogen.sh
	# Setup an rpath, since it's a modular library
	export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared --enable-static --enable-cxx-exceptions
	make ${JOBSFLAGS}
	make install
	export LDFLAGS="${BASE_LDFLAGS}"
	# We'll need that...
	cp ../lib/libunwind-ptrace.so.0.0.0 ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libunwind-ptrace.so.0
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libunwind-ptrace.so.0
	for my_lib in libunwind-arm libunwind  ; do
		cp ../lib/${my_lib}.so.${UNWIND_SOVER} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${my_lib}.so.${UNWIND_SOVER%%.*}
		${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${my_lib}.so.${UNWIND_SOVER%%.*}
	done
fi

echo "* Building strace . . ."
echo ""
cd ..
rm -rf strace
until git clone git://git.code.sf.net/p/strace/code strace ; do
	rm -rf strace
	sleep 15
done
cd strace
update_title_info
# Regen the ioctl list...
if [[ "${KINDLE_TC}" == "PW2" ]] ; then
	# NOTE: As usual, the kernel tarball is mangled/incomplete...  Import <linux/lab126_touch.h> from the 5.6.1.0.6 package (5.6.2.1 appears to be sane too, FWIW)...
	# cp -av {5.6.1.0.6,5.6.5}/gplrelease/linux/include/linux/lab126_touch.h
	ksrc="${HOME}/Kindle/SourceCode_Packages/5.6.5/gplrelease/linux"
	asrc="${ksrc}/arch/arm/include"
elif [[ "${KINDLE_TC}" == "K5" ]] ; then
	# NOTE: Don't move to 5.6.1.1, it ships includes for the updated eink driver, but that doesn't match the actual binaries on prod in 5.6.1.1 on the PW1...
	# We'd need a custom mxcfb.h header like on KOReader to handle this properly if the PW1 ever actually inherits the updated driver...
	ksrc="${HOME}/Kindle/SourceCode_Packages/5.4.4.2/gplrelease/linux"
	asrc="${ksrc}/arch/arm/include"
elif [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	ksrc="${HOME}/Kindle/SourceCode_Packages/Kobo-H2O/linux-2.6.35.3"
	asrc="${ksrc}/arch/arm/include"
else
	ksrc="${HOME}/Kindle/SourceCode_Packages/3.4.2/gplrelease/linux/linux-2.6.26"
	asrc="${ksrc}/include/asm-arm"
fi
# NOTE: Fix the permissions after unpacking, they're sometimes wonky...
# s chown -cvR ${UID}:${GID} "${ksrc}" && s chmod -cvR ug+rX "${ksrc}"

# NOTE: The K3 kernel is too old for strace's scripts to handle properly, even from the the sanitized Kernel headers...
# cd "${ksrc}" && sed -e 's/getline/get_line/g' -i scripts/unifdef.c && make headers_install SRCARCH=arm && cd -
# Faking the directory structure doesn't help either...
# cd "${ksrc}" && ln -sf ../../include/asm-arm arch/arm/include && ln -sf ../include/asm-arm include/asm && cd -
#
## NOTE: The new ioctl parsing handling isn't made for handling ancient kernels, and is already a mess to use with custom ones.
## Just forget about it, and use the last commit before everything went kablooey on the K3.
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	git checkout 6f9a01c72121bc0b0fc760d9fea6879fb85f6f02
	sh ./linux/ioctlent.sh ${ksrc}/include ${asrc}
	gcc -Wall -I. ioctlsort.c -o ioctlsort
	./ioctlsort > ioctlent.h
	mv -fv ioctlent.h linux/ioctlent.h.in
else
	# NOTE: Comment out some stuff not found in our ancient kernels to avoid build failures...
	#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-ancient-kernel-compat.patch
	# Clear CFLAGS to avoid passing ARM flags to our host's compiler...
	unset CFLAGS
	# NOTE: We have to use the host's compiler, since the scripts need to run the output... This isn't optimal in our cross-compilation case...
	# Avoid bitness weirdness by making sure we at least match the bitness of our target... (Fixes MXCFB_SEND_UPDATE mismatch on Kobos, for instance).
	if [[ "$(uname -m)" == "x86_64" ]] ; then
		export CFLAGS="-Wall -O2 -m32"
		export LDFLAGS="-m32"
	fi
	# /tmp is noeexec....
	mkdir -p tmp
	export TMPDIR="${PWD}/tmp"
	# Some more ugly workarounds for the positively wierd & ancient kernels used....
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-ioctls_sym-tweaks.patch
	sh ./maint/ioctls_gen.sh ${ksrc}/include ${asrc}
	gcc -Wall -I. ioctlsort.c -o ioctlsort
	./ioctlsort > ioctlent0.h
	export LDFLAGS="${BASE_LDFLAGS}"
	export CFLAGS="${BASE_CFLAGS}"
	unset TMPDIR
	# Copy mxcfb from the Amazon/Kobo sources, since we're building against a vanilla Kernel, and we'll need this include for the ioctl decoding patch...
	if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
		cp -v ${ksrc}/include/linux/mxcfb.h linux/mxcfb.h
	fi
	unset ksrc asrc
	# Apply the ioctl decode patch for our TC. Based on https://gist.github.com/erosennin/593de363a4361411cd4f (erosennin's patch for https://github.com/koreader/koreader/issues/741) ;).
	if [[ "${KINDLE_TC}" == "K5" ]] ; then
		patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-mxcfb-ioctls-k5.patch
	elif [[ "${KINDLE_TC}" == "PW2" ]] ; then
		patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-mxcfb-ioctls-pw2.patch
	elif [[ "${KINDLE_TC}" == "KOBO" ]] ; then
		patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-mxcfb-ioctls-kobo.patch
	fi
	# NOTE: Our kernel headers are old and possibly not all that sane, and strace doesn't always cover all bases in these cases...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-old-kernels-compat.patch
fi

# And build
./bootstrap
# <linux/types.h> is too old on this kernel...
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	sed -re 's/(#include <linux\/types.h>)/\1\n\n#define __aligned_u64 __u64 __attribute__\(\(aligned\(8\)\)\)/' -i linux/fanotify.h
fi
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
# NOTE: Don't try to build with libunwind support when we didn't build it... (cf. previous FIXME about libunwind on GCC 5.3 < 2016.04)
if [[ -f "../lib/libunwind-ptrace.so.0.0.0" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --with-libunwind
else
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --without-libunwind
fi
make ${JOBSFLAGS}
make install
export LDFLAGS="${BASE_LDFLAGS}"
${CROSS_TC}-strip --strip-unneeded ../bin/strace
cp ../bin/strace ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/strace

# ltrace depends on elfutils
# FIXME: readelf relies on qsort_r, which was introduced in glibc 2.8... That obviously doesn't fly for the K3...
echo "* Building elfutils . . ."
echo ""
cd ..
ELFUTILS_VERSION="0.166"
tar -I lbzip2 -xvf /usr/portage/distfiles/elfutils-${ELFUTILS_VERSION}.tar.bz2
cd elfutils-${ELFUTILS_VERSION}
#sed -i -e '/^lib_LIBRARIES/s:=.*:=:' -e '/^%.os/s:%.o$::' lib{asm,dw,elf}/Makefile.in
sed -i 's:-Werror::' */Makefile.in
# Avoid PIC/TEXTREL issue w/ LTO... (NOTE: Not enough, symbol versioning issues or even weirder crap)
#for my_dir in libasm backends libelf libdw src ; do
#	sed -e 's/$(LINK) -shared/$(LINK) -fPIC -shared/' -i ${my_dir}/Makefile.in
#	sed -e 's/$(LINK) -shared/$(LINK) -fPIC -shared/' -i ${my_dir}/Makefile.am
#done
# FIXME: So, do without LTO... (Linaro GCC 5.2 2015.11-2 & binutils 2.26)
if [[ "${CFLAGS}" != "${NOLTO_CFLAGS}" ]] ; then
	temp_nolto="true"
	export CFLAGS="${NOLTO_CFLAGS}"
fi
autoreconf -fi
# Pull our own zlib to avoid symbol versioning issues......
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
env LIBS="-lz" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-thread-safety --program-prefix="eu-" --with-zlib --without-bzlib --without-lzma
make ${JOBSFLAGS}
make install
export LDFLAGS="${BASE_LDFLAGS}"
# NOTE: Restore LTO flags if needed
if [[ "${temp_nolto}" == "true" ]] ; then
	unset temp_nolto
	export CFLAGS="${BASE_CFLAGS}"
fi
# Install...
for my_bin in eu-nm eu-objdump eu-strings ; do
	${CROSS_TC}-strip --strip-unneeded ../bin/${my_bin}
	cp ../bin/${my_bin} ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/${my_bin}
done
# NOTE: readelf relies on qsort_r, which was introduced in glibc 2.8... We ship the binutils copy instead on the K3 ;).
if [[ "${KINDLE_TC}" != "K3" ]] ; then
	for my_bin in eu-readelf ; do
		${CROSS_TC}-strip --strip-unneeded ../bin/${my_bin}
		cp ../bin/${my_bin} ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/${my_bin}
	done
fi
# Don't forget the shared libs...
for my_lib in libelf libasm libdw ; do
	cp ../lib/${my_lib}-${ELFUTILS_VERSION}.so ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${my_lib}.so.1
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${my_lib}.so.1
done
# And also the CPU libebl modules...
for my_cpu in arm aarch64 ; do
	cp ../lib/elfutils/libebl_${my_cpu}-${ELFUTILS_VERSION}.so ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libebl_${my_cpu}.so
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libebl_${my_cpu}.so
done

# ltrace apprently needs a semi-recent ptrace implementation. Kernel appears to be too old for that on legacy devices.
if [[ "${KINDLE_TC}" != "K3" ]] ; then
	echo "* Building ltrace . . ."
	echo ""
	cd ..
	rm -rf ltrace
	until git clone git://anonscm.debian.org/collab-maint/ltrace.git ; do
		rm -rf ltrace
		sleep 15
	done
	cd ltrace
	update_title_info
	./autogen.sh
	# Regen the syscall list...
	cd sysdeps/linux-gnu
	if [[ "${KINDLE_TC}" == "PW2" ]] ; then
		./mksyscallent < ${HOME}/Kindle/SourceCode_Packages/5.6.5/gplrelease/linux/arch/arm/include/asm/unistd.h > arm/syscallent.h
		./mksignalent < ${HOME}/Kindle/SourceCode_Packages/5.6.5/gplrelease/linux/arch/arm/include/asm/signal.h > arm/signalent.h
	elif [[ "${KINDLE_TC}" == "K5" ]] ; then
		./mksyscallent < ${HOME}/Kindle/SourceCode_Packages/5.4.4.2/gplrelease/linux/arch/arm/include/asm/unistd.h > arm/syscallent.h
		./mksignalent < ${HOME}/Kindle/SourceCode_Packages/5.4.4.2/gplrelease/linux/arch/arm/include/asm/signal.h > arm/signalent.h
	elif [[ "${KINDLE_TC}" == "KOBO" ]] ; then
		./mksyscallent < ${HOME}/Kindle/SourceCode_Packages/Kobo-H2O/linux-2.6.35.3/arch/arm/include/asm/unistd.h > arm/syscallent.h
		./mksignalent < ${HOME}/Kindle/SourceCode_Packages/Kobo-H2O/linux-2.6.35.3/arch/arm/include/asm/signal.h > arm/signalent.h
	else
		./mksyscallent < ${HOME}/Kindle/SourceCode_Packages/3.4.2/gplrelease/linux/linux-2.6.26/include/asm-arm/unistd.h > arm/syscallent.h
		./mksignalent < ${HOME}/Kindle/SourceCode_Packages/3.4.2/gplrelease/linux/linux-2.6.26/include/asm-arm/signal.h > arm/signalent.h
	fi
	cd ../..

	# Setup our rpath...
	export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
	env LIBS="-lz" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --sysconfdir=${DEVICE_USERSTORE}/usbnet/etc --datarootdir=${DEVICE_USERSTORE}/usbnet/etc --disable-werror --disable-debug --without-libunwind --with-elfutils
	make ${JOBSFLAGS}
	make install
	export LDFLAGS="${BASE_LDFLAGS}"
	${CROSS_TC}-strip --strip-unneeded ../bin/ltrace
	cp ../bin/ltrace ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/ltrace
	# Don't forget the config files...
	for my_file in libc.so.conf libm.so.conf libacl.so.conf syscalls.conf ; do
		cp ${DEVICE_USERSTORE}/usbnet/etc/ltrace/${my_file} ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/ltrace/${my_file}
	done
fi
## Stable version...
#tar -I lbzip2 -xvf /usr/portage/distfiles/ltrace_0.7.3.orig.tar.bz2
#cd ltrace-0.7.3
#tar -I pigz -xvf /usr/portage/distfiles/ltrace_0.7.3-4.debian.tar.gz
#for file in debian/patches/0* ; do ; patch -p1 < ${file} ; done
#sed -i '/^dist_doc_DATA/d' Makefile.am
#autoreconf -fi
## Setup our rpath...
#export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
#env LIBS="-lz -lstdc++" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --sysconfdir=${DEVICE_USERSTORE}/usbnet/etc --datarootdir=${DEVICE_USERSTORE}/usbnet/etc --disable-werror --disable-debug
#make ${JOBSFLAGS}
#make install
#export LDFLAGS="${BASE_LDFLAGS}"
#${CROSS_TC}-strip --strip-unneeded ../bin/ltrace
#cp ../bin/ltrace ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/ltrace
#cp ${DEVICE_USERSTORE}/usbnet/etc/ltrace.conf  ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/ltrace.conf


## Building file for nano
echo "* Building file . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/file-5.28.tar.gz
cd file-5.28
update_title_info
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/file-fix-Makefile-for-lto.patch
autoreconf -fi
libtoolize
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
export ac_cv_header_zlib_h=yes
export ac_cv_lib_z_gzopen=yes
# Make sure libtool doesn't eat any our of our CFLAGS when linking...
export AM_LDFLAGS="${XC_LINKTOOL_CFLAGS}"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-fsect-man5 --datarootdir="${DEVICE_USERSTORE}/usbnet/share"
make ${JOBSFLAGS} V=1
make install
unset AM_LDFLAGS
unset ac_cv_lib_z_gzopen
unset ac_cv_header_zlib_h
export LDFLAGS="${BASE_LDFLAGS}"
cp ../lib/libmagic.so.1.0.0 ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libmagic.so.1
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libmagic.so.1
# Ship the magic db...
mkdir -p ${BASE_HACKDIR}/USBNetwork/src/usbnet/share/misc
cp -f ${DEVICE_USERSTORE}/usbnet/share/misc/magic.mgc ${BASE_HACKDIR}/USBNetwork/src/usbnet/share/misc/magic.mgc

## Nano itself
echo "* Building nano . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/nano-2.7.1.tar.gz
cd nano-2.7.1
update_title_info
# NOTE: On Kindles, we hit a number of dumb collation issues with regexes needed for syntax highlighting on some locales (notably en_GB...) on some FW versions, so enforce en_US...
patch -p0 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/nano-kindle-locale-hack.patch
# Look for nanorc in usbnet/etc...
sed -e "s#SYSCONFDIR \"/nanorc\"#\"${DEVICE_USERSTORE}/usbnet/etc/nanorc\"#" -i src/rcfile.c
# Same thing for the various state files...
sed -e "s#construct_filename(\"/.nano#strdup(\"${DEVICE_USERSTORE}/usbnet/etc/nano#g" -i src/files.c
# Store configs in usbnet/etc
sed -e "s#getenv(\"HOME\")#\"${DEVICE_USERSTORE}/usbnet/etc\"#" -i src/utils.c
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
export ac_cv_header_magic_h=yes
export ac_cv_lib_magic_magic_open=yes
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --with-wordbounds --enable-color --enable-multibuffer --enable-nanorc --disable-wrapping-as-root --enable-speller --disable-justify --disable-debug --enable-nls --enable-utf8 --disable-tiny
# Fixup some undetectable stuff when cross-compiling...
sed -e 's|/\* #undef REDEFINING_MACROS_OK \*/|#define REDEFINING_MACROS_OK 1|' -i config.h
make ${JOBSFLAGS}
make install
unset ac_cv_lib_magic_magic_open
unset ac_cv_header_magic_h
export LDFLAGS="${BASE_LDFLAGS}"
cp ../bin/nano ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/nano
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/nano
# Handle the config...
cp doc/nanorc.sample ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/nanorc
for my_opt in constantshow historylog matchbrackets nowrap positionlog smarthome smooth wordbounds ; do
	sed -e "s/^# set ${my_opt}/set ${my_opt}/" -i ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/nanorc
done
sed -e "s%^# include \"${TC_BUILD_DIR}/share/nano/\*\.nanorc\"%include \"${DEVICE_USERSTORE}/usbnet/etc/nano/\*\.nanorc\"%" -i ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/nanorc
mkdir -p ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/nano
cp -f ../share/nano/*.nanorc ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/nano/

## ZSH itself
echo "* Building ZSH . . ."
echo ""
ZSH_VER="5.2"
cd ..
tar -xvJf /usr/portage/distfiles/zsh-${ZSH_VER}.tar.xz
cd zsh-${ZSH_VER}
update_title_info
ln -s Doc man1
mv Doc/zshall.1 Doc/zshall.1.soelim
soelim Doc/zshall.1.soelim > Doc/zshall.1
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/zsh-fix-Makefile-for-lto.patch
# Store configs in usbnet/etc/zsh
sed -e "s#VARARR(char, buf, strlen(h) + strlen(s) + 2);#VARARR(char, buf, strlen(\"${DEVICE_USERSTORE}/usbnet/etc/zsh\") + strlen(s) + 2);#" -i Src/init.c
sed -e "s#sprintf(buf, \"%s/%s\", h, s);#sprintf(buf, \"${DEVICE_USERSTORE}/usbnet/etc/zsh/%s\", s);#" -i Src/init.c
# Setup our rpath, plus another one for modules...
# NOTE: Also explicitly look in the TC's sysroot, because pcre-config --libs is trying to be smart by automagically adding -L/usr/lib64 on x86_64 with no recourse against it...
# See my note on binary python extension earlier for why it is such a terrible idea and how thoroughly it fucks us over.
export LDFLAGS="${BASE_LDFLAGS} -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib/zsh"
# Oh, the joys of cross-compiling... (short-circuit runtime tests, we really can have dynamic modules)
export zsh_cv_shared_environ=yes
export zsh_cv_shared_tgetent=yes
export zsh_cv_shared_tigetstr=yes
export zsh_cv_sys_dynamic_clash_ok=yes
export zsh_cv_sys_dynamic_execsyms=yes
export zsh_cv_sys_dynamic_rtld_global=yes
export zsh_cv_sys_dynamic_strip_exe=yes
export zsh_cv_sys_dynamic_strip_lib=yes
# Fix modules path so they won't fail at runtime...
sed -e "s%#define MODULE_DIR \"'\$(MODDIR)'\"%#define MODULE_DIR \"${DEVICE_USERSTORE}/usbnet/lib\"%" -i Src/zsh.mdd
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-etcdir="${DEVICE_USERSTORE}/usbnet/etc/zsh" --enable-runhelpdir="${DEVICE_USERSTORE}/usbnet/share/zsh/help" --enable-fndir="${DEVICE_USERSTORE}/usbnet/share/zsh/functions" --enable-site-fndir="${DEVICE_USERSTORE}/usbnet/share/zsh/site-functions" --enable-scriptdir="${DEVICE_USERSTORE}/usbnet/share/zsh/scripts" --enable-site-scriptdir="${DEVICE_USERSTORE}/usbnet/share/zsh/site-scripts" --enable-function-subdirs --with-tcsetpgrp --disable-maildir-support --enable-pcre --disable-cap --enable-multibyte --disable-gdbm
make ${JOBSFLAGS}
make install
unset zsh_cv_sys_dynamic_strip_lib
unset zsh_cv_sys_dynamic_strip_exe
unset zsh_cv_sys_dynamic_rtld_global
unset zsh_cv_sys_dynamic_execsyms
unset zsh_cv_sys_dynamic_clash_ok
unset zsh_cv_shared_tigetstr
unset zsh_cv_shared_tgetent
unset zsh_cv_shared_environ
export LDFLAGS="${BASE_LDFLAGS}"
# Okay, now take a deep breath...
cp ../bin/zsh ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/zsh
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/zsh
mkdir -p ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/zsh
cp -a ../lib/zsh/${ZSH_VER}/zsh/. ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/zsh
find ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/zsh -name '*.so*' -exec ${CROSS_TC}-strip --strip-unneeded {} +
# Now for the functions & co...
mkdir -p ${BASE_HACKDIR}/USBNetwork/src/usbnet/share/zsh
cp -aL /mnt/us/usbnet/share/zsh/. ${BASE_HACKDIR}/USBNetwork/src/usbnet/share/zsh
# Now, get the latest dircolors-solarized db, because the default one is eye-poppingly awful
until git clone https://github.com/seebi/dircolors-solarized.git ; do
	rm -rf dircolors-solarized
	sleep 15
done
mkdir -p ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/zsh
cp -f dircolors-solarized/dircolors.* ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/zsh/
# And finally, our own zshrc & zshenv
cp ${SVN_ROOT}/Configs/trunk/Kindle/Misc/zshrc ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/zsh/zshrc
cp ${SVN_ROOT}/Configs/trunk/Kindle/Misc/zshenv ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/zsh/zshenv

## XZ (for packaging purposes only, to drop below MR's 20MB attachment limit... -_-". On the plus side, it's also twice as fast as bzip2 to uncompress, which is neat).
echo "* Building XZ-Utils . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/xz-5.2.2.tar.gz
cd xz-5.2.2
update_title_info
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-nls --disable-threads --enable-static --disable-shared --disable-{lzmadec,lzmainfo,lzma-links,scripts}
make ${JOBSFLAGS}
make install
# And send that to our common pool of binaries...
cp ../bin/xzdec ${BASE_HACKDIR}/Common/bin/xzdec
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Common/bin/xzdec

## AG (because it's awesome)
echo "* Building the silver searcher . . ."
echo ""
cd ..
rm -rf the_silver_searcher
until git clone https://github.com/ggreer/the_silver_searcher.git the_silver_searcher ; do
	rm -rf the_silver_searcher
	sleep 15
done
cd the_silver_searcher
update_title_info
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
./build.sh --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-zlib --enable-lzma
make install
export LDFLAGS="${BASE_LDFLAGS}"
${CROSS_TC}-strip --strip-unneeded ../bin/ag
cp ../bin/ag ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/ag

## libevent (for tmux)
echo "* Building libevent . . ."
echo ""
cd ..
LIBEVENT_SOVER="5.0.0"
LIBEVENT_LIBSUF="-2.1"
tar -I pigz -xvf /usr/portage/distfiles/libevent-2.1.5-beta.tar.gz
cd libevent-2.1.5-beta
update_title_info
patch -p1 < /usr/portage/dev-libs/libevent/files/libevent-2.1.5-event_signals_ordering.patch
autoreconf -fi
libtoolize
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-samples --disable-debug-mode --disable-malloc-replacement --disable-libevent-regress --enable-openssl --enable-thread-support
make ${JOBSFLAGS}
make install
export LDFLAGS="${BASE_LDFLAGS}"
for my_lib in libevent libevent_core libevent_extra libevent_openssl libevent_pthreads ; do
	my_lib="${my_lib}${LIBEVENT_LIBSUF}"
	cp ../lib/${my_lib}.so.${LIBEVENT_SOVER} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${my_lib}.so.${LIBEVENT_SOVER%%.*}
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${my_lib}.so.${LIBEVENT_SOVER%%.*}
done

echo "* Building tmux . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/tmux-2.3.tar.gz
cd tmux-2.3
update_title_info
patch -p1 < /usr/portage/app-misc/tmux/files/tmux-2.3-flags.patch
# Actually honor our custom config path...
sed -e 's%#define TMUX_CONF "/etc/tmux.conf"%#ifndef TMUX_CONF\n#define TMUX_CONF "/etc/tmux.conf"\n#endif%' -i tmux.h
rm aclocal.m4
autoreconf -fi
# Needed to find the ncurses (narrowc) headers
export CPPFLAGS="${BASE_CPPFLAGS} -I${TC_BUILD_DIR}/include/ncurses"
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --sysconfdir=${DEVICE_USERSTORE}/usbnet/etc
make ${JOBSFLAGS}
make install
export LDFLAGS="${BASE_LDFLAGS}"
export CPPFLAGS="${BASE_CPPFLAGS}"
${CROSS_TC}-strip --strip-unneeded ../bin/tmux
cp ../bin/tmux ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/tmux
# And our tmux.conf
cp ${SVN_ROOT}/Configs/trunk/Kindle/Misc/tmux.conf ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/tmux.conf

## GDB
echo "* Building GDB . . ."
echo ""
cd ..
tar -xvJf /usr/portage/distfiles/gdb-7.11.1.tar.xz
cd gdb-7.11.1
update_title_info
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-werror --disable-{binutils,etc,gas,gold,gprof,ld} --enable-gdbserver --enable-64-bit-bfd --disable-install-libbfd --disable-install-libiberty --without-guile --disable-readline --with-system-readline --without-zlib --with-system-zlib --with-expat --without-lzma --enable-nls --without-python
make ${JOBSFLAGS}
make install
export LDFLAGS="${BASE_LDFLAGS}"
for my_gdb in gdb gdbserver ; do
	${CROSS_TC}-strip --strip-unneeded ../bin/${my_gdb}
	cp ../bin/${my_gdb} ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/${my_gdb}
done
cp ../bin/gcore ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/gcore

## Binutils (for objdump, since elfutils' doesn't support arm)
echo "* Building Binutils . . ."
echo ""
cd ..
rm -rf binutils
until git clone -b binutils-2_26-branch git://sourceware.org/git/binutils-gdb.git binutils ; do
	rm -rf binutils
	sleep 15
done
cd binutils
update_title_info
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=no --enable-static=yes --disable-nls --with-zlib --enable-secureplt --enable-threads --enable-install-libiberty --disable-werror --disable-{gdb,libdecnumber,readline,sim} --without-stage1-ldflags
make ${JOBSFLAGS}
${CROSS_TC}-strip --strip-unneeded binutils/objdump
cp binutils/objdump ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/objdump
# NOTE: On the K3, we can't use the elfutils copy of readelf, so use this one ;).
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	${CROSS_TC}-strip --strip-unneeded binutils/readelf
	cp binutils/readelf ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/readelf
fi

## cURL
#
#patch -p0 < /usr/portage/net-misc/curl/files/curl-7.18.2-prefix.patch
#patch -p1 < /usr/portage/net-misc/curl/files/curl-respect-cflags-3.patch
#patch -p1 < /usr/portage/net-misc/curl/files/curl-fix-gnutls-nettle.patch
#sed -i '/LD_LIBRARY_PATH=/d' configure.ac
#
#env LIBS="-lz -ldl" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=no --enable-static=yes --without-axtls --without-cyassl --without-gnutls --without-nss --without-polarssl --without-ssl --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt --with-ssl --without-ca-bundle --with-ca-path=/etc/ssl/certs --enable-dict --enable-file --enable-ftp --enable-gopher --enable-http --enable-imap --enable-pop3 --without-librtmp --enable-rtsp --disable-ldap --disable-ldaps --without-libssh2 --enable-smtp --enable-telnet -enable-tftp --disable-ares --enable-cookies --enable-hidden-symbols --disable-ipv6 --enable-largefile --enable-manual --enable-nonblocking --enable-proxy --disable-soname-bump --disable-sspi --disable-threaded-resolver --disable-versioned-symbols --without-libidn --without-gssapi --without-krb4 --without-spnego --with-zlib
#
#make ${JOBSFLAGS}
#
#${CROSS_TC}-strip --strip-unneeded src/curl
#
# NOTE: Even with shared=no static=yes, I ended up with NEEDED entries for shared libraries for everything except OpenSSL (because I don't *have* a shared library for it), and it avoided the PIC issues entirely, without needing to build OpenSSL PIC...
# FIXME: Try this on every project that had a PIC issue?
#
##

## wget
#
#patch -p1 < /usr/portage/net-misc/wget/files/wget-1.13.4-openssl-pkg-config.patch
#autoreconf -fi
# pkg-config will take care of that for us...
#export ac_cv_lib_{z_compress,dl_{dlopen,shl_load}}=no
#export ac_cv_{header_pcre_h,lib_pcre_pcre_compile}=no
#export ac_cv_{header_uuid_uuid_h,lib_uuid_uuid_generate}=no
# Takes care of pulling libdl & libz for OpenSSL static
#export PKG_CONFIG="pkg-config --static"
#./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-rpath --with-ssl=openssl --enable-opie --enable-digest --disable-iri --disable-ipv6 --disable-nls --disable-ntlm --disable-debug --with-zlib
#make ${JOBSFLAGS}
#${CROSS_TC}-strip --strip-unneeded src/wget
#unset ac_cv_lib_{z_compress,dl_{dlopen,shl_load}} ac_cv_{header_pcre_h,lib_pcre_pcre_compile} ac_cv_{header_uuid_uuid_h,lib_uuid_uuid_generate} PKG_CONFIG
#
##


## TODO: Build kpdfviewer?
