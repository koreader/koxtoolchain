#!/bin/bash -ex
#
# Kindle cross toolchain & lib/bin/util build script
#
# $Id: x-compile.sh 16867 2020-02-14 16:46:00Z NiLuJe $
#
# kate: syntax bash;
#
##

## Using CrossTool-NG (http://crosstool-ng.org/)
SVN_ROOT="${HOME}/SVN"
## Remember where we are... (c.f., https://stackoverflow.com/questions/9901210/bash-source0-equivalent-in-zsh)
SCRIPT_NAME="${BASH_SOURCE[0]-${(%):-%x}}"
SCRIPTS_BASE_DIR="$(readlink -f "${SCRIPT_NAME%/*}")"

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

## We never, ever want to be using libtool's .la files. They're terrible, and cause more trouble than they're worth...
# NOTE: c.f., https://flameeyes.blog/2008/04/14/what-about-those-la-files/ for more details.
# NOTE: In our particular context, see the FT build comments for the particular insanity they caused...
prune_la_files()
{
	if [ -d "${TC_BUILD_DIR}/lib" ] ; then
		find "${TC_BUILD_DIR}/lib" -name "*.la" -type l -delete
		find "${TC_BUILD_DIR}/lib" -name "*.la" -type f -delete
	fi
}

## Make the window title useful when running this through tmux...
pkgIndex="0"
update_title_info()
{
	# Get package name from the current directory, because I'm lazy ;)
	pkgName="${PWD##*/}"
	# Increment package counter...
	pkgIndex="$((pkgIndex + 1))"
	# Get number of packages by counting the amount of calls to this very function in the script...
	if [[ -z ${pkgCount} ]] ; then
		# May not be 100% accurate because of the branching, although we try to manually correct that...
		pkgCount="$(grep -c '^[[:blank:]]*update_title_info$' "${SCRIPTS_BASE_DIR}/x-compile.sh")"
		# Try to correct the total count by hard-coding the amount of branches...
		# There's zlib vs. zlib-ng...
		pkgCount="$((pkgCount - 1))"
		# There's Gandalf which we only build for K5 & PW2...
		if [[ "${KINDLE_TC}" != "K5" ]] && [[ "${KINDLE_TC}" != "PW2" ]] ; then
			pkgCount="$((pkgCount - 1))"
		fi
		# There's ICU which we don't always build...
		if [[ "${KINDLE_TC}" != "K5" ]] && [[ "${KINDLE_TC}" != "PW2" ]] && [[ "${KINDLE_TC}" != "KOBO" ]] ; then
			pkgCount="$((pkgCount - 1))"
		fi
		# There's ltrace which we don't build on the K3...
		if [[ "${KINDLE_TC}" == "K3" ]] ; then
			pkgCount="$((pkgCount - 1))"
		fi
	fi

	# Set the panel name to something short & useful
	myPanelTitle="X-TC ${KINDLE_TC}"
	echo -e '\033k'${myPanelTitle}'\033\\'
	# Set the window title to a longer description of what we're doing...
	myWindowTitle="Building ${pkgName} for ${KINDLE_TC} (${pkgIndex} of ${pkgCount})"
	echo -e '\033]2;'${myWindowTitle}'\007'

	# Bye, Felicia!
	prune_la_files
}

## Install/Setup CrossTool-NG
Build_CT-NG-Legacy() {
	echo "* Building CrossTool-NG 1.23 . . ."
	echo ""
	cd ${HOME}/Kindle
	mkdir -p CrossTool
	cd CrossTool

	# Remove previous CT-NG install...
	rm -rf CT-NG

	mkdir -p CT-NG
	cd CT-NG
	# Pull our own CT-NG branch, which includes a few tweaks needed to support truly old glibc & kernel versions...
	git clone -b 1.23-kindle --single-branch https://github.com/NiLuJe/crosstool-ng.git .

	git clean -fxdq
	./bootstrap
	./configure --enable-local
	make -j$(nproc)

	# We need a clean set of *FLAGS, or shit happens...
	unset CFLAGS CXXFLAGS LDFLAGS

	## And then build every TC one after the other...
	for my_tc in kindle kindle5 kindlepw2 kobo remarkable pocketbook ; do
		echo ""
		echo "* Building the ${my_tc} ToolChain . . ."
		echo ""

		# Start by removing the old TC...
		[[ -d "${HOME}/x-tools/_arm-${my_tc}-linux-gnueabi" ]] && chmod -R u+w ${HOME}/x-tools/_arm-${my_tc}-linux-gnueabi && rm -rf ${HOME}/x-tools/_arm-${my_tc}-linux-gnueabi
		[[ -d "${HOME}/x-tools/_arm-${my_tc}-linux-gnueabihf" ]] && chmod -R u+w ${HOME}/x-tools/_arm-${my_tc}-linux-gnueabihf && rm -rf ${HOME}/x-tools/_arm-${my_tc}-linux-gnueabihf
		# Then backup the current one...
		[[ -d "${HOME}/x-tools/arm-${my_tc}-linux-gnueabi" ]] && mv ${HOME}/x-tools/{,_}arm-${my_tc}-linux-gnueabi
		[[ -d "${HOME}/x-tools/arm-${my_tc}-linux-gnueabihf" ]] && mv ${HOME}/x-tools/{,_}arm-${my_tc}-linux-gnueabihf

		# Clean the WD
		./ct-ng clean

		# Build the config from this TC's sample
		./ct-ng $(find samples -type d -name "arm-${my_tc}-linux-gnueabi*" | cut -d'/' -f2)

		# And fire away!
		./ct-ng oldconfig
		#./ct-ng menuconfig

		./ct-ng updatetools

		nice ./ct-ng build
	done
}

## Install/Setup CrossTool-NG
Build_CT-NG() {
	echo "* Building CrossTool-NG 1.24 . . ."
	echo ""
	cd ${HOME}/Kindle
	mkdir -p CrossTool
	cd CrossTool

	# Remove previous CT-NG install...
	rm -rf CT-NG

	mkdir -p CT-NG
	cd CT-NG
	# Pull our own CT-NG branch, which includes a few tweaks needed to support truly old glibc & kernel versions...
	git clone -b 1.24-kindle --single-branch https://github.com/NiLuJe/crosstool-ng.git .
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

	# XXX: Something is very, very wrong with my Linaro 2016.01 builds: everything segfaults on start (in __libc_csu_init).
	# XXX: Progress! With the 2016.02 & 2016.03 snapshots, as well as the 2016.02 release, it SIGILLs (in _init/call_gmon_start)...
	# XXX: Building the PW2 TC against glibc 2.19, on the other hand, results in working binaries... WTF?! (5.3 2016.03 snapshot)
	# NOTE: Joy? The issue appears to be fixed in Linaro GCC 5.3 2016.04 snapshot! :)

	# XXX: I'm seriously considering adding proper support for binutil's native handling of the LTO plugin, via lib/bfd-plugins, instead of relying on the GCC wrappers...
	#        cd ${HOME}/x-tools/arm-kobo-linux-gnueabihf
	#        mkdir -p lib/bfd-plugins
	#        cd lib/bfd-plugins
	#        ln -sf ../../libexec/gcc/arm-kobo-linux-gnueabihf/7.3.1/liblto_plugin.so.0.0.0 liblto_plugin.so
	# NOTE: This *should* be automatically taken care of on ct-ng 1.24 ;).

	# NOTE: Performance appears to have gone *noticeably* down between GCC Linaro 7.4 and ARM 8.3 (and even more sharply between ARM 8.3 & FSF 9.2)... :/
	#       Possibly related: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=91598
	#       TL;DR: We're not moving away from the final Linaro TC for now. Yay?
	#              The good news is all the work involved in moving to ct-ng 1.24 is done, and building Linaro 7.4 also works there, FWIW.
	# NOTE: I should also probably revert https://github.com/NiLuJe/crosstool-ng/commit/90c619fe156f997dfe8ec21bb316901ecd264efc
	#       It doesn't seem to have a noticeable impact in practice, and it *does* break -mcpu GCC 9.2 builds (-march+-mtune are okay, though).

	git clean -fxdq
	./bootstrap
	./configure --enable-local
	make -j$(nproc)

	# We need a clean set of *FLAGS, or shit happens...
	unset CFLAGS CXXFLAGS LDFLAGS

	## And then build every TC one after the other...
	## FIXME: kindle is broken in the 1.24 branch (The pass-2 core C gcc compiler fails to build libgcc with a multiple definition of `__libc_use_alloca' link failure), for some reason...
	for my_tc in kindle5 kindlepw2 kobo ; do
		echo ""
		echo "* Building the ${my_tc} ToolChain . . ."
		echo ""

		# Start by removing the old TC...
		[[ -d "${HOME}/x-tools/_arm-${my_tc}-linux-gnueabi" ]] && chmod -R u+w ${HOME}/x-tools/_arm-${my_tc}-linux-gnueabi && rm -rf ${HOME}/x-tools/_arm-${my_tc}-linux-gnueabi
		[[ -d "${HOME}/x-tools/_arm-${my_tc}-linux-gnueabihf" ]] && chmod -R u+w ${HOME}/x-tools/_arm-${my_tc}-linux-gnueabihf && rm -rf ${HOME}/x-tools/_arm-${my_tc}-linux-gnueabihf
		# Then backup the current one...
		[[ -d "${HOME}/x-tools/arm-${my_tc}-linux-gnueabi" ]] && mv ${HOME}/x-tools/{,_}arm-${my_tc}-linux-gnueabi
		[[ -d "${HOME}/x-tools/arm-${my_tc}-linux-gnueabihf" ]] && mv ${HOME}/x-tools/{,_}arm-${my_tc}-linux-gnueabihf

		# Clean the WD
		./ct-ng distclean

		# Build the config from this TC's sample
		./ct-ng $(find samples -type d -name "arm-${my_tc}-linux-gnueabi*" | cut -d'/' -f2)

		# And fire away!
		./ct-ng oldconfig
		#./ct-ng menuconfig

		./ct-ng updatetools

		nice ./ct-ng build
	done

	## NOTE: Do that ourselves?
	echo ""
	echo "* You can now remove the source tarballs ct-ng downloaded in ${HOME}/src . . ."
	echo ""

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
	CPU: arm1136jf-s	|	cortex-a8	|	cortex-a9	# NOTE: Prefer setting CPU instead of Arch & Tune (NOTE: In practice, we do the opposite in our CFLAGS, but using -mcpu when building GCC used to lead to a more accurate Tag_CPU_name aeabi attribute. That doesn't appear to be the case anymore with GCC8+, where -mcpu appears to simply autodetect what to set for -march & -mtune).
	Tune: arm1136jf-s	|	cortex-a8	|	cortex-a9
	FPU: vfp		|	neon or vfpv3
	Floating point: softfp				# NOTE: Can't use hardf, it requires a linux-armhf loader (also, terrible idea to mix ABIs). Interwork is meaningless on ARMv6+. K5: I'm not sure Amazon defaults to Thumb2, but AFAICT we can use it safely.
	CFLAGS:		# Be very fucking conservative here, so, leave them empty to use the defaults (-O2 -pipe).... And, FWIW, don't use -ffast-math or -Ofast here, '#error "glibc must not be compiled with -ffast-math"' ;).
	LDFLAGS:
	Default instruction set mode:	arm	|	thumb	# NOTE: While Thumb produces noticeably smaller code, that may come at the cost of a veeeeeery small performance hit. Or the better code density might give it a veeeeeery small performance edge ;).
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
	nickel | Nickel | NICKEL )
		KINDLE_TC="NICKEL"
	;;
	mk7 | Mk7 | MK7 )
		KINDLE_TC="MK7"
	;;
	remarkable | reMarkable | Remarkable )
		KINDLE_TC="REMARKABLE"
	;;
	pb | PB | pocketbook )
		KINDLE_TC="PB"
	;;
	# Or build them?
	tc )
		Build_CT-NG-Legacy
		# FIXME: See the NOTE above about perf regression for why we don't move to GCC 8 or 9...
		#Build_CT-NG
		# And exit happy now :)
		exit 0
	;;
	* )
		echo "You must choose a ToolChain! (k3, k5, pw2, kobo, mk7, nickel, remarkable or pocketbook)"
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
#	emerge -a lbzip2 pigz dev-perl/File-MimeInfo kindletool svn2cl rar p7zip python-swiftclient python-keystoneclient
#
# For harfbuzz:
#	cave resolve -1 ragel gobject-introspection-common -x
#
#	emerge -a ragel gobject-introspection-common
#
# For OpenSSH & co:
#	mkdir -p /mnt/onboard/.niluje/usbnet && mkdir -p /mnt/us/usbnet && chown -cvR niluje:users /mnt/us && chown -cvR niluje:users /mnt/onboard
#
# For Python:
#
#	emerge -a dev-lang/python:2.7 dev-lang/python:3.7
#
# For Python 3rd party modules:
#	cave resolve -x distutilscross
#
#	emerge -a distutilscross
#
# For FC:
#	cave resolve -x dev-python/lxml (for fontconfig)
#
#	emerge -a dev-python/lxml
#
# For SQLite:
#	emerge -a dev-lang/tcl
#
# For lxml:
#	emerge -a cython
#
# For BeautifulSoup:
#	emerge -a bzr
#
# To fetch everything:
#	cave resolve -1 -z -f -x sys-libs/zlib expat freetype harfbuzz util-linux fontconfig coreutils dropbear rsync busybox dev-libs/openssl:0 openssh ncurses htop lsof protobuf mosh libarchive gmp nettle libpng libjpeg-turbo '<=media-gfx/imagemagick-7' bzip2 dev-libs/libffi sys-libs/readline icu sqlite dev-lang/python:2.7 dev-lang/python dev-libs/glib sys-fs/fuse elfutils file nano libpcre zsh mit-krb5 libtirpc xz-utils libevent tmux gdb --uninstalls-may-break '*/*'
#	OR
#	emerge -1 -f sys-libs/zlib expat freetype harfbuzz util-linux fontconfig coreutils dropbear rsync busybox dev-libs/openssl:0 openssh ncurses htop lsof protobuf mosh libarchive gmp nettle libpng libjpeg-turbo '<=media-gfx/imagemagick-7' bzip2 dev-libs/libffi sys-libs/readline icu sqlite dev-lang/python:2.7 dev-lang/python:3.7 dev-libs/glib sys-fs/fuse elfutils file nano libpcre zsh mit-krb5 libtirpc xz-utils libevent tmux gdb libxml2 libxslt
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
		BASE_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} ${ARM_NO_UNALIGNED_ACCESS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin -fno-stack-protector"
		NOLTO_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} ${ARM_NO_UNALIGNED_ACCESS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -fno-stack-protector"
		## Here be dragons!
		RICE_CFLAGS="-O3 -ffast-math -ftree-vectorize -funroll-loops ${ARCH_FLAGS} ${ARM_NO_UNALIGNED_ACCESS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin -fno-stack-protector"

		## NOTE: And here comes another string of compatibility related tweaks...
		# We don't have mkostemp on Glibc 2.5... ;) (fontconfig)
		export ac_cv_func_mkostemp=no
		# Avoid pulling __isoc99_sscanf@GLIBC_2.7 (dropbear, libjpeg-turbo, fuse, sshfs, zsh), and disable fortify to avoid the few _chk symbols that are from glibc 2.8
		# NOTE: We do this here because, besides being the right place for them, some stuff (autotools?) might put CPPFLAGS *after* CFLAGS...
		#       And, yeah, the insane -U -> -D=0 dance appears to be necessary, or some things would stubbornly attempt to pull _chk symbols...
		BASE_CPPFLAGS="-D_GNU_SOURCE -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -U__USE_FORTIFY_LEVEL -D__USE_FORTIFY_LEVEL=0"
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
		## NOTE: The Glade guys built a tool to automate the symver approach to at worst detecting, at best handling the "build for an earlier glibc ABI" situation ;).
		#        It's called LibcWrapGenerator, and the libcwrap-kindle.h header in this repo was built with it.
		#        You basically pass it to every GCC call via -include (via a CC override instead of CPPFLAGS to deal with the largest amount of stupid buildsystems).
		#        It's not perfect: it won't help you automagically avoid *new* or *variant* symbols for instance, but it'll at least make it very explicit with a linker failure,
		#        instead of having to check everything later via readelf!
		#        c.f., https://gitlab.gnome.org/GNOME/glade/blob/master/build/linux/README for more info.


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

		# NOTE: We're no longer using the gold linker by default...
		# FIXME: Because for some mysterious reason, gold + LTO leads to an unconditional dynamic link against libgcc_s (uless -static-libgcc is passed, of course).
		export CTNG_LD_IS="bfd"

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

		## CMake is hell.
		export CMAKE="cmake -DCMAKE_TOOLCHAIN_FILE=${SCRIPTS_BASE_DIR}/CMakeCross.txt -DCMAKE_INSTALL_PREFIX=${TC_BUILD_DIR}"

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
		## Here be dragons!
		RICE_CFLAGS="-O3 -ffast-math -ftree-vectorize -funroll-loops ${ARCH_FLAGS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin"

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

		# NOTE: We're no longer using the gold linker by default...
		# FIXME: Because for some mysterious reason, gold + LTO leads to an unconditional dynamic link against libgcc_s (uless -static-libgcc is passed, of course).
		export CTNG_LD_IS="bfd"

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

		## CMake is hell.
		export CMAKE="cmake -DCMAKE_TOOLCHAIN_FILE=${SCRIPTS_BASE_DIR}/CMakeCross.txt -DCMAKE_INSTALL_PREFIX=${TC_BUILD_DIR}"

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
		## Here be dragons!
		RICE_CFLAGS="-O3 -ffast-math -ftree-vectorize -funroll-loops ${ARCH_FLAGS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin"

		## XXX: Crazy compat flags if the TC has been built against glibc 2.19...
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
			# XXX: Don't forget to kill those stray checks if I ever get rid of this monstrosity...
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

		# NOTE: We're no longer using the gold linker by default...
		# FIXME: Because for some mysterious reason, gold + LTO leads to an unconditional dynamic link against libgcc_s (uless -static-libgcc is passed, of course).
		export CTNG_LD_IS="bfd"

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

		## CMake is hell.
		export CMAKE="cmake -DCMAKE_TOOLCHAIN_FILE=${SCRIPTS_BASE_DIR}/CMakeCross.txt -DCMAKE_INSTALL_PREFIX=${TC_BUILD_DIR}"

		DEVICE_USERSTORE="/mnt/us"
	;;
	KOBO | NICKEL | MK7 )
		if [[ "${KINDLE_TC}" == "MK7" ]] ; then
			ARCH_FLAGS="-march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard -mthumb"
		else
			ARCH_FLAGS="-march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -mthumb"
		fi

		case ${KINDLE_TC} in
			KOBO )
				CROSS_TC="arm-kobo-linux-gnueabihf"
				TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"
			;;
			NICKEL )
				CROSS_TC="arm-nickel-linux-gnueabihf"
				# NOTE: We use a directory tree slightly more in line w/ ct-ng here...
				TC_BUILD_DIR="${HOME}/Kobo/CrossTool/Build_${KINDLE_TC}/${CROSS_TC}/${CROSS_TC}/sysroot"
			;;
			MK7 )
				CROSS_TC="arm-kobomk7-linux-gnueabihf"
				TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"
			;;
		esac

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
		## Here be dragons!
		RICE_CFLAGS="-O3 -ffast-math -ftree-vectorize -funroll-loops ${ARCH_FLAGS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin"

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

		# NOTE: We're no longer using the gold linker by default...
		# FIXME: Because for some mysterious reason, gold + LTO leads to an unconditional dynamic link against libgcc_s (uless -static-libgcc is passed, of course).
		export CTNG_LD_IS="bfd"

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

		## CMake is hell.
		export CMAKE="cmake -DCMAKE_TOOLCHAIN_FILE=${SCRIPTS_BASE_DIR}/CMakeCross.txt -DCMAKE_INSTALL_PREFIX=${TC_BUILD_DIR}"

		# Kobos are finnicky as hell, so take some more precautions...
		# On the vfat partition, don't use the .kobo folder, since it might go poof with no warning in case of troubles...
		# (It gets deleted by the Account sign out process, which is *possibly* what happens automatically in case of database corruption...)
		# NOTE: One massive downside is that, since FW 4.17, Nickel will now scan *all* subdirectories, including hidden ones... >_<"
		DEVICE_ONBOARD_USERSTORE="/mnt/onboard/.niluje"
		# And we'll let dropbear live in the internal memory to avoid any potential interaction with USBMS...
		DEVICE_INTERNAL_USERSTORE="/usr/local/niluje"
		DEVICE_USERSTORE="${DEVICE_ONBOARD_USERSTORE}"
	;;
	REMARKABLE )
		ARCH_FLAGS="-march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard -mthumb"
		CROSS_TC="arm-remarkable-linux-gnueabihf"
		TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"

		# Export it for our CMakeCross TC file
		export CROSS_TC
		export TC_BUILD_DIR

		export CROSS_PREFIX="${CROSS_TC}-"
		export PATH="${HOME}/x-tools/${CROSS_TC}/bin:${PATH}"

		## NOTE: Upstream is (currently) using GCC 7.3, so we have no potential C++ ABI issue to take care of :)

		BASE_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin"
		NOLTO_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} -pipe -fomit-frame-pointer -frename-registers -fweb"
		## Here be dragons!
		RICE_CFLAGS="-O3 -ffast-math -ftree-vectorize -funroll-loops ${ARCH_FLAGS} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin"

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

		# NOTE: We're no longer using the gold linker by default...
		# FIXME: Because for some mysterious reason, gold + LTO leads to an unconditional dynamic link against libgcc_s (uless -static-libgcc is passed, of course).
		export CTNG_LD_IS="bfd"

		## NOTE: We jump through terrible hoops to counteract libtool's stripping of 'unknown' or 'harmful' FLAGS... (cf. https://www.gnu.org/software/libtool/manual/html_node/Stripped-link-flags.html)
		## That's a questionable behavior that is bound to screw up LTO in fun and interesting ways, at the very least on the performance aspect of things...
		## Store those in the right format here, and apply patches or tricks to anything using libtool, because of course it's a syntax that gcc doesn't know about, so we can't simply put it in the global LDFLAGS.... -_-".
		## And since autotools being autotools, it's used in various completely idiosyncratic ways, we can't always rely on simply overriding AM_LDFLAGS...
		## NOTE: Hopefully, GCC 5's smarter LTO handling means we don't have to care about that anymore... :).
		export XC_LINKTOOL_CFLAGS="-Wc,-ffast-math -Wc,-fomit-frame-pointer -Wc,-frename-registers -Wc,-fweb"

		BASE_HACKDIR="${SVN_ROOT}/Configs/trunk/Kindle/reMarkable_Hacks"

		BASE_PKG_CONFIG_PATH="${TC_BUILD_DIR}/lib/pkgconfig"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_DIR=
		export PKG_CONFIG_PATH="${BASE_PKG_CONFIG_PATH}"
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"

		## CMake is hell.
		export CMAKE="cmake -DCMAKE_TOOLCHAIN_FILE=${SCRIPTS_BASE_DIR}/CMakeCross.txt -DCMAKE_INSTALL_PREFIX=${TC_BUILD_DIR}"

		DEVICE_USERSTORE="/home/root"
	;;
	PB )
		# NOTE: The TC itself is built in ARM mode, otherwise glibc 2.9 doesn't build (fails with a "r15 not allowed here" assembler error on csu/libc-start.o during the early multilib start-files step).
		#       AFAICT, the official SDK doesn't make a specific choice on that front (i.e., it passes neither -marm not -mthumb)...
		ARCH_FLAGS="-march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=softfp -mthumb"
		CROSS_TC="arm-pocketbook-linux-gnueabi"
		TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"

		# Export it for our CMakeCross TC file
		export CROSS_TC
		export TC_BUILD_DIR

		export CROSS_PREFIX="${CROSS_TC}-"
		export PATH="${HOME}/x-tools/${CROSS_TC}/bin:${PATH}"

		## NOTE: The new libstdc++ ABI might cause some issues if not handled on GCC >= 5.1 (c.f., https://gcc.gnu.org/onlinedocs/libstdc++/manual/using_dual_abi.html), so, disable it...
		## NOTE: This is a bit annoying on PB, because older FW were based on GCC 4.8.1 (so, old ABI), but newer FW (5.19+) are based on GCC 6.3.0 + Clang 7 (so, new ABI, not libc++) :/.
		if is_ver_gte "$(${CROSS_TC}-gcc -dumpversion)" "5.1" ; then
			LEGACY_GLIBCXX_ABI="-D_GLIBCXX_USE_CXX11_ABI=0"
			## NOTE: Like the FORTIFY stuff, this should *really* be in CPPFLAGS, but we have to contend with broken buildsystems that don't honor CPPFLAGS... So we go with the more ubiquitous CFLAGS instead ;/.
		fi

		BASE_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin"
		NOLTO_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb"
		## Here be dragons!
		RICE_CFLAGS="-O3 -ffast-math -ftree-vectorize -funroll-loops ${ARCH_FLAGS} ${LEGACY_GLIBCXX_ABI} -pipe -fomit-frame-pointer -frename-registers -fweb -flto=${AUTO_JOBS} -fuse-linker-plugin"

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

		# NOTE: We're no longer using the gold linker by default...
		# FIXME: Because for some mysterious reason, gold + LTO leads to an unconditional dynamic link against libgcc_s (uless -static-libgcc is passed, of course).
		export CTNG_LD_IS="bfd"

		## NOTE: We jump through terrible hoops to counteract libtool's stripping of 'unknown' or 'harmful' FLAGS... (cf. https://www.gnu.org/software/libtool/manual/html_node/Stripped-link-flags.html)
		## That's a questionable behavior that is bound to screw up LTO in fun and interesting ways, at the very least on the performance aspect of things...
		## Store those in the right format here, and apply patches or tricks to anything using libtool, because of course it's a syntax that gcc doesn't know about, so we can't simply put it in the global LDFLAGS.... -_-".
		## And since autotools being autotools, it's used in various completely idiosyncratic ways, we can't always rely on simply overriding AM_LDFLAGS...
		## NOTE: Hopefully, GCC 5's smarter LTO handling means we don't have to care about that anymore... :).
		export XC_LINKTOOL_CFLAGS="-Wc,-ffast-math -Wc,-fomit-frame-pointer -Wc,-frename-registers -Wc,-fweb"

		BASE_HACKDIR="${SVN_ROOT}/Configs/trunk/Kindle/PB_Hacks"

		BASE_PKG_CONFIG_PATH="${TC_BUILD_DIR}/lib/pkgconfig"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_DIR=
		export PKG_CONFIG_PATH="${BASE_PKG_CONFIG_PATH}"
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"

		## CMake is hell.
		export CMAKE="cmake -DCMAKE_TOOLCHAIN_FILE=${SCRIPTS_BASE_DIR}/CMakeCross.txt -DCMAKE_INSTALL_PREFIX=${TC_BUILD_DIR}"

		DEVICE_USERSTORE="/mnt/ext1/applications"
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
		# We have our own CMake shenanigans
		unset CMAKE
		# We also don't want to look at or pick up our own custom sysroot, for fear of an API/ABI mismatch somewhere...
		export CPPFLAGS="${CPPFLAGS/-isystem${TC_BUILD_DIR}\/include/}"
		export LDFLAGS="${LDFLAGS/-L${TC_BUILD_DIR}\/lib /}"
		# NOTE: Play it safe, and disable LTO.
		#BASE_CFLAGS="${NOLTO_CFLAGS}"
		#export CFLAGS="${BASE_CFLAGS}"
		#export CXXFLAGS="${BASE_CFLAGS}"
		# NOTE: Let's try breaking shit! LTO!
		export CFLAGS="${RICE_CFLAGS}"
		export CXXFLAGS="${RICE_CFLAGS}"
		# NOTE: In the same vein, disable gold too...
		unset CTNG_LD_IS
		# NOTE: And we want to link to libstdc++ statically...
		export LDFLAGS="${LDFLAGS} -static-libstdc++"

		# XXX: Go back to GCC 4.9 for now, as CRe mysteriously breaks when built w/ Linaro GCC 5.2 2015.11-2...
		# NOTE: Now fixed in CRe ;).
		#export PATH="${PATH/${CROSS_TC}/gcc49_${CROSS_TC}}"
		# XXX: Oh, joy. It also segfaults w/ Linaro GCC 4.9 2016.02...
		# NOTE: Because that was during the great 2016 snapshot breakening! :D
	# As well as a no-sysroot version for standalone projects (i.e., KFMon)
	elif [[ "${3}" == "bare" ]] ; then
		echo "* Not using our custom sysroot! :)"
		# We don't want to pull any of our own libs through pkg-config
		unset PKG_CONFIG_DIR
		unset PKG_CONFIG_PATH
		unset PKG_CONFIG_LIBDIR
		# We also don't want to look at or pick up anything from our own custom sysroot, to make sure vendoring works as intended in standalone projects
		export CPPFLAGS="${CPPFLAGS/-isystem${TC_BUILD_DIR}\/include/}"
		export LDFLAGS="${LDFLAGS/-L${TC_BUILD_DIR}\/lib /}"
		# NOTE: We might also want to link to libgcc/libstdc++ statically...
		#export LDFLAGS="${LDFLAGS} -static-libgcc"
		#export LDFLAGS="${LDFLAGS} -static-libstdc++"
	# And let's try to break some stuff w/ Clang (just the Gentoo ebuild w/ ARM in LLVM_TARGETS for now)
	elif [[ "${3}" == "clang" ]] || [[ "${3}" == "clang-gcc" ]] ; then
		echo "* With Clang :)"
		# Implies bare, because this is just a (fun?) experiment...
		# We don't want to pull any of our own libs through pkg-config
		unset PKG_CONFIG_DIR
		unset PKG_CONFIG_PATH
		unset PKG_CONFIG_LIBDIR
		# We also don't want to look at or pick up anything from our own custom sysroot, to make sure vendoring works as intended in standalone projects
		export CPPFLAGS="${CPPFLAGS/-isystem${TC_BUILD_DIR}\/include/}"
		export LDFLAGS="${LDFLAGS/-L${TC_BUILD_DIR}\/lib /}"
		# Setup Clang + lld
		# Strip unsupported flags
		export BASE_CFLAGS="${BASE_CFLAGS/ -frename-registers -fweb/}"
		export RICE_CFLAGS="${RICE_CFLAGS/ -frename-registers -fweb/}"
		export NOLTO_CFLAGS="${NOLTO_CFLAGS/ -frename-registers -fweb/}"
		export BASE_CFLAGS="${BASE_CFLAGS/ -fuse-linker-plugin/}"
		export RICE_CFLAGS="${RICE_CFLAGS/ -fuse-linker-plugin/}"
		# We need to tweak LTO flags (classic LTO is just -flto, while ThinLTO is -flto=thin, and will parallelize automatically to the right amount of cores).
		export BASE_CFLAGS="${BASE_CFLAGS/-flto=${AUTO_JOBS}/-flto=thin}"
		export RICE_CFLAGS="${RICE_CFLAGS/-flto=${AUTO_JOBS}/-flto=thin}"
		export CC="clang"
		export CXX="clang++"
		# NOTE: Swap between compiler-rt and libgcc
		#       c.f., x-clang-compiler-rt.sh to build compiler-rt in the first place ;).
		# NOTE: Don't run it blindly, though, as it's experimental, tailored to Gentoo, and (minimally) affects the host's rootfs!
		# NOTE: For C++, the general idea would be the same to swap to libunwind/libc++ via --stdlib=libc++ instead of libgcc_s/libstdc++ ;).
		# NOTE: c.f., https://archive.fosdem.org/2018/schedule/event/crosscompile/attachments/slides/2107/export/events/attachments/crosscompile/slides/2107/How_to_cross_compile_with_LLVM_based_tools.pdf for a good recap.
		if [[ "${3}" == "clang-gcc" ]] ; then
			export CFLAGS="--target=${CROSS_TC} --sysroot=$(${CROSS_TC}-gcc -print-sysroot) --gcc-toolchain=${HOME}/x-tools/${CROSS_TC} ${RICE_CFLAGS}"
			export CXXFLAGS="--target=${CROSS_TC} --sysroot=$(${CROSS_TC}-gcc -print-sysroot) --gcc-toolchain=${HOME}/x-tools/${CROSS_TC} ${RICE_CFLAGS}"
			export LDFLAGS="-fuse-ld=lld ${BASE_LDFLAGS}"
		else
			export CFLAGS="--target=${CROSS_TC} --sysroot=$(${CROSS_TC}-gcc -print-sysroot) ${RICE_CFLAGS}"
			export CXXFLAGS="--target=${CROSS_TC} --sysroot=$(${CROSS_TC}-gcc -print-sysroot) ${RICE_CFLAGS}"
			export LDFLAGS="--rtlib=compiler-rt -fuse-ld=lld ${BASE_LDFLAGS}"
		fi
		export AR="llvm-ar"
		export NM="llvm-nm"
		export RANLIB="llvm-ranlib"
		export STRIP="llvm-strip"
		# NOTE: There's also OBJDUMP, but we don't set it as part of our env, because nothing we currently build needs it (apparently).
	fi

	# And return happy now :)
	return 0
fi

## Some helper functions for extremely unfriendly build-systems (hi, meson!).
meson_setup() {
	# NOTE: Let's deal with Meson and its lack of support for env vars...
	#       c.f., https://github.com/gentoo/gentoo/blob/39008f571c7693e1bd34109614e02a39e6805a96/eclass/meson.eclass#L123
	cp -f ${SCRIPTS_BASE_DIR}/MesonCross.tpl MesonCross.txt
	sed -e "s#%CC%#$(command -v ${CROSS_TC}-gcc)#g" -i MesonCross.txt
	sed -e "s#%CXX%#$(command -v ${CROSS_TC}-g++)#g" -i MesonCross.txt
	sed -e "s#%AR%#$(command -v ${CROSS_TC}-gcc-ar)#g" -i MesonCross.txt
	sed -e "s#%STRIP%#$(command -v ${CROSS_TC}-strip)#g" -i MesonCross.txt
	sed -e "s#%PKGCONFIG%#${TC_BUILD_DIR}/bin/pkg-config#g" -i MesonCross.txt
	sed -e "s#%SYSROOT%#${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot#g" -i MesonCross.txt
	sed -e "s#%MARCH%#$(echo ${CFLAGS} | tr ' ' '\n' | grep mtune | cut -d'=' -f 2)#g" -i MesonCross.txt
	sed -e "s#%PREFIX%#${TC_BUILD_DIR}#g" -i MesonCross.txt

	# Deal with the *FLAGS insanity (see below)
	meson_flags=""
	for my_flag in $(echo ${CPPFLAGS} ${CFLAGS} | tr ' ' '\n') ; do
		meson_flags+="'${my_flag}', "
	done
	sed -e "s#%CFLAGS%#${meson_flags%,*}#" -i MesonCross.txt
	meson_flags=""
	for my_flag in $(echo ${CPPFLAGS} ${CXXFLAGS} | tr ' ' '\n') ; do
		meson_flags+="'${my_flag}', "
	done
	sed -e "s#%CXXFLAGS%#${meson_flags%,*}#" -i MesonCross.txt
	meson_flags=""
	for my_flag in $(echo ${LDFLAGS} | tr ' ' '\n') ; do
		meson_flags+="'${my_flag}', "
	done
	sed -e "s#%LDFLAGS%#${meson_flags%,*}#g" -i MesonCross.txt
	unset meson_flags

	# NOTE: This is in case we ever need an pkg-config wrapper again,
	#       if meson decides to enforce PKG_CONFIG_SYSROOT_DIR in another stupid way...
	# NOTE: Plus, we honor PKG_CONFIG from the env, so we can easily pass --static...
	if [[ "${MESON_NEEDS_PKGCFG_WRAPPER}" == "true" ]] ; then
		cat <<-EOF > "${TC_BUILD_DIR}/bin/pkg-config"
			#!/bin/sh
			exec ${PKG_CONFIG} --define-variable=prefix=/ "\$@"
		EOF
		chmod -cvR a+x "${TC_BUILD_DIR}/bin/pkg-config"
	fi
}

## Get to our build dir
mkdir -p "${TC_BUILD_DIR}"
cd "${TC_BUILD_DIR}"

## Clear local userstore...
if [[ -n "${DEVICE_USERSTORE}" ]] && [[ -d "${DEVICE_USERSTORE}" ]] ; then
	rm -rfv ${DEVICE_USERSTORE}/*
	# But re-create the USBNet directory, so that we actually install OpenSSH properly...
	mkdir -p "${DEVICE_USERSTORE}/usbnet"
fi

## And start building stuff!

## FT & FC for Fonts
# XXX: Look into Dead2/zlib-ng?
# XXX: Test gildor2/fast_zlib (c.f., ${SVN_ROOT}/Configs/trunk/Kindle/Misc/zlib-fast-zlib-longest_match.patch)?
# NOTE: Very, very quick tests show that zlib-ng is faster with fbgrab (compression -1), while fast_zlib is faster w/ IM (quality 75). Yay?
# NOTE: In fact, zlib-ng is potentially slower than vanilla in my IM use-case...
# FIXME: With *both* (i.e., zlib-ng + ${SVN_ROOT}/Configs/trunk/Kindle/Misc/zlib-ng-fast-zlib-longest_match.patch), fbgrab is fastest, and IM is between def and fast.
#       ... but I'm seeing corruption in fbgrab snaps... This is why we can't have nice thing :(.
#
# NOTE: Try going with zlib-ng, it at least has slightly more following than fast_zlib...
USE_ZLIB_NG="true"
if [[ "${USE_ZLIB_NG}" == "true" ]] ; then
	echo "* Building zlib-ng . . ."
	echo ""
	ZLIB_SOVER="1.2.11.zlib-ng"
	rm -rf zlib-ng
	until git clone --depth 1 https://github.com/zlib-ng/zlib-ng.git ; do
		rm -rf zlib-ng
		sleep 15
	done
	cd zlib-ng
	update_title_info
	# NOTE: We CANNOT support runtime HWCAP checks, because we mostly don't have access to getauxval (c.f., comments around OpenSSL for more details).
	#       On the other hand, we don't need 'em: we know the exact target we're running on.
	#       So switch back to compile-time checks.
	patch -p1 <  ${SVN_ROOT}/Configs/trunk/Kindle/Misc/zlib-ng-nerf-arm-hwcap.patch
	export CFLAGS="${RICE_CFLAGS}"
	if [[ "${KINDLE_TC}" == "K3" ]] ; then
		# No NEON, and no unaligned access!
		sed -e 's/-DUNALIGNED_OK//g' -i configure
		env CHOST="${CROSS_TC}" ./configure --shared --prefix=${TC_BUILD_DIR} --zlib-compat --without-acle --without-neon
	else
		env CHOST="${CROSS_TC}" ./configure --shared --prefix=${TC_BUILD_DIR} --zlib-compat --without-acle
	fi
	make ${JOBSFLAGS}
	make install
	export CFLAGS="${BASE_CFLAGS}"
	# NOTE: No need to sanitize the headers
else
	echo "* Building zlib . . ."
	echo ""
	ZLIB_SOVER="1.2.11"
	tar -I pigz -xvf /usr/portage/distfiles/zlib-1.2.11.tar.gz
	cd zlib-1.2.11
	patch -p1 < /usr/portage/sys-libs/zlib/files/zlib-1.2.11-fix-deflateParams-usage.patch
	patch -p1 < /usr/portage/sys-libs/zlib/files/zlib-1.2.11-minizip-drop-crypt-header.patch
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
fi
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
EXPAT_SOVER="1.6.11"
tar -xvJf /usr/portage/distfiles/expat-2.2.9.tar.xz
cd expat-2.2.9
update_title_info
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-docbook
make ${JOBSFLAGS}
make install

## NOTE: This is called from a function because we need to do two sets of builds in the same TC run to handle a weird, but critical issue with GCC 5 on the K4...
## NOTE: The shitty news is that it still happens with Linaro 7.2 2017.11 & binutils 2.30... :(
Build_FreeType_Stack() {
	## HarfBuzz for FT's authinter
	# Funnily enough, it depends on freetype too...
	# NOTE: I thought I *might* have to disable TT_CONFIG_OPTION_COLOR_LAYERS in snapshots released after 2.9.1_p20180512,
	#       but in practice in turns out that wasn't needed ;).
	FT_VER="2.10.1_p20200204"
	FT_SOVER="6.17.1"
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
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-bzip2 --without-harfbuzz --without-png --disable-freetype-config
	make ${JOBSFLAGS}
	make install
	# NOTE: Because libtool is the pits, we rely on our prune_la_files helper (folded into update_title_info) to get rid of installed .la files.
	#       In practical terms, this prevents libtool from expanding -llib flags into absolute/path/lib.so for libraries linked w/ libtool.
	#       Because besides being blatantly insane on modern systems, in the specific instance of freetype & harfbuzz, which are in the peculiar position of being circular dependencies,
	#       that would generate a final freetype library with a freetype DT_NEEDED entry... >_<"

	echo "* Building harfbuzz . . ."
	echo ""
	cd ..
	HB_SOVER="0.20600.4"
	#rm -rf harfbuzz
	#tar -xvJf /usr/portage/distfiles/harfbuzz-2.6.2_p20190930.tar.xz
	#cd harfbuzz
	rm -rf harfbuzz-2.6.4
	tar -xvJf /usr/portage/distfiles/harfbuzz-2.6.4.tar.xz
	cd harfbuzz-2.6.4
	update_title_info
	env NOCONFIGURE=1 sh autogen.sh
	# Make sure libtool doesn't eat any our of our CFLAGS when linking...
	export AM_LDFLAGS="${XC_LINKTOOL_CFLAGS}"
	export CXXFLAGS="${BASE_CFLAGS} -std=gnu++14 -Wno-narrowing"
	# Add the same rpath as FT...
	export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=/var/local/linkfonts/lib -Wl,-rpath=${DEVICE_USERSTORE}/linkfonts/lib -Wl,-rpath=${DEVICE_USERSTORE}/linkss/lib"
	# NOTE: Needed to properly link FT... For some reason gold did not care, while bfd does...
	export PKG_CONFIG="pkg-config --static"
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-coretext --without-fontconfig --without-uniscribe --without-cairo --without-glib --without-gobject --without-graphite2 --without-icu --disable-introspection --with-freetype
	make ${JOBSFLAGS} V=1
	make install
	export CXXFLAGS="${BASE_CFLAGS}"
	unset AM_LDFLAGS
	# Install the shared version, to avoid the circular dep FT -> HB -> FT...
	cp ../lib/libharfbuzz.so.${HB_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libharfbuzz.so.${HB_SOVER%%.*}
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libharfbuzz.so.${HB_SOVER%%.*}
	# We also need it for the K5 ScreenSavers hack, because the pinfo support relies on it, and Amazon's FT build is evil (it segfaults since FW 5.6.1)...
	# Now that we link IM dynamically, everybody needs it :).
	cp ../lib/libharfbuzz.so.${HB_SOVER} ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libharfbuzz.so.${HB_SOVER%%.*}
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libharfbuzz.so.${HB_SOVER%%.*}
	unset PKG_CONFIG
	export LDFLAGS="${BASE_LDFLAGS}"

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
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-bzip2 --with-harfbuzz --without-png --disable-freetype-config
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
	#patch -p1 < /usr/portage/media-libs/freetype/files/freetype-2.7-enable-valid.patch
	#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-kindle-num_grays-16.patch
	sh autogen.sh
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-bzip2 --with-harfbuzz --without-png --disable-freetype-config
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
	#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-2.6.2-spr-fir-filter-weight-to-gibson-coeff.patch
	sh autogen.sh
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-bzip2 --with-harfbuzz --without-png --disable-freetype-config
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
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-bzip2 --with-harfbuzz --without-png --disable-freetype-config
	make ${JOBSFLAGS}
	make install
	cp ../lib/libfreetype.so.${FT_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/bci/libfreetype.so
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/bci/libfreetype.so
	# As with harfbuzz, we need it for the K5 ScreenSavers hack, because the pinfo support relies on it, and Amazon's FT build is evil (it segfaults since FW 5.6.1)...
	# Now that we link IM dynamically, everybody needs it :).
	cp ../lib/libfreetype.so.${FT_SOVER} ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libfreetype.so.${FT_SOVER%%.*}
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libfreetype.so.${FT_SOVER%%.*}
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

## FIXME: Apparently, when using an FT override built with GCC >= 5 (at least Linaro 5.2 2015.09), the framework will crash and fail to start on legacy devices (<= K4), which is bad.
##        To avoid breaking stuff, use an older GCC 4.9 (Linaro 2015.06) TC, at least for the K3 & K5 builds.
##        AFAICT, it appears to work fine on anything running FW 5.x, though (even a Kindle Touch), so don't do anything special with the PW2 builds.
## NOTE:  Still happening with Linaro 7.2 2017.11 & binutils 2.30. :(
##        Building the full FT stack with -static-libgcc doesn't help.
##        So we're currently using Linaro 4.9 2017.01 & binutils 2.30...
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

## Build util-linux (for libuuid, needed by fontconfig)
echo "* Building util-linux . . ."
echo ""
cd ..
tar -xvJf /usr/portage/distfiles/util-linux-2.35.tar.xz
cd util-linux-2.35
update_title_info
sed -i -E \
	-e '/NCURSES_/s:(ncursesw?)[56]-config:$PKG_CONFIG \1:' \
	-e 's:(ncursesw?)[56]-config --version:$PKG_CONFIG --exists --print-errors \1:' \
	configure
libtoolize
export scanf_cv_alloc_modifier=ms
# FIXME: bfd insists on libuuid being built PIC...
if [[ "${CTNG_LD_IS}" == "bfd" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=no --enable-static=yes --disable-makeinstall-chown --disable-makeinstall-setuid --without-python --without-readline --without-slang --without-systemd --without-udev --without-ncursesw --without-ncurses --enable-widechar --without-selinux --without-tinfo --disable-all-programs --disable-bash-completion --without-systemdsystemunitdir --enable-libuuid --disable-libblkid --disable-libsmartcols --disable-libfdisk --disable-libmount --without-cryptsetup --with-pic
else
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=no --enable-static=yes --disable-makeinstall-chown --disable-makeinstall-setuid --without-python --without-readline --without-slang --without-systemd --without-udev --without-ncursesw --without-ncurses --enable-widechar --without-selinux --without-tinfo --disable-all-programs --disable-bash-completion --without-systemdsystemunitdir --enable-libuuid --disable-libblkid --disable-libsmartcols --disable-libfdisk --disable-libmount --without-cryptsetup
fi
make ${JOBSFLAGS}
make install
unset scanf_cv_alloc_modifier

## Build FC
echo "* Building fontconfig . . ."
echo ""
FC_SOVER="1.12.0"
FC_VER="2.13.91_p20191209"
cd ..
tar -xvJf /usr/portage/distfiles/fontconfig-${FC_VER}.tar.xz
cd fontconfig
update_title_info
# Fix Makefile for LTO...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/fontconfig-fix-Makefile-for-lto.patch
patch -p1 < /usr/portage/media-libs/fontconfig/files/fontconfig-2.12.3-latin-update.patch
patch -p1 < /usr/portage/media-libs/fontconfig/files/fontconfig-2.10.2-docbook.patch
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/fontconfig-2.10.0-do-not-deprecate-dotfile.patch
# NOTE: Pick-up our own expat via rpath, we're using expat 2.1.0, the Kindle is using 2.0.0 (and it's not in the tree anymore). Same from FT & HB.
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/linkfonts/lib"
# NOTE: Needed to properly link FT...
export PKG_CONFIG="pkg-config --static"
env NOCONFIGURE=1 sh autogen.sh
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=no --disable-docs --disable-docbook --localstatedir=/var --with-templatedir=/etc/fonts/conf.avail --with-baseconfigdir=/etc/fonts --with-xmldir=/etc/fonts --with-arch=arm --with-expat=${TC_BUILD_DIR}
make ${JOBSFLAGS} V=1
make install-exec
make install-pkgconfigDATA
cp ../lib/libfontconfig.so.${FC_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libfontconfig.so.${FC_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libfontconfig.so.${FC_SOVER%%.*}
cp ../lib/libexpat.so.${EXPAT_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libexpat.so.${EXPAT_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libexpat.so.${EXPAT_SOVER%%.*}
cp ../lib/libz.so.${ZLIB_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libz.so.${ZLIB_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libz.so.${ZLIB_SOVER%%.*}
## NOTE: Keep a copy of the shared version, to check if it behaves...
cp ../bin/fc-scan ${BASE_HACKDIR}/Fonts/src/linkfonts/bin/shared_fc-scan
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/bin/shared_fc-scan

## XXX: And then build it statically (at least as far as libfontconfig is concerned) for fc-scan,
##      because for some unknown and baffling reason, linking it dynamically leaves us with a binary that loops forever,
##      which horribly breaks the boot on legacy devices when the KF8 support is enabled in the fonts hack...
## NOTE: Historically, there was also apparently weird semi-random segfaults (c.f., http://trac.ak-team.com/trac/changeset/7146/niluje).
##       But given the age of said commit (8 years!), I really can't remember the details...
##       After that, during the switch to LTO, the consistent looping issue appeared.
##       I just happened to quickly re-check a current binary, on a K4, built after the prune_la_files fix (Linaro 7.2 2017.11, binutils 2.30),
##       and I saw neither issues...
##       But given the history, and the finicky nature of this crap, let's keep that workaround in...
cd ..
rm -rf fontconfig
tar -xvJf /usr/portage/distfiles/fontconfig-${FC_VER}.tar.xz
cd fontconfig
update_title_info
# Fix Makefile for LTO...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/fontconfig-fix-Makefile-for-lto.patch
patch -p1 < /usr/portage/media-libs/fontconfig/files/fontconfig-2.12.3-latin-update.patch
patch -p1 < /usr/portage/media-libs/fontconfig/files/fontconfig-2.10.2-docbook.patch
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/fontconfig-2.10.0-do-not-deprecate-dotfile.patch
env NOCONFIGURE=1 sh autogen.sh
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=no --enable-static=yes --disable-docs --disable-docbook --localstatedir=/var --with-templatedir=/etc/fonts/conf.avail --with-baseconfigdir=/etc/fonts --with-xmldir=/etc/fonts --with-arch=arm --with-expat=${TC_BUILD_DIR}
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
tar xvJf /usr/portage/distfiles/coreutils-8.31.tar.xz
cd coreutils-8.31
update_title_info
tar xvJf /usr/portage/distfiles/coreutils-8.30-patches-01.tar.xz
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	## Dirty hack to avoid pulling the __sched_cpucount@GLIBC_2.6 symbol from <sched.h> in sort.c (through lib/nproc.c), since we only have glibc 2.5 on the target. (Needed since coreutils 8.6)
	sed -e "s/CPU_COUNT/GLIBC_26_CPU_COUNT/g" -i lib/nproc.c
fi
for patchfile in patch/*.patch ; do
	patch -p1 < ${patchfile}
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
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-libcap --disable-nls --disable-acl --disable-xattr --without-gmp --enable-install-program=hostname
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
if [[ "${BUILD_UPSTREAM_LIBTOM}" == "true" ]] ; then
	# We build libtommath & libtomcrypt ourselves in an attempt to avoid the performance regressions on ARM of the stable releases... FWIW, it's still there :/.
	echo "* Building libtommath . . ."
	echo ""
	cd ..
	rm -rf libtommath
	until git clone -b develop --single-branch --depth 1 https://github.com/libtom/libtommath.git libtommath ; do
		rm -rf libtommath
		sleep 15
	done
	cd libtommath
	update_title_info
	# NOTE: Upstream force enables -funroll-loops, assume it's for a reason, so make it actually useful by combining it with ftree-vectorize
	export CFLAGS="${CPPFLAGS} ${RICE_CFLAGS}"
	sed -i -e '/CFLAGS += -O3 -funroll-loops/d' makefile_include.mk
	sed -i -e 's/-O3//g' etc/makefile
	sed -i -e 's/-funroll-loops//g' etc/makefile
	make ${JOBSFLAGS} CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" INCPATH=${TC_BUILD_DIR}/include LIBPATH=${TC_BUILD_DIR}/lib V=1
	make ${JOBSFLAGS} CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" INCPATH=${TC_BUILD_DIR}/include LIBPATH=${TC_BUILD_DIR}/lib INSTALL_USER=$(id -u) INSTALL_GROUP=$(id -g) install
	export CFLAGS="${BASE_CFLAGS}"

	echo "* Building libtomcrypt . . ."
	echo ""
	cd ..
	rm -rf libtomcrypt
	until git clone -b develop --single-branch https://github.com/libtom/libtomcrypt.git libtomcrypt ; do
		rm -rf libtomcrypt
		sleep 15
	done
	cd libtomcrypt
	update_title_info
	# FIXME: Peg a commit before the ECC API changes...
	#        ... At least until the dropbear changes (https://github.com/karel-m/dropbear/commits/new-libtomcrypt) get merged upstream.
	#git checkout a528528a2b0bbce7f894c6b572611d80b9705ede
	# Enable the math descriptors for dropbear's ECC support
	export CFLAGS="${CPPFLAGS} -DUSE_LTM -DLTM_DESC ${RICE_CFLAGS}"
	sed -i -e '/CFLAGS += -O3 -funroll-loops/d' makefile_include.mk
	make ${JOBSFLAGS} CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1
	make ${JOBSFLAGS} CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" INCPATH=${TC_BUILD_DIR}/include LIBPATH=${TC_BUILD_DIR}/lib DATAPATH=${TC_BUILD_DIR}/share INSTALL_USER=$(id -u) INSTALL_GROUP=$(id -g) NODOCS=true install
	export CFLAGS="${BASE_CFLAGS}"
fi

echo "* Building dropbear . . ."
echo ""
cd ..
DROPBEAR_SNAPSHOT="2019.78_p20191018"
wget http://files.ak-team.com/niluje/gentoo/dropbear-${DROPBEAR_SNAPSHOT}.tar.xz -O dropbear-${DROPBEAR_SNAPSHOT}.tar.xz
tar -xvJf dropbear-${DROPBEAR_SNAPSHOT}.tar.xz
cd dropbear
update_title_info
# NOTE: As mentioned earlier, on Kobos, let dropbear live in the internal memory to avoid trouble...
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	DEVICE_USERSTORE="${DEVICE_INTERNAL_USERSTORE}"
fi
# Apply a few things that haven't even hit upstream yet ;).
# This is https://github.com/mkj/dropbear/pull/61
# tweaked a bit to play nice with the craptastically old glibc of the K3 TC
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-pr61.patch
# This is https://github.com/mkj/dropbear/pull/80
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-pr80.patch
# This is https://github.com/mkj/dropbear/pull/83
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-pr83.patch
# This is https://github.com/mkj/dropbear/pull/86
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-pr86.patch
# This is https://github.com/karel-m/dropbear/commit/4530ff68975932680d674a33ea477fa7afc79ade
# updated for https://github.com/libtom/libtomcrypt/pull/423
# FIXME: Broken right now (Exit before auth: ECC error)
#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-tomcrypt-1.19-compat.patch
# Gentoo patches/tweaks
patch -p1 < /usr/portage/net-misc/dropbear/files/dropbear-0.46-dbscp.patch
sed -i -e "/SFTPSERVER_PATH/s:\".*\":\"${DEVICE_USERSTORE}/usbnet/libexec/sftp-server\":" default_options.h
sed -i -e '/pam_start/s:sshd:dropbear:' svr-authpam.c
sed -i -e "/DSS_PRIV_FILENAME/s:\".*\":\"${DEVICE_USERSTORE}/usbnet/etc/dropbear_dss_host_key\":" -e "/RSA_PRIV_FILENAME/s:\".*\":\"${DEVICE_USERSTORE}/usbnet/etc/dropbear_rsa_host_key\":" -e "/ECDSA_PRIV_FILENAME/s:\".*\":\"${DEVICE_USERSTORE}/usbnet/etc/dropbear_ecdsa_host_key\":" default_options.h
sed -e 's%#define DROPBEAR_X11FWD 1%#define DROPBEAR_X11FWD 0%' -i default_options.h
sed -i -e "/DROPBEAR_PIDFILE/s:\".*\":\"${DEVICE_USERSTORE}/usbnet/run/sshd.pid\":" default_options.h
# This only affects the bundled libtom, but disable it anyway
sed -e 's%#define DROPBEAR_SMALL_CODE 1%#define DROPBEAR_SMALL_CODE 0%' -i default_options.h
# Moar crypto!
sed -e 's%#define DROPBEAR_BLOWFISH 0%#define DROPBEAR_BLOWFISH 1%' -i default_options.h
# We want our MOTD! It has critical information on Kindles!
sed -e 's%#define DO_MOTD 0%#define DO_MOTD 1%' -i default_options.h
# Ensure we have a full path, like with telnet, on Kobo devices, since ash doesn't take care of it for us...
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	sed -e '/DEFAULT_PATH/s:".*":"/sbin\:/usr/sbin\:/bin\:/usr/bin":' -i default_options.h
fi
# Show /etc/issue (on Kindle only)
if [[ "${KINDLE_TC}" != "KOBO" ]] ; then
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-kindle-show-issue.patch
fi
# No passwd...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2019.77-kindle-nopasswd-hack.patch
# Pubkeys in ${DEVICE_USERSTORE}/usbnet/etc/authorized_keys & with perms checks curbed a bit
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2019.77-kindle-pubkey-hack.patch
# Fix the Makefile so that LTO flags aren't dropped in the linking stage...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-fix-Makefile-for-lto.patch
# Kill bundled libtom, we're using our own, from the latest develop branch
# FIXME: Not currently, because of growing API mismatches (c.f., the pegged libtomcrypt commit, and https://github.com/mkj/dropbear/pull/84 for libtommath 1.2.x)
#rm -rf libtomcrypt libtommath
# Fix userstore path on Kobos...
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	sed -e "s#/mnt/us#${DEVICE_USERSTORE}#g" -i svr-authpubkey.c
	# And the logs, we're on a Kobo, not a Kindle ;)
	sed -e "s#Kindle#Kobo#g" -i svr-authpasswd.c
fi
autoreconf -fi
# Use the same CFLAGS as libtom*
export CFLAGS="${RICE_CFLAGS}"
# We now ship our own shared zlib, so let's use it
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
#export CFLAGS="${BASE_CFLAGS/-ffast-math /}"
# NOTE: Can't use FORTIFY_SOURCE on the K3... (with our general nerfs in place, that'd only pull a single offending symbol: __vasprintf_chk@GLIBC_2.8)
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-lastlog --enable-zlib --enable-openpty --enable-shadow --enable-syslog --enable-bundled-libtom --disable-harden
else
	# FIXME: Since 2018.76, enabling hardening support is wonderfully broken on at least PW2 & Kobo: connection hangs on SSH2_MSG_KEX_ECDH_REPLY, and leaves a dropbear process hogging 100% CPU!
	#        It *may* be CFLAGS related, since it only starts happening with https://github.com/mkj/dropbear/commit/8d0b48f16550c9bf3693b2fa683f21e8276b1b1a#diff-67e997bcfdac55191033d57a16d1408a
	#        applied...
	# NOTE:  This is also possibly related to the fact that it's the first release where hardening is enabled by default, and the culprit here might be PIE,
	#        since we certainly don't build anything else PIE, and mixing PIE code with non-PIE code is a sure recipe for weird shit happening...
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-lastlog --enable-zlib --enable-openpty --enable-shadow --enable-syslog --enable-bundled-libtom --disable-harden
fi
make ${JOBSFLAGS} MULTI=1 PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp"
export LDFLAGS="${BASE_LDFLAGS}"
export CFLAGS="${BASE_CFLAGS}"
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
	rm -rf dropbear
	wget http://files.ak-team.com/niluje/gentoo/dropbear-${DROPBEAR_SNAPSHOT}.tar.xz -O dropbear-${DROPBEAR_SNAPSHOT}.tar.xz
	tar -xvJf dropbear-${DROPBEAR_SNAPSHOT}.tar.xz
	cd dropbear
	update_title_info
	# And apply a few things that haven't even hit upstream yet ;).
	# This is https://github.com/mkj/dropbear/pull/61
	# tweaked a bit to play nice with the craptastically old glibc of the K3 TC
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-pr61.patch
	# This is https://github.com/mkj/dropbear/pull/80
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-pr80.patch
	# This is https://github.com/mkj/dropbear/pull/83
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-pr83.patch
	# This is https://github.com/mkj/dropbear/pull/86
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-pr86.patch
	# This is https://github.com/karel-m/dropbear/commit/4530ff68975932680d674a33ea477fa7afc79ade
	# updated for https://github.com/libtom/libtomcrypt/pull/423
	# FIXME: Broken right now (Exit before auth: ECC error)
	#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-tomcrypt-1.19-compat.patch
	# Gentoo patches/tweaks
	patch -p1 < /usr/portage/net-misc/dropbear/files/dropbear-0.46-dbscp.patch
	sed -i -e "/SFTPSERVER_PATH/s:\".*\":\"${DEVICE_USERSTORE}/usbnet/libexec/sftp-server\":" default_options.h
	sed -i -e '/pam_start/s:sshd:dropbear:' svr-authpam.c
	sed -e 's%#define DROPBEAR_X11FWD 1%#define DROPBEAR_X11FWD 0%' -i default_options.h
	# This only affects the bundled libtom, but disable it anyway
	sed -e 's%#define DROPBEAR_SMALL_CODE 1%#define DROPBEAR_SMALL_CODE 0%' -i default_options.h
	# Moar crypto!
	sed -e 's%#define DROPBEAR_BLOWFISH 0%#define DROPBEAR_BLOWFISH 1%' -i default_options.h
	# We want our MOTD! It has critical information on Kindles!
	sed -e 's%#define DO_MOTD 0%#define DO_MOTD 1%' -i default_options.h
	# More diags specific tweaks
	sed -e '/_PATH_SSH_PROGRAM/s:".*":"/usr/local/bin/dbclient":' -i default_options.h
	sed -e '/DEFAULT_PATH/s:".*":"/usr/local/bin\:/usr/bin\:/bin":' -i default_options.h
	# Show /etc/issue
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-kindle-show-issue.patch
	# No passwd...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2019.77-kindle-nopasswd-hack.patch
	# Pubkeys in ${DEVICE_USERSTORE}/usbnet/etc/authorized_keys & with perms checks curbed a bit
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2019.77-kindle-pubkey-hack.patch
	# Enable the no password mode by default
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2018.76-kindle-nopasswd-hack-as-default.patch
	# Fix the Makefile so that LTO flags aren't dropped in the linking stage...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-fix-Makefile-for-lto.patch
	# Kill bundled libtom, we're using our own, from the latest develop branch
	#rm -rf libtomcrypt libtommath
	autoreconf -fi
	# Use the same CFLAGS as libtom*
	export CFLAGS="${RICE_CFLAGS}"
	# Build that one against a static zlib...
	for db_dep in libz.so libz.so.${ZLIB_SOVER%%.*} libz.so.${ZLIB_SOVER} ; do mv -v ../lib/${db_dep} ../lib/_${db_dep} ; done
	# NOTE: Disable hardeneing, always, we don't know how weird some diags build may be...
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-lastlog --enable-zlib --enable-openpty --enable-shadow --enable-syslog --enable-bundled-libtom --disable-harden
	make ${JOBSFLAGS} MULTI=1 PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp"
	for db_dep in libz.so libz.so.${ZLIB_SOVER%%.*} libz.so.${ZLIB_SOVER} ; do mv -v ../lib/_${db_dep} ../lib/${db_dep} ; done
	export CFLAGS="${BASE_CFLAGS}"
	${CROSS_TC}-strip --strip-unneeded dropbearmulti
	cp dropbearmulti ${BASE_HACKDIR}/RescuePack/src/dropbearmulti
fi

echo "* Building rsync . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/rsync-3.1.3.tar.gz
cd rsync-3.1.3
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

	# XXX: Someone will have to explain that one to me. This is supposed to one day replace glibc's rpc support, which isn't built by default anymore... and yet it requires the glibc's rpc headers at build time. WTF?!
	# At least I'm not alone to have noticed... but nobody seems to care. (cf. http://sourceforge.net/p/libtirpc/bugs/25/, which is roughly 4 years old).
	# Work that shit around by siphoning the headers from our K5 TC, which is the closest match...
	mkdir -p include/rpcsvc
	cp -v ${HOME}/x-tools/arm-kindle5-linux-gnueabi/arm-kindle5-linux-gnueabi/sysroot/usr/include/rpcsvc/nis.h include/rpcsvc/
	cp -v ${HOME}/x-tools/arm-kindle5-linux-gnueabi/arm-kindle5-linux-gnueabi/sysroot/usr/include/rpcsvc/nis_tags.h include/rpcsvc/
	cp -v ${HOME}/x-tools/arm-kindle5-linux-gnueabi/arm-kindle5-linux-gnueabi/sysroot/usr/include/rpcsvc/nislib.h include/rpcsvc/

	echo "* Building TI-RPC . . ."
	# XXX: For added fun, linking this w/ LTO fucks it up silently (broken pmap_* symbols)... (Linaro GCC 4.9 2015.04-1 & Linaro binutils 2.25.0-2015.01-2)
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
cd ..
tar -I lbzip2 -xvf /usr/portage/distfiles/busybox-1.31.1.tar.bz2
cd busybox-1.31.1
update_title_info
# FIXME: Workarounds conflicting typedefs between <unistd.h> and <linux/types.h> because of the terribly old kernel we're using...
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	export CPPFLAGS="${BASE_CPPFLAGS} -D__KERNEL_STRICT_NAMES"
fi
# NOTE: We won't be resetting CROSS_COMPILE, a few other packages down the line make use of it...
#       It being slightly non-standard may explain why I never simply made it part of the env setup?
export CROSS_COMPILE="${CROSS_TC}-"
#export CFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
#export CXXFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
#patch -p1 < /usr/portage/sys-apps/busybox/files/busybox-1.26.2-bb.patch
for patchfile in /usr/portage/sys-apps/busybox/files/busybox-1.31.1-*.patch ; do
	[[ -f "${patchfile}" ]] && patch -p1 < ${patchfile}
done
#cp /usr/portage/sys-apps/busybox/files/ginit.c init/
sed -i -r -e 's:[[:space:]]?-(Werror|Os|falign-(functions|jumps|loops|labels)=1|fomit-frame-pointer)\>::g' Makefile.flags
# Print issue & auth as root without pass over telnet...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/busybox-1.31.1-kindle-nopasswd-hack.patch
# Look for ash profile & history in usbnet/etc
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/busybox-1.31.1-ash-home.patch
sed -e "s#%DEVICE_USERSTORE%#${DEVICE_USERSTORE}#g" -i shell/ash.c
# Apply the depmod patch on Kobo
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/busybox-1.28.4-kobo-depmod.patch
fi

make allnoconfig
sleep 5
## Busybox config...
cat << EOF

	* Settings >
	Support --long-options
	Show applet usage messages
	Enable locale
	Support Unicode [w/o libc routines, they're FUBAR on Kobo due to lack of locales]
	Use sendfile system call
	devpts
	utmp
	wtmp
	Include busybox applet
	SUID (solo)
	exec prefers applets

	* Settings -- Library Tuning >
	Enable fractional duration arguments
	MD5: 0
	SHA3: 0
	faster /proc
	Command line editing
	History saving
	Reverse history search
	Tab completion
		Username completion
	Fancy shell prompts
	Query cursor position from terminal
	Enable locale support
	Support Unicode
		Check $LC_ALL, $LC_CTYPE and $LANG environment variables
		Allow zero-width Unicode characters on output
		Allow wide Unicode characters on output
		Bidirectional character-aware line input
			In bidi input, support non-ASCII neutral chars too
		Make it possible to enter sequences of chars which are not Unicode
	Use sendfile system call
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
		Enable -w (upload commands)
	httpd
	inetd
	telnetd

	* Applets > Shell >
	ash	[w/o Idle timeout; Check for new mail; Optimize for size]
	cttyhack
	Alias sh & bash to ash
	POSIX math
	Hide message...
	read -t N.NNN support
	Use HISTFILESIZE

EOF
#make menuconfig
# NOTE: Enable modutils on Kobo, and workaround the broken locales/multibyte handling of its hobbled libc...
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	cp -v ${SVN_ROOT}/Configs/trunk/Kindle/Misc/busybox-1.31.0-kobo-depmod-config .config
else
	cp -v ${SVN_ROOT}/Configs/trunk/Kindle/Misc/busybox-1.31.0-config .config
fi
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
if [[ "${KINDLE_TC}" == "K3" ]] ; then
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
	cp -v ${SVN_ROOT}/Configs/trunk/Kindle/Misc/busybox-1.31.0-gandalf-config .config
	make oldconfig
	sleep 5
	make ${JOBSFLAGS} AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1
	cp busybox ${BASE_HACKDIR}/DevCerts/src/install/gandalf
fi


echo "* Building OpenSSL 1.1.1 . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/openssl-1.1.1d.tar.gz
cd openssl-1.1.1d
update_title_info
OPENSSL_SOVER="1.1"
export CPPFLAGS="${BASE_CPPFLAGS} -DOPENSSL_NO_BUF_FREELISTS"
#export CFLAGS="${CPPFLAGS} ${BASE_CFLAGS} -fno-strict-aliasing"
export CFLAGS="${CPPFLAGS} ${BASE_CFLAGS}"
#export CXXFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wa,--noexecstack -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib -Wl,-rpath=${DEVICE_USERSTORE}/python3/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib"
rm -f Makefile
patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.1.0j-parallel_install_fix.patch
patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.1.1d-fix-zlib.patch
patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.1.1d-fix-potential-memleaks-w-BN_to_ASN1_INTEGER.patch
patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.1.1d-reenable-the-stitched-AES-CBC-HMAC-SHA-implementations.patch
# FIXME: Periodically check if the Kernel has been tweaked, and we can use the PMCCNTR in userland.
# NOTE: When Amazon ported FW 5.4.x to the PW1, they apparently helpfully backported this regression too, so apply that to K5 builds, too...
# NOTE: Since OpenSSL 1.0.2, there's also the crypto ARMv8 stuff, but that of course will never happen for us, so we can just ditch it.
# NOTE: Appears to be okay on Kobo... Or at least it doesn't spam dmesg ;).
if [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "K3" ]] ; then
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/openssl-1.1.1d-nerf-armv7_tick_armv8-armcaps.patch
fi
# NOTE: getauxval appeared in glibc 2.16, but we can't pick it up on Kobo, since those run eglibc 2_15... Nerf it (if we're using glibc 2.16).
# XXX: Same deal for the PW2-against-glibc-2.19 ...
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
sed -i -e '/^MANSUFFIX/s:=.*:=ssl:' -e "/^MAKEDEPPROG/s:=.*:=${CROSS_TC}-gcc:" -e '/^install:/s:install_docs::' Configurations/unix-Makefile.tmpl
cp /usr/portage/dev-libs/openssl/files/gentoo.config-1.0.2 gentoo.config
chmod a+rx gentoo.config
sed -e '/^$config{dirs}/s@ "test",@@' -i Configure
sed -i '/stty -icanon min 0 time 50; read waste/d' config
#unset CROSS_COMPILE
# We need it to be PIC, or mosh fails to link (not an issue anymore, now that we use a shared lib)
#./Configure linux-armv4 -DL_ENDIAN ${BASE_CFLAGS} -fno-strict-aliasing enable-camellia enable-mdc2 enable-tlsext enable-zlib --prefix=${TC_BUILD_DIR} --openssldir=${TC_BUILD_DIR}/etc/ssl shared threads
env CFLAGS= LDFLAGS= ./Configure linux-armv4 -DL_ENDIAN enable-camellia enable-ec enable-srp enable-idea enable-mdc2 enable-rc5 enable-asm enable-heartbeats enable-zlib --prefix=${TC_BUILD_DIR} --openssldir=${TC_BUILD_DIR}/etc/ssl shared threads
grep '^CFLAGS=' Makefile | LC_ALL=C sed -e 's:^CFLAGS=::' -e 's:\(^\| \)-fomit-frame-pointer::g' -e 's:\(^\| \)-O[^ ]*::g' -e 's:\(^\| \)-march=[^ ]*::g' -e 's:\(^\| \)-mcpu=[^ ]*::g' -e 's:\(^\| \)-m[^ ]*::g' -e 's:^ *::' -e 's: *$::' -e 's: \+: :g' -e 's:\\:\\\\:g' > x-compile-tmp
DEFAULT_CFLAGS="$(< x-compile-tmp)"
sed -i -e "/^CFLAGS=/s|=.*|=${DEFAULT_CFLAGS} ${CFLAGS}|" -e "/^LDFLAGS=/s|=[[:space:]]*$|=${LDFLAGS}|" Makefile
make -j1 AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1 depend
make AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1 all
make AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" V=1 install
# XXX: If we want to only link statically because FW 5.1 moved to OpenSSL 1 while FW 5.0 was on OpenSSL 0.9.8...
# NOTE: It's now irrelevant anyway, we alwyas use our own shared version via rpath.
#rm -fv ../lib/engines/lib*.so ../lib/libcrypto.so ../lib/libcrypto.so.${OPENSSL_SOVER} ../lib/libssl.so ../lib/libssl.so.${OPENSSL_SOVER}

# Copy it for the USBNet rpath...
for ssl_lib in libcrypto.so.${OPENSSL_SOVER} libssl.so.${OPENSSL_SOVER} ; do
	cp -f ../lib/${ssl_lib} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
	chmod -cvR ug+w ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
done
export CPPFLAGS="${BASE_CPPFLAGS}"
export CFLAGS="${BASE_CFLAGS}"
export LDFLAGS="${BASE_LDFLAGS}"
unset DEFAULT_CFLAGS

echo "* Building OpenSSH . . ."
echo ""
cd ..
OPENSSH_VERSION="8.1p1"
tar -I pigz -xvf /usr/portage/distfiles/openssh-${OPENSSH_VERSION}.tar.gz
cd openssh-${OPENSSH_VERSION}
update_title_info
#tar xvJf /usr/portage/distfiles/openssh-7.9p1-patches-1.0.tar.xz
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
# XXX: Needed on the K5 because of the 0.9.8 -> 1.0.0 switch,
# XXX: and needed on the K3, because OpenSSH (client) segfaults during the hostkey exchange with Amazon's bundled OpenSSL lib (on FW 2.x at least)
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
# Why, oh why are you finding ar in a weird way?
export ac_cv_path_AR=${CROSS_TC}-gcc-ar
sed -i -e '/_PATH_XAUTH/s:/usr/X11R6/bin/xauth:/usr/bin/xauth:' pathnames.h
sed -i '/^AuthorizedKeysFile/s:^:#:' sshd_config
patch -p1 < /usr/portage/net-misc/openssh/files/openssh-7.9_p1-include-stdlib.patch
patch -p1 < /usr/portage/net-misc/openssh/files/openssh-8.1_p1-GSSAPI-dns.patch
patch -p1 < /usr/portage/net-misc/openssh/files/openssh-6.7_p1-openssl-ignore-status.patch
patch -p1 < /usr/portage/net-misc/openssh/files/openssh-7.5_p1-disable-conch-interop-tests.patch
patch -p1 < /usr/portage/net-misc/openssh/files/openssh-8.0_p1-fix-putty-tests.patch
for patchfile in patch/*.patch ; do
	[[ -f "${patchfile}" ]] && patch -p1 < ${patchfile}
done
# Pubkeys in ${DEVICE_USERSTORE}/usbnet/etc/authorized_keys & with perms checks curbed a bit
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/openssh-${OPENSSH_VERSION}-kindle-pubkey-hack.patch
# Curb some more permission checks to avoid dying horribly on FW >= 5.3.9...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/openssh-${OPENSSH_VERSION}-kindle-perm-hack.patch
# Fix Makefile to actually make use of LTO ;).
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/openssh-8.1p1-fix-Makefile-for-lto.patch
sed -i -e "s:-lcrypto:$(pkg-config --libs ../lib/pkgconfig/openssl.pc):" configure{,.ac}
sed -i -e 's:^PATH=/:#PATH=/:' configure{,.ac}
# Tweak a whole lot of paths to suit our needs...
# NOTE: This is particularly ugly, but the code handles $HOME from the passwd db itself, so, gotta trick it... Use a decent amount of .. to handle people with custom HOMEdirs
sed -e "s#\.ssh#../../../../../..${DEVICE_USERSTORE}/usbnet/etc/dot\.ssh#" -i pathnames.h
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
fi
autoreconf -fi
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
	cp ${DEVICE_USERSTORE}/usbnet/etc/ssh_config ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/ssh_config
	# Do the same for the client...
	sed -e '/# configuration file, and defaults at the end./s/$/\n\n# Kindle tweaks: enable aggressive KeepAlive\nServerAliveInterval 15\nServerAliveCountMax 3/' -i ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/ssh_config
	# NOTE: And apply the Gentoo config tweaks, too.
	locale_vars=( LANG LC_ALL LC_COLLATE LC_CTYPE LC_MESSAGES LC_MONETARY LC_NUMERIC LC_TIME LANGUAGE LC_ADDRESS LC_IDENTIFICATION LC_MEASUREMENT LC_NAME LC_PAPER LC_TELEPHONE )
	# First the server config.
	cat <<-EOF >> "${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/sshd_config"

	# Allow client to pass locale environment variables. #367017
	AcceptEnv ${locale_vars[*]}

	# Allow client to pass COLORTERM to match TERM. #658540
	AcceptEnv COLORTERM
	EOF
	# Then the client config.
	cat <<-EOF >> "${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/ssh_config"

	# Send locale environment variables. #367017
	SendEnv ${locale_vars[*]}

	# Send COLORTERM to match TERM. #658540
	SendEnv COLORTERM
	EOF
	unset locale_vars
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
NCURSES_SOVER="6.1"
cd ..
tar -I pigz -xvf /usr/portage/distfiles/ncurses-6.2.tar.gz
cd ncurses-6.2
update_title_info
export CFLAGS="${BASE_CFLAGS}"
export CXXFLAGS="${BASE_CFLAGS}"
#bzcat /usr/portage/distfiles/ncurses-6.1-20190609-patch.sh.bz2 > ncurses-6.1-20190609-patch.sh
#sh ncurses-6.1-20190609-patch.sh
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-5.7-nongnu.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-rxvt-unicode-9.15.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-pkg-config.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-5.9-gcc-5.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-ticlib.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-cppflags-cross.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.2-no_user_ldflags_in_libs.patch
unset TERMINFO
export CPPFLAGS="${BASE_CPPFLAGS} -D_GNU_SOURCE"
# NOTE: cross-compile fun times, build tic for our host, in case we're not running the same ncurses version...
export CBUILD="$(uname -m)-pc-linux-gnu"
mkdir -p ${CBUILD}
cd ${CBUILD}
env CHOST=${CBUILD} CFLAGS="-O2 -pipe -march=native" CXXFLAGS="-O2 -pipe -march=native" LDFLAGS="-Wl,--as-needed -static" CPPFLAGS="-D_GNU_SOURCE" CC="gcc" CXX="g++" AR="ar" RANLIB="ranlib" NM="nm" LD="ld" ../configure --{build,host}=${CBUILD} --without-shared --with-normal
# NOTE: use our host's tic
MY_BASE_PATH="${PATH}"
export PATH="${TC_BUILD_DIR}/ncurses-6.1/${CBUILD}/progs:${PATH}"
export TIC_PATH="${TC_BUILD_DIR}/ncurses-6.1/${CBUILD}/progs/tic"
cd ..
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --with-terminfo-dirs="${DEVICE_USERSTORE}/usbnet/etc/terminfo:/etc/terminfo:/usr/share/terminfo" --with-pkg-config-libdir="${TC_BUILD_DIR}/lib/pkgconfig" --enable-pc-files --with-shared --without-hashed-db --without-ada --without-cxx --without-cxx-binding --without-debug --without-profile --without-gpm --disable-term-driver --disable-termcap --enable-symlinks --with-rcs-ids --with-manpage-format=normal --enable-const --enable-colorfgbg --enable-hard-tabs --enable-echo --with-progs --disable-widec --without-pthread --without-reentrant --with-termlib --disable-stripping
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
# Kobo doesn't ship ncurses at all, but we always need it anyway, since >= 6.0 changed the sover ;)
cp ../lib/libncurses.so.${NCURSES_SOVER} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libncurses.so.${NCURSES_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libncurses.so.${NCURSES_SOVER%%.*}
cp ../lib/libtinfo.so.${NCURSES_SOVER} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libtinfo.so.${NCURSES_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libtinfo.so.${NCURSES_SOVER%%.*}
# We then do a widechar build, which is actually mostly the one we'll be relying on
echo "* Building ncurses (widec) . . ."
echo ""
cd ..
rm -rf ncurses-6.1
tar -I pigz -xvf /usr/portage/distfiles/ncurses-6.1.tar.gz
cd ncurses-6.1
update_title_info
bzcat /usr/portage/distfiles/ncurses-6.1-20181020-patch.sh.bz2 > ncurses-6.1-20181020-patch.sh
sh ncurses-6.1-20181020-patch.sh
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-5.7-nongnu.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-rxvt-unicode-9.15.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-pkg-config.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-5.9-gcc-5.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-ticlib.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-6.0-cppflags-cross.patch
export CPPFLAGS="${BASE_CPPFLAGS} -D_GNU_SOURCE"
# NOTE: cross-compile fun times, build tic for our host, in case we're not running the same ncurses version...
export CBUILD="$(uname -m)-pc-linux-gnu"
mkdir -p ${CBUILD}
cd ${CBUILD}
env CHOST=${CBUILD} CFLAGS="-O2 -pipe -march=native" CXXFLAGS="-O2 -pipe -march=native" LDFLAGS="-Wl,--as-needed -static" CPPFLAGS="-D_GNU_SOURCE" CC="gcc" CXX="g++" AR="ar" RANLIB="ranlib" NM="nm" LD="ld" ../configure --{build,host}=${CBUILD} --without-shared --with-normal
# NOTE: use our host's tic
MY_BASE_PATH="${PATH}"
export PATH="${TC_BUILD_DIR}/ncurses-6.1/${CBUILD}/progs:${PATH}"
export TIC_PATH="${TC_BUILD_DIR}/ncurses-6.1/${CBUILD}/progs/tic"
cd ..
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --with-terminfo-dirs="${DEVICE_USERSTORE}/usbnet/etc/terminfo:/etc/terminfo:/usr/share/terminfo" --with-pkg-config-libdir="${TC_BUILD_DIR}/lib/pkgconfig" --enable-pc-files --with-shared --without-hashed-db --without-ada --without-cxx --without-cxx-binding --without-debug --without-profile --without-gpm --disable-term-driver --disable-termcap --enable-symlinks --with-rcs-ids --with-manpage-format=normal --enable-const --enable-colorfgbg --enable-hard-tabs --enable-echo --with-progs --enable-widec --without-pthread --without-reentrant --with-termlib --includedir="${TC_BUILD_DIR}/include/ncursesw" --disable-stripping
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
cp ../lib/libtinfow.so.${NCURSES_SOVER} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libtinfow.so.${NCURSES_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libtinfow.so.${NCURSES_SOVER%%.*}
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
tar -I pigz -xvf /usr/portage/distfiles/htop-2.2.0.tar.gz
cd htop-2.2.0
update_title_info
# NOTE: Used to fail to build w/ LTO (ICE)... (K5 TC, Linaro GCC 5.2 2015.09 & binutils 2.25.1)
#if [[ "${CFLAGS}" != "${NOLTO_CFLAGS}" ]] ; then
#	temp_nolto="true"
#	export CFLAGS="${NOLTO_CFLAGS}"
#fi
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/htop-2.2.0-to-HEAD.patch
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/htop-2.2.0-kindle-tweaks.patch
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
# NOTE: ncurses-config is the pits. Use the x-compiled one, not our system's...
export HTOP_NCURSES_CONFIG_SCRIPT="${TC_BUILD_DIR}/bin/ncurses6-config"
export HTOP_NCURSESW_CONFIG_SCRIPT="${TC_BUILD_DIR}/bin/ncursesw6-config"
# NOTE: Locales are broken, gconv modules are missing, wchar_t is basically unusable. Don't try to handle widechars/multibyte on Kobo.
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-hwloc --enable-taskstats --disable-cgroup --disable-linux-affinity --disable-unicode
else
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-hwloc --enable-taskstats --disable-cgroup --disable-linux-affinity --enable-unicode
fi
make ${JOBSFLAGS}
make install
${CROSS_TC}-strip --strip-unneeded ../bin/htop
unset ac_cv_func_malloc_0_nonnull
unset ac_cv_func_realloc_0_nonnull
unset ac_cv_file__proc_meminfo
unset ac_cv_file__proc_stat
unset HTOP_NCURSES_CONFIG_SCRIPT
unset HTOP_NCURSESW_CONFIG_SCRIPT
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
tar -I pigz -xvf /usr/portage/distfiles/lsof-4.93.2.tar.gz
cd lsof-4.93.2
update_title_info
touch .neverInv
patch -p1 < /usr/portage/sys-process/lsof/files/lsof-4.85-cross.patch
export CPPFLAGS="${BASE_CPPFLAGS} -DHASNOTRPC -DHASNORPC_H"
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	LSOF_CC="${CROSS_TC}-gcc" LSOF_AR="${CROSS_TC}-gcc-ar rc" LSOF_RANLIB="${CROSS_TC}-gcc-ranlib" LSOF_NM="${CROSS_TC}-gcc-nm" LSOF_CFGF="${CFLAGS} ${CPPFLAGS}" LSOF_CFGL="${CFLAGS} ${LDFLAGS}" LSOF_ARCH="armv6l" LSOF_INCLUDE="${TC_BUILD_DIR}/include" LINUX_CLIB="-DGLIBCV=2" LINUX_HASSELINUX="N" ./Configure -n linux
elif [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	LSOF_CC="${CROSS_TC}-gcc" LSOF_AR="${CROSS_TC}-gcc-ar rc" LSOF_RANLIB="${CROSS_TC}-gcc-ranlib" LSOF_NM="${CROSS_TC}-gcc-nm" LSOF_CFGF="${CFLAGS} ${CPPFLAGS}" LSOF_CFGL="${CFLAGS} ${LDFLAGS}" LSOF_ARCH="armv7-a" LSOF_INCLUDE="${TC_BUILD_DIR}/include" LINUX_CLIB="-DGLIBCV=2" LINUX_HASSELINUX="N" ./Configure -n linux
fi
make ${JOBSFLAGS} DEBUG="" all
${CROSS_TC}-strip --strip-unneeded lsof
cp lsof ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/lsof
export CPPFLAGS="${BASE_CPPFLAGS}"

## shlock for Fonts & SS
echo "* Building shlock . . ."
echo ""
cd ..
mkdir shlock
cd shlock
update_title_info
wget https://gitweb.dragonflybsd.org/dragonfly.git/blob_plain/HEAD:/usr.bin/shlock/shlock.c -O shlock.c
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
tar -I pigz -xvf /usr/portage/distfiles/protobuf-3.11.2.tar.gz
cd protobuf-3.11.2
update_title_info
patch -p1 < /usr/portage/dev-libs/protobuf/files/protobuf-3.11.0-disable_no-warning-test.patch
patch -p1 < /usr/portage/dev-libs/protobuf/files/protobuf-3.11.0-system_libraries.patch
patch -p1 < /usr/portage/dev-libs/protobuf/files/protobuf-3.11.0-protoc_input_output_files.patch
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
tar -I pigz -xvf /usr/portage/distfiles/mosh-1.3.2.tar.gz
cd mosh-1.3.2
update_title_info
patch -p1 < /usr/portage/net-misc/mosh/files/mosh-1.2.5-git-version.patch
./autogen.sh
if [[ "${KINDLE_TC}" == "K3" ]] || [[ "${KINDLE_TC_IS_GLIBC_219}" == "true" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-completion --enable-client --enable-server --disable-examples --disable-urw --disable-hardening --without-utempter
elif [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-completion --enable-client --enable-server --disable-examples --disable-urw --enable-hardening --without-utempter
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
tar -xvJf /usr/portage/distfiles/libarchive-3.4.1_p20200207.tar.xz
cd libarchive
update_title_info
export CFLAGS="${RICE_CFLAGS}"
# Kill -Werror, git master doesn't always build with it...
sed -e 's/-Werror //' -i ./Makefile.am
./build/autogen.sh
export ac_cv_header_ext2fs_ext2_fs_h=0
# We now ship our own shared zlib, so let's use it
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --disable-xattr --disable-acl --with-zlib --without-bz2lib --without-lzmadec --without-iconv --without-lzma --without-nettle --without-openssl --without-expat --without-xml2 --without-lz4
make ${JOBSFLAGS} V=1
make install
export CFLAGS="${BASE_CFLAGS}"
export LDFLAGS="${BASE_LDFLAGS}"
unset ac_cv_header_ext2fs_ext2_fs_h

## GMP (kindletool dep)
echo "* Building GMP . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/gmp-6.2.0.tar.xz
cd gmp-6.2.0
update_title_info
export CFLAGS="${RICE_CFLAGS}"
patch -p1 < /usr/portage/dev-libs/gmp/files/gmp-6.1.0-noexecstack-detect.patch
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
export CFLAGS="${BASE_CFLAGS}"

## Nettle (kindletool dep)
echo "* Building nettle . . ."
echo ""
cd ..
if [[ "${USE_STABLE_NETTLE}" == "true" ]] ; then
	tar -I pigz -xvf /usr/portage/distfiles/nettle-3.5.1.tar.gz
	cd nettle-3.5.1
	update_title_info
	export CFLAGS="${RICE_CFLAGS}"
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
		env ac_cv_host="armv7l-kobo-linux-gnueabihf" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --enable-arm-neon
	fi
	make ${JOBSFLAGS}
	make install
	export CFLAGS="${BASE_CFLAGS}"
else
	# Build from git
	rm -rf nettle-git
	until git clone --depth 1 https://git.lysator.liu.se/nettle/nettle.git nettle-git ; do
		rm -rf nettle-git
		sleep 15
	done
	cd nettle-git
	update_title_info
	export CFLAGS="${RICE_CFLAGS}"
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
		env ac_cv_host="armv7l-kobo-linux-gnueabihf" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --enable-arm-neon
	fi
	make ${JOBSFLAGS}
	make install
	export CFLAGS="${BASE_CFLAGS}"
fi

## KindleTool for USBNet
echo "* Building KindleTool . . ."
echo ""
cd ..
rm -rf KindleTool
# NOTE: Not shallow because we want a proper version tag
until git clone https://github.com/NiLuJe/KindleTool.git ; do
	rm -rf KindleTool
	sleep 15
done
cd KindleTool
update_title_info
export KT_NO_USERATHOST_TAG="true"
export CFLAGS="${RICE_CFLAGS} -DKT_USERATHOST='\"niluje@tyrande\"'"
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
LIBPNG_SOVER="16.37.0"
tar xvJf /usr/portage/distfiles/libpng-1.6.37.tar.xz
cd libpng-1.6.37
update_title_info
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/libpng-fix-Makefile-for-lto.patch
autoreconf -fi
export CFLAGS="${RICE_CFLAGS}"
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
export CFLAGS="${BASE_CFLAGS}"
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
LIBJPG_SOVER="62.3.0"
LIBTJP_SOVER="0.2.0"
tar -I pigz -xvf /usr/portage/distfiles/libjpeg-turbo-2.0.4.tar.gz
cd libjpeg-turbo-2.0.4
update_title_info
# Oh, CMake (https://gitlab.kitware.com/cmake/cmake/issues/12928) ...
export CFLAGS="${BASE_CPPFLAGS} ${RICE_CFLAGS}"
mkdir -p build
cd build
if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	${CMAKE} .. -DENABLE_STATIC=OFF -DENABLE_SHARED=ON -DWITH_MEM_SRCDST=ON -DWITH_JAVA=OFF
else
	${CMAKE} .. -DENABLE_STATIC=OFF -DENABLE_SHARED=ON -DWITH_MEM_SRCDST=ON -DWITH_JAVA=OFF -DREQUIRE_SIMD=OFF -DWITH_SIMD=OFF
fi
make ${JOBSFLAGS} VERBOSE=1
make install
cd ..
export CFLAGS="${BASE_CFLAGS}"
# Install shared libs...
cp ../lib/libjpeg.so.${LIBJPG_SOVER} ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libjpeg.so.${LIBJPG_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libjpeg.so.${LIBJPG_SOVER%%.*}
cp ../lib/libturbojpeg.so.${LIBTJP_SOVER} ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libturbojpeg.so.${LIBTJP_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/libturbojpeg.so.${LIBTJP_SOVER%%.*}

## ImageMagick for ScreenSavers
echo "* Building ImageMagick . . ."
echo ""
IM_SOVER="6.0.0"
cd ..
# FWIW, you can pretty much use the same configure line for GraphicsMagick, although the ScreenSavers hack won't work with it.
# It doesn't appear to need the quantize patch though, it consumes a 'normal' amount of memory by default.
tar xvJf /usr/portage/distfiles/ImageMagick-6.9.10-92.tar.xz
cd ImageMagick-6.9.10-92
update_title_info
# Use the same codepath as on iPhone devices to nerf the 65MB alloc of the dither code... (We also use a quantum-depth of 8 to keep the memory usage down)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/ImageMagick-6.8.6-5-nerf-dither-mem-alloc.patch
export CFLAGS="${RICE_CFLAGS}"
# Pull our own zlib to avoid symbol versioning issues...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/linkss/lib"
# Make sure configure won't think we might want modules because it mixes the modules check with the automagic availability of OpenCL...
export ax_cv_check_cl_libcl=no
# NOTE: Because FT's pkg-config file is terrible w/ LTO...
export PKG_CONFIG="pkg-config --static"
env LIBS="-lrt" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --without-magick-plus-plus --disable-openmp --disable-deprecated --disable-installed --disable-hdri --disable-opencl --disable-largefile --with-threads --without-modules --with-quantum-depth=8 --without-perl --without-bzlib --without-x --with-zlib --without-autotrace --without-dps --without-djvu --without-fftw --without-fpx --without-fontconfig --with-freetype --without-gslib --without-gvc --without-jbig --with-jpeg --without-openjp2 --without-lcms --without-lcms --without-lqr --without-lzma --without-openexr --without-pango --with-png --without-rsvg --without-tiff --without-webp --without-wmf --without-xml
make ${JOBSFLAGS} V=1
make install
unset PKG_CONFIG
unset ax_cv_check_cl_libcl
export LDFLAGS="${BASE_LDFLAGS}"
export CFLAGS="${BASE_CFLAGS}"
# Install binaries...
for im_bin in identify convert mogrify ; do
	${CROSS_TC}-strip --strip-unneeded ../bin/${im_bin}
	cp ../bin/${im_bin} ${BASE_HACKDIR}/ScreenSavers/src/linkss/bin/${im_bin}
done
# Shared libs...
for im_lib in libMagickCore libMagickWand ; do
	my_lib="${im_lib}-6.Q8"
	cp ../lib/${my_lib}.so.${IM_SOVER} ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/${my_lib}.so.${IM_SOVER%%.*}
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/ScreenSavers/src/linkss/lib/${my_lib}.so.${IM_SOVER%%.*}
done
# Auxiliary configs...
cp -f ../etc/ImageMagick-6/* ${BASE_HACKDIR}/ScreenSavers/src/linkss/etc/ImageMagick-6/

## bzip2 for Python
echo "* Building bzip2 . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/bzip2-1.0.8.tar.gz
cd bzip2-1.0.8
update_title_info
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.4-makefile-CFLAGS.patch
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.8-saneso.patch
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.4-man-links.patch
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.6-progress.patch
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.3-no-test.patch
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.8-mingw.patch
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.8-out-of-tree-build.patch
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/bzip2-fix-Makefile-for-lto.patch
sed -i -e 's:\$(PREFIX)/man:\$(PREFIX)/share/man:g' -e 's:ln -s -f $(PREFIX)/bin/:ln -s -f :' -e 's:$(PREFIX)/lib:$(PREFIX)/$(LIBDIR):g' Makefile
make ${JOBSFLAGS} CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" ${JOBSFLAGS} -f Makefile-libbz2_so all
export CFLAGS="${BASE_CFLAGS} -static"
make ${JOBSFLAGS} CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-gcc-ar" RANLIB="${CROSS_TC}-gcc-ranlib" NM="${CROSS_TC}-gcc-nm" ${JOBSFLAGS} all
export CFLAGS="${BASE_CFLAGS}"
make PREFIX="${TC_BUILD_DIR}" LIBDIR="lib" install

## libffi for Python
echo "* Building libffi . . ."
echo ""
FFI_SOVER="7.1.0"
cd ..
tar -I pigz -xvf /usr/portage/distfiles/libffi-3.3.tar.gz
cd libffi-3.3
update_title_info
patch -p1 < /usr/portage/dev-libs/libffi/files/libffi-3.2.1-o-tmpfile-eacces.patch
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
	ICU_SOVER="65.1"
	cd ..
	tar -I pigz -xvf /usr/portage/distfiles/icu4c-65_1-src.tgz
	cd icu/source
	update_title_info
	patch -p1 < /usr/portage/dev-libs/icu/files/icu-65.1-remove-bashisms.patch
	patch -p1 < /usr/portage/dev-libs/icu/files/icu-64.2-darwin.patch
	patch -p1 < /usr/portage/dev-libs/icu/files/icu-64.1-data_archive_generation.patch
	# FIXME: Once again a weird cmath issue, like gdb...
	if [[ "${KINDLE_TC}" != "KOBO" ]] ; then
		patch -p2 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/icu-62.1-kindle-round-fix.patch
	fi
	sed -i -e "s/#define U_DISABLE_RENAMING 0/#define U_DISABLE_RENAMING 1/" common/unicode/uconfig.h
	sed -i -e "s:LDFLAGSICUDT=-nodefaultlibs -nostdlib:LDFLAGSICUDT=:" config/mh-linux
	sed -i -e 's:icudefs.mk:icudefs.mk Doxyfile:' configure.ac
	autoreconf -fi
	# Cross-Compile fun...
	mkdir ../../icu-host
	cd ../../icu-host
	env CFLAGS="" CXXFLAGS="" ASFLAGS="" LDFLAGS="" CC="gcc" CXX="g++" AR="ar" RANLIB="ranlib" NM="nm" LD="ld" ../icu/source/configure --disable-renaming --disable-debug --disable-samples --disable-layoutex --enable-static
	# NOTE: Don't care about verbose output for the host build ;).
	make ${JOBSFLAGS}
	cd -
	# ICU tries to use clang by default
	export CC="${CROSS_TC}-gcc"
	export CXX="${CROSS_TC}-g++"
	export LD="${CROSS_TC}-ld"
	# Use C++14
	export CXXFLAGS="${BASE_CFLAGS} -std=gnu++14"
	# Setup our Python rpath, plus a static lstdc++, since we pull CXXABI_1.3.8, which is too new for even the K5...
	export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/python3/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib -static-libstdc++"
	# Huh. Why this only shows up w/ LTO is a mystery...
	export ac_cv_c_bigendian=no
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --disable-renaming --disable-samples --disable-layoutex --disable-debug --with-cross-build="${TC_BUILD_DIR}/icu-host"
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
READLINE_SOVER="8.0"
READLINE_PATCHLVL="4"
cd ..
tar -I pigz -xvf /usr/portage/distfiles/readline-${READLINE_SOVER}.tar.gz
cd readline-${READLINE_SOVER}
update_title_info
for patch in $(seq 1 ${READLINE_PATCHLVL}) ; do
	patch_file="readline${READLINE_SOVER//.}-$(printf "%03d" ${patch})"
	[[ -f "${patch_file}" ]] && patch -p0 < /usr/portage/distfiles/${patch_file}
done
patch -p1 < /usr/portage/sys-libs/readline/files/readline-5.0-no_rpath.patch
patch -p1 < /usr/portage/sys-libs/readline/files/readline-6.2-rlfe-tgoto.patch
patch -p1 < /usr/portage/sys-libs/readline/files/readline-7.0-headers.patch
patch -p1 < /usr/portage/sys-libs/readline/files/readline-8.0-headers.patch
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/readline-fix-Makefile-for-lto.patch
ncurses_libs="$(pkg-config ncursesw --libs)"
sed -e "/^SHLIB_LIBS=/s:=.*:='${ncurses_libs}':" -i support/shobj-conf
sed -e "/^[[:space:]]*LIBS=.-lncurses/s:-lncurses:${ncurses_libs}:" -i examples/rlfe/configure
unset ncurses_libs
sed -e '/objformat/s:if .*; then:if true; then:' -i support/shobj-conf
ln -s ../.. examples/rlfe/readline
export CPPFLAGS="${BASE_CPPFLAGS} -D_GNU_SOURCE -Dxrealloc=_rl_realloc -Dxmalloc=_rl_malloc -Dxfree=_rl_free"
export ac_cv_prog_AR=${CROSS_TC}-gcc-ar
export ac_cv_prog_RANLIB=${CROSS_TC}-gcc-ranlib
export ac_cv_prog_NM=${CROSS_TC}-gcc-nm
export bash_cv_termcap_lib=ncursesw
export bash_cv_func_sigsetjmp='present'
export bash_cv_func_ctype_nonascii='yes'
export bash_cv_wcwidth_broken='no'
# Setup an rpath to make sure it won't pick-up a weird ncurses lib...
export LDFLAGS="${BASE_LDFLAGS} -L. -Wl,-rpath=${DEVICE_USERSTORE}/python3/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib"
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
SQLITE_VER="3310100"
cd ..
wget https://sqlite.org/2020/sqlite-src-${SQLITE_VER}.zip -O sqlite-src-${SQLITE_VER}.zip
unzip sqlite-src-${SQLITE_VER}.zip
cd sqlite-src-${SQLITE_VER}
update_title_info
# Gentoo patches
# NOTE: Maybe wait for the proper Gentoo ebuild for that version, because this one makes the build go kablooey with undefined symbols ;).
#patch -p1 < /usr/portage/dev-db/sqlite/files/sqlite-3.28.0-full_archive-build.patch
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/sqlite-fix-Makefile-for-lto.patch
autoreconf -fi
# Enable some extra features...
export CPPFLAGS="${BASE_CPPFLAGS} -DNDEBUG -D_REENTRANT=1 -D_GNU_SOURCE"
export CPPFLAGS="${CPPFLAGS} -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_RTREE -DSQLITE_SOUNDEX -DSQLITE_ENABLE_UNLOCK_NOTIFY"
# And a few of the recommended build options from https://sqlite.org/compile.html (we only leave shared cache enabled, just in case...)
# NOTE: We can't use SQLITE_OMIT_DECLTYPE with SQLITE_ENABLE_COLUMN_METADATA
# NOTE: The Python SQLite module also prevents us from using SQLITE_OMIT_PROGRESS_CALLBACK as well as SQLITE_OMIT_DEPRECATED
export CPPFLAGS="${CPPFLAGS} -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_MAX_EXPR_DEPTH=0 -DSQLITE_USE_ALLOCA"
if [[ "${SQLITE_WITH_ICU}" == "true" ]] ; then
	export CPPFLAGS="${CPPFLAGS} -DSQLITE_ENABLE_ICU"
	# Need to tweak that a bit to link properly against ICU...
	sed -e "s/LIBS = @LIBS@/& -licui18n -licuuc -licudata/" -i Makefile.in
fi
# Setup our Python rpath.
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/python3/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib"
# SQLite doesn't want to be built w/ -ffast-math...
export CFLAGS="${BASE_CFLAGS/-ffast-math /}"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --disable-static-shell --enable-shared --disable-amalgamation --enable-threadsafe --enable-dynamic-extensions --enable-readline --with-readline-inc=-I${TC_BUILD_DIR}/include/readline --with-readline-lib="-lreadline -ltinfow" --enable-fts5 --enable-json1 --disable-tcl --disable-releasemode
# NOTE: We apparently need to make sure the header is generated first, or parallel compilation goes kablooey...
make -j1 sqlite3.h
make ${JOBSFLAGS}
make install
export CFLAGS="${BASE_CFLAGS}"
export LDFLAGS="${BASE_LDFLAGS}"
export CPPFLAGS="${BASE_CPPFLAGS}"

## FBInk
echo "* Building FBInk . . ."
echo ""
cd ..
rm -rf FBInk
# NOTE: Not shallow because we want a proper version tag
until git clone --recurse-submodules https://github.com/NiLuJe/FBInk.git ; do
	rm -rf FBInk
	sleep 15
done
cd FBInk
update_title_info
# NOTE: Yeah, we need up to four different build variants:
#       static for USBNet
#       static, but minimal, for libkh
#       static, but minial w/ TTF, for MRPI
#       shared libary only for py-fbink
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	make ${JOBSFLAGS} legacy
	cp Release/fbink ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/fbink
	make clean
	make ${JOBSFLAGS} legacy MINIMAL=1
	cp Release/fbink ${BASE_HACKDIR}/Common/bin/fbink
	make clean
	make ${JOBSFLAGS} kindle MINIMAL=1 OPENTYPE=1
	cp Release/fbink ${BASE_HACKDIR}/../KUAL/MRInstaller/extensions/MRInstaller/bin/${KINDLE_TC}/fbink
	make clean
	make ${JOBSFLAGS} sharedlib SHARED=1 KINDLE=1 LEGACY=1
	make ${JOBSFLAGS} striplib
elif [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] ; then
	make ${JOBSFLAGS} kindle
	cp Release/fbink ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/fbink
	make clean
	make ${JOBSFLAGS} kindle MINIMAL=1
	cp Release/fbink ${BASE_HACKDIR}/Common/bin/fbink
	make clean
	make ${JOBSFLAGS} kindle MINIMAL=1 OPENTYPE=1
	cp Release/fbink ${BASE_HACKDIR}/../KUAL/MRInstaller/extensions/MRInstaller/bin/${KINDLE_TC}/fbink
	make clean
	make ${JOBSFLAGS} sharedlib SHARED=1 KINDLE=1
	make ${JOBSFLAGS} striplib
else
	make ${JOBSFLAGS} strip
	cp Release/fbink ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/fbink
	make clean
	make ${JOBSFLAGS} sharedlib SHARED=1
	make ${JOBSFLAGS} striplib
fi
# 'Install' it for py-fbink's sake...
cp -av fbink.h ${TC_BUILD_DIR}/include/fbink.h
cp -av Release/libfbink* ${TC_BUILD_DIR}/lib/
# And handle the MRPI data tarball now that we've got everything
if [[ "${KINDLE_TC}" != "KOBO" ]] ; then
	# Package the binaries in a tarball...
	rm -f ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/data/mrpi-${KINDLE_TC}.tar.gz
	tar --show-transformed-names --owner 0 --group 0 --transform "s,^${SVN_ROOT#*/}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/,,S" -I pigz -cvf ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/data/mrpi-${KINDLE_TC}.tar.gz ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/lib/${KINDLE_TC} ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/bin/${KINDLE_TC}
	# Clear extra binaries...
	rm -f ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/lib/${KINDLE_TC}/* ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/MRInstaller/extensions/MRInstaller/bin/${KINDLE_TC}/*
fi

## libxml2 for BeautifulSoup
echo "* Building libxml2 . . ."
echo ""
LIBXML2_VERSION="2.9.9"
cd ..
tar -I pigz -xvf /usr/portage/distfiles/libxml2-${LIBXML2_VERSION}.tar.gz
cd libxml2-${LIBXML2_VERSION}
update_title_info
tar -xvJf /usr/portage/distfiles/libxml2-${LIBXML2_VERSION}-patchset.tar.xz
# Gentoo Patches...
for patchfile in patches/* ; do
	# Try to detect if we need p0 or p1...
	if grep -q 'diff --git' "${patchfile}" ; then
		echo "Applying ${patchfile} w/ p1 . . ."
		patch -p1 < ${patchfile}
	else
		echo "Applying ${patchfile} w/ p0 . . ."
		patch -p0 < ${patchfile}
	fi
done
patch -p1 < /usr/portage/dev-libs/libxml2/files/libxml2-2.7.1-catalog_path.patch
patch -p1 < /usr/portage/dev-libs/libxml2/files/libxml2-2.9.2-python-ABIFLAG.patch
patch -p1 < /usr/portage/dev-libs/libxml2/files/libxml2-2.9.8-out-of-tree-test.patch
patch -p1 < /usr/portage/dev-libs/libxml2/files/2.9.9-python3-unicode-errors.patch
autoreconf -fi
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/python3/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib"
if [[ "${SQLITE_WITH_ICU}" == "true" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --without-run-debug --without-mem-debug --without-lzma --disable-ipv6 --without-readline --without-history --without-python --with-icu
else
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --without-run-debug --without-mem-debug --without-lzma --disable-ipv6 --without-readline --without-history --without-python --without-icu
fi
make ${JOBSFLAGS} V=1
make install
export LDFLAGS="${BASE_LDFLAGS}"

## libxslt for BeautifulSoup
echo "* Building libxslt . . ."
echo ""
LIBXSLT_VERSION="1.1.33"
LIBEXSLT_SOVER="0.8.20"
cd ..
tar -I pigz -xvf /usr/portage/distfiles/libxslt-${LIBXSLT_VERSION}.tar.gz
cd libxslt-${LIBXSLT_VERSION}
update_title_info
# Gentoo Patches...
patch -p1 < /usr/portage/dev-libs/libxslt/files/1.1.32-simplify-python.patch
patch -p1 < /usr/portage/dev-libs/libxslt/files/libxslt-1.1.28-disable-static-modules.patch
patch -p1 < /usr/portage/distfiles/libxslt-1.1.33-CVE-2019-11068.patch
autoreconf -fi
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/python3/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib"
env ac_cv_path_ac_pt_XML_CONFIG=${TC_BUILD_DIR}/bin/xml2-config PKG_CONFIG="pkg-config --static" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-static --enable-shared --without-crypto --without-debug --without-mem-debug --without-python
make ${JOBSFLAGS} V=1
make install
export LDFLAGS="${BASE_LDFLAGS}"

## Python for ScreenSavers
PYTHON_CUR_VER="2.7.17"
PYTHON2_PATCH_REV="2.7.17-r1"
echo "* Building Python . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/Python-${PYTHON_CUR_VER}.tar.xz
cd Python-${PYTHON_CUR_VER}
update_title_info
rm -fr Modules/expat
rm -fr Modules/_ctypes/libffi*
rm -fr Modules/zlib
# Gentoo Patches...
tar xvJf /usr/portage/distfiles/python-gentoo-patches-${PYTHON2_PATCH_REV}.tar.xz
#rm -f python-gentoo-patches-${PYTHON2_PATCH_REV}/0006-Regenerate-platform-specific-modules.patch
for patchfile in python-gentoo-patches-${PYTHON2_PATCH_REV}/* ; do
	# Try to detect if we need p0 or p1...
	if grep -q 'diff --git' "${patchfile}" ; then
		echo "Applying ${patchfile} w/ p1 . . ."
		patch -p1 < ${patchfile}
	else
		echo "Applying ${patchfile} w/ p0 . . ."
		patch -p0 < ${patchfile}
	fi
done
# Adapted from Gentoo's 2.7.3 cross-compile patchset. There's some fairly ugly and unportable hacks in there, because for the life of me I can't figure out how the cross-compile support merged in 2.7.4 is supposed to take care of some stuff... (namely, pgen & install)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/python-2.7.17-cross-compile.patch
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/python-fix-Makefile-for-lto.patch
sed -i -e "s:@@GENTOO_LIBDIR@@:lib:g" Lib/distutils/command/install.py Lib/distutils/sysconfig.py Lib/site.py Lib/sysconfig.py Lib/test/test_site.py Makefile.pre.in Modules/Setup.dist Modules/getpath.c setup.py
# Fix building against a static OpenSSL... (depends on zlib)
sed -e "s/\['ssl', 'crypto'\]/\['ssl', 'crypto', 'z'\]/g" -i setup.py
if [[ "${SQLITE_WITH_ICU}" == "true" ]] ; then
	# Make sure SQLite picks up ICU properly...
	sed -e 's/\["sqlite3",\]/\["sqlite3", "icui18n", "icuuc", "icudata",\]/g' -i setup.py
fi
# Bzip2 needs to be PIC (compile/link time match w/ LTO)
sed -e "s/bz2_extra_link_args = ()/bz2_extra_link_args = ('-fPIC',)/" -i setup.py
# Fix building with Python 3 as the default Python interpreter...
sed -e 's#python#python2#' -i Tools/scripts/h2py.py
autoreconf -fi

# Note that curses needs ncursesw, which doesn't ship on every Kindle, so we ship our own. Same deal for readline.
export PYTHON_DISABLE_MODULES="dbm _bsddb gdbm _tkinter"
# c.f., https://fedoraproject.org/wiki/Changes/PythonNoSemanticInterpositionSpeedup
export CFLAGS="${BASE_CFLAGS} -fwrapv -fno-semantic-interposition"
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
export ac_cv_header_bluetooth_bluetooth_h=no
export ac_cv_buggy_getaddrinfo=no
export ac_cv_have_long_long_format=yes
export ac_cv_file__dev_ptmx=yes
export ac_cv_file__dev_ptc=no
# Would probably need a custom zoneinfo directory...
#export ac_cv_working_tzset=yes
export _PYTHON_HOST_PLATFORM="linux-arm"
export PYTHON_FOR_BUILD="hostpython"
export PGEN_FOR_BUILD="./Parser/hostpgen"
export CC="${CROSS_TC}-gcc"
export CXX="${CROSS_TC}-g++"
# Huh. For some reason, adding --static here breaks it... (Well, it's not useful here anyway, but, still...)
export ac_cv_path_PKG_CONFIG="pkg-config"
# Setup an rpath since we use a shared libpython to be able to build third-party modules...
export LDFLAGS="${BASE_LDFLAGS} -L. -Wl,-rpath=${DEVICE_USERSTORE}/python/lib"
# NOTE: Used to fail to build w/ LTO (bad instruction: fldcw [sp,#6] & fnstcw [sp,#6])... (Linaro GCC 5.2 2015.09 & binutils 2.25.1)
#        Those are x86 instructions, so, WTH?
#if [[ "${CFLAGS}" != "${NOLTO_CFLAGS}" ]] ; then
#	temp_nolto="true"
#	export CFLAGS="${NOLTO_CFLAGS}"
#fi
cd ${CHOST}
# NOTE: Enable the shared library to be able to compile third-party C modules...
OPT="" ../configure --prefix=${TC_BUILD_DIR}/python --build=${CBUILD} --host=${CROSS_TC} --enable-static --enable-shared --with-fpectl --disable-ipv6 --with-threads --enable-unicode=ucs4 --with-computed-gotos --with-libc="" --enable-loadable-sqlite-extensions --with-system-expat --with-system-ffi --without-ensurepip
# More cross-compile hackery...
sed -e '1iHOSTPYTHONPATH = ./hostpythonpath' -e '/^PYTHON_FOR_BUILD/s:=.*:=./hostpython -E:' -e '/^PGEN_FOR_BUILD/s:=.*:= ./Parser/hostpgen:' -i Makefile{.pre,}
cd ..

cd ${CBUILD}
# Disable as many modules as possible -- but we need a few to install.
PYTHON_DISABLE_MODULES=$(sed -n "/Extension('/{s:^.*Extension('::;s:'.*::;p}" ../setup.py | egrep -v '(unicodedata|time|cStringIO|_struct|binascii)') PYTHON_DISABLE_SSL="1" SYSROOT= make ${JOBSFLAGS}
make Parser/pgen
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
unset ac_cv_header_bluetooth_bluetooth_h
#unset ac_cv_working_tzset
unset CHOST
unset CBUILD
export CPPFLAGS="${BASE_CPPFLAGS}"
export CFLAGS="${BASE_CFLAGS}"
unset PYTHON_DISABLE_MODULES

## Python 3
PYTHON3_CUR_VER="3.8.1"
PYTHON3_PATCH_REV="3.8.1-r2"
echo "* Building Python 3 . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/Python-${PYTHON3_CUR_VER}.tar.xz
cd Python-${PYTHON3_CUR_VER}
update_title_info
rm -fr Modules/expat
rm -fr Modules/_ctypes/libffi*
rm -fr Modules/zlib
# Gentoo Patches...
tar xvJf /usr/portage/distfiles/python-gentoo-patches-${PYTHON3_PATCH_REV}.tar.xz
for patchfile in python-gentoo-patches-${PYTHON3_PATCH_REV}/* ; do
	# Try to detect if we need p0 or p1...
	if grep -q 'diff --git' "${patchfile}" ; then
		echo "Applying ${patchfile} w/ p1 . . ."
		patch -p1 < ${patchfile}
	else
		echo "Applying ${patchfile} w/ p0 . . ."
		patch -p0 < ${patchfile}
	fi
done
sed -i -e "s:@@GENTOO_LIBDIR@@:lib:g" setup.py
# Bzip2 needs to be PIC (compile/link time match w/ LTO)
sed -e "s/bz2_extra_link_args = ()/bz2_extra_link_args = ('-fPIC',)/" -i setup.py
autoreconf -fi

# Note that curses needs ncursesw, which doesn't ship on every Kindle, so we ship our own. Same deal for readline.
export PYTHON_DISABLE_MODULES="gdbm _tkinter"
# c.f., https://fedoraproject.org/wiki/Changes/PythonNoSemanticInterpositionSpeedup
export CFLAGS="${BASE_CFLAGS} -fwrapv -fno-semantic-interposition"
# c.f., https://bugs.gentoo.org/700012
export CFLAGS="${CFLAGS} -ffat-lto-objects -flto-partition=none"
# Apparently, we need -I here, or Python cannot find any our our stuff when building modules...
# And the ncursesw stuff is also needed for cross-builds...
export CPPFLAGS="${BASE_CPPFLAGS} -I${TC_BUILD_DIR}/include -I${TC_BUILD_DIR}/include/ncursesw"
# What we're building on (specificing a --host != --build is mandatory for the cross-compilation detection to work!)
# NOTE: For various cross-compilation info, see:
#       https://bugs.python.org/issue28444
#       https://bugs.python.org/issue20211
#       https://bugs.python.org/issue28266
#       https://bugs.python.org/issue28833
#       In particular, https://bugs.python.org/msg282141 for 3rd-party modules cross-compile
#       As well as https://github.com/yan12125/python3-android, the custom build-scripts he's using
#       There's also https://pypi.org/project/crossenv/ which I haven't tried (I'm happy w/ distutilscross).
export CBUILD="$(uname -m)-pc-linux-gnu"

# The configure script assumes it's buggy when cross-compiling.
export ac_cv_header_bluetooth_bluetooth_h=no
export ac_cv_buggy_getaddrinfo=no
export ac_cv_have_long_long_format=yes
export ac_cv_file__dev_ptmx=yes
export ac_cv_file__dev_ptc=no
# Would probably need a custom zoneinfo directory...
#export ac_cv_working_tzset=yes
export CC="${CROSS_TC}-gcc"
export CXX="${CROSS_TC}-g++"
export READELF="${CROSS_TC}-readelf"
# Setup an rpath since we use a shared libpython to be able to build third-party modules...
export LDFLAGS="${BASE_LDFLAGS} -L. -Wl,-rpath=${DEVICE_USERSTORE}/python3/lib"
# Fallback to a sane PYTHONHOME, so we don't necessarily have to set PYTHONHOME in our env...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/python-3.8.1-kindle-pythonhome-fallback.patch
# Fix userstore path on Kobos...
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	sed -e "s#/mnt/us#${DEVICE_USERSTORE}#g" -i Python/initconfig.c
fi
# NOTE: Enable the shared library to be able to compile third-party C modules...
env PKG_CONFIG="pkg-config --static" OPT="" ./configure --prefix=${TC_BUILD_DIR}/python3 --build=${CBUILD} --host=${CROSS_TC} --oldincludedir=${TC_BUILD_DIR}/include --enable-shared --disable-ipv6 --with-computed-gotos --with-libc="" --enable-loadable-sqlite-extensions --without-ensurepip --with-system-expat --with-system-ffi
# NOTE: Prevent the K3 from picking up a few unsupported symbols (epoll_create1, dup3, __sched_cpucount, __sched_cpufree & __sched_cpualloc)
# We do it post-configure, because for some reason, at least for epoll_create1, it's happily ignoring our enforced ac_cv_func values...
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	for py_def in EPOLL_CREATE1 DUP3 SCHED_SETAFFINITY ; do
		sed -e "/#define HAVE_${py_def}/ { s:^:/* :; s:$: */: }" -i pyconfig.h
	done
fi

make ${JOBSFLAGS}
make altinstall


export LDFLAGS="${BASE_LDFLAGS}"
unset READELF
unset CXX
unset CC
unset ac_cv_file__dev_ptc
unset ac_cv_file__dev_ptmx
unset ac_cv_have_long_long_format
unset ac_cv_buggy_getaddrinfo
unset ac_cv_header_bluetooth_bluetooth_h
#unset ac_cv_working_tzset
unset CBUILD
export CPPFLAGS="${BASE_CPPFLAGS}"
export CFLAGS="${BASE_CFLAGS}"
unset PYTHON_DISABLE_MODULES

# Bundle some third-party modules...
PYTHON_VERSIONS="${PYTHON_CUR_VER%.*} ${PYTHON3_CUR_VER%.*}"
cd ..
## NOTE: Usig the host's real Python install is hackish, but our hostpython might not have enough modules built to handle everything... Here's how it should have been called, though:
# env PYTHONPATH="${TC_BUILD_DIR}/Python-${PYTHON_CUR_VER}/${CROSS_TC}/hostpythonpath" ../Python-${PYTHON_CUR_VER}/${CROSS_TC}/hostpython
## chardet
rm -rf chardet-3.0.4
wget https://pypi.python.org/packages/source/c/chardet/chardet-3.0.4.tar.gz -O chardet-3.0.4.tar.gz
tar -I pigz -xvf chardet-3.0.4.tar.gz
cd chardet-3.0.4
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## idna
rm -rf idna
until git clone --depth 1 https://github.com/kjd/idna.git ; do
	rm -rf idna
	sleep 15
done
cd idna
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## urllib3
rm -rf urllib3
until git clone --depth 1 https://github.com/urllib3/urllib3.git ; do
	rm -rf urllib3
	sleep 15
done
cd urllib3
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## certifi
rm -rf certifi-2019.11.28
wget https://pypi.python.org/packages/source/c/certifi/certifi-2019.11.28.tar.gz -O certifi-2019.11.28.tar.gz
tar -I pigz -xvf certifi-2019.11.28.tar.gz
cd certifi-2019.11.28
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## Requests
rm -rf requests
until git clone --depth 1 https://github.com/kennethreitz/requests.git ; do
	rm -rf requests
	sleep 15
done
cd requests
update_title_info
# Patch compatibility checks so that they stop complaining about our git packages,
# and an actual fix to actually work w/ urllib3 master
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/requests-git-deps.patch
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## Unidecode
rm -rf unidecode
until git clone --depth 1 https://github.com/avian2/unidecode.git ; do
	rm -rf unidecode
	sleep 15
done
cd unidecode
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## pycparser for CFFI
rm -rf pycparser
until git clone --depth 1 https://github.com/eliben/pycparser.git ; do
	rm -rf pycparser
	sleep 15
done
cd pycparser
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## CFFI
rm -rf cffi
until hg clone https://bitbucket.org/cffi/cffi ; do
	rm -rf cffi
	sleep 15
done
cd cffi
update_title_info
# NOTE: Cross-compiling Python modules is hell.
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/cffi-py2-x-compile.patch
# NOTE: This is hackish. If the host's Python doesn't exactly match, here be dragons.
# We're using https://pypi.python.org/pypi/distutilscross to soften some of the sillyness, but it's still a pile of dominoes waiting to fall...
#env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" CFLAGS="${BASE_CFLAGS} -I${TC_BUILD_DIR}/python/include/python2.7" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --no-compile
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py clean --all
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py build -x
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile --skip-build
done
cd ..
## SimpleJSON
rm -rf simplejson
until git clone --depth 1 https://github.com/simplejson/simplejson.git ; do
	rm -rf simplejson
	sleep 15
done
cd simplejson
update_title_info
#env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" CFLAGS="${BASE_CFLAGS} -I${TC_BUILD_DIR}/python/include/python2.7" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --no-compile
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py clean --all
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py build -x
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile --skip-build
done
cd ..
## six
rm -rf six
until git clone --depth 1 https://github.com/benjaminp/six.git ; do
	rm -rf six
	sleep 15
done
cd six
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## asn1crypto
rm -rf asn1crypto
until git clone --depth 1 https://github.com/wbond/asn1crypto.git ; do
	rm -rf asn1crypto
	sleep 15
done
cd asn1crypto
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## enum34
## NOTE: Not on Py3k!
rm -rf enum34
until hg clone https://bitbucket.org/stoneleaf/enum34 ; do
	rm -rf enum34
	sleep 15
done
cd enum34
update_title_info
python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --install-lib=lib/python2.7/site-packages --no-compile
cd ..
## ipaddress
## NOTE: Even though it's a backport, apparently safe on Py3k
rm -rf ipaddress
until git clone --depth 1 https://github.com/phihag/ipaddress.git ; do
	rm -rf ipaddress
	sleep 15
done
cd ipaddress
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..


## cryptography
# NOTE: Building from git doesn't work, for some obscure reason...
rm -rf cryptography-2.8
wget https://pypi.python.org/packages/source/c/cryptography/cryptography-2.8.tar.gz -O cryptography-2.8.tar.gz
tar -I pigz -xvf cryptography-2.8.tar.gz
cd cryptography-2.8
update_title_info
#env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" CFLAGS="${BASE_CFLAGS} -I${TC_BUILD_DIR}/python/include/python2.7" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --no-compile
# NOTE: We need to link against pthreads, and distutils is terrible.
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared -pthread" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py clean --all
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared -pthread" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py build -x
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared -pthread" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile --skip-build
done
cd ..
## PyOpenSSL
rm -rf pyopenssl
# NOTE: Not shallow because it leads to broken versioning
until git clone https://github.com/pyca/pyopenssl.git ; do
	rm -rf pyopenssl
	sleep 15
done
cd pyopenssl
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..

## toolbelt
rm -rf toolbelt
until git clone --depth 1 https://github.com/requests/toolbelt.git ; do
	rm -rf toolbelt
	sleep 15
done
cd toolbelt
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## betamax
rm -rf betamax
until git clone --depth 1 https://github.com/betamaxpy/betamax.git ; do
	rm -rf betamax
	sleep 15
done
cd betamax
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## pyjwt for Python 2
rm -rf pyjwt
# Final release w/ Python 2.7 support
until git clone -b 1.7.1 --single-branch --depth 1 https://github.com/jpadilla/pyjwt.git ; do
	rm -rf pyjwt
	sleep 15
done
cd pyjwt
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
		# Skip
		continue
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## pyjwt for Python 3
rm -rf pyjwt
until git clone --depth 1 https://github.com/jpadilla/pyjwt.git ; do
	rm -rf pyjwt
	sleep 15
done
cd pyjwt
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
		# Skip
		continue
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## oauthlib for Python 2
rm -rf oauthlib
# Final release w/ Python 2.7 support
until git clone -b v3.1.0 --single-branch --depth 1 https://github.com/oauthlib/oauthlib.git ; do
	rm -rf oauthlib
	sleep 15
done
cd oauthlib
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
		# Skip
		continue
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## oauthlib for Python 3
rm -rf oauthlib
until git clone --depth 1 https://github.com/oauthlib/oauthlib.git ; do
	rm -rf oauthlib
	sleep 15
done
cd oauthlib
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
		# Skip
		continue
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## requests-oauthlib
rm -rf requests-oauthlib
until git clone --depth 1 https://github.com/requests/requests-oauthlib.git ; do
	rm -rf requests-oauthlib
	sleep 15
done
cd requests-oauthlib
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## py-fbink
rm -rf py-fbink
until git clone --depth 1 https://github.com/NiLuJe/py-fbink.git ; do
	rm -rf py-fbink
	sleep 15
done
cd py-fbink
update_title_info
#env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" CFLAGS="${BASE_CFLAGS} -I${TC_BUILD_DIR}/python/include/python2.7" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --no-compile
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py clean --all
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py build -x
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile --skip-build
done
cd ..
## Pillow for Python 2
rm -rf Pillow
until git clone -b 6.2.x --single-branch --depth 1 https://github.com/python-pillow/Pillow.git ; do
	rm -rf Pillow
	sleep 15
done
cd Pillow
update_title_info
# Nerf the setup to avoid pulling in native paths...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/Pillow-py2-fix-setup-paths.patch
#env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" CFLAGS="${BASE_CFLAGS} -I${TC_BUILD_DIR}/python/include/python2.7" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --no-compile
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
		# We want the latest version on Py3k
		continue
	else
		py_home="python"
	fi

	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py clean --all
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py build -x
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile --skip-build
done
cd ..
## Pillow for Python 3
rm -rf Pillow
until git clone --depth 1 https://github.com/python-pillow/Pillow.git ; do
	rm -rf Pillow
	sleep 15
done
cd Pillow
update_title_info
# Nerf the setup to avoid pulling in native paths...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/Pillow-fix-setup-paths.patch
#env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" CFLAGS="${BASE_CFLAGS} -I${TC_BUILD_DIR}/python/include/python2.7" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --no-compile
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
		# We already dealt with Python 2 above
		continue
	fi

	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py clean --all
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py build -x
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile --skip-build
done
cd ..
## wand
rm -rf wand
until git clone --depth 1 https://github.com/emcconville/wand.git ; do
	rm -rf wand
	sleep 15
done
cd wand
update_title_info
# Make sure we'll be able to load our own IM libs (we basically enforce a hardcoded MAGICK_HOME, as ctypes.util.find_library has no hopes of ever finding anything on our target platforms...; plus a few tweaks to pickup the right IM variant/sover)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/wand-fix-library-loading.patch
sed -e "s#/mnt/us#${DEVICE_USERSTORE}#g" -i wand/api.py
#env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" CFLAGS="${BASE_CFLAGS} -I${TC_BUILD_DIR}/python/include/python2.7" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --no-compile
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
		sed -e "s#'${DEVICE_USERSTORE}/python'#'${DEVICE_USERSTORE}/python3'#g" -i wand/api.py
	else
		py_home="python"
		sed -e "s#'${DEVICE_USERSTORE}/python3'#'${DEVICE_USERSTORE}/python'#g" -i wand/api.py
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## python-ioctl-opt
rm -rf python-ioctl-opt
until git clone --depth 1 https://github.com/vpelletier/python-ioctl-opt.git ; do
	rm -rf python-ioctl-opt
	sleep 15
done
cd python-ioctl-opt
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## cssselect
rm -rf cssselect
until git clone --depth 1 https://github.com/scrapy/cssselect.git ; do
	rm -rf cssselect
	sleep 15
done
cd cssselect
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## webencodings
rm -rf python-webencodings
until git clone --depth 1 https://github.com/gsnedders/python-webencodings.git ; do
	rm -rf python-webencodings
	sleep 15
done
cd python-webencodings
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## html5lib
rm -rf html5lib-python
until git clone --depth 1 https://github.com/html5lib/html5lib-python.git ; do
	rm -rf html5lib-python
	sleep 15
done
cd html5lib-python
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## lxml
rm -rf lxml
until git clone --depth 1 https://github.com/lxml/lxml.git ; do
	rm -rf lxml
	sleep 15
done
cd lxml
update_title_info
#env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" CFLAGS="${BASE_CFLAGS} -I${TC_BUILD_DIR}/python/include/python2.7" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/python/lib -L${TC_BUILD_DIR}/python/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib" python2.7 setup.py install --root=${TC_BUILD_DIR}/python --prefix=. --no-compile
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" python${py_ver} setup.py clean --all
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" XML2_CONFIG="${TC_BUILD_DIR}/bin/xml2-config" XSLT_CONFIG="${TC_BUILD_DIR}/bin/xslt-config" python${py_ver} setup.py build -x
	env CC="${CROSS_TC}-gcc" LDSHARED="${CROSS_TC}-gcc -shared" PYTHONXCPREFIX="${TC_BUILD_DIR}/${py_home}" LDFLAGS="${BASE_LDFLAGS} -L${TC_BUILD_DIR}/${py_home}/lib -L${TC_BUILD_DIR}/${py_home}/usr/lib -L${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot/usr/lib -Wl,-rpath=${DEVICE_USERSTORE}/${py_home}/lib" XML2_CONFIG="${TC_BUILD_DIR}/bin/xml2-config" XSLT_CONFIG="${TC_BUILD_DIR}/bin/xslt-config" python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile --skip-build
done
cd ..
## BeautifulSoup
rm -rf beautifulsoup
until bzr branch lp:beautifulsoup ; do
	rm -rf beautifulsoup
	sleep 15
done
cd beautifulsoup
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## soupsieve for Python 2
rm -rf soupsieve
until git clone -b 1.9.X --single-branch --depth 1 https://github.com/facelessuser/soupsieve.git ; do
	rm -rf soupsieve
	sleep 15
done
cd soupsieve
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
		# Skip
		continue
	else
		py_home="python"
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..
## soupsieve for Python 3
rm -rf soupsieve
until git clone --depth 1 https://github.com/facelessuser/soupsieve.git ; do
	rm -rf soupsieve
	sleep 15
done
cd soupsieve
update_title_info
for py_ver in ${PYTHON_VERSIONS} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
		# Skip
		continue
	fi

	python${py_ver} setup.py clean --all
	python${py_ver} setup.py install --root=${TC_BUILD_DIR}/${py_home} --prefix=. --install-lib=lib/python${py_ver}/site-packages --no-compile
done
cd ..

for py_ver in ${PYTHON_CUR_VER} ${PYTHON3_CUR_VER} ; do
	if [[ "${py_ver}" == 3.* ]] ; then
		py_home="python3"
	else
		py_home="python"
	fi

	cd Python-${py_ver}
	# Don't forget libffi ;)
	cp ../lib/libffi.so.${FFI_SOVER} ../${py_home}/lib/libffi.so.${FFI_SOVER%%.*}
	# We're gonna need our shared libs... (expat because the one on the Kindle is too old, zlib to avoid symbol versioning issues, ncursesw & readline for the CLI)
	cp ../lib/libexpat.so.${EXPAT_SOVER} ../${py_home}/lib/libexpat.so.${EXPAT_SOVER%%.*}
	cp ../lib/libz.so.${ZLIB_SOVER} ../${py_home}/lib/libz.so.${ZLIB_SOVER%%.*}
	cp ../lib/libncurses.so.${NCURSES_SOVER} ../${py_home}/lib/libncurses.so.${NCURSES_SOVER%%.*}
	cp ../lib/libncursesw.so.${NCURSES_SOVER} ../${py_home}/lib/libncursesw.so.${NCURSES_SOVER%%.*}
	cp ../lib/libpanel.so.${NCURSES_SOVER} ../${py_home}/lib/libpanel.so.${NCURSES_SOVER%%.*}
	cp ../lib/libpanelw.so.${NCURSES_SOVER} ../${py_home}/lib/libpanelw.so.${NCURSES_SOVER%%.*}
	cp ../lib/libtinfo.so.${NCURSES_SOVER} ../${py_home}/lib/libtinfo.so.${NCURSES_SOVER%%.*}
	cp ../lib/libtinfow.so.${NCURSES_SOVER} ../${py_home}/lib/libtinfow.so.${NCURSES_SOVER%%.*}
	cp ../lib/libreadline.so.${READLINE_SOVER} ../${py_home}/lib/libreadline.so.${READLINE_SOVER%%.*}
	chmod -cvR ug+w ../${py_home}/lib/libreadline.so.${READLINE_SOVER%%.*}
	# And OpenSSL...
	for my_lib in libcrypto.so.${OPENSSL_SOVER} libssl.so.${OPENSSL_SOVER} ; do
		# The _ssl module links to the full sover
		cp ../lib/${my_lib} ../${py_home}/lib/${my_lib}
		chmod -cvR ug+w ../${py_home}/lib/${my_lib}
	done
	# And SQLite, too...
	if [[ "${SQLITE_WITH_ICU}" == "true" ]] ; then
		# We're going to need our ICU shared libs...
		for my_icu_lib in libicudata libicui18n libicuuc ; do
			cp ../lib/${my_icu_lib}.so.${ICU_SOVER} ../${py_home}/lib/${my_icu_lib}.so.${ICU_SOVER%%.*}
		done
	fi
	cp ../lib/libsqlite3.so.${SQLITE_SOVER} ../${py_home}/lib/libsqlite3.so.${SQLITE_SOVER%%.*}
	# And FBInk...
	cp ../lib/libfbink.so.1.0.0 ../${py_home}/lib/libfbink.so.1
	# And various stuff for Pillow (jpeg-turbo, FT & HB)
	# NOTE: imagequant is useless for our purposes (we only dither to a single, fixed palette, which it's... bad at).
	#       raqm might be nice to have, but it hard-depends on FriBiDi, too.
	cp ../lib/libjpeg.so.${LIBJPG_SOVER} ../${py_home}/lib/libjpeg.so.${LIBJPG_SOVER%%.*}
	cp ../lib/libturbojpeg.so.${LIBTJP_SOVER} ../${py_home}/lib/libturbojpeg.so.${LIBTJP_SOVER%%.*}
	cp ../lib/libfreetype.so.${FT_SOVER} ../${py_home}/lib/libfreetype.so.${FT_SOVER%%.*}
	cp ../lib/libharfbuzz.so.${HB_SOVER} ../${py_home}/lib/libharfbuzz.so.${HB_SOVER%%.*}
	# And IM for wand
	cp ../lib/libMagickCore-6.Q8.so.${IM_SOVER} ../${py_home}/lib/libMagickCore-6.Q8.so.${IM_SOVER%%.*}
	cp ../lib/libMagickWand-6.Q8.so.${IM_SOVER} ../${py_home}/lib/libMagickWand-6.Q8.so.${IM_SOVER%%.*}
	# Keep our own sqlite3 CLI, for shit'n giggles
	cp ../bin/sqlite3 ../${py_home}/bin/sqlite3
	# libxml2 & libxslt for BeautifulSoup
	cp ../lib/libxml2.so.${LIBXML2_VERSION} ../${py_home}/lib/libxml2.so.${LIBXML2_VERSION%%.*}
	cp ../lib/libxslt.so.${LIBXSLT_VERSION} ../${py_home}/lib/libxslt.so.${LIBXSLT_VERSION%%.*}
	cp ../lib/libexslt.so.${LIBEXSLT_SOVER} ../${py_home}/lib/libexslt.so.${LIBEXSLT_SOVER%%.*}

	if [[ "${py_ver}" == 2.* ]] ; then
		# And now, clean it up, to try to end up with the smallest install package possible...
		sed -e "s/\(LDFLAGS=\).*/\1/" -i "../python/lib/python2.7/config/Makefile"
		# The DT_NEEDED entries all appear to point to the shared library w/ the full sover, kill the short symlink, since we can't use it on vfat as-is...
		rm -rf ../python/lib/libpython2.7.so
		# First, strip...
		chmod a+w ../python/lib/libpython2.7.so.1.0
		while read -d $'\0' -r file; do
			files+=("${file}")
		done < <(find "../python" -name '*.so*' -type f -print0)
		if [[ "${#files[@]}" -gt 0 ]]; then
			echo "Stripping libraries:"
			for file in "${files[@]}"; do
				echo " ${file}"
				${CROSS_TC}-strip --strip-unneeded "${file}"
			done
		fi
		unset file files
		chmod a-w ../python/lib/libpython2.7.so.1.0
		echo "Stripping binaries"
		${CROSS_TC}-strip --strip-unneeded ../python/bin/python2.7 ../python/bin/sqlite3
		# Assume we're only ever going to need the shared libpython...
		rm -rf ../python/lib/libpython2.7.a
		# Next, kill a bunch of stuff we don't care about...
		rm -rf ../python/lib/pkgconfig ../python/share
		# Kill the symlinks we can't use on vfat anyway...
		find ../python -type l -delete
		# And now, do the same cleanup as the Gentoo ebuild...
		rm -rf ../python/lib/python2.7/{bsddb,dbhash.py,test/test_bsddb*}
		rm -rf ../python/bin/idle ../usr/bin/idle2.7 ../python/lib/python2.7/{idlelib,lib-tk}
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
					rmdir --ignore-fail-on-non-empty "${file%/*}"
				fi
			done
		fi

		if [[ -d "../python/lib/python2.7/site-packages" ]]; then
			find "../python/lib/python2.7/site-packages" "(" -name "*.c" -o -name "*.h" -o -name "*.la" ")" -type f -delete
		fi
		unset file files
		# Fix some shebangs to use the target prefix, not the one from my host...
		sed -e "s#${TC_BUILD_DIR}/#${DEVICE_USERSTORE}/#" -i ../python/bin/smtpd.py ../python/bin/python2.7-config ../python/bin/pydoc ../python/bin/2to3
	else
		py_maj="${PYTHON3_CUR_VER%.*}"
		# Cleanup, Py3k variant ;)
		sed -e "s/\(CONFIGURE_LDFLAGS=\).*/\1/" -e "s/\(PY_LDFLAGS=\).*/\1/" -i ../${py_home}/lib/python${py_maj}/config-${py_maj}*/Makefile
		# The DT_NEEDED entries all appear to point to the shared library w/ the full sover, kill the short symlink, since we can't use it on vfat as-is...
		# NOTE: We do this only now, because not having this prevents building 3rd party Python modules ;).
		#       This is potentially no longer an issue, since C extensions no longer link to libpython since Python 3.8 :).
		rm -rf ../${py_home}/lib/libpython${py_maj}.so
		rm -rf ../${py_home}/lib/libpython3.so
		# First, strip...
		chmod a+w ../${py_home}/lib/libpython${py_maj}.so.1.0
		while read -d $'\0' -r file; do
			files+=("${file}")
		done < <(find "../${py_home}" -name '*.so*' -type f -print0)
		if [[ "${#files[@]}" -gt 0 ]]; then
			echo "Stripping libraries:"
			for file in "${files[@]}"; do
				echo " ${file}"
				${CROSS_TC}-strip --strip-unneeded "${file}"
			done
		fi
		unset file files
		chmod a-w ../${py_home}/lib/libpython${py_maj}.so.1.0
		echo "Stripping binaries"
		${CROSS_TC}-strip --strip-unneeded ../${py_home}/bin/python${py_maj} ../${py_home}/bin/sqlite3
		# Assume we're only ever going to need the shared libpython...
		rm -rf ../${py_home}/lib/libpython${py_maj}.a
		# Next, kill a bunch of stuff we don't care about...
		rm -rf ../${py_home}/lib/pkgconfig ../${py_home}/share
		# Kill the symlinks we can't use on vfat anyway...
		find ../${py_home} -type l -delete
		# And now, do the same cleanup as the Gentoo ebuild...
		rm -rf ../usr/bin/idle${py_maj} ../${py_home}/lib/python${py_maj}/{idlelib,tkinter,test/test_tk*}
		rm -f ../${py_home}/lib/python${py_maj}/distutils/command/wininst-*.exe
		# And the big one, kill bytecode (we'll rebuild it during install on the Kindle)
		while read -d $'\0' -r file; do
			files+=("${file}")
		done < <(find "../${py_home}" "(" -name "*.py[co]" -o -name "*\$py.class" ")" -type f -print0)
		if [[ "${#files[@]}" -gt 0 ]]; then
			echo "Deleting byte-compiled Python modules needlessly generated by build system:"
			for file in "${files[@]}"; do
				echo " ${file}"
				rm -f "${file}"

				if [[ "${file%/*}" == *"/__pycache__" ]]; then
					rmdir --ignore-fail-on-non-empty "${file%/*}"
				fi
			done
		fi

		if [[ -d "../${py_home}/lib/python${py_maj}/site-packages" ]]; then
			find "../${py_home}/lib/python${py_maj}/site-packages" "(" -name "*.c" -o -name "*.h" -o -name "*.la" ")" -type f -delete
			find "../${py_home}" -name "__pycache__" -type d -delete
		fi
		unset file files
		# Fix some shebangs to use the target prefix, not the one from my host...
		sed -e "s#${TC_BUILD_DIR}/#${DEVICE_USERSTORE}/#" -i ../${py_home}/bin/python${py_maj}-config ../${py_home}/bin/pydoc${py_maj} ../${py_home}/bin/2to3-${py_maj} ../${py_home}/bin/idle${py_maj} ../${py_home}/lib/python${py_maj}/config-${py_maj}*/python-config.py
		# NOTE: Because of course we can't have nice things, some 3rd-party modules pick the host's EXT_SUFFIX from _sysconfigdata instead of the target's...
		#       Instead of trying to figure that one out, just rename 'em.
		#       Right now, this seems to affect cFFI, simplejson & Pillow...
		# NOTE: The _PYTHON_SYSCONFIGDATA_NAME + PYTHONHOME trick from https://bugs.python.org/msg282141 doesn't exhibit this issue, but is throwing an UserWarning: Unknown distribution option: 'python_requires' instead (which, granted, appears mostly harmless).
		#       On the upside, it also prevents include directory poisoning: no more trailing -I/usr/include in the mix ;).
		#       It's *possible* an ensurepip build would prevent the warning?
		# NOTE: It *does* generate a few __pycache__ folder we'd have to cleanup, though...
		native_suffix="$(grep EXT_SUFFIX /usr/lib/python${py_maj}/_sysconfigdata_*.py | cut -f4 -d "'")"
		target_suffix="$(grep EXT_SUFFIX ../${py_home}/lib/python${py_maj}/_sysconfigdata_*.py | cut -f4 -d "'")"
		while read -d $'\0' -r file; do
			files+=("${file}")
		done < <(find "../${py_home}" -name "*${native_suffix}" -type f -print0)
		if [[ "${#files[@]}" -gt 0 ]]; then
			echo "Fixing bogus extension suffix:"
			for file in "${files[@]}"; do
				echo " ${file}"
				mv -v "${file}" "${file/${native_suffix}/${target_suffix}}"
			done
		fi
		unset file files
		unset native_suffix target_suffix
		unset py_maj
	fi
	cd ..
done

# And finally, build our shiny tarball
tar --hard-dereference -cvJf python.tar.xz python
cp -f python.tar.xz ${BASE_HACKDIR}/Python/src/python.tar.xz
# And then Py3k
tar --hard-dereference -cvJf python3.tar.xz python3
cp -f python3.tar.xz ${BASE_HACKDIR}/Python/src/python3.tar.xz
cd -
unset PYTHON_VERSIONS py_ver py_home
# NOTE: Might need to use the terminfo DB from usbnet to make the interpreter UI useful: export TERMINFO=${DEVICE_USERSTORE}/usbnet/etc/terminfo

## inotify-tools for ScreenSavers on the K2/3/4
echo "* Building inotify-tools . . ."
echo ""
cd ..
rm -rf inotify-tools
until git clone --depth 1 https://github.com/rvoicilas/inotify-tools.git ; do
	rm -rf inotify-tools
	sleep 15
done
cd inotify-tools
update_title_info
# Kill -Werror, it whines about _GNU_SOURCE on the K3...
sed -e 's/-Werror//' -i src/Makefile.am libinotifytools/src/Makefile.am
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
tar -I lbzip2 -xvf /usr/portage/distfiles/pcre-8.44.tar.bz2
cd pcre-8.44
update_title_info
sed -e "s:-lpcre ::" -i libpcrecpp.pc.in
patch -p1 < /usr/portage/dev-libs/libpcre/files/libpcre-8.41-fix-stack-size-detection.patch
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
cp ../lib/libpcre.so.1.2.11 ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libpcre.so.1
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libpcre.so.1
cp ../lib/libpcreposix.so.0.0.6 ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libpcreposix.so.0
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libpcreposix.so.0

## sshfs for USBNet (Build it at the end, I don't want glib to be automagically pulled by something earlier...)
#
# Depends on glib
echo "* Building glib . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/glib-2.60.7.tar.xz
cd glib-2.60.7
update_title_info
patch -p1 < /usr/portage/dev-libs/glib/files/2.60.7-gdbus-fixes.patch
#tar xvJf /usr/portage/distfiles/glib-2.58.1-patchset.tar.xz
for patchfile in patches/*.patch ; do
	[[ -f "${patchfile}" ]] && patch -p1 < ${patchfile}
done
sed -i -e '/subdir.*tests/d' {.,gio,glib}/meson.build
sed -i -e '/subdir.*fuzzing/d' meson.build

export CFLAGS="${BASE_CFLAGS} -DG_DISABLE_CAST_CHECKS"
export CXXFLAGS="${BASE_CFLAGS} -DG_DISABLE_CAST_CHECKS"

# NOTE: Let's deal with Meson and generate our cross file...
meson_setup

# c.f., https://developer.gnome.org/glib/stable/glib-cross-compiling.html
my_meson_props=( "growing_stack=false" "have_c99_vsnprintf=true" "have_c99_snprintf=true" "have_unix98_printf=true" "have_strlcpy=false" )
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	# Glibc >= 2.8!
	my_meson_props+=("has_function_qsort_r=false")
	# Glibc >= 2.9
	my_meson_props+=("has_function_pipe2=false")
	my_meson_props+=("has_function_inotify_init1=false")
	# Glibc >= 2.7
	my_meson_props+=("has_function_mkostemp=false")
	# NOTE: Custom fragment, no idea how to disable that the right way.... *sigh*
	sed -e 's/\(eventfd[[:blank:]]*(\)/NO_\1/g' -i meson.build
else
	my_meson_props+=("has_function_qsort_r=true")
fi

# Set the props in the Meson Cross file...
my_meson_props+=("have_libelf=false")
for my_prop in "${my_meson_props[@]}" ; do
	sed "/#%MESON_PROPS%/ a ${my_prop}" -i MesonCross.txt
done
unset my_meson_props

# NOTE: Meson sanity checks the *native* compiler with the CFLAGS from the env, which of course contain target-specific flags.
#       This is extremely stupid. Deal with that nonsense.
#       According to https://mesonbuild.com/Running-Meson.html#environment-variables,
#       The idea appears to be that the env should only apply to the native TC. Which is... weird, and extremely counter-intuitive, but, okay...
env -u CPPFLAGS -u CFLAGS -u CXXFLAGS -u LDFLAGS meson . builddir --cross-file MesonCross.txt --buildtype plain -Ddefault_library=static -Dselinux=disabled -Dxattr=false -Dlibmount=false -Dinternal_pcre=false -Dman=false -Ddtrace=false -Dsystemtap=false -Dgtk_doc=false -Dfam=false -Dinstalled_tests=false -Dnls=enabled
ninja -v -C builddir
ninja -v -C builddir install
export CFLAGS="${BASE_CFLAGS}"
export CXXFLAGS="${BASE_CFLAGS}"

# And of course FUSE ;)
echo "* Building fuse . . ."
echo ""
cd ..
tar -xvJf /usr/portage/distfiles/fuse-3.9.0.tar.xz
cd fuse-3.9.0
update_title_info

if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	# NOTE: This was introduced in Linux 3.5, so it's not in our TC's headers, but will work at runtime on *some* of our target devices (i.e., >= Mk. 7).
	#       Older devices can still use umount as root ;).
	export CPPFLAGS="${BASE_CPPFLAGS} -DPR_SET_NO_NEW_PRIVS=38"
fi
# NOTE: Can't use LTO (https://github.com/libfuse/libfuse/issues/198)
export CFLAGS="${NOLTO_CFLAGS}"

# NOTE: Let's deal with Meson...
meson_setup
# We also need to disable pipe2 on K3, like for glib
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	my_meson_props=( "has_function_pipe2=false" )
	for my_prop in "${my_meson_props[@]}" ; do
		sed "/#%MESON_PROPS%/ a ${my_prop}" -i MesonCross.txt
	done
	unset my_meson_props
fi

# NOTE: Kobo doesn't ship fusermount, so, we build utils & ship it (along with mount.fuse3). On the other hand, they don't ship with FUSE in the kernel, either :D.
#       Nevertheless, stick to static libraries to keep things simple... We don't actually need these helpers in most cases, as we're mostly always root ;).
# NOTE: Random mildly related comment re: building modules. Reading https://github.com/marek-g/kobo-kernel-2.6.35.3-marek/blob/linux/build_instructions is a good start.
#       In practice, on the old H2O kernel, I've also had to:
#         * Clear LDFLAGS to prevent them from being picked up by something and and borking it. In the end, I ended up clearing CPPFLAGS/CFLAGS/CXXFLAGS, too, just to be on the safe side.
#         * Fix scripts/kconfig/lxdialog/check-lxdialog.sh to link against libtinfow (i.e., add -ltinfow to the -l${lib} string), too (similar to what I had to do in ct-ng 1.23), in order to be able to run menuconfig and enable FUSE.
#         * Kill the final defined() call in kernel/timeconst.pl, as per the warning, to get the main kernel to build.
#         * Because of CONFIG_MODVERSIONS, you need a full kernel build first, otherwise init_module throws a fit (ENOEXEC, invalid module format). So you can't just make modules && make modules_install :/.
#       The H2O kernel appears to have been built with truly ancient MG/CodeSourcery (2010q1-202) GCC 4.4.1 TCs, so I went with my bare 'nickel' GCC 4.9 TC to stay as close as that as possible. That worked out fine.
#       On that note, fun fact: On Mk. 7, while the rootfs is indeed built with Linaro GCC 4.9-2017.01, the kernel appears to be built w/ GCC 5.3.0...
#       Kobo doesn't do modprobe, so I just threw the modules into /drivers/${PLATFORM}/fs/fuse and called it a day ;).
#       No need to have the u-boot tools installed since I'm not actually planning on flashing a custom kernel ;). You probably don't want to do that anyway, since the sources aren't always up to date...
#       The H2O sources ship with the right .config in place, otherwise, simply zcat /proc/config.gz from a live device. Or pick the right defconfig (i.e., imx_v7_kobo_defconfig for Mk.7 kernels, in arch/arm/configs).
#       Also, needed lzop for Mk. 7 kernels ;). And the proper target is now zImage, not uImage.
#       TL;DR:
#               source ~SVN/Configs/trunk/Kindle/Misc/x-compile.sh nickel env bare
#               unset CPPFLAGS CFLAGS CXXFLAGS LDFLAGS
#               make CROSS_COMPILE=${CROSS_PREFIX} ARCH=arm INSTALL_MOD_PATH=/var/tmp/niluje/kobo/modules menuconfig
#               make -j8 CROSS_COMPILE=${CROSS_PREFIX} ARCH=arm INSTALL_MOD_PATH=/var/tmp/niluje/kobo/modules uImage
#               make -j8 CROSS_COMPILE=${CROSS_PREFIX} ARCH=arm INSTALL_MOD_PATH=/var/tmp/niluje/kobo/modules modules
#               make -j8 CROSS_COMPILE=${CROSS_PREFIX} ARCH=arm INSTALL_MOD_PATH=/var/tmp/niluje/kobo/modules modules_install
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	env -u CPPFLAGS -u CFLAGS -u CXXFLAGS -u LDFLAGS meson . builddir --cross-file MesonCross.txt --buildtype plain -Ddefault_library=static -Dudevrulesdir=${TC_BUILD_DIR}/etc/udev/rules.d -Dexamples=false -Dutils=true -Duseroot=false
else
	env -u CPPFLAGS -u CFLAGS -u CXXFLAGS -u LDFLAGS meson . builddir --cross-file MesonCross.txt --buildtype plain -Ddefault_library=static -Dudevrulesdir=${TC_BUILD_DIR}/etc/udev/rules.d -Dexamples=false -Dutils=false
fi
ninja -v -C builddir
# Make sure it won't attempt to install the init script to the live, rootfs...
sed -e 's#${DESTDIR}/etc#${DESTDIR}${sysconfdir}#' -i util/install_helper.sh
ninja -v -C builddir install

export CFLAGS="${BASE_CFLAGS}"
export CPPFLAGS="${BASE_CPPFLAGS}"

# Install the utils on Kobo
if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	${CROSS_TC}-strip --strip-unneeded ../bin/fusermount3
	cp ../bin/fusermount3 ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/fusermount3
	${CROSS_TC}-strip --strip-unneeded ../sbin/mount.fuse3
	cp ../sbin/mount.fuse3 ${BASE_HACKDIR}/USBNetwork/src/usbnet/sbin/mount.fuse3
fi

# And finally sshfs
echo "* Building sshfs . . ."
echo ""
cd ..
rm -rf sshfs
until git clone --depth 1 https://github.com/libfuse/sshfs.git ; do
	rm -rf sshfs
	sleep 15
done
cd sshfs
update_title_info

# We don't have ssh in $PATH, call our own
sed -e "s#ssh_add_arg(\"ssh\");#ssh_add_arg(\"${DEVICE_USERSTORE}/usbnet/bin/ssh\");#" -i ./sshfs.c
# Same for sftp-server
sed -e "s#\"/usr/lib/sftp-server\"#\"${DEVICE_USERSTORE}/usbnet/libexec/sftp-server\"#" -i ./sshfs.c

# NOTE: Let's deal with Meson...
meson_setup
env -u CPPFLAGS -u CFLAGS -u CXXFLAGS -u LDFLAGS meson . builddir --cross-file MesonCross.txt --buildtype plain -Ddefault_library=static
ninja -v -C builddir
ninja -v -C builddir install

${CROSS_TC}-strip --strip-unneeded ../bin/sshfs
cp ../bin/sshfs ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/sshfs


# Build gawk for KUAL
echo "* Building gawk . . ."
echo ""
cd ..
rm -rf gawk
until git clone --depth 1 git://git.savannah.gnu.org/gawk.git ; do
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
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/gawk-4.2.1-allow-closing-stdout.patch
export ac_cv_libsigsegv=no
export ac_cv_func_working_mktime=yes
export has_f_format=yes
export has_a_format=yes
export CFLAGS="${RICE_CFLAGS}"
# Setup an rpath for the extensions...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/extensions/gawk/lib/gawk"
# FIXME: I'm guessing the old glibc somehow doesn't play nice with GCC, and stddef.h gets confused, but this is *very* weird.
# So, here goes an ugly workaround to get a ptrdiff_t typedef on time...
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	export CPPFLAGS="${BASE_CPPFLAGS} -D__need_ptrdiff_t"
fi
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --without-mpfr --disable-nls --without-readline
# Don't call the just-built binary...
sed -e 's#../gawk$(EXEEXT)#gawk#' -i extension/Makefile
make ${JOBSFLAGS}
make install
unset ac_cv_libsigsegv
unset ac_cv_func_working_mktime
unset has_f_format
unset has_a_format
export LDFLAGS="${BASE_LDFLAGS}"
export CFLAGS="${BASE_CFLAGS}"
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
export CFLAGS="${RICE_CFLAGS}"
# Pull our own zlib to avoid symbol versioning issues (and enjoy better PNG compression perf)...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
make ${JOBSFLAGS} CC=${CROSS_TC}-gcc
${CROSS_TC}-strip --strip-unneeded fbgrab
cp fbgrab ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/fbgrab
export LDFLAGS="${BASE_LDFLAGS}"
export CFLAGS="${BASE_CFLAGS}"

# strace & ltrace
# XXX: Craps out w/ Linaro GCC 5.3 2016.01/2016.02/2016.03 on Thumb2 TCs (i.e., everything except K3)
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
	until git clone --depth 1 git://git.savannah.gnu.org/libunwind.git libunwind ; do
		rm -rf libunwind
		sleep 15
	done
	cd libunwind
	update_title_info
	# Older glibc's <elf.h> don't have the required constants (elfutils does, but we're building this *for* elfutils ;))...
	# NOTE: Only an issue since https://git.savannah.gnu.org/gitweb/?p=libunwind.git;a=commit;h=a36ec8cfdb8764e4f8bf6b16a149a60ea6ad038d
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/libunwind-old-glibc-build-fix.diff
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
# NOTE: Not shallow because we need a checkout for the K3 build, and we want a proper version tag
until git clone https://github.com/strace/strace.git strace ; do
	rm -rf strace
	sleep 15
done
cd strace
update_title_info
# Regen the ioctl list...
if [[ "${KINDLE_TC}" == "PW2" ]] ; then
	# NOTE: Thankfully, this one appears sane, and include/linux/linux/mxcfb.h still matches the one from 5.6.5 ;).
	#       Make sure you're using the PW2 build: https://s3.amazonaws.com/kindledownloads/Kindle_src_5.9.5.1_3301940011.tar.gz
	ksrc="${HOME}/Kindle/SourceCode_Packages/5.9.5.1/gplrelease/linux"
	#ksrc="${HOME}/Kindle/SourceCode_Packages/KOA2_5.9.6.1/gplrelease/linux"
	#ksrc="${HOME}/Kindle/SourceCode_Packages/PW4_5.10.1.2/gplrelease/linux"
	asrc="${ksrc}/arch/arm/include"
elif [[ "${KINDLE_TC}" == "K5" ]] ; then
	# NOTE: Don't move to 5.6.1.1, it ships includes for the updated eink driver, but that doesn't match the actual binaries on prod in 5.6.1.1 on the PW1...
	# We'd need a custom mxcfb.h header like on KOReader to handle this properly if the PW1 ever actually inherits the updated driver...
	# NOTE: For ref: https://kindle.s3.amazonaws.com/Kindle_src_5.4.4.2_2323310003.tar.gz
	ksrc="${HOME}/Kindle/SourceCode_Packages/5.4.4.2/gplrelease/linux"
	asrc="${ksrc}/arch/arm/include"
elif [[ "${KINDLE_TC}" == "KOBO" ]] ; then
	# NOTE: Use the H2O² (Rev 2) kernel, it has the most up to date mxcfb.h header. Might need some minor hand-holding for backward compat stuff...
	#       c.f., https://github.com/koreader/koreader-base/issues/390
	ksrc="${HOME}/Kindle/SourceCode_Packages/Kobo-H2O2R2"
	asrc="${ksrc}/arch/arm/include"
else
	# NOTE: https://kindle.s3.amazonaws.com/Kindle_src_3.4.2_2687240004.tar.gz
	ksrc="${HOME}/Kindle/SourceCode_Packages/3.4.2/gplrelease/linux-2.6.26"
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

	# Because I'm a little bit crazy, and I needed to make sure of something for FBInk... (Only decodes the bare minimum)
	cp -v ${ksrc}/include/linux/einkfb.h linux/einkfb.h
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-einkfb-ioctls-k3.patch
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
	# Some more ugly workarounds for the positively weird & ancient kernels used....
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-ioctls_sym-tweaks.patch
	#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-ioctls_sym-tweaks-koa2.patch
	#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-ioctls_sym-tweaks-pw4.patch
	sh ./maint/ioctls_gen.sh ${ksrc}/include ${asrc}
	cpp -P ioctl_iocdef.c -o ioctl_iocdef.i
	sed -n 's/^DEFINE HOST/#define /p' ioctl_iocdef.i > ioctl_iocdef.h
	gcc -Wall -I. ioctlsort.c -o ioctlsort
	./ioctlsort > ioctlent0.h
	export LDFLAGS="${BASE_LDFLAGS}"
	export CFLAGS="${BASE_CFLAGS}"
	unset TMPDIR
	# Copy mxcfb from the Amazon/Kobo sources, since we're building against a vanilla Kernel, and we'll need this include for the ioctl decoding patch...
	if [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] || [[ "${KINDLE_TC}" == "KOBO" ]] ; then
		cp -v ${ksrc}/include/linux/mxcfb.h linux/mxcfb.h
		if [[ "${KINDLE_TC}" == "KOBO" ]] ; then
			# NOTE: Needed for KOA2 & PW4 builds, too!
			mkdir -p uapi/linux
			cp -v ${ksrc}/include/uapi/linux/mxcfb.h uapi/linux/mxcfb.h
			#cp -v ${ksrc}/include/linux/fb.h linux/fb.h
			# NOTE: On the PW4, we instead kill the fb.h include to avoid dependency hell on other kernel headers...
			#sed -e 's%#include <linux/fb.h>%//#include <linux/fb.h>%' -i uapi/linux/mxcfb.h
			#sed -e 's%struct fb_var_screeninfo var;%//struct fb_var_screeninfo var;%' -i uapi/linux/mxcfb.h

		fi
	fi
	unset ksrc asrc
	# Apply the ioctl decode patch for our TC. Based on https://gist.github.com/erosennin/593de363a4361411cd4f (erosennin's patch for https://github.com/koreader/koreader/issues/741) ;).
	if [[ "${KINDLE_TC}" == "K5" ]] ; then
		patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-mxcfb-ioctls-k5.patch
	elif [[ "${KINDLE_TC}" == "PW2" ]] ; then
		patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-mxcfb-ioctls-pw2.patch
		#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-mxcfb-ioctls-koa2.patch
		#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/strace-mxcfb-ioctls-pw4.patch
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
# NOTE: Don't try to build with libunwind support when we didn't build it... (cf. previous XXX about libunwind on GCC 5.3 < 2016.04)
if [[ -f "../lib/libunwind-ptrace.so.0.0.0" ]] ; then
	# NOTE: The configure's check for libunwind doesn't rely on pkg-config, so we have to enforce libunwind's new dependency on zlib ourselves...
	env LIBS="-lz" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-stacktrace=yes --with-libunwind --disable-gcc-Werror
else
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-stacktrace=no --without-libunwind --disable-gcc-Werror
fi
make ${JOBSFLAGS}
make install
export LDFLAGS="${BASE_LDFLAGS}"
${CROSS_TC}-strip --strip-unneeded ../bin/strace
cp ../bin/strace ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/strace

# ltrace depends on elfutils
# NOTE: readelf relies on qsort_r, which was introduced in glibc 2.8... That obviously doesn't fly for the K3...
echo "* Building elfutils . . ."
echo ""
cd ..
ELFUTILS_VERSION="0.178"
tar -I lbzip2 -xvf /usr/portage/distfiles/elfutils-${ELFUTILS_VERSION}.tar.bz2
cd elfutils-${ELFUTILS_VERSION}
update_title_info
patch -p1 < /usr/portage/dev-libs/elfutils/files/elfutils-0.175-disable-biarch-test-PR24158.patch
patch -p1 < /usr/portage/dev-libs/elfutils/files/elfutils-0.177-disable-large.patch
# This essentially reverts https://sourceware.org/git/?p=elfutils.git;a=commit;h=5f9fab9efb042d803fcd2546f29613493f55d666
# re-introducing a broken behavior, but we can't actually use aligned_alloc on our targets, as it was introduced in glibc 2.16...
# NOTE: FWIW, trying to use the GCC builtin didn't pan out... (sed -e 's/aligned_alloc/__builtin_aligned_alloc/' -i libelf/elf32_updatefile.c)
#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/elfutils-0.176-no-aligned_alloc.patch
# NOTE: What we can do, is patch in a shim that uses posix_memalign instead...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/elfutils-0.176-aligned_alloc-compat-shim.patch
#sed -i -e '/^lib_LIBRARIES/s:=.*:=:' -e '/^%.os/s:%.o$::' lib{asm,dw,elf}/Makefile.in
sed -i 's:-Werror::' configure.ac configure */Makefile.in config/eu.am
# aligned_alloc was standardized in C11, and we know our compilers are recent enough to accept that (in fact, that's their default std value for C)
sed -i 's:gnu99:gnu11:' configure.ac configure */Makefile.in config/eu.am
# Disable FORTIFY for K3 builds
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/elfutils-0.176-no-fortify.patch
fi
# Avoid PIC/TEXTREL issue w/ LTO... (NOTE: Not enough, symbol versioning issues or even weirder crap)
#for my_dir in libasm backends libelf libdw src ; do
#	sed -e 's/$(LINK) -shared/$(LINK) -fPIC -shared/' -i ${my_dir}/Makefile.in
#	sed -e 's/$(LINK) -shared/$(LINK) -fPIC -shared/' -i ${my_dir}/Makefile.am
#done
# FIXME: So, do without LTO... (Linaro GCC 5.2 2015.11-2 & binutils 2.26)
# NOTE: Currently (Linaro GCC 7.2 2017.11, binutil 2.30, elfutiils 0.170), there's also a symbol versionning/binutils related issue.
#       We don't care about ABI compatibility, so we could disable symbol versioning for now... Which indeed helps on that front.
#       But since there's still other weird LTO issues left, so just continue ditching LTO.
if [[ "${CFLAGS}" != "${NOLTO_CFLAGS}" ]] ; then
	temp_nolto="true"
	export CFLAGS="${NOLTO_CFLAGS}"
fi
autoreconf -fi
# Pull our own zlib to avoid symbol versioning issues......
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
env LIBS="-lz" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-thread-safety --program-prefix="eu-" --with-zlib --without-bzlib --without-lzma --disable-valgrind --disable-debuginfod
make ${JOBSFLAGS} V=1
make install V=1
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

# ltrace apprently needs a semi-recent ptrace implementation. Kernel appears to be too old for that on legacy devices.
# XXX: Debian discontinued Alioth. Migration to Salsa is NOT automatic. So, basically, I have no idea if/when this repo will ever show up again. Yay?
#      In the meantime, Debian provided archives of old repos on https://alioth-archive.debian.org, so I rolled a tarball from that + the latest Debian patchset.
if [[ "${KINDLE_TC}" != "K3" ]] ; then
	echo "* Building ltrace . . ."
	echo ""
	cd ..
	rm -rf ltrace
	# NOTE: Use Debian's HTTPS transport because it's less flakey that their git one. It doesn't support shallow clones, though.
	#       https://anonscm.debian.org/git/collab-maint/ltrace.git ?
	#until git clone https://alioth.debian.org/anonscm/git/collab-maint/ltrace.git ; do
	#	rm -rf ltrace
	#	sleep 15
	#done
	wget http://files.ak-team.com/niluje/gentoo/ltrace-0.7.3.6_p20150612.tar.xz -O ltrace-0.7.3.6_p20150612.tar.xz
	tar xvJf ltrace-0.7.3.6_p20150612.tar.xz
	cd ltrace
	update_title_info
	./autogen.sh
	# Regen the syscall list...
	cd sysdeps/linux-gnu
	if [[ "${KINDLE_TC}" == "PW2" ]] ; then
		./mksyscallent < ${HOME}/Kindle/SourceCode_Packages/5.9.5.1/gplrelease/linux/arch/arm/include/asm/unistd.h > arm/syscallent.h
		./mksignalent < ${HOME}/Kindle/SourceCode_Packages/5.9.5.1/gplrelease/linux/arch/arm/include/asm/signal.h > arm/signalent.h
	elif [[ "${KINDLE_TC}" == "K5" ]] ; then
		./mksyscallent < ${HOME}/Kindle/SourceCode_Packages/5.4.4.2/gplrelease/linux/arch/arm/include/asm/unistd.h > arm/syscallent.h
		./mksignalent < ${HOME}/Kindle/SourceCode_Packages/5.4.4.2/gplrelease/linux/arch/arm/include/asm/signal.h > arm/signalent.h
	elif [[ "${KINDLE_TC}" == "KOBO" ]] ; then
		./mksyscallent < ${HOME}/Kindle/SourceCode_Packages/Kobo-H2O2R2/arch/arm/include/asm/unistd.h > arm/syscallent.h
		./mksignalent < ${HOME}/Kindle/SourceCode_Packages/Kobo-H2O2R2/arch/arm/include/asm/signal.h > arm/signalent.h
	else
		./mksyscallent < ${HOME}/Kindle/SourceCode_Packages/3.4.2/gplrelease/linux-2.6.26/include/asm-arm/unistd.h > arm/syscallent.h
		./mksignalent < ${HOME}/Kindle/SourceCode_Packages/3.4.2/gplrelease/linux-2.6.26/include/asm-arm/signal.h > arm/signalent.h
	fi
	cd ../..

	# Setup our rpath...
	export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
	env LIBS="-ldw -lelf -lz" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --sysconfdir=${DEVICE_USERSTORE}/usbnet/etc --datarootdir=${DEVICE_USERSTORE}/usbnet/etc --disable-werror --disable-debug --without-libunwind --with-elfutils
	make ${JOBSFLAGS}
	make install
	export LDFLAGS="${BASE_LDFLAGS}"
	${CROSS_TC}-strip --strip-unneeded ../bin/ltrace
	cp ../bin/ltrace ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/ltrace
	# Don't forget the config files...
	for my_file in libc.so.conf libm.so.conf libacl.so.conf syscalls.conf libpthread.so.conf libpthread.so-types.conf libc.so-types.conf ; do
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
tar -I pigz -xvf /usr/portage/distfiles/file-5.38.tar.gz
cd file-5.38
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
# NOTE: We can't do much regarding Kobo's broken widechar support. Building with --disable-utf8 is not a viable solution.
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-libseccomp --enable-fsect-man5 --disable-bzlib --disable-xzlib --with-zlib --datarootdir="${DEVICE_USERSTORE}/usbnet/share"
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
tar -I pigz -xvf /usr/portage/distfiles/nano-4.8.tar.gz
cd nano-4.8
update_title_info
# NOTE: On Kindles, we hit a number of dumb collation issues with regexes needed for syntax highlighting on some locales (notably en_GB...) on some FW versions, so enforce en_US...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/nano-kindle-locale-hack.patch
# Look for nanorc in usbnet/etc...
sed -e "s#SYSCONFDIR \"/nanorc\"#\"${DEVICE_USERSTORE}/usbnet/etc/nanorc\"#" -i src/rcfile.c
# Store configs & state files in usbnet/etc
sed -e "s#getenv(\"HOME\")#\"${DEVICE_USERSTORE}/usbnet/etc\"#" -i src/utils.c
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
export ac_cv_header_magic_h=yes
export ac_cv_lib_magic_magic_open=yes
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-color --enable-multibuffer --enable-nanorc --enable-libmagic --enable-speller --disable-justify --disable-debug --enable-nls --enable-utf8 --disable-tiny --without-slang
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
cp doc/sample.nanorc ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/nanorc
for my_opt in constantshow historylog linenumbers matchbrackets positionlog smarthome softwrap wordbounds ; do
	sed -e "s/^# set ${my_opt}/set ${my_opt}/" -i ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/nanorc
done
sed -e "s%^# include \"${TC_BUILD_DIR}/share/nano/\*\.nanorc\"%include \"${DEVICE_USERSTORE}/usbnet/etc/nano/\*\.nanorc\"%" -i ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/nanorc
mkdir -p ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/nano
cp -f ../share/nano/*.nanorc ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/nano/

## ZSH itself
echo "* Building ZSH . . ."
echo ""
ZSH_VER="5.7.1"
cd ..
tar -xvJf /usr/portage/distfiles/zsh-${ZSH_VER}.tar.xz
cd zsh-${ZSH_VER}
update_title_info
# Gentoo patches
patch -p1 < /usr/portage/app-shells/zsh/files/zsh-5.7.1-ncurses_colors.patch
ln -s Doc man1
mv Doc/zshall.1 Doc/zshall.1.soelim
soelim Doc/zshall.1.soelim > Doc/zshall.1
# LTO makefile compat...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/zsh-fix-Makefile-for-lto.patch
# Store configs in usbnet/etc/zsh
sed -e "s#VARARR(char, buf, strlen(h) + strlen(s) + 2);#VARARR(char, buf, strlen(\"${DEVICE_USERSTORE}/usbnet/etc/zsh\") + strlen(s) + 2);#" -i Src/init.c
sed -e "s#sprintf(buf, \"%s/%s\", h, s);#sprintf(buf, \"${DEVICE_USERSTORE}/usbnet/etc/zsh/%s\", s);#" -i Src/init.c
# Needed to find the ncurses (narrowc) headers for tinfo
export CPPFLAGS="${BASE_CPPFLAGS} -I${TC_BUILD_DIR}/include/ncurses"
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
# NOTE: Much like nano, I don't think there's anything sane we can do to workaround Kobo's broken widechar support... (I haven't tried building with --disable-multibyte, but I'd wager it's as unusable as nano with --disable-utf8)
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-etcdir="${DEVICE_USERSTORE}/usbnet/etc/zsh" --enable-runhelpdir="${DEVICE_USERSTORE}/usbnet/share/zsh/help" --enable-fndir="${DEVICE_USERSTORE}/usbnet/share/zsh/functions" --enable-site-fndir="${DEVICE_USERSTORE}/usbnet/share/zsh/site-functions" --enable-scriptdir="${DEVICE_USERSTORE}/usbnet/share/zsh/scripts" --enable-site-scriptdir="${DEVICE_USERSTORE}/usbnet/share/zsh/site-scripts" --enable-function-subdirs --with-tcsetpgrp --with-term-lib="tinfow ncursesw" --disable-maildir-support --enable-pcre --disable-cap --enable-multibyte --disable-gdbm
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
export CPPFLAGS="${BASE_CPPFLAGS}"
# Okay, now take a deep breath...
cp ../bin/zsh ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/zsh
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/zsh
mkdir -p ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/zsh
cp -a ../lib/zsh/${ZSH_VER}/zsh/. ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/zsh
find ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/zsh -name '*.so*' -type f -exec ${CROSS_TC}-strip --strip-unneeded {} +
# Now for the functions & co...
mkdir -p ${BASE_HACKDIR}/USBNetwork/src/usbnet/share/zsh
cp -aL ${DEVICE_USERSTORE}/usbnet/share/zsh/. ${BASE_HACKDIR}/USBNetwork/src/usbnet/share/zsh
# Now, get the latest dircolors-solarized db, because the default one is eye-poppingly awful
rm -rf dircolors-solarized
until git clone --depth 1 https://github.com/seebi/dircolors-solarized.git ; do
	rm -rf dircolors-solarized
	sleep 15
done
mkdir -p ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/zsh
cp -f dircolors-solarized/dircolors.* ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/zsh/
# Then, take care of zsh-syntax-highlighting
rm -rf zsh-syntax-highlighting
until git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git ; do
	rm -rf zsh-syntax-highlighting
	sleep 15
done
make -C zsh-syntax-highlighting install DESTDIR="${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/zsh" PREFIX="/usr"
# And finally, our own zshrc, zshenv & zlogin
cp ${SVN_ROOT}/Configs/trunk/Kindle/Misc/zshrc ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/zsh/zshrc
cp ${SVN_ROOT}/Configs/trunk/Kindle/Misc/zshenv ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/zsh/zshenv
cp ${SVN_ROOT}/Configs/trunk/Kindle/Misc/zlogin ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/zsh/zlogin

## XZ (for packaging purposes only, to drop below MR's 20MB attachment limit... -_-". On the plus side, it's also twice as fast as bzip2 to uncompress, which is neat).
echo "* Building XZ-Utils . . ."
echo ""
cd ..
tar -I pigz -xvf /usr/portage/distfiles/xz-5.2.4.tar.gz
cd xz-5.2.4
update_title_info
export CFLAGS="${RICE_CFLAGS}"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-nls --disable-threads --enable-static --disable-shared --disable-{lzmadec,lzmainfo,lzma-links,scripts}
make ${JOBSFLAGS}
make install
export CFLAGS="${BASE_CFLAGS}"
# And send that to our common pool of binaries...
cp ../bin/xzdec ${BASE_HACKDIR}/Common/bin/xzdec
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Common/bin/xzdec

## AG (because it's awesome)
echo "* Building the silver searcher . . ."
echo ""
cd ..
rm -rf the_silver_searcher
until git clone --depth 1 https://github.com/ggreer/the_silver_searcher.git the_silver_searcher ; do
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
LIBEVENT_SOVER="7.0.0"
LIBEVENT_LIBSUF="-2.1"
tar -I pigz -xvf /usr/portage/distfiles/libevent-2.1.11.tar.gz
cd libevent-2.1.11-stable
update_title_info
autoreconf -fi
libtoolize
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-samples --disable-debug-mode --disable-malloc-replacement --disable-libevent-regress --enable-openssl --disable-static --enable-thread-support
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
tar -I pigz -xvf /usr/portage/distfiles/tmux-3.0a.tar.gz
cd tmux-3.0a
update_title_info
patch -p1 < /usr/portage/app-misc/tmux/files/tmux-2.4-flags.patch
# As usual, locales are being a bitch... Try to enforce a sane UTF-8 locale, and relax checks to not abort on failure...
# NOTE: This is mainly an issue on Kobo, where both locales and widechar handling is just plain broken.
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/tmux-2.8-kobo-locale-hack.patch
autoreconf -fi
# Needed to find the ncurses (narrowc) headers
export CPPFLAGS="${BASE_CPPFLAGS} -I${TC_BUILD_DIR}/include/ncurses"
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --sysconfdir=${DEVICE_USERSTORE}/usbnet/etc --disable-debug --disable-utempter
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
GDB_VERSION="9.1"
cd ..
tar -xvJf /usr/portage/distfiles/gdb-${GDB_VERSION}.tar.xz
cd gdb-${GDB_VERSION}
update_title_info
#tar xvJf /usr/portage/distfiles/gdb-8.3-patches-1.tar.xz
for patchfile in patch/*.patch ; do
	[[ -f "${patchfile}" ]] && patch -p1 < ${patchfile}
done
patch -p1 < /usr/portage/sys-devel/gdb/files/gdb-8.3.1-verbose-build.patch
# NOTE: Workaround weird-ass error: 'log2' is not a member of 'std' when using the K3/K5/PW2 TC...
if [[ "${KINDLE_TC}" == "K3" ]] || [[ "${KINDLE_TC}" == "K5" ]] || [[ "${KINDLE_TC}" == "PW2" ]] ; then
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/gdb-9.1-k3-log2-fix.patch
fi
# GDB >= 9.1 requires being built out of tree
mkdir -p ../gdb-${GDB_VERSION}-build
cd ../gdb-${GDB_VERSION}-build
# Setup our rpath... (And link against the STL statically)
export LDFLAGS="${BASE_LDFLAGS} -static-libstdc++ -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib -Wl,-rpath=${DEVICE_USERSTORE}/python3/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib"
# Some bits and bobs appear to be ignoring CPPFLAGS...
export CFLAGS="${BASE_CPPFLAGS} ${BASE_CFLAGS}"
export CXXFLAGS="${BASE_CPPFLAGS} ${BASE_CFLAGS}"
# NOTE: source highlight is incompatible with -static-libstdc++
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	# Avoid pulling in open64_2 (LFS)
	${TC_BUILD_DIR}/gdb-${GDB_VERSION}/configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-werror --disable-{binutils,etc,gas,gold,gprof,ld} --enable-gdbserver --disable-64-bit-bfd --disable-install-libbfd --disable-install-libiberty --without-guile --disable-readline --with-system-readline --without-zlib --with-system-zlib --with-expat --without-lzma --enable-nls --without-python --disable-largefile --disable-source-highlight
else
	${TC_BUILD_DIR}/gdb-${GDB_VERSION}/configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-werror --disable-{binutils,etc,gas,gold,gprof,ld} --enable-gdbserver --enable-64-bit-bfd --disable-install-libbfd --disable-install-libiberty --without-guile --disable-readline --with-system-readline --without-zlib --with-system-zlib --with-expat --without-lzma --enable-nls --without-python --disable-source-highlight
fi
make ${JOBSFLAGS} V=1
make install
export LDFLAGS="${BASE_LDFLAGS}"
export CFLAGS="${BASE_CFLAGS}"
export CXXFLAGS="${BASE_CFLAGS}"
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
# NOTE: Use a GH mirror, because there's over 300MB of sources, and the sourceware master isn't always in tip top shape...
#until git clone -b binutils-2_34-branch --single-branch --depth 1 git://sourceware.org/git/binutils-gdb.git binutils ; do
until git clone -b binutils-2_34-branch --single-branch --depth 1 https://github.com/bminor/binutils-gdb.git binutils ; do
	rm -rf binutils
	sleep 15
done
cd binutils
update_title_info
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib -Wl,-rpath=${DEVICE_USERSTORE}/python3/lib -Wl,-rpath=${DEVICE_USERSTORE}/python/lib"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=no --enable-static=yes --disable-nls --with-system-zlib --enable-obsolete --enable-threads --enable-install-libiberty --disable-werror --disable-{gdb,libdecnumber,readline,sim} --without-stage1-ldflags
make ${JOBSFLAGS}
${CROSS_TC}-strip --strip-unneeded binutils/objdump
cp binutils/objdump ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/objdump
${CROSS_TC}-strip --strip-unneeded gprof/gprof
cp gprof/gprof ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/gprof
# NOTE: On the K3, we can't use the elfutils copy of readelf, so use this one ;).
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	${CROSS_TC}-strip --strip-unneeded binutils/readelf
	cp binutils/readelf ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/readelf
fi
export LDFLAGS="${BASE_LDFLAGS}"

## cURL
CURL_SOVER="4.6.0"
echo "* Building cURL . . ."
echo ""
cd ..
tar -xvJf /usr/portage/distfiles/curl-7.68.0.tar.xz
cd curl-7.68.0
update_title_info
# Gentoo patches
patch -p1 < /usr/portage/net-misc/curl/files/curl-7.30.0-prefix.patch
patch -p1 < /usr/portage/net-misc/curl/files/curl-respect-cflags-3.patch
patch -p1 < /usr/portage/net-misc/curl/files/curl-fix-gnutls-nettle.patch
sed -i '/LD_LIBRARY_PATH=/d' configure.ac
sed -i '/CURL_MAC_CFLAGS/d' configure.ac
autoreconf -fi
# We'll need a ca-bundle for HTTPS
make ca-bundle
cp lib/ca-bundle.crt ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/ca-bundle.crt
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
# NOTE: esni isn't in mainline OpenSSL (https://bugs.gentoo.org/699648)
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=no --without-gnutls --without-mbedtls --without-nss --without-polarssl --without-winssl --with-ca-fallback --with-ca-bundle=${DEVICE_USERSTORE}/usbnet/lib/ca-bundle.crt --with-ssl --with-ca-path=/etc/ssl/certs --disable-alt-svc --enable-crypto-auth --enable-dict --disable-esni --enable-file --enable-ftp --enable-gopher --enable-http --enable-imap --disable-ldap --disable-ldaps --disable-ntlm-wb --enable-pop3 --enable-rt --enable-rtsp --disable-smb --without-libssh2 --enable-smtp --enable-telnet -enable-tftp --enable-tls-srp --disable-ares --enable-cookies --enable-dateparse --enable-dnsshuffle --enable-doh --enable-hidden-symbols --enable-http-auth --disable-ipv6 --enable-largefile --without-libpsl --enable-manual --enable-mime --enable-netrc --enable-progress-meter --enable-proxy --disable-sspi --enable-threaded-resolver --enable-pthreads --disable-versioned-symbols --without-amissl --without-bearssl --without-cyassl --without-darwinssl --without-fish-functions-dir --without-libidn2 --without-gssapi --without-libmetalink --without-nghttp2 --without-librtmp --without-brotli --without-schannel --without-secure-transport --without-spnego --without-winidn --without-wolfssl --with-zlib
make ${JOBSFLAGS} V=1
make install
${CROSS_TC}-strip --strip-unneeded ../bin/curl
cp ../bin/curl ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/curl
cp ../lib/libcurl.so.${CURL_SOVER} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libcurl.so.${CURL_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libcurl.so.${CURL_SOVER%%.*}
export LDFLAGS="${BASE_LDFLAGS}"

## evtest
echo "* Building evtest . . ."
echo ""
cd ..
rm -rf evtest
until git clone --depth 1 https://gitlab.freedesktop.org/libevdev/evtest.git evtest ; do
	rm -rf evtest
	sleep 15
done
cd evtest
update_title_info
autoreconf -fi
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=no
make ${JOBSFLAGS}
${CROSS_TC}-strip --strip-unneeded evtest
cp evtest ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/evtest

## libevdev for evemu
LIBEVDEV_SOVER="2.3.0"
echo "* Building libevdev . . ."
echo ""
cd ..
rm -rf libevdev
until git clone --depth 1 https://gitlab.freedesktop.org/libevdev/libevdev.git libevdev ; do
	rm -rf libevdev
	sleep 15
done
cd libevdev
update_title_info
autoreconf -fi
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=no
make ${JOBSFLAGS}
make install
cp ../lib/libevdev.so.${LIBEVDEV_SOVER} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libevdev.so.${LIBEVDEV_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libevdev.so.${LIBEVDEV_SOVER%%.*}

## evemu
EVEMU_SOVER="3.0.4"
echo "* Building evemu . . ."
echo ""
cd ..
rm -rf evemu
until git clone --depth 1 https://gitlab.freedesktop.org/libevdev/evemu.git evemu ; do
	rm -rf evemu
	sleep 15
done
cd evemu
update_title_info
autoreconf -fi
# Setup our rpath...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=${DEVICE_USERSTORE}/usbnet/lib"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=no --disable-python-bindings --disable-tests
make ${JOBSFLAGS}
make install
for my_bin in describe device event play record ; do
	${CROSS_TC}-strip --strip-unneeded ../bin/evemu-${my_bin}
	cp ../bin/evemu-${my_bin} ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/evemu-${my_bin}
done
cp ../lib/libevemu.so.${EVEMU_SOVER} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libevemu.so.${EVEMU_SOVER%%.*}
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/libevemu.so.${EVEMU_SOVER%%.*}
export LDFLAGS="${BASE_LDFLAGS}"

## static cURL (7.65.1)
#
#patch -p1 < /usr/portage/net-misc/curl/files/curl-7.30.0-prefix.patch
#patch -p1 < /usr/portage/net-misc/curl/files/curl-respect-cflags-3.patch
#patch -p1 < /usr/portage/net-misc/curl/files/curl-fix-gnutls-nettle.patch
#sed -i '/LD_LIBRARY_PATH=/d' configure.ac
#sed -i '/CURL_MAC_CFLAGS/d' configure.ac
#
#autoreconf -fi
#
#make ca-bundle
#
#env LIBS="-ldl" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=no --enable-static=yes --without-gnutls --without-mbedtls --without-nss --without-polarssl --without-ssl --without-winssl --with-ca-fallback --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt --with-ssl --with-ca-path=/etc/ssl/certs --disable-alt-svc --enable-crypto-auth --enable-dict --enable-file --enable-ftp --enable-gopher --enable-http --enable-imap --disable-ldap --disable-ldaps --disable-ntlm-wb --enable-pop3 --enable-rt --enable-rtsp --disable-smb --without-libssh2 --enable-smtp --enable-telnet -enable-tftp --enable-tls-srp --disable-ares --enable-cookies --enable-hidden-symbols --disable-ipv6 --enable-largefile --without-libpsl --enable-manual --enable-proxy --disable-sspi --enable-threaded-resolver --enable-pthreads --disable-versioned-symbols --without-amissl --without-cyassl --without-darwinssl --without-fish-functions-dir --without-libidn2 --without-gssapi --without-libmetalink --without-nghttp2 --without-librtmp --without-brotli --without-schannel --without-secure-transport --without-spnego --without-winidn --without-wolfssl --with-zlib
#
#make ${JOBSFLAGS} V=1 LIBCURL_LIBS="-l:libssl.a -l:libcrypto.a -l:libz.a -ldl -lrt"
#
#${CROSS_TC}-strip --strip-unneeded src/curl
#
# NOTE (OLD): Even with shared=no static=yes, I ended up with NEEDED entries for shared libraries for everything except OpenSSL (because I don't *have* a shared library for it), and it avoided the PIC issues entirely, without needing to build OpenSSL PIC...
# XXX: Try this on every project that had a PIC issue?
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
