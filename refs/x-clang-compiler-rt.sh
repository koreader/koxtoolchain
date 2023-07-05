#!/bin/bash -ex
#
# Companion script to x-compile compiler-rt for Clang experiments
#
# $Id: x-clang-compiler-rt.sh 19004 2022-12-25 17:22:43Z NiLuJe $
#
# kate: syntax bash;
#
##

SVN_ROOT="${HOME}/SVN"
## Remember where we are... (c.f., https://stackoverflow.com/questions/9901210/bash-source0-equivalent-in-zsh)
SCRIPT_NAME="${BASH_SOURCE[0]-${(%):-%x}}"
SCRIPTS_BASE_DIR="$(readlink -f "${SCRIPT_NAME%/*}")"

# First, we'll need the right env (i.e., Clang + gcc-toolchain)
# NOTE: Hardcoded to Kobo because that's what I care about ;).
. ${SCRIPTS_BASE_DIR}/x-compile.sh kobo env clang-gcc

# We'll need the sources...
# emerge -1 -f sys-libs/compiler-rt

# Setup parallellization... Shamelessly stolen from crosstool-ng ;).
AUTO_JOBS=$(($(getconf _NPROCESSORS_ONLN 2> /dev/null || echo 0) + 1))
JOBSFLAGS="-j${AUTO_JOBS}"

## Get to our build dir
mkdir -p "${TC_BUILD_DIR}"
cd "${TC_BUILD_DIR}"

# c.f., https://llvm.org/docs/HowToCrossCompileBuiltinsOnArm.html
CLANG_VERSION="15.0.6"
tar xvJf /usr/portage/distfiles/llvm-project-${CLANG_VERSION}.src.tar.xz
cd llvm-project-${CLANG_VERSION}.src
tar xvJf /usr/portage/distfiles/llvm-gentoo-patchset-${CLANG_VERSION}.tar.xz
for patch in llvm-gentoo-patchset-15.0.6/* ; do
	patch -p1 < "${patch}"
done
cd compiler-rt
mkdir build
cd build
# NOTE: Install path is the *live* Clang installation from the host (Gentoo paths)!
#       That's mainly because I can't be arsed to figure out how to tel lld to go look elsewhere for those.
cmake .. -G Ninja \
	-DCOMPILER_RT_INSTALL_PATH="/usr/lib/clang/${CLANG_VERSION}" \
	-DCMAKE_BUILD_TYPE=RelWithDebInfo \
	-DCOMPILER_RT_INCLUDE_TESTS=OFF \
	-DCOMPILER_RT_BUILD_BUILTINS=ON \
	-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
	-DCOMPILER_RT_BUILD_XRAY=OFF \
	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	-DCOMPILER_RT_BUILD_MEMPROF=OFF \
	-DCOMPILER_RT_BUILD_ORC=OFF \
	-DCOMPILER_RT_BUILD_PROFILE=OFF \
	-DCMAKE_C_COMPILER=$(command -v clang) \
	-DCMAKE_AR=$(command -v llvm-ar) \
	-DCMAKE_NM=$(command -v llvm-nm) \
	-DCMAKE_RANLIB=$(command -v llvm-ranlib) \
	-DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld" \
	-DCMAKE_C_COMPILER_TARGET="${CROSS_TC}" \
	-DCMAKE_ASM_COMPILER_TARGET="${CROSS_TC}" \
	-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
	-DLLVM_CONFIG_PATH=$(command -v llvm-config) \
	-DCMAKE_C_FLAGS="${CFLAGS}" \
	-DCMAKE_ASM_FLAGS="${CFLAGS}"
ninja -v
# NOTE: That's not particularly great, but, eh, I won't whine too much for three files with very specific filenames ;).
sudo ninja -v install
