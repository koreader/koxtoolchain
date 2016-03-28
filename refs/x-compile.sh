#! /bin/bash -e
#
# Kindle cross toolchain & lib/bin/util build script
#
# $Id: x-compile.sh 10071 2013-11-14 18:13:01Z NiLuJe $
#
# kate: syntax bash;
#
##

## Using CrossTool-NG (http://crosstool-ng.org/)
SVN_ROOT="/home/niluje/SVN"

## Install/Setup CrossTool-NG
Build_CT-NG() {
	echo "* Building CrossTool-NG . . ."
	echo ""
	cd ~/Kindle
	mkdir -p CrossTool
	cd CrossTool
	mkdir -p CT-NG
	cd CT-NG
	hg clone http://crosstool-ng.org/hg/crosstool-ng .
	# Add latest Linaro GCC version...
	patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/ct-ng-linaro-2013.10.patch
	# Add the Make-3.82 patch to Glibc 2.9 too, because it fails to build in softfp with make 3.81... -_-" [Cf. http://lists.gnu.org/archive/html/help-make/2012-02/msg00025.html]
	cp -v patches/glibc/2.12.1/920-make-382.patch patches/glibc/2.9/920-make-382.patch

	./bootstrap
	./configure --prefix=/home/niluje/Kindle/CrossTool
	make
	make install
	export PATH="${PATH}:/home/niluje/Kindle/CrossTool/bin"

	cd ..
	mkdir -p TC_Kindle
	cd TC_Kindle

	#ct-ng distclean
	rm -rf build.log config .config .config.2 config.gen .build/arm-kindle-linux-gnueabi .build/arm-kindle5-linux-gnueabi .build/src .build/tools .build/tarballs/eglibc-2_12.tar.bz2 .build/tarballs/eglibc-ports-2_12.tar.bz2 .build/tarballs/gcc-linaro-*.tar.xz

	unset CFLAGS CXXFLAGS LDFLAGS
	ct-ng menuconfig

	## Config:
	cat << EOF

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
	CPU: arm1136jf-s	|	cortex-a8
	Tune: arm1136jf-s	|	cortex-a8
	FPU: vfp		|	neon or vfpv3
	Floating point: softfp				# NOTE: Can't use hardf anymore, it requires the linux-armhf loader. Amazon never used interwork, and it's not as useful anymore with Thumb2. K5: I'm not sure Amazon defaults to Thumb2, but AFAICT we can use it safely.
	CFLAGS: -O2 -fomit-frame-pointer -mno-unaligned-access -pipe	|	-O3 -fomit-frame-pointer -pipe		# See env setup for the reasoning behind -mno-unaligned-access on K3 (it's actually for the K2). Don't use -ffast-math or -Ofast here, '#error "glibc must not be compiled with -ffast-math"'.
	LDFLAGS: -Wl,-O1 -Wl,--as-needed
	Default instruction set mode:	arm	|	thumb
	Use EABI: [*]

	* TC >
	Tuple's vendor: kindle	|	kindle5

	* OS >
	Target: linux
	Kernel: 2.6.27.62 (long-term)	|	2.6.31.14	# [Or use the -lab126 tarball from Kindle Source Code packages, but you'll need to patch it. (sed -e 's/getline/get_line/g' -i scripts/unifdef.c)]

	* Binary >
	Format: ELF
	Binutils: 2.23.2
	Linkers to enable: ld, gold
	Enable threaded gold: [*]
	Add ld wrapper: [*]
	Enable support for plugins: [*]

	* C Compiler >
	Type: gcc
	Linaro: [*]
	Version: linaro-4.8-2013.10
	Additional Lang: C++
	Link lstdc++ statically
	Enable GRAPHITE
	Enable LTO
	Opt gcc libs for size [ ]	# -Os is evil?
	Use __cxa_atexit
	<M> sjlj
	<M> 128-bit long doubles
	Linker hash-style: Default	|	gnu

	* C library >
	Type: glibc	|	eglibc
	Version: 2.9	|	2_12
	Threading: nptl
	Minimum supported kernel version: 2.6.22	|	2.6.31

EOF
	##

	nice ct-ng build
}

## Choose your TC!
case ${1} in
	k2 | K2 | k3 | k3 )
		KINDLE_TC="K3"
	;;
	k4 | K4 | k5 | K5 )
		KINDLE_TC="K5"
	;;
	* )
		echo "You must choose a ToolChain! (k3 or k5)"
		exit 1
	;;
esac

## Setup our env to use the right TC
echo "* Setting environment up . . ."
echo ""
case ${KINDLE_TC} in
	K3 )
		ARCH_FLAGS="-march=armv6j -mtune=arm1136jf-s -mfpu=vfp -mfloat-abi=softfp"
		CROSS_TC="arm-kindle-linux-gnueabi"
		TC_BUILD_DIR="/home/niluje/Kindle/CrossTool/Build_${KINDLE_TC}"

		# Export it for our CMakeCross TC file
		export CROSS_TC
		export TC_BUILD_DIR

		export CROSS_PREFIX="${CROSS_TC}-"
		export PATH="/home/niluje/x-tools/${CROSS_TC}/bin:${PATH}"

		## NOTE: See http://gcc.gnu.org/gcc-4.7/changes.html & http://comments.gmane.org/gmane.linux.linaro.devel/12115 & http://comments.gmane.org/gmane.linux.ports.arm.kernel/117863
		## But, basically, if you want to build a Kernel, backport https://github.com/mirrors/linux/commit/8428e84d42179c2a00f5f6450866e70d802d1d05 [it's not in FW 2.5.8/3.4/4.1.0/5.1.2],
		## or build your Kernel with -mno-unaligned-access
		## You might also want to backport https://github.com/mirrors/linux/commit/088c01f1e39dbe93a13e0b00f4532ed8b79d35f4 if you intend to roll your own Kernel.
		## For those interested, basically, if your kernel has this: https://github.com/mirrors/linux/commit/baa745a3378046ca1c5477495df6ccbec7690428 then you're safe in userland.
		## (That's the commit merged in 2.6.28 that the GCC docs refer to).
		## It's in FW 3.x/4.x/5.x, so we're good on *some* Kindles. However, it's *NOT* in FW 2.x, and the trap handler defaults to ignoring unaligned access faults.
		## I haven't seen any *actual* issues yet, but the counter does increment...
		## So, to be on the safe side, let's use -mno-unaligned-access on the K3 TC, to avoid going kablooey in weird & interesting ways on FW 2.x... ;)
		ARM_NO_UNALIGNED_ACCESS="-mno-unaligned-access"

		## NOTE: When linking dynamically, disable GCC 4.3/Glibc 2.8 fortify & stack-smashing protection support to avoid pulling symbols requiring GLIBC_2.8 or GCC_4.3
		BASE_CFLAGS="-O2 -ffast-math ${ARCH_FLAGS} ${ARM_NO_UNALIGNED_ACCESS} -pipe -fomit-frame-pointer -flto=2 -fuse-linker-plugin -fno-stack-protector -U_FORTIFY_SOURCE"
		NOLTO_CFLAGS="-O2 -ffast-math ${ARCH_FLAGS} ${ARM_NO_UNALIGNED_ACCESS} -pipe -fomit-frame-pointer -fno-stack-protector -U_FORTIFY_SOURCE"
		## FIXME: Disable LTO for now, it breaks a few key parts of what we build right now (OpenSSH) ;)
		BASE_CFLAGS="${NOLTO_CFLAGS}"
		export CFLAGS="${BASE_CFLAGS}"
		export CXXFLAGS="${BASE_CFLAGS}"
		# NOTE: Use -isystem instead of -I to make sure GMP doesn't do crazy stuff... Not quite sure what's the difference w/ -idirafter though...
		BASE_CPPFLAGS="-isystem${TC_BUILD_DIR}/include"
		export CPPFLAGS="${BASE_CPPFLAGS}"
		BASE_LDFLAGS="-L${TC_BUILD_DIR}/lib -Wl,-O1 -Wl,--as-needed"
		export LDFLAGS="${BASE_LDFLAGS}"

		BASE_HACKDIR="${SVN_ROOT}/Configs/trunk/Kindle/Hacks"

		BASE_PKG_CONFIG_PATH="${TC_BUILD_DIR}/lib/pkgconfig"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_DIR=
		export PKG_CONFIG_PATH="${BASE_PKG_CONFIG_PATH}"
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"
	;;
	K5 )
		ARCH_FLAGS="-march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=softfp -mthumb"
		CROSS_TC="arm-kindle5-linux-gnueabi"
		TC_BUILD_DIR="/home/niluje/Kindle/CrossTool/Build_${KINDLE_TC}"

		# Export it for our CMakeCross TC file
		export CROSS_TC
		export TC_BUILD_DIR

		export CROSS_PREFIX="${CROSS_TC}-"
		export PATH="/home/niluje/x-tools/${CROSS_TC}/bin:${PATH}"

		BASE_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} -pipe -fomit-frame-pointer -flto=2 -fuse-linker-plugin"
		NOLTO_CFLAGS="-O3 -ffast-math ${ARCH_FLAGS} -pipe -fomit-frame-pointer"
		## FIXME: Disable LTO for now, it breaks (at runtime) a few key parts of what we build right now (OpenSSH), and fails to build some of it (Coreutils) ;)
		BASE_CFLAGS="${NOLTO_CFLAGS}"
		export CFLAGS="${BASE_CFLAGS}"
		export CXXFLAGS="${BASE_CFLAGS}"
		# NOTE: Use -isystem instead of -I to make sure GMP doesn't do crazy stuff... Not quite sure what's the difference w/ -idirafter though...
		BASE_CPPFLAGS="-isystem${TC_BUILD_DIR}/include"
		export CPPFLAGS="${BASE_CPPFLAGS}"
		BASE_LDFLAGS="-L${TC_BUILD_DIR}/lib -Wl,-O1 -Wl,--as-needed"
		export LDFLAGS="${BASE_LDFLAGS}"

		BASE_HACKDIR="${SVN_ROOT}/Configs/trunk/Kindle/Touch_Hacks"

		BASE_PKG_CONFIG_PATH="${TC_BUILD_DIR}/lib/pkgconfig"
		BASE_PKG_CONFIG_LIBDIR="${TC_BUILD_DIR}/lib/pkgconfig"
		export PKG_CONFIG_DIR=
		export PKG_CONFIG_PATH="${BASE_PKG_CONFIG_PATH}"
		export PKG_CONFIG_LIBDIR="${BASE_PKG_CONFIG_LIBDIR}"
	;;
	* )
		echo "Unknown TC: ${KINDLE_TC} !"
		exit 1
	;;
esac

## Get to our build dir
mkdir -p "${TC_BUILD_DIR}"
cd "${TC_BUILD_DIR}"

## And start building stuff!

## FT & FC for Fonts
echo "* Building zlib . . ."
echo ""
tar xvzf /usr/portage/distfiles/zlib-1.2.8.tar.gz
cd zlib-1.2.8
# Needs to be PIC for Python...
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	export CFLAGS="${BASE_CFLAGS} -fPIC -DPIC"
	sed -e 's/$(CC) -c _match.s/$(CC) -c -fPIC _match.s/' -i Makefile.in
fi
./configure --shared --prefix=${TC_BUILD_DIR}
make -j2
make install
sed -i -r 's:\<(O[FN])\>:_Z_\1:g' ${TC_BUILD_DIR}/include/z*.h
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	export CFLAGS="${BASE_CFLAGS}"
fi

echo "* Building expat . . ."
echo ""
cd ..
tar xvzf /usr/portage/distfiles/expat-2.1.0.tar.gz
cd expat-2.1.0
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	# We need it to be PIC, or fontconfig (shared) fails to link
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --with-pic
fi
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes
fi
make -j2
make install

## FIXME: Should we link against a static libz for perf/stability? (So far, no issues, and no symbol versioning mishap either, but then again, it's only used for compressed PCF font AFAIR).
echo "* Building freetype . . ."
echo ""
FT_VER="2.5.0.1_p20131112"
FT_SOVER="6.10.2"
## Autohint
cd ..
tar xvjf /usr/portage/distfiles/freetype-${FT_VER}.tar.bz2
cd freetype2
## Always force autohinter (Like on the K2)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-2.4.9-kindle-force-autohint.patch
#patch -p1 < /usr/portage/media-libs/freetype/files/freetype-2.3.2-enable-valid.patch
## NOTE: Let's try to break everything! AA to 16 shades of grey intead of 256. Completely destroys the rendering on my box, doesn't seem to have an effect on my K5 :?.
#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-kindle-num_grays-16.patch
sh autogen.sh
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-png
make -j2
make install
cp ../lib/libfreetype.so.${FT_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/autohint/libfreetype.so
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/autohint/libfreetype.so
## Light
cd ..
rm -rf freetype2
tar xvjf /usr/portage/distfiles/freetype-${FT_VER}.tar.bz2
cd freetype2
## Always force light grey hinting (light hinting implicitly forces autohint) unless we asked for monochrome rendering (ie. in some popups & address bars, if we don't take this into account, these all render garbled glyphs)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-2.4.9-kindle-force-light.patch
## Let's try the experimental autofit warper too, since it's only enabled with LIGHT :)
sed -e "/#define AF_CONFIG_OPTION_USE_WARPER/a #define AF_CONFIG_OPTION_USE_WARPER" -i include/freetype/config/ftoption.h
#patch -p1 < /usr/portage/media-libs/freetype/files/freetype-2.3.2-enable-valid.patch
#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-kindle-num_grays-16.patch
sh autogen.sh
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-png
make -j2
make install
cp ../lib/libfreetype.so.${FT_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/light/libfreetype.so
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/light/libfreetype.so
## BCI
cd ..
rm -rf freetype2
tar xvjf /usr/portage/distfiles/freetype-${FT_VER}.tar.bz2
cd freetype2
## Always force grey hinting (bci implicitly takes precedence over autohint)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-2.4.9-kindle-force-bci.patch
#patch -p1 < /usr/portage/media-libs/freetype/files/freetype-2.3.2-enable-valid.patch
#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-kindle-num_grays-16.patch
sh autogen.sh
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-png
make -j2
make install
cp ../lib/libfreetype.so.${FT_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/bci/libfreetype.so
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/bci/libfreetype.so
## SPR
cd ..
rm -rf freetype2
tar xvjf /usr/portage/distfiles/freetype-${FT_VER}.tar.bz2
cd freetype2
## Always force grey hinting (bci implicitly takes precedence over autohint)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-2.4.9-kindle-force-bci.patch
#patch -p1 < /usr/portage/media-libs/freetype/files/freetype-2.3.2-enable-valid.patch
#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-kindle-num_grays-16.patch
## Enable the v38 native hinter...
sed -e "/#define FT_CONFIG_OPTION_SUBPIXEL_RENDERING/a #define FT_CONFIG_OPTION_SUBPIXEL_RENDERING" -i include/freetype/config/ftoption.h
sed -e "/#define TT_CONFIG_OPTION_SUBPIXEL_HINTING/a #define TT_CONFIG_OPTION_SUBPIXEL_HINTING" -i include/freetype/config/ftoption.h
## Haha. LCD filter. Hahahahahaha.
#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/freetype-2.3.12-spr-fir-filter-weight-to-gibson-coeff.patch
sh autogen.sh
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --without-png
make -j2
make install
cp ../lib/libfreetype.so.${FT_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/spr/libfreetype.so
${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/spr/libfreetype.so

## Build ftbench
echo "* Building ftbench . . ."
echo ""
cd ..
cd freetype2-demos
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
make -j2
${CROSS_TC}-strip --strip-unneeded bin/.libs/ftbench
cp bin/.libs/ftbench ftbench

## Build FC static because the Kindle's bundled fontconfig lib is too old for us.
echo "* Building fontconfig . . ."
echo ""
ZLIB_SOVER="1.2.8"
EXPAT_SOVER="1.6.0"
FC_SOVER="1.7.0"
cd ..
tar xvjf /usr/portage/distfiles/fontconfig-2.11.0_p20131111.tar.bz2
cd fontconfig
patch -p1 < /usr/portage/media-libs/fontconfig/files/fontconfig-2.7.1-latin-reorder.patch
patch -p1 < /usr/portage/media-libs/fontconfig/files/fontconfig-2.10.2-docbook.patch
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/fontconfig-2.10.0-do-not-deprecate-dotfile.patch
# Actually, we build it shared first, we might need it.
# Needed to properly link FT...
export PKG_CONFIG="pkg-config --static"
# NOTE: Link to expat statically, we're using expat 2.1.0, the Kindle is using 2.0.0 (and it's not in the tree anymore)
for fc_dep in libexpat.so libexpat.so.1 libexpat.so.${EXPAT_SOVER} libexpat.la ; do mv -v ../lib/${fc_dep} ../lib/_${fc_dep} ; done
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	# We don't have mkostemp on glibc 2.5... ;)
	export ac_cv_func_mkostemp=no
fi
sh autogen.sh --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --disable-docs --disable-docbook --localstatedir=/var --with-templatedir=/etc/fonts/conf.avail --with-baseconfigdir=/etc/fonts --with-xmldir=/etc/fonts --with-arch=arm --with-expat=${TC_BUILD_DIR}
make -j2
make install-exec
make install-pkgconfigDATA
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	unset ac_cv_func_mkostemp
fi
#cp ../lib/libfontconfig.so.${FC_SOVER} ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libfontconfig.so
#${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/Fonts/src/linkfonts/lib/libfontconfig.so
for fc_dep in libexpat.so libexpat.so.1 libexpat.so.${EXPAT_SOVER} libexpat.la ; do mv -v ../lib/_${fc_dep} ../lib/${fc_dep} ; done
# And then static for fc-scan
make clean
# NOTE: We move stuff around to ensure we fully link statically, otherwise there's some potential ABI mismatches ending in semi-random segfaults...
for fc_dep in libfreetype.so libfreetype.so.6 libfreetype.so.${FT_SOVER} libfreetype.la libz.so libz.so.1 libz.so.${ZLIB_SOVER} libexpat.so libexpat.so.1 libexpat.so.${EXPAT_SOVER} libexpat.la ; do mv -v ../lib/${fc_dep} ../lib/_${fc_dep} ; done
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	export ac_cv_func_mkostemp=no
fi
sh autogen.sh --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=no --enable-static=yes --disable-docs --disable-docbook --localstatedir=/var --with-templatedir=/etc/fonts/conf.avail --with-baseconfigdir=/etc/fonts --with-xmldir=/etc/fonts --with-arch=arm --with-expat=${TC_BUILD_DIR}
make -j2
make install-exec
make install-pkgconfigDATA
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	unset ac_cv_func_mkostemp
fi
${CROSS_TC}-strip --strip-unneeded ../bin/fc-scan
cp ../bin/fc-scan ${BASE_HACKDIR}/Fonts/src/linkfonts/bin/fc-scan
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	${CROSS_TC}-strip --strip-unneeded ../bin/fc-list
	cp ../bin/fc-list ${BASE_HACKDIR}/Fonts/src/linkfonts/bin/fc-list
fi
# Restore our shared libs
for fc_dep in libfreetype.so libfreetype.so.6 libfreetype.so.${FT_SOVER} libfreetype.la libz.so libz.so.1 libz.so.${ZLIB_SOVER} libexpat.so libexpat.so.1 libexpat.so.${EXPAT_SOVER} libexpat.la ; do mv -v ../lib/_${fc_dep} ../lib/${fc_dep} ; done
unset PKG_CONFIG

## Coreutils for SS
echo "* Building coreutils . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/coreutils-8.21.tar.xz
cd coreutils-8.21
tar xvJf /usr/portage/distfiles/coreutils-8.21-patches-1.0.tar.xz
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
export fu_cv_sys_stat_statfs2_bsize=yes
export gl_cv_func_realpath_works=yes
export gl_cv_func_fstatat_zero_flag=yes
export gl_cv_func_mknod_works=yes
export gl_cv_func_working_mkstemp=yes
# Some cross compilation tweaks lifted from http://cross-lfs.org/view/svn/x86_64-64/temp-system/coreutils.html
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-acl --disable-xattr --disable-libcap --enable-install-program=hostname
cp -v Makefile{,.orig}
sed -e 's/^#run_help2man\|^run_help2man/#&/' -e 's/^\##run_help2man/run_help2man/' Makefile.orig > Makefile
make -j2
make install
${CROSS_TC}-strip --strip-unneeded ../bin/sort
unset fu_cv_sys_stat_statfs2_bsize
unset gl_cv_func_realpath_works
unset gl_cv_func_fstatat_zero_flag
unset gl_cv_func_mknod_works
unset gl_cv_func_working_mkstemp
cp ../bin/sort ${BASE_HACKDIR}/ScreenSavers/src/linkss/bin/sort

## SSHD, rsync, telnetd, sftp for USBNet
# We build libtommath & libtomcrypt ourselves in an attempt to avoid the performance regressions on ARM of the stable releases... FWIW, it's still there :/.
echo "* Building libtommath . . ."
echo ""
cd ..
rm -rf libtommath
git clone git://github.com/libtom/libtommath.git -b develop libtommath
cd libtommath
sed -i -e 's/-O3//g' etc/makefile makefile makefile.shared
sed -i -e 's/-funroll-loops//g' etc/makefile makefile makefile.shared
make CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-ar" INCPATH=${TC_BUILD_DIR}/include LIBPATH=${TC_BUILD_DIR}/lib
make CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-ar" INCPATH=${TC_BUILD_DIR}/include LIBPATH=${TC_BUILD_DIR}/lib INSTALL_USER=$(id -u) INSTALL_GROUP=$(id -g) install

echo "* Building libtomcrypt . . ."
echo ""
cd ..
rm -rf libtomcrypt
git clone git://github.com/libtom/libtomcrypt.git -b develop libtomcrypt
cd libtomcrypt
sed -i -e 's/-O3//g' makefile makefile.shared
sed -i -e 's/-funroll-loops//g' makefile
# GCC doesn't like the name 'B0' for a variable, make it longer. (Breaks dropbear build later on)
sed -i -e 's/B0/SB0/g' src/encauth/ccm/ccm_memory_ex.c src/headers/tomcrypt_mac.h
make CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-ar" RANLIB="${CROSS_TC}-ranlib"
make CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-ar" RANLIB="${CROSS_TC}-ranlib" INCPATH=${TC_BUILD_DIR}/include LIBPATH=${TC_BUILD_DIR}/lib DATAPATH=${TC_BUILD_DIR}/share INSTALL_USER=$(id -u) INSTALL_GROUP=$(id -g) NODOCS=true install

echo "* Building dropbear . . ."
# NOTE: According to https://secure.ucc.asn.au/hg/dropbear/rev/34b73c9d8aa3 the next version might enable SMALL_CODE by default. Get rid of it ;).
echo ""
cd ..
#tar xvjf /usr/portage/distfiles/dropbear-2013.60.tar.bz2
tar xvjf ${HOME}/Downloads/dropbear-2013.61test.tar.bz2
cd dropbear-2013.61test
# Resync dropbear-tfm branch to latest release
#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-tfm-tip-to-2012.55.patch
# Gentoo patches/tweaks
patch -p0 < /usr/portage/net-misc/dropbear/files/dropbear-0.46-dbscp.patch
sed -i -e '1i#define _GNU_SOURCE' scpmisc.c
sed -i -e '/SFTPSERVER_PATH/s:".*":"/mnt/us/usbnet/libexec/sftp-server":' -e '/XAUTH_COMMAND/s:/X11/:/:' options.h
sed -i -e '/pam_start/s:sshd:dropbear:' svr-authpam.c
sed -i -e '/DSS_PRIV_FILENAME/s:".*":"/mnt/us/usbnet/etc/dropbear_dss_host_key":' -e '/RSA_PRIV_FILENAME/s:".*":"/mnt/us/usbnet/etc/dropbear_rsa_host_key":' -e '/ECDSA_PRIV_FILENAME/s:".*":"/mnt/us/usbnet/etc/dropbear_ecdsa_host_key":' options.h
sed -e 's%#define ENABLE_X11FWD%/*#define ENABLE_X11FWD*/%' -i options.h	# Already commented out in dropbear-tfm
sed -i -e '/DROPBEAR_PIDFILE/s:".*":"/mnt/us/usbnet/run/sshd.pid":' options.h
# Show /etc/issue
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2013.61-kindle-show-issue.patch
# No passwd...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2013.61-kindle-nopasswd-hack.patch
# Pubkeys in /mnt/us/usbnet/etc/authorized_keys & with perms checks curbed a bit
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2013.61-kindle-pubkey-hack.patch
# Make sure we can safely kill the bundled libtom, and still end up with a working configure ;)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2013.61-no-bundled-libtom.patch
# Fix the Makefile so that LTO flags aren't dropped in the linking stage... FIXME: Disabled while we're not using LTO ;)
#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/dropbear-2012.55-fix-Makefile-for-lto.patch
# Kill bundled libtom, we're using our own, from the latest develop branch
rm -rf libtomcrypt libtommath
autoconf
autoheader
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-lastlog --enable-zlib --enable-openpty --enable-shadow --enable-syslog --disable-bundled-libtom
make -j2 MULTI=1 PROGRAMS="dropbear dbclient scp"
${CROSS_TC}-strip --strip-unneeded dropbearmulti
cp dropbearmulti ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/dropbearmulti

echo "* Building rsync . . ."
echo ""
cd ..
tar xvzf /usr/portage/distfiles/rsync-3.1.0.tar.gz
cd rsync-3.1.0
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	# utimensat's only available since Glibc 2.6, so we can't use it.
	export ac_cv_func_utimensat=no
fi
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-acl-support --disable-xattr-support --disable-ipv6 --disable-debug
make -j2
make install
${CROSS_TC}-strip --strip-unneeded ../bin/rsync
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	unset ac_cv_func_utimensat
fi
cp ../bin/rsync ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/rsync

echo "* Building busybox . . ."
echo ""
cd ..
tar xvjf /usr/portage/distfiles/busybox-1.21.1.tar.bz2
cd busybox-1.21.1
export CROSS_COMPILE="${CROSS_TC}-"
#export CFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
#export CXXFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
patch -p1 < /usr/portage/sys-apps/busybox/files/busybox-1.19.0-bb.patch
#for patchfile in /usr/portage/sys-apps/busybox/files/busybox-1.21.1-*.patch ; do
#	patch -p1 < ${patchfile}
#done
cp /usr/portage/sys-apps/busybox/files/ginit.c init/
sed -i -r -e 's:[[:space:]]?-(Werror|Os|falign-(functions|jumps|loops|labels)=1|fomit-frame-pointer)\>::g' Makefile.flags
#sed -i '/bbsh/s:^//::' include/applets.h
sed -i '/^#error Aborting compilation./d' applets/applets.c
sed -i 's:-Wl,--gc-sections::' Makefile
sed -i 's:-static-libgcc::' Makefile.flags
# Print issue & auth as root without pass over telnet...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/busybox-1.21.0-kindle-nopasswd-hack.patch
make allnoconfig
sleep 5
## Busybox config...
cat << EOF

	* General >
	Show applet usage messages (solo)
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

	* Applets > Login/Password >
	shadow passwords
	login (solo)

	* Applets > Networking >
	ftpd
	httpd
	telnetd

EOF
#make menuconfig
cp -v ${SVN_ROOT}/Configs/trunk/Kindle/Misc/busybox-1.21.0-config .config
make oldconfig
sleep 5
make -j2
cp busybox ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/busybox

if [[ "${KINDLE_TC}" == "K3" ]] ; then
	echo "* Building OpenSSL 0.9.8 . . ."
	echo ""
	cd ..
	tar xvzf /usr/portage/distfiles/openssl-0.9.8y.tar.gz
	cd openssl-0.9.8y
	#export CFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
	#export CXXFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
	export LDFLAGS="${BASE_LDFLAGS} -Wa,--noexecstack"
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-0.9.8e-bsd-sparc64.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-0.9.8h-ldflags.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-0.9.8m-binutils.patch
	sed -i -e '/DIRS/s: fips : :g' -e '/^MANSUFFIX/s:=.*:=ssl:' -e "/^MAKEDEPPROG/s:=.*:=${CROSS_TC}-gcc:" -e '/^install:/s:install_docs::' Makefile{,.org}
	sed -i '/^SET_X/s:=.*:=set -x:' Makefile.shared
	cp /usr/portage/dev-libs/openssl/files/gentoo.config-0.9.8 gentoo.config
	chmod a+rx gentoo.config
	sed -i '1s,^:$,#!/usr/bin/perl,' Configure
	sed -i '/^"debug-ben-debug-64"/d' Configure
	sed -i '/^"debug-steve/d' Configure
	#./Configure linux-generic32 -DL_ENDIAN ${BASE_CFLAGS} -fno-strict-aliasing enable-camellia enable-mdc2 enable-tlsext enable-zlib --prefix=${TC_BUILD_DIR} --openssldir=${TC_BUILD_DIR}/etc/ssl shared threads
	./Configure linux-generic32 -DL_ENDIAN ${BASE_CFLAGS} enable-camellia enable-mdc2 enable-tlsext enable-zlib --prefix=${TC_BUILD_DIR} --openssldir=${TC_BUILD_DIR}/etc/ssl shared threads
	grep '^CFLAG=' Makefile | LC_ALL=C sed -e 's:^CFLAG=::' -e 's:-ffast-math ::g' -e 's:-fomit-frame-pointer ::g' -e 's:-O[0-9] ::g' -e 's:-march=[-a-z0-9]* ::g' -e 's:-mcpu=[-a-z0-9]* ::g' -e 's:-m[a-z0-9]* ::g' > x-compile-tmp
	CFLAG="$(< x-compile-tmp)"
	sed -i -e "/^CFLAG/s:=.*:=${CFLAG} ${CFLAGS}:" -e "/^SHARED_LDFLAGS=/s:$: ${LDFLAGS}:" Makefile
	make -j1 depend
	make -j1 build_libs
	make -j1 install

	# Copy it for the USBNet rpath...
	for ssl_lib in libcrypto.so.0.9.8 libssl.so.0.9.8 ; do
		cp -f ../lib/${ssl_lib} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
		chmod -cvR ug+w ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
		${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
	done
fi

if [[ "${KINDLE_TC}" == "K5" ]] ; then
	# NOTE: We build & link it statically for K4/K5 because KT 5.1.0 move from openssl-0.9.8 to openssl-1...
	echo "* Building OpenSSL 1 . . ."
	echo ""
	cd ..
	tar xvzf /usr/portage/distfiles/openssl-1.0.1e.tar.gz
	cd openssl-1.0.1e
	#export CFLAGS="${CPPFLAGS} ${BASE_CFLAGS} -fno-strict-aliasing"
	export CFLAGS="${CPPFLAGS} ${BASE_CFLAGS}"
	#export CXXFLAGS="${BASE_CFLAGS} -fno-strict-aliasing"
	export LDFLAGS="${BASE_LDFLAGS} -Wa,--noexecstack"
	rm -f Makefile
	patch -p0 < /usr/portage/dev-libs/openssl/files/openssl-1.0.0a-ldflags.patch
	patch -p0 < /usr/portage/dev-libs/openssl/files/openssl-1.0.0d-windres.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.0h-pkg-config.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.1-parallel-build.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.1-x32.patch
	patch -p0 < /usr/portage/dev-libs/openssl/files/openssl-1.0.1e-ipv6.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.1e-bad-mac-aes-ni.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.1e-perl-5.18.patch
	patch -p1 < /usr/portage/dev-libs/openssl/files/openssl-1.0.1e-s_client-verify.patch
	sed -i -e '/DIRS/s: fips : :g' -e '/^MANSUFFIX/s:=.*:=ssl:' -e "/^MAKEDEPPROG/s:=.*:=${CROSS_TC}-gcc:" -e '/^install:/s:install_docs::' Makefile.org
	sed -i '/^SET_X/s:=.*:=set -x:' Makefile.shared
	cp /usr/portage/dev-libs/openssl/files/gentoo.config-1.0.0 gentoo.config
	chmod a+rx gentoo.config
	sed -i '1s,^:$,#!/usr/bin/perl,' Configure
	sed -i '/stty -icanon min 0 time 50; read waste/d' config
	#unset CROSS_COMPILE
	# We need it to be PIC, or mosh fails to link
	#./Configure linux-armv4 -DL_ENDIAN ${BASE_CFLAGS} -fno-strict-aliasing enable-camellia enable-mdc2 enable-tlsext enable-zlib --prefix=${TC_BUILD_DIR} --openssldir=${TC_BUILD_DIR}/etc/ssl shared threads
	./Configure linux-armv4 -DL_ENDIAN ${BASE_CFLAGS} enable-camellia enable-mdc2 enable-tlsext enable-zlib --prefix=${TC_BUILD_DIR} --openssldir=${TC_BUILD_DIR}/etc/ssl shared threads
	grep '^CFLAG=' Makefile | LC_ALL=C sed -e 's:^CFLAG=::' -e 's:-ffast-math ::g' -e 's:-fomit-frame-pointer ::g' -e 's:-O[0-9] ::g' -e 's:-march=[-a-z0-9]* ::g' -e 's:-mcpu=[-a-z0-9]* ::g' -e 's:-m[a-z0-9]* ::g' > x-compile-tmp
	CFLAG="$(< x-compile-tmp)"
	sed -i -e "/^CFLAG/s:=.*:=${CFLAG} ${CFLAGS}:" -e "/^SHARED_LDFLAGS=/s:$: ${LDFLAGS}:" Makefile
	make -j1 depend
	make -j1 all
	make -j1 rehash
	make -j1 install
	# If we want to only link statically because FW 5.1 moved to OpenSSL 1 while FW 5.0 was on OpenSSL 0.9.8...
	#rm -fv ../lib/engines/lib*.so ../lib/libcrypto.so ../lib/libcrypto.so.1.0.0 ../lib/libssl.so ../lib/libssl.so.1.0.0

	# Copy it for the USBNet rpath...
	for ssl_lib in libcrypto.so.1.0.0 libssl.so.1.0.0 ; do
		cp -f ../lib/${ssl_lib} ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
		chmod -cvR ug+w ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
		${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/lib/${ssl_lib}
	done
fi

echo "* Building OpenSSH . . ."
echo ""
cd ..
tar xvzf /usr/portage/distfiles/openssh-6.4p1.tar.gz
cd openssh-6.4p1
# FIXME: LTO seems to be breaking sshd on K3? (openssh-6.0p1/GCC Linaro 4.7.2012.06)
export CFLAGS="${BASE_CFLAGS}"
export CXXFLAGS="${BASE_CFLAGS}"
# Setup an RPATH for OpenSSL....
# Needed on the K5 because of the 0.9.8 -> 1.0.0 switch,
# and needed on the K3, because OpenSSH (client) segfaults during the hostkey exchange with Amazon's bundled OpenSSL lib (on FW 2.x at least)
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=/mnt/us/usbnet/lib"
sed -i -e '/_PATH_XAUTH/s:/usr/X11R6/bin/xauth:/usr/bin/xauth:' pathnames.h
sed -i '/^AuthorizedKeysFile/s:^:#:' sshd_config
patch -p0 < /usr/portage/net-misc/openssh/files/openssh-5.9_p1-sshd-gssapi-multihomed.patch
patch -p0 < /usr/portage/net-misc/openssh/files/openssh-4.7_p1-GSSAPI-dns.patch
# Pubkeys in /mnt/us/usbnet/etc/authorized_keys & with perms checks curbed a bit
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/openssh-6.3p1-kindle-pubkey-hack.patch
# Fix Makefile to actually make use of LTO ;). FIXME: LTO seems to be breaking sshd on K3? (openssh-6.0p1/GCC Linaro 4.7.2012.06)
#patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/openssh-6.0p1-fix-Makefile-for-lto.patch
sed -i -e "s:-lcrypto:$(pkg-config --libs ../lib/pkgconfig/openssl.pc):" configure{,.ac}
sed -i -e 's:^PATH=/:#PATH=/:' configure{,.ac}
# Tweak a whole lot of paths to suit our needs...
# NOTE: Tis is particularly ugly, but the code handles $HOME from the passwd db itself, so, gotta trick it... Use a decent amount of .. to handle people with custom HOMEdirs
sed -e 's#~/\.ssh#/mnt/us/usbnet/etc/dot\.ssh#g' -i pathnames.h
sed -e 's#"\.ssh#"../../../../../../mnt/us/usbnet/etc/dot\.ssh#g' -i pathnames.h
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	# OpenSSH >= 6.0 wants to build with stack-protection & _FORTIFY_SOURCE=2 but we can't on these devices...
	sed -i -e 's:-D_FORTIFY_SOURCE=2::' configure{,.ac}
	autoreconf
fi
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	## Easier to just fake it now than edit a bunch of defines later... (Only useful for sshd, you don't have to bother with it if you're just interested in sftp-server)
	if [[ -d "/mnt/us/usbnet" ]] ; then
		./configure --prefix=/mnt/us/usbnet --with-pid-dir=/mnt/us/usbnet/run --with-privsep-path=/mnt/us/usbnet/empty --host=${CROSS_TC} --with-ldflags="${LDFLAGS}" --disable-etc-default-login --disable-lastlog --with-ssl-engine --with-md5-passwords --disable-strip --without-stackprotect
	else
		./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --with-ldflags="${LDFLAGS}" --disable-etc-default-login --disable-lastlog --with-ssl-engine --with-md5-passwords --disable-strip --without-stackprotect
	fi
fi
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	if [[ -d "/mnt/us/usbnet" ]] ; then
		./configure --prefix=/mnt/us/usbnet --with-pid-dir=/mnt/us/usbnet/run --with-privsep-path=/mnt/us/usbnet/empty --host=${CROSS_TC} --with-ldflags="${LDFLAGS}" --disable-etc-default-login --disable-lastlog --with-ssl-engine --with-md5-passwords --disable-strip
	else
		./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --with-ldflags="${LDFLAGS}" --disable-etc-default-login --disable-lastlog --with-ssl-engine --with-md5-passwords --disable-strip
	fi
fi
make -j2
if [[ -d "/mnt/us/usbnet" ]] ; then
	# Make sure it's clean before install...
	rm -rf /mnt/us/usbnet/bin /mnt/us/usbnet/empty /mnt/us/usbnet/etc /mnt/us/usbnet/libexec /mnt/us/usbnet/sbin /mnt/us/usbnet/share
fi
make install-nokeys
if [[ -d "/mnt/us/usbnet" ]] ; then
	for file in /mnt/us/usbnet/bin/* /mnt/us/usbnet/sbin/* /mnt/us/usbnet/libexec/* ; do
		if [[ "${file}" != "/mnt/us/usbnet/bin/slogin" ]] ; then
			${CROSS_TC}-strip --strip-unneeded ${file}
			cp ${file} ${BASE_HACKDIR}/USBNetwork/src/usbnet/${file#/mnt/us/usbnet/*}
		fi
	done
	cp /mnt/us/usbnet/etc/moduli ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/moduli
	cp /mnt/us/usbnet/etc/sshd_config  ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/sshd_config
	cp /mnt/us/usbnet/etc/ssh_config  ${BASE_HACKDIR}/USBNetwork/src/usbnet/etc/ssh_config
else
	cp ../libexec/sftp-server ${BASE_HACKDIR}/USBNetwork/src/usbnet/libexec/sftp-server
	${CROSS_TC}-strip --strip-unneeded ${BASE_HACKDIR}/USBNetwork/src/usbnet/libexec/sftp-server
fi
export LDFLAGS="${BASE_LDFLAGS}"

## ncurses & htop for USBNet
echo "* Building ncurses . . ."
echo ""
cd ..
tar xvzf /usr/portage/distfiles/ncurses-5.9.tar.gz
cd ncurses-5.9
export CFLAGS="${BASE_CFLAGS}"
export CXXFLAGS="${BASE_CFLAGS}"
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-5.8-gfbsd.patch
patch -p1 < /usr/portage/sys-libs/ncurses/files/ncurses-5.7-nongnu.patch
patch -p0 < /usr/portage/sys-libs/ncurses/files/ncurses-5.9-rxvt-unicode-9.15.patch
patch -p2 < /usr/portage/sys-libs/ncurses/files/ncurses-5.9-fix-clang-build.patch
sed -i -e '/^PKG_CONFIG_LIBDIR/s:=.*:=$(libdir)/pkgconfig:' misc/Makefile.in
unset TERMINFO
export CPPFLAGS="${BASE_CPPFLAGS} -D_GNU_SOURCE"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --with-normal --with-chtype=long --with-mmask-t=long --disable-ext-colors --disable-ext-mouse --without-pthread --without-reentrant --with-terminfo-dirs="/etc/terminfo:/usr/share/terminfo" --with-shared --without-hashed-db --without-ada --without-cxx --without-cxx-binding --without-debug --without-profile --without-gpm --disable-termcap --enable-symlinks --with-rcs-ids --with-manpage-format=normal --enable-const --enable-colorfgbg --enable-echo --enable-pc-files --enable-overwrite
make -j1 sources
rm -f misc/pc-files
make -j2 -C progs tic
make install
export CPPFLAGS="${BASE_CPPFLAGS}"

echo "* Building htop . . ."
echo ""
cd ..
tar xvzf /usr/portage/distfiles/htop-1.0.2.tar.gz
cd htop-1.0.2
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/htop-1.0.2-to-r308.patch
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/htop-0.9-kindle-terminfo.patch
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/htop-1.0.1-kindle-htoprc.patch
autoreconf
export ac_cv_func_malloc_0_nonnull=yes
export ac_cv_func_realloc_0_nonnull=yes
export ac_cv_file__proc_meminfo=yes
export ac_cv_file__proc_stat=yes
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-unicode --enable-taskstats
make -j2
make install
${CROSS_TC}-strip --strip-unneeded ../bin/htop
unset ac_cv_func_malloc_0_nonnull
unset ac_cv_func_realloc_0_nonnull
unset ac_cv_file__proc_meminfo
unset ac_cv_file__proc_stat
cp ../bin/htop ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/htop

## lsof for USBNet
echo "* Building lsof . . ."
echo ""
cd ..
tar xvjf /usr/portage/distfiles/lsof_4.87.tar.bz2
cd lsof_4.87
tar xvf lsof_4.87_src.tar
cd lsof_4.87_src
touch .neverInv
patch -p1 < /usr/portage/sys-process/lsof/files/lsof-4.85-cross.patch
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	LSOF_CC="${CROSS_TC}-gcc" LSOF_AR="${CROSS_TC}-ar rc" LSOF_RANLIB="${CROSS_TC}-ranlib" LSOF_CFGF="${CFLAGS} ${CPPFLAGS}" LSOF_CFGL="${CFLAGS} ${LDFLAGS}" LSOF_ARCH="armv6l" LSOF_INCLUDE="${TC_BUILD_DIR}/include" LINUX_CLIB="-DGLIBCV=2" LINUX_HASSELINUX="N" ./Configure -n linux
fi
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	LSOF_CC="${CROSS_TC}-gcc" LSOF_AR="${CROSS_TC}-ar rc" LSOF_RANLIB="${CROSS_TC}-ranlib" LSOF_CFGF="${CFLAGS} ${CPPFLAGS}" LSOF_CFGL="${CFLAGS} ${LDFLAGS}" LSOF_ARCH="armv7-a" LSOF_INCLUDE="${TC_BUILD_DIR}/include" LINUX_CLIB="-DGLIBCV=2" LINUX_HASSELINUX="N" ./Configure -n linux
fi
make -j2 DEBUG="" all
${CROSS_TC}-strip --strip-unneeded lsof
cp lsof ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/lsof
cd ..

## shlock for Fonts & SS
echo "* Building shlock . . ."
echo ""
cd ..
mkdir shlock
cd shlock
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
tar xvjf /usr/portage/distfiles/protobuf-2.5.0.tar.bz2
cd protobuf-2.5.0
patch -p0 < /usr/portage/dev-libs/protobuf/files/protobuf-2.3.0-asneeded-2.patch
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	# Needs to be PIC on K5, or mosh throws a fit (reloc against a local symbol, as always)
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static=yes --enable-shared=no --with-protoc=/usr/bin/protoc --with-pic
fi
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static=yes --enable-shared=no --with-protoc=/usr/bin/protoc
fi
make -j2
make install

## mosh for USBNet
echo "* Building mosh . . ."
echo ""
cd ..
# Link libstdc++ statically, because the bundled one if friggin' ancient (especially on the K3, but the one on the K5 is still too old) (and we pull GLIBCXX_3.4.10 / CXXABI_ARM_1.3.3 / GLIBCXX_3.4.15)
# The K5 handles: <= GLIBCXX_3.4.14 / CXXABI_1.3.4 / CXXABI_ARM_1.3.3
# Also, setup an RPATH for OpenSSL....
export LDFLAGS="${BASE_LDFLAGS} -static-libstdc++ -Wl,-rpath=/mnt/us/usbnet/lib"
tar xvzf /usr/portage/distfiles/mosh-1.2.4.tar.gz
cd mosh-1.2.4
./autogen.sh
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-client --enable-server --disable-hardening
fi
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-client --enable-server --enable-hardening
fi
make -j2
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
tar xvjf /usr/portage/distfiles/libarchive-3.1.2_p20130926.tar.bz2
cd libarchive
# Fix issue 317
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/libarchive-fix-issue-317.patch
./build/autogen.sh
export ac_cv_header_ext2fs_ext2_fs_h=0
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	# Avoid pulling stuff from glibc 2.6...
	export ac_cv_func_futimens=no
	export ac_cv_func_utimensat=no
fi
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --disable-xattr --disable-acl --with-zlib --without-bz2lib --without-lzmadec --without-iconv --without-lzma --without-nettle --without-openssl --without-expat --without-xml2
make -j2
make install
unset ac_cv_header_ext2fs_ext2_fs_h
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	unset ac_cv_func_futimens
	unset ac_cv_func_utimensat
fi

## GMP (kindletool dep)
echo "* Building GMP . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/gmp-5.1.3.tar.xz
cd gmp-5.1.3
patch -p1 < /usr/portage/dev-libs/gmp/files/gmp-4.1.4-noexecstack.patch
libtoolize
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	env MPN_PATH="arm/v6 arm/v5 arm generic" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --disable-cxx
fi
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	env MPN_PATH="arm/v6t2 arm/v6 arm/v5 arm generic" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --disable-cxx
fi
make -j2
make install

## Nettle (kindletool dep)
echo "* Building nettle . . ."
echo ""
cd ..
if [[ "${USE_STABLE_NETTLE}" == "true" ]] ; then
	tar xvzf /usr/portage/distfiles/nettle-2.7.1.tar.gz
	cd nettle-2.7.1
	# Breaks the tools build if we don't build the shared libs at all, which is precisely what we do ;).
	#patch -p1 < /usr/portage/dev-libs/nettle/files/nettle-2.7-shared.patch
	sed -e '/CFLAGS=/s: -ggdb3::' -e 's/solaris\*)/sunldsolaris*)/' -i configure.ac
	sed -i '/SUBDIRS/s/testsuite examples//' Makefile.in
	autoreconf -fi
	if [[ "${KINDLE_TC}" == "K3" ]] ; then
		env ac_cv_host="armv6j-kindle-linux-gnueabi" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --disable-arm-neon
	fi
	if [[ "${KINDLE_TC}" == "K5" ]] ; then
		env ac_cv_host="armv7l-kindle5-linux-gnueabi" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --enable-arm-neon
	fi
	make -j2
	make install
else
	# Build from git to benefit from the more x86_64 friendly API changes
	if [[ -d "nettle-git" ]] ; then
		cd nettle-git
		make distclean
		git checkout -- configure.ac Makefile.in
		git pull
	else
		git clone git://git.lysator.liu.se/nettle/nettle.git nettle-git
		cd nettle-git
	fi
	sed -e '/CFLAGS=/s: -ggdb3::' -e 's/solaris\*)/sunldsolaris*)/' -i configure.ac
	sed -i '/SUBDIRS/s/testsuite examples//' Makefile.in
	sh ./.bootstrap
	if [[ "${KINDLE_TC}" == "K3" ]] ; then
		env ac_cv_host="armv6j-kindle-linux-gnueabi" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --disable-arm-neon
	fi
	if [[ "${KINDLE_TC}" == "K5" ]] ; then
		env ac_cv_host="armv7l-kindle5-linux-gnueabi" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-public-key --disable-openssl --disable-documentation --enable-arm-neon
	fi
	make -j2
	make install
fi

## KindleTool for USBNet
echo "* Building KindleTool . . ."
echo ""
cd ..
if [[ -d "./KindleTool" ]] ; then
	cd KindleTool
	git pull
	make clean
else
	git clone https://github.com/NiLuJe/KindleTool.git
	cd KindleTool
fi
export KT_NO_USERATHOST_TAG="true"
export CFLAGS="${BASE_CFLAGS} -DKT_USERATHOST='\"niluje@ajulutsikael\"'"
# Setup an RPATH for OpenSSL on the K5....
# Keep it K5 only, because on the K3, so far we haven't had any issues with KindleTool, and we use it in the JailBreak, too, so an rpath isn't the way to go
#if [[ "${KINDLE_TC}" == "K5" ]] ; then
#	export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=/mnt/us/usbnet/lib"
#fi
make kindle
unset KT_NO_USERATHOST_TAG
export CFLAGS="${BASE_CFLAGS}"
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	export LDFLAGS="${BASE_LDFLAGS}"
fi
cp KindleTool/Kindle/kindletool ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/kindletool
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	cp KindleTool/Kindle/kindletool ${BASE_HACKDIR}/Jailbreak/src/linkjail/bin/kindletool
fi

## Build the little USBNet helper...
echo "* Building USBNet helper . . ."
echo ""
cd ..
mkdir -p usbnet_helper
cd usbnet_helper
${CROSS_TC}-gcc ${SVN_ROOT}/Configs/trunk/Kindle/Hacks/USBNetwork/src/kindle_usbnet_addr.c ${BASE_CFLAGS} ${BASE_LDFLAGS} -o kindle_usbnet_addr
${CROSS_TC}-strip --strip-unneeded kindle_usbnet_addr
cp kindle_usbnet_addr ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/kindle_usbnet_addr

## libpng for ImageMagick
echo "* Building libpng . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/libpng-1.6.6.tar.xz
cd libpng-1.6.6
# Link against zlib statically to avoid symbol versioning issues...
for my_lib in libz.so libz.so.1 libz.so.${ZLIB_SOVER} ; do mv -v ../lib/${my_lib} ../lib/_${my_lib} ; done
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --enable-arm-neon=yes
else
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared
fi
make -j2
make install
for my_lib in libz.so libz.so.1 libz.so.${ZLIB_SOVER} ; do mv -v ../lib/_${my_lib} ../lib/${my_lib} ; done

## libjpg-turbo for ImageMagick
echo "* Building libjpeg-turbo . . ."
echo ""
cd ..
tar xvzf /usr/portage/distfiles/libjpeg-turbo-1.3.0.tar.gz
cd libjpeg-turbo-1.3.0
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --with-mem-srcdst
else
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --with-mem-srcdst --without-simd
fi
make -j2
make install

## ImageMagick for ScreenSavers
echo "* Building ImageMagick . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/ImageMagick-6.8.7-5.tar.xz
cd ImageMagick-6.8.7-5
# Use the same codepath as on iPhone devices to nerf the 65MB alloc of the dither code... (We also use a quantum-depth of 8 to keep the memory usage down)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/ImageMagick-6.8.6-5-nerf-dither-mem-alloc.patch
# Link against zlib statically to avoid symbol versioning issues...
for my_lib in libz.so libz.so.1 libz.so.${ZLIB_SOVER} ; do mv -v ../lib/${my_lib} ../lib/_${my_lib} ; done
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --without-magick-plus-plus --disable-openmp --disable-deprecated --disable-installed --disable-hdri --disable-opencl --disable-largefile --with-threads --without-modules --with-quantum-depth=8 --without-perl --without-bzlib --without-x --with-zlib --without-autotrace --without-dps --without-djvu --without-fftw --without-fpx --without-fontconfig --with-freetype --without-gslib --without-gvc --without-jbig --with-jpeg --without-jp2 --without-lcms --without-lcms2 --without-lqr --without-lzma --without-openexr --without-pango --with-png --without-rsvg --without-tiff --without-webp --without-corefonts --without-wmf --without-xml
make -j2
make install
for my_lib in libz.so libz.so.1 libz.so.${ZLIB_SOVER} ; do mv -v ../lib/_${my_lib} ../lib/${my_lib} ; done
${CROSS_TC}-strip --strip-unneeded ../bin/convert
cp ../bin/convert ${BASE_HACKDIR}/ScreenSavers/src/linkss/bin/convert
cp -f ../etc/ImageMagick-6/* ${BASE_HACKDIR}/ScreenSavers/src/linkss/etc/ImageMagick-6/

## bzip2 for Python
echo "* Building bzip2 . . ."
echo ""
cd ..
tar xvzf /usr/portage/distfiles/bzip2-1.0.6.tar.gz
cd bzip2-1.0.6
patch -p0 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.4-makefile-CFLAGS.patch
patch -p0 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.6-saneso.patch
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.4-man-links.patch
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.6-progress.patch
patch -p0 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.3-no-test.patch
patch -p0 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.4-POSIX-shell.patch
patch -p1 < /usr/portage/app-arch/bzip2/files/bzip2-1.0.6-mingw.patch
sed -i -e 's:\$(PREFIX)/man:\$(PREFIX)/share/man:g' -e 's:ln -s -f $(PREFIX)/bin/:ln -s :' -e 's:$(PREFIX)/lib:$(PREFIX)/$(LIBDIR):g' Makefile
make CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-ar" RANLIB="${CROSS_TC}-ranlib" -j2 -f Makefile-libbz2_so all
export CFLAGS="${BASE_CFLAGS} -static"
make CC="${CROSS_TC}-gcc" AR="${CROSS_TC}-ar" RANLIB="${CROSS_TC}-ranlib" -j2 all
export CFLAGS="${BASE_CFLAGS}"
make PREFIX="${TC_BUILD_DIR}" LIBDIR="lib" install

## libffi for Python
echo "* Building libffi . . ."
echo ""
cd ..
tar xvzf /usr/portage/distfiles/libffi-3.0.13.tar.gz
cd libffi-3.0.13
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	# Needs to be PIC for Python...
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared --with-pic
else
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared
fi
make -j2
make install

## Python for ScreenSavers
echo "* Building Python . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/Python-2.7.5.tar.xz
cd Python-2.7.5
rm -fr Modules/expat
rm -fr Modules/_ctypes/libffi*
rm -fr Modules/zlib
tar xvJf /usr/portage/distfiles/python-gentoo-patches-2.7.5-0.tar.xz
for patchfile in 2.7.5-0/* ; do
	patch -p0 < ${patchfile}
done
# Adapted from Gentoo's 2.7.3 cross-compile patchset. There's some fairly ugly and unportable hacks in there, because for the life of me I can't figure out how the cross-compile support merged in 2.7.4 is supposed to take care of some stuff... (namely, pgen & install)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/python-2.7.5-cross-compile.patch
patch -p1 < /usr/portage/dev-lang/python/files/python-2.7.5-library-path.patch
patch -p1 < /usr/portage/dev-lang/python/files/python-2.7.5-re_unsigned_ptrdiff.patch
patch -p1 < /usr/portage/dev-lang/python/files/CVE-2013-4238_py27.patch
patch -p1 < /usr/portage/dev-lang/python/files/python-2.7-issue16248.patch
patch -p1 < /usr/portage/dev-lang/python/files/python-2.7-issue18851.patch
sed -i -e "s:@@GENTOO_LIBDIR@@:lib:g" Lib/distutils/command/install.py Lib/distutils/sysconfig.py Lib/site.py Lib/sysconfig.py Lib/test/test_site.py Makefile.pre.in Modules/Setup.dist Modules/getpath.c setup.py
# Fix building against a static OpenSSL... (depends on zlib)
sed -e "s/\['ssl', 'crypto'\]/\['ssl', 'crypto', 'z'\]/g" -i setup.py
autoconf
autoheader

# Link against expat statically because the one bundled on the Kindle is too old, and zlib statically to avoid symbol versioning issues...
for my_lib in libexpat.so libexpat.so.1 libexpat.so.${EXPAT_SOVER} libexpat.la libz.so libz.so.1 libz.so.${ZLIB_SOVER} ; do mv -v ../lib/${my_lib} ../lib/_${my_lib} ; done
# link against OpenSSL statically on the K5
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	for my_lib in libcrypto.so libcrypto.so.1.0.0 libssl.so libssl.so.1.0.0 ; do mv -v ../lib/${my_lib} ../lib/_${my_lib} ; done
fi

# Kill curses too, it wants ncursesw
export PYTHON_DISABLE_MODULES="dbm _bsddb gdbm readline _sqlite3 _tkinter _curses _curses_panel"
export CFLAGS="${BASE_CFLAGS} -fwrapv"
# Apparently, we need -I here, or Python cannot find any our our stuff...
export CPPFLAGS="${BASE_CPPFLAGS/-isystem/-I}"

# How fun is it to cross-compile stuff? >_<"
# NOTE: We're following the Gentoo ebuild, so, set the vars up the Gentoo way
# What we're building on
export CBUILD="i686-pc-linux-gnu"
# What we're building for
export CHOST="${CROSS_TC}"
mkdir -p {${CBUILD},${CHOST}}
cd ${CBUILD}
OPT="-O1" CFLAGS="" CPPFLAGS="" LDFLAGS="" CC="" ../configure --{build,host}=${CBUILD}
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
export LDFLAGS="${BASE_LDFLAGS} -L."
cd ${CHOST}
OPT="" ../configure --prefix=${TC_BUILD_DIR}/python --build=${CBUILD} --host=${CROSS_TC} --enable-static --disable-shared --with-fpectl --disable-ipv6 --with-threads --enable-unicode=ucs4 --with-libc="" --enable-loadable-sqlite-extensions --with-system-expat --with-system-ffi
# More cross-compile hackery...
sed -i -e '1iHOSTPYTHONPATH = ./hostpythonpath' -e '/^PYTHON_FOR_BUILD/s:=.*:= ./hostpython:' -e '/^PGEN_FOR_BUILD/s:=.*:= ./Parser/hostpgen:' Makefile{.pre,}
cd ..

cd ${CBUILD}
# Disable as many modules as possible -- but we need a few to install.
PYTHON_DISABLE_MODULES=$(sed -n "/Extension('/{s:^.*Extension('::;s:'.*::;p}" ../setup.py | egrep -v '(unicodedata|time|cStringIO|_struct|binascii)') PYTHON_DISABLE_SSL="1" SYSROOT= make
ln python ../${CHOST}/hostpython
ln Parser/pgen ../${CHOST}/Parser/hostpgen
ln -s ../${CBUILD}/build/lib.*/ ../${CHOST}/hostpythonpath
cd ..

# Fallback to a sane PYTHONHOME, so we don't necessarily have to set PYTHONHOME in our env...
# NOTE: We only patch the CHOST build, because this fallback is Kindle-centric, and would break the build if used for the CBUILD Python ;)
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/python-2.7.5-kindle-pythonhome-fallback.patch
cd ${CHOST}
# Hardcode PYTHONHOME so we don't have to tweak our env... (NOTE: Now handled in a slightly more elegant/compatible way in a patch)
#sed -e 's#static char \*default_home = NULL;#static char \*default_home = "/mnt/us/python";#' -i ../Python/pythonrun.c
make -j2
make altinstall
cd ..

for my_lib in libexpat.so libexpat.so.1 libexpat.so.${EXPAT_SOVER} libexpat.la libz.so libz.so.1 libz.so.${ZLIB_SOVER} ; do mv -v ../lib/_${my_lib} ../lib/${my_lib} ; done
if [[ "${KINDLE_TC}" == "K5" ]] ; then
	for my_lib in libcrypto.so libcrypto.so.1.0.0 libssl.so libssl.so.1.0.0 ; do mv -v ../lib/_${my_lib} ../lib/${my_lib} ; done
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

# And now, clean it up, to try to end up with the smallest install package possible...
sed -e "s/\(LDFLAGS=\).*/\1/" -i "../python/lib/python2.7/config/Makefile"
# First, strip...
chmod a+w ../python/lib/libpython2.7.a
${CROSS_TC}-strip --strip-unneeded ../python/lib/libpython2.7.a
chmod a-w ../python/lib/libpython2.7.a
find ../python -name '*.so' -exec ${CROSS_TC}-strip --strip-unneeded {} +
${CROSS_TC}-strip --strip-unneeded ../python/bin/python2.7
# Next, kill a bunch of stuff we don't care about...
rm -rf ../python/lib/pkgconfig ../python/share
# Kill the symlinks we can't use on vfat anyway...
find ../python -type l -delete
# And now, do the same cleanup as the Gentoo ebuild...
rm -rf ../python/lib/python2.7/{bsddb,dbhash.py,test/test_bsddb*}
rm -rf ../python/lib/python2.7/{sqlite3,test/test_sqlite*}
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
sed -e 's#/home/niluje/Kindle/CrossTool/Build_K5/#/mnt/us/#' -i ../python/bin/idle ../python/bin/smtpd.py ../python/bin/python2.7-config ../python/bin/pydoc ../python/bin/2to3
# And finally, build our shiny tarball
cd ..
tar cvjf python.tar.bz2 python
cp -f python.tar.bz2 ${BASE_HACKDIR}/Python/src/python.tar.bz2
cd -
# NOTE: Might need to use the terminfo DB from usbnet to make the interpreter UI useful: export TERMINFO=/mnt/us/usbnet/etc/terminfo

## inotify-tools for ScreenSavers on the K2/3/4
echo "* Building inotify-tools . . ."
echo ""
cd ..
if [[ -d "./inotify-tools" ]] ; then
	cd inotify-tools
	git pull
	make clean
else
	git clone git://github.com/rvoicilas/inotify-tools.git
	cd inotify-tools
	# Make automake 1.13 happy
	mkdir -p m4
	./autogen.sh
fi
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-static --disable-shared
make -j2
make install
${CROSS_TC}-strip --strip-unneeded ../bin/inotifywait
cp ../bin/inotifywait ${BASE_HACKDIR}/ScreenSavers/src/linkss/bin/inotifywait


## sshfs for USBNet (Build it at the end, I don't want glib to be automagically pulled by something earlier...)
#
# Depends on glib
echo "* Building glib . . ."
echo ""
cd ..
tar xvJf /usr/portage/distfiles/glib-2.36.4.tar.xz
cd glib-2.36.4
patch -p1 < /usr/portage/dev-libs/glib/files/glib-2.36.4-znodelete.patch
autoreconf -fi
# Cf. https://developer.gnome.org/glib/stable/glib-cross-compiling.html
export glib_cv_stack_grows=no
export glib_cv_uscore=yes
export ac_cv_func_posix_getpwuid_r=yes
export ac_cv_func_posix_getgrgid_r=yes
# Avoid pulling stuff from GLIBC_2.7 & 2.9 on the K3
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	export glib_cv_eventfd=no
	export ac_cv_func_pipe2=no
fi
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=yes --enable-static=yes --disable-libelf --disable-selinux --disable-compile-warnings --with-pcre=internal --with-threads=posix
make -j2
make install
unset glib_cv_stack_grows glib_cv_uscore ac_cv_func_posix_getpwuid_r c_cv_func_posix_getgrgid_r
if [[ "${KINDLE_TC}" == "K3" ]] ; then
	unset glib_cv_eventfd ac_cv_func_pipe2
fi

# And of course FUSE ;)
echo "* Building fuse . . ."
echo ""
cd ..
tar xvzf /usr/portage/distfiles/fuse-2.9.3.tar.gz
cd fuse-2.9.3
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} INIT_D_PATH=${TC_BUILD_DIR}/etc/init.d MOUNT_FUSE_PATH=${TC_BUILD_DIR}/sbin UDEV_RULES_PATH=${TC_BUILD_DIR}/etc/udev/rules.d --enable-shared=no --enable-static=yes --disable-example
make -j2
make install

# And finally sshfs
echo "* Building sshfs . . ."
echo ""
cd ..
if [[ -d "./fuse-sshfs" ]] ; then
	cd fuse-sshfs
	git checkout -- ./sshfs.c
	git pull
	make clean
else
	git clone git://git.code.sf.net/p/fuse/sshfs fuse-sshfs
	cd fuse-sshfs
	# We don't have ssh in $PATH, call our own
	sed -e 's#ssh_add_arg("ssh");#ssh_add_arg("/mnt/us/usbnet/bin/ssh");#' -i ./sshfs.c
	autoreconf -fi
fi
# Static libfuse...
env PKG_CONFIG="pkg-config --static" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-sshnodelay
make -j2
make install
${CROSS_TC}-strip --strip-unneeded ../bin/sshfs
cp ../bin/sshfs ${BASE_HACKDIR}/USBNetwork/src/usbnet/bin/sshfs


# Build gawk for KUAL
echo "* Building gawk . . ."
echo ""
cd ..
if [[ -d "./gawk" ]] ; then
	cd gawk
	git checkout -- Makefile.in doc/Makefile.in test/Makefile.in io.c
	git pull
	make clean
else
	git clone git://git.sv.gnu.org/gawk.git
	cd gawk
	./bootstrap.sh
fi
sed -i -e '/^LN =/s:=.*:= $(LN_S):' -e '/install-exec-hook:/s|$|\nfoo:|' Makefile.in doc/Makefile.in
sed -i '/^pty1:$/s|$|\n_pty1:|' test/Makefile.in
# Awful hack to allow closing stdout, so that we don't block KUAL on cache hits...
patch -p1 < ${SVN_ROOT}/Configs/trunk/Kindle/Misc/gawk-4.1.0-allow-closing-stdout.patch
export ac_cv_libsigsegv=no
# Setup an rpath for the extensions...
export LDFLAGS="${BASE_LDFLAGS} -Wl,-rpath=/mnt/us/extensions/gawk/lib/gawk"
./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-nls --without-readline
# Don't call the just-built binary...
sed -e 's#../gawk$(EXEEXT)#gawk#' -i extension/Makefile
make -j2
make install
unset ac_cv_libsigsegv
export LDFLAGS="${BASE_LDFLAGS}"
${CROSS_TC}-strip --strip-unneeded ../bin/gawk
${CROSS_TC}-strip --strip-unneeded ../lib/gawk/*.so
# Bundle it up...
tar -cvzf gawk-${KINDLE_TC}.tar.gz ../lib/gawk/*.so ../bin/gawk
cp gawk-${KINDLE_TC}.tar.gz ${SVN_ROOT}/Configs/trunk/Kindle/KUAL/gawk/extensions/gawk/data/

## cURL
#
#patch -p0 < /usr/portage/net-misc/curl/files/curl-7.18.2-prefix.patch
#patch -p1 < /usr/portage/net-misc/curl/files/curl-respect-cflags-3.patch
#patch -p1 < /usr/portage/net-misc/curl/files/curl-fix-gnutls-nettle.patch
#sed -i '/LD_LIBRARY_PATH=/d' configure.ac
#
#env LIBS="-lz -ldl" ./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --enable-shared=no --enable-static=yes --without-axtls --without-cyassl --without-gnutls --without-nss --without-polarssl --without-ssl --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt --with-ssl --without-ca-bundle --with-ca-path=/etc/ssl/certs --enable-dict --enable-file --enable-ftp --enable-gopher --enable-http --enable-imap --enable-pop3 --without-librtmp --enable-rtsp --disable-ldap --disable-ldaps --without-libssh2 --enable-smtp --enable-telnet -enable-tftp --disable-ares --enable-cookies --enable-hidden-symbols --disable-ipv6 --enable-largefile --enable-manual --enable-nonblocking --enable-proxy --disable-soname-bump --disable-sspi --disable-threaded-resolver --disable-versioned-symbols --without-libidn --without-gssapi --without-krb4 --without-spnego --with-zlib
#
#make -j2
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
#autoreconf
# pkg-config will take care of that for us...
#export ac_cv_lib_{z_compress,dl_{dlopen,shl_load}}=no
#export ac_cv_{header_pcre_h,lib_pcre_pcre_compile}=no
#export ac_cv_{header_uuid_uuid_h,lib_uuid_uuid_generate}=no
# Takes care of pulling libdl & libz for OpenSSL static
#export PKG_CONFIG="pkg-config --static"
#./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC} --disable-rpath --with-ssl=openssl --enable-opie --enable-digest --disable-iri --disable-ipv6 --disable-nls --disable-ntlm --disable-debug --with-zlib
#make -j2
#${CROSS_TC}-strip --strip-unneeded src/wget
#unset ac_cv_lib_{z_compress,dl_{dlopen,shl_load}} ac_cv_{header_pcre_h,lib_pcre_pcre_compile} ac_cv_{header_uuid_uuid_h,lib_uuid_uuid_generate} PKG_CONFIG
#
##


## TODO: Build kpdfviewer?

Build_FBGrab() {
	## FBGrab
	# libpng 1.2
	cd ..
	tar xvzf /usr/portage/distfiles/libpng-1.2.47.tar.gz
	cd libpng-1.2.47
	./configure --prefix=${TC_BUILD_DIR} --host=${CROSS_TC}
	make
	make install

	# fbgrab (doesn't handle low bitdepth fb like the eInk one on the K3...)
	cd ..
	tar xvzf /usr/portage/distfiles/fbgrab-1.0.tar.gz
	cd fbgrab-1.0
	patch -p1 < ~/fbgrab-565-fixup.patch
	${CROSS_TC}-gcc fbgrab.c ${CPPFLAGS} ${CFLAGS} ${LDFLAGS} -lpng -lz -o fbgrab
	${CROSS_TC}-strip --strip-unneeded fbgrab
}
