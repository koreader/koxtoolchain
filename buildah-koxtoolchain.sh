#!/bin/bash -e
export BUILDAH_HISTORY=true
KOX_VERSION=2021.12
HELP_MSG="\
usage: $0 PLATFORM [VERSION]
       $0 -h

PLATFORMS include any platform supported by koxtoolchain/gen-tc.sh
VERSION defaults to $KOX_VERSION if not set

-h displays this message"

if [[ -z "$1" ]]; then
    echo "$HELP_MSG"
    exit 1
elif [[ $1 == "-h" ]]; then
    echo "$HELP_MSG"
    exit 0
else
    TARGET=$1
fi

if [[ -n "$2" ]]; then
    KOX_VERSION=$2
fi


kox_builder=$(buildah from --ulimit nofile=2048:2048 ubuntu:latest)
buildah run -e DEBIAN_FRONTEND=noninteractive $kox_builder -- apt-get -y update
buildah run -e DEBIAN_FRONTEND=noninteractive $kox_builder -- apt-get -y install build-essential autoconf automake \
    bison flex gawk libtool libtool-bin libncurses-dev curl file git gperf help2man texinfo unzip wget sudo vim
buildah run $kox_builder -- useradd -p kox -G sudo kox-user
buildah config -u kox-user --workingdir /home/kox-user --entrypoint /bin/bash $kox_builder

buildah run $kox_builder -- git clone -b $KOX_VERSION https://github.com/koreader/koxtoolchain.git koxtoolchain
buildah run --workingdir /home/kox-user/koxtoolchain $kox_builder -- bash ./gen-tc.sh $TARGET
buildah run -e TARGET=$TARGET $kox_builder -- bash -c \
    'printf "source /home/kox-user/koxtoolchain/refs/x-compile.sh %s env\n" $TARGET >> .bashrc'
buildah run $kox_builder -- bash -c 'echo ". .bashrc" >> .bash_profile'
buildah run $kox_builder -- rm -rf /home/kox-user/koxtoolchain/build/

buildah config -a org.opencontainers.image.authors='Cameron Rodriguez <dev@camrod.me>' \
    -a org.opencontainers.image.title="koxtoolchain container" \
    -a org.opencontainers.image.description="Container image for KOReader cross-compile toolchain - $TARGET" \
    -a org.opencontainers.image.version=$KOX_VERSION \
    -a org.opencontainers.image.source="https://github.com/cam-rod/koxtoolchain" $kox_builder

buildah commit $kox_builder ghcr.io/cam-rod/koxtoolchain:$TARGET-$KOX_VERSION
buildah rm $kox_builder