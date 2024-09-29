#!/bin/bash -ex
#
# Kindle cross toolchain & lib/bin/util build script
#
# $Id: x-compile.sh 19557 2024-09-29 19:12:13Z NiLuJe $
#
# kate: syntax bash;
#
##

## Mostly needed by the x-compile-packages stuff, since I store all that in an SVN repo.
SVN_ROOT="${HOME}/SVN"
## Remember where we are... (c.f., https://stackoverflow.com/questions/9901210/bash-source0-equivalent-in-zsh)
SCRIPT_NAME="${BASH_SOURCE[0]-${(%):-%x}}"
SCRIPTS_BASE_DIR="$(readlink -f "${SCRIPT_NAME%/*}")"

## Version comparison (req. coreutils 7) [cf. https://stackoverflow.com/questions/4023830]
is_ver_gte()
{
	[ "${1}" = "$(echo -e "${1}\n${2}" | sort -V | tail -n1)" ]
}

## Choose your TC!
case ${1} in
	kindle | k2 | K2 | k3 | K3 )
		KINDLE_TC="K3"
	;;
	kindle5 | k4 | K4 | k5 | K5 )
		KINDLE_TC="K5"
	;;
	kindlepw2 | pw2 | PW2 )
		KINDLE_TC="PW2"
	;;
	kindlehf | khf | KHF )
		KINDLE_TC="KHF"
	;;
	cervantes )
		KINDLE_TC="CERVANTES"
	;;
	kobo | Kobo | KOBO )
		KINDLE_TC="KOBO"
	;;
	nickel | Nickel | NICKEL )
		KINDLE_TC="NICKEL"
	;;
	kobov4 | kobomk7 | mk7 | Mk7 | MK7 )
		KINDLE_TC="KOBOV4"
	;;
	kobov5 | kobomk8 | mk8 | Mk8 | MK8 )
		KINDLE_TC="KOBOV5"
	;;
	remarkable | reMarkable | Remarkable )
		KINDLE_TC="REMARKABLE"
	;;
	pocketbook | pb | PB )
		KINDLE_TC="PB"
	;;
	bookeen | cy | CY )
		KINDLE_TC="CY"
	;;
	# Or build them?
	tc )
		# NOTE: This is handled by a dedicted script shard to avoid cluttering the koxtoolchain repo.
		#       It predates koxtoolchain, and basically does the exact same thing as koxtoolchain's gen-tc.sh, but worse ;).
		. "${SCRIPTS_BASE_DIR}/x-compile-toolchains.sh"
		# And exit happy now :)
		exit 0
	;;
	* )
		echo "You must choose a ToolChain! (k3, k5, pw2, khf, kobo, kobov4, kobov5, nickel, remarkable, pocketbook or bookeen)"
		echo "Or, alternatively, ask to build them (tc)"
		exit 1
	;;
esac

## Setup our env to use the right TC
echo "* Setting environment up . . ."
echo ""

## Setup parallellization... Shamelessly stolen from crosstool-ng ;).
AUTO_JOBS=$(($(getconf _NPROCESSORS_ONLN 2> /dev/null || echo 0) + 1))

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
		## NOTE: Shitty one-liner to check binaries: for file in $(find Configs/trunk/Kindle/Hacks -type f) ; do ; file "${file}" | grep -q "ELF 32-bit" && echo "${file}" && readelf -V "${file}" | grep "Name: GLIBC_" | awk '{print $3}' | sort -u ; done


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

		# We always rely on the native pkg-config, with custom search paths
		BASE_PKG_CONFIG="pkg-config"
		export PKG_CONFIG="${BASE_PKG_CONFIG}"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_PATH=""
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

		# We always rely on the native pkg-config, with custom search paths
		BASE_PKG_CONFIG="pkg-config"
		export PKG_CONFIG="${BASE_PKG_CONFIG}"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_PATH=""
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

		# We always rely on the native pkg-config, with custom search paths
		BASE_PKG_CONFIG="pkg-config"
		export PKG_CONFIG="${BASE_PKG_CONFIG}"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_PATH=""
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"

		## CMake is hell.
		export CMAKE="cmake -DCMAKE_TOOLCHAIN_FILE=${SCRIPTS_BASE_DIR}/CMakeCross.txt -DCMAKE_INSTALL_PREFIX=${TC_BUILD_DIR}"

		DEVICE_USERSTORE="/mnt/us"
	;;
	KHF )
		ARCH_FLAGS="-march=armv7-a -mtune=cortex-a7 -mfpu=neon -mfloat-abi=hard -mthumb"
		CROSS_TC="arm-kindlehf-linux-gnueabihf"
		TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"

		# Export it for our CMakeCross TC file
		export CROSS_TC
		export TC_BUILD_DIR

		export CROSS_PREFIX="${CROSS_TC}-"
		export PATH="${HOME}/x-tools/${CROSS_TC}/bin:${PATH}"

		## NOTE: The new libstdc++ ABI might cause some issues if not handled on GCC >= 5.1 (cf. https://gcc.gnu.org/onlinedocs/libstdc++/manual/using_dual_abi.html), so, disable it...
		##       Apparently, the vendor TC is still (at least in part) based on GCC 4.9.1, so, keep doing this...
		if is_ver_gte "$(${CROSS_TC}-gcc -dumpversion)" "5.1" ; then
			LEGACY_GLIBCXX_ABI="-D_GLIBCXX_USE_CXX11_ABI=0"
			## NOTE: Like the FORTIFY stuff, this should *really* be in CPPFLAGS, but we have to contend with broken buildsystems that don't honor CPPFLAGS... So we go with the more ubiquitous CFLAGS instead ;/.
		fi

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

		BASE_HACKDIR="${SVN_ROOT}/Configs/trunk/Kindle/PW2_Hacks"

		# We always rely on the native pkg-config, with custom search paths
		BASE_PKG_CONFIG="pkg-config"
		export PKG_CONFIG="${BASE_PKG_CONFIG}"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_PATH=""
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"

		## CMake is hell.
		export CMAKE="cmake -DCMAKE_TOOLCHAIN_FILE=${SCRIPTS_BASE_DIR}/CMakeCross.txt -DCMAKE_INSTALL_PREFIX=${TC_BUILD_DIR}"

		DEVICE_USERSTORE="/mnt/us"
	;;
	KOBO | NICKEL | KOBOV4 | KOBOV5 | CERVANTES )
		case ${KINDLE_TC} in
			KOBOV5 )
				# NOTE: We actually build the TC with -mcpu=cortex-a7, because cortex-a53 would switch to armv8-a, whereas our targets still use an armv7 software stack...
				#       (The choice of using the A7 over the A9 stems both from the sunxi socs running on A7,
				#       and the fact the A9 had an out-of-order pipeline, while both the A7 & A53 are in-order).
				ARCH_FLAGS="-march=armv7-a -mtune=cortex-a53 -mfpu=neon -mfloat-abi=hard -mthumb"
			;;
			KOBOV4 )
				# NOTE: The sunxi B300 SoCs *technically* run on A7...
				ARCH_FLAGS="-march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard -mthumb"
				## NOTE: The only difference between FSF GCC (https://gcc.gnu.org/git/?p=gcc.git;a=shortlog;h=refs/heads/releases/gcc-10) and Arm's branch (https://gcc.gnu.org/git/?p=gcc.git;a=shortlog;h=refs/vendors/ARM/heads/arm-10) is
				##       https://gcc.gnu.org/git?p=gcc.git;a=commit;h=3b91aab15443ee150b2ba314a4b26645ce8d713b (e.g., https://gcc.gnu.org/bugzilla/show_bug.cgi?id=80155).
				##       If we wanted to mimic that, since we actually build against FSF GCC, we could disable code-hoisting here. Doesn't really seem to help us in practice though, so, eh.
				#ARCH_FLAGS="${ARCH_FLAGS} -fno-code-hoisting"
				## NOTE: As for defaulting to Thumb mode, that's consistent with Linaro's default armv7 configs.
			;;
			CERVANTES )
				# NOTE: Not quite sure why this is using vfpv3 with a TC built with -mcpu=cortex-a8...
				#       But I'm not the one that came up with it, so, follow what's done in KOReader (which, technically, even downgrades -mtune to generic-armv7-a).
				ARCH_FLAGS="-march=armv7-a -mtune=cortex-a8 -mfpu=vfpv3 -mfloat-abi=softfp -mthumb"
			;;
			* )
				ARCH_FLAGS="-march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -mthumb"
			;;
		esac

		case ${KINDLE_TC} in
			KOBO )
				CROSS_TC="arm-kobo-linux-gnueabihf"
				TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"
			;;
			NICKEL )
				CROSS_TC="arm-nickel-linux-gnueabihf"
				# NOTE: We use a directory tree slightly more in line w/ ct-ng here...
				if [[ -n "${_XTC_WD}" ]] ; then
					TC_BUILD_DIR="${_XTC_WD}/${CROSS_TC}/${CROSS_TC}/sysroot/usr"
				else
					TC_BUILD_DIR="${HOME}/Kobo/CrossTool/Build_${KINDLE_TC}/${CROSS_TC}/${CROSS_TC}/sysroot/usr"
				fi
			;;
			KOBOV4 )
				CROSS_TC="arm-kobov4-linux-gnueabihf"
				TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"
			;;
			KOBOV5 )
				CROSS_TC="arm-kobov5-linux-gnueabihf"
				TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"
			;;
			CERVANTES )
				CROSS_TC="arm-cervantes-linux-gnueabi"
				TC_BUILD_DIR="${HOME}/Kindle/CrossTool/Build_${KINDLE_TC}"
			;;
		esac

		# Export it for our CMakeCross TC file
		export CROSS_TC
		export TC_BUILD_DIR

		export CROSS_PREFIX="${CROSS_TC}-"
		if [[ -n "${_XTC_DIR}" ]] ; then
			export PATH="${_XTC_DIR}/${CROSS_TC}/bin:${PATH}"
		else
			export PATH="${HOME}/x-tools/${CROSS_TC}/bin:${PATH}"
		fi

		case ${KINDLE_TC} in
			KOBOV5 )
				## Vendor TC is using GCC 11.3, so we don't have to jump through any shitty hoops.
				;;
			*)
				## NOTE: The new libstdc++ ABI might cause some issues if not handled on GCC >= 5.1 (cf. https://gcc.gnu.org/onlinedocs/libstdc++/manual/using_dual_abi.html), so, disable it...
				if is_ver_gte "$(${CROSS_TC}-gcc -dumpversion)" "5.1" ; then
					LEGACY_GLIBCXX_ABI="-D_GLIBCXX_USE_CXX11_ABI=0"
					## NOTE: Like the FORTIFY stuff, this should *really* be in CPPFLAGS, but we have to contend with broken buildsystems that don't honor CPPFLAGS... So we go with the more ubiquitous CFLAGS instead ;/.
				fi
			;;
		esac

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
		if [[ "${KINDLE_TC}" == "NICKEL" ]] ; then
			# GCC 4.9 was terrible at LTO
			BASE_CFLAGS="${NOLTO_CFLAGS}"
		fi
		export CFLAGS="${BASE_CFLAGS}"
		export CXXFLAGS="${BASE_CFLAGS}"
		# NOTE: Use -isystem instead of -I to make sure GMP doesn't do crazy stuff... (FIXME: -idirafter sounds more correct for our use-case, though...)
		if [[ "${KINDLE_TC}" == "NICKEL" ]] ; then
			# That's a standard searchpath, no need to enforce it
			BASE_CPPFLAGS=""
		else
			BASE_CPPFLAGS="-isystem${TC_BUILD_DIR}/include"
		fi
		export CPPFLAGS="${BASE_CPPFLAGS}"
		if [[ "${KINDLE_TC}" == "NICKEL" ]] ; then
			# That's a standard searchpath, no need to enforce it
			BASE_LDFLAGS="-Wl,-O1 -Wl,--as-needed"
		else
			BASE_LDFLAGS="-L${TC_BUILD_DIR}/lib -Wl,-O1 -Wl,--as-needed"
		fi
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

		# We always rely on the native pkg-config, with custom search paths
		BASE_PKG_CONFIG="pkg-config"
		export PKG_CONFIG="${BASE_PKG_CONFIG}"
		## NOTE: For Nickel, we want to pickup the sysroot, too, because this is where we chucked Qt...
		if [[ "${KINDLE_TC}" == "NICKEL" ]] ; then
			if [[ -n "${_XTC_DIR}" ]] ; then
				BASE_SYSROOT="${_XTC_DIR}/${CROSS_TC}/${CROSS_TC}/sysroot"
			else
				BASE_SYSROOT="${HOME}/x-tools/${CROSS_TC}/${CROSS_TC}/sysroot"
			fi
			BASE_SYSROOT_PKG_CONFIG_LIBDIR="${BASE_SYSROOT}/usr/lib/pkgconfig"
			BASE_PKG_CONFIG_LIBDIR="${BASE_SYSROOT_PKG_CONFIG_LIBDIR}:${TC_BUILD_DIR}/lib/pkgconfig"
			# And since we'll have potentially two different sources of .pc files, and some of them may have been been baked with a no-longer viable build prefix, letting pkg-config compute the prefix based on the .pc's location sounds like a Great Idea!
			# c.f., https://github.com/pgaskin/kobo-plugin-experiments/commit/7020977c611c9301c07ef1cb24656fd09acef77a
			# NOTE: We bypass the TC's pkg-config wrapper because we want to use multiple searchpaths, no fixed sysroot, and --define-prefix ;).
			BASE_PKG_CONFIG="pkg-config --define-prefix"
			export PKG_CONFIG="${BASE_PKG_CONFIG}"

			# Let pkg-config strip the right redundant system paths
			export PKG_CONFIG_SYSTEM_INCLUDE_PATH="${BASE_SYSROOT}/usr/include"
			export PKG_CONFIG_SYSTEM_LIBRARY_PATH="${BASE_SYSROOT}/usr/lib:${BASE_SYSROOT}/lib"
		else
			BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		fi
		export PKG_CONFIG_PATH=""
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

		# We always rely on the native pkg-config, with custom search paths
		BASE_PKG_CONFIG="pkg-config"
		export PKG_CONFIG="${BASE_PKG_CONFIG}"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_PATH=""
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"

		## CMake is hell.
		export CMAKE="cmake -DCMAKE_TOOLCHAIN_FILE=${SCRIPTS_BASE_DIR}/CMakeCross.txt -DCMAKE_INSTALL_PREFIX=${TC_BUILD_DIR}"

		DEVICE_USERSTORE="/home/root"
	;;
	PB )
		# NOTE: The TC itself is built in ARM mode, otherwise glibc 2.9 doesn't build (fails with a "r15 not allowed here" assembler error on csu/libc-start.o during the early multilib start-files step).
		#       AFAICT, the official SDK doesn't make a specific choice on that front (i.e., it passes neither -marm not -mthumb. That usually means ARM)...
		# NOTE: This is probably related to our choice of -mcpu target, as the kindle TC builds just fine on the same glibc version... for armv6j ;).
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

		# We always rely on the native pkg-config, with custom search paths
		BASE_PKG_CONFIG="pkg-config"
		export PKG_CONFIG="${BASE_PKG_CONFIG}"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_PATH=""
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"

		## CMake is hell.
		export CMAKE="cmake -DCMAKE_TOOLCHAIN_FILE=${SCRIPTS_BASE_DIR}/CMakeCross.txt -DCMAKE_INSTALL_PREFIX=${TC_BUILD_DIR}"

		DEVICE_USERSTORE="/mnt/ext1/applications"
	;;
	CY )
		ARCH_FLAGS="-march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=softfp -mthumb"
		CROSS_TC="arm-bookeen-linux-gnueabi"
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

		BASE_HACKDIR="${SVN_ROOT}/Configs/trunk/Kindle/Bookeen_Hacks"

		# We always rely on the native pkg-config, with custom search paths
		BASE_PKG_CONFIG="pkg-config"
		export PKG_CONFIG="${BASE_PKG_CONFIG}"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_PATH=""
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"

		## CMake is hell.
		export CMAKE="cmake -DCMAKE_TOOLCHAIN_FILE=${SCRIPTS_BASE_DIR}/CMakeCross.txt -DCMAKE_INSTALL_PREFIX=${TC_BUILD_DIR}"

		DEVICE_USERSTORE="/mnt/fat"
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
		# We don't want to pull *any* libs through pkg-config
		export PKG_CONFIG_PATH=""
		export PKG_CONFIG_LIBDIR=""
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
		# We ship our own shared STL, no need to downgrade the ABI
		if [[ -n "${LEGACY_GLIBCXX_ABI}" ]]; then
			export CFLAGS="${CFLAGS/${LEGACY_GLIBCXX_ABI}/}"
			export CXXFLAGS="${CXXFLAGS/${LEGACY_GLIBCXX_ABI}/}"
		fi
	# As well as a no-sysroot version for standalone projects (i.e., KFMon)
	elif [[ "${3}" == "bare" ]] ; then
		echo "* Not using our custom sysroot! :)"
		# We don't want to pull any of our own libs through pkg-config
		# NOTE: But we *are* okay with the sysroot's libs, in case there's a sysroot pkg-config wrapper, like in the Nickel TC,
		#       which is why we unset PKG_CONFIG instead of enforcing it to unprefixed pkg-config.
		#       (autotools will prefer ${CROSS_TC}-pkg-config, i.e., the wrapper pointing to the sysroot).
		unset PKG_CONFIG
		# NOTE: We also don't really want to look into native paths, either...
		export PKG_CONFIG_PATH=""
		export PKG_CONFIG_LIBDIR=""
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
		unset PKG_CONFIG
		export PKG_CONFIG_PATH=""
		export PKG_CONFIG_LIBDIR=""
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
		# NOTE: For C++, the general idea would be the same to swap to libunwind/libc++ via --unwindlib=libunwind --stdlib=libc++ instead of libgcc/libstdc++ ;).
		#       An annoying caveat is that llvm-libunwind/libcxxabi/libcxx live in standard library search paths, not custom LLVM ones, unlike compiler-rt... :/ (i.e., we'd probably have to move 'em to the TC's sysroot or a staging one).
		# NOTE: c.f., https://archive.fosdem.org/2018/schedule/event/crosscompile/attachments/slides/2107/export/events/attachments/crosscompile/slides/2107/How_to_cross_compile_with_LLVM_based_tools.pdf for a good recap.
		if [[ "${3}" == "clang-gcc" ]] ; then
			export CFLAGS="--target=${CROSS_TC} --sysroot=$(${CROSS_TC}-gcc -print-sysroot) --gcc-toolchain=${HOME}/x-tools/${CROSS_TC} --gcc-install-dir=$(basedir "$(${CROSS_TC}-gcc -print-libgcc-file-name)") ${RICE_CFLAGS}"
			export CXXFLAGS="--target=${CROSS_TC} --sysroot=$(${CROSS_TC}-gcc -print-sysroot) --gcc-toolchain=${HOME}/x-tools/${CROSS_TC} --gcc-install-dir=$(basedir "$(${CROSS_TC}-gcc -print-libgcc-file-name)") ${RICE_CFLAGS}"
			export LDFLAGS="-fuse-ld=lld ${BASE_LDFLAGS}"
		else
			export CFLAGS="--target=${CROSS_TC} --sysroot=$(${CROSS_TC}-gcc -print-sysroot) --gcc-toolchain=${HOME}/x-tools/${CROSS_TC} --gcc-install-dir=$(basedir "$(${CROSS_TC}-gcc -print-libgcc-file-name)") ${RICE_CFLAGS}"
			export CXXFLAGS="--target=${CROSS_TC} --sysroot=$(${CROSS_TC}-gcc -print-sysroot) --gcc-toolchain=${HOME}/x-tools/${CROSS_TC} --gcc-install-dir=$(basedir "$(${CROSS_TC}-gcc -print-libgcc-file-name)") ${RICE_CFLAGS}"
			export LDFLAGS="--rtlib=compiler-rt --unwindlib=libgcc --stdlib=libstdc++ -fuse-ld=lld ${BASE_LDFLAGS}"
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

##
### Everything else is related to building all the crap I ship in my various packages (c.f., what's in Configs/trunk/Kindle/Misc/x-compile.d in the SVN repo)
##
# NOTE: This is handled by a dedicated script shard to avoid cluttering the koxtoolchain repo (again, the whole thing is on SVN).
. "${SCRIPTS_BASE_DIR}/x-compile-packages.sh"
