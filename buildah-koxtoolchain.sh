#!/bin/bash -e
export BUILDAH_HISTORY=true
KOX_VERSION=2021.12
HELP_MSG="\
usage: $0 PLATFORM [VERSION]
       $0 -h/--help

PLATFORMS any platform supported by koxtoolchain (run \`./gen-tc.sh -h\` to list platforms)
VERSION defaults to $KOX_VERSION if not set
-h/--help displays this message"

if [[ -z "$1" ]]; then
    echo "$HELP_MSG"
    exit 1
elif [[ $1 == "-h" || $1 == "--help" ]]; then
    echo "$HELP_MSG"
    exit 0
else
    TARGET=$1
fi

if [[ -n "$2" ]]; then
    KOX_VERSION=$2
fi


# Dependencies
kox_builder=$(buildah from --ulimit nofile=2048:2048 ubuntu:latest)
buildah run -e DEBIAN_FRONTEND=noninteractive "$kox_builder" -- apt-get -y update
buildah run -e DEBIAN_FRONTEND=noninteractive "$kox_builder" -- apt-get -y install build-essential autoconf automake \
    bison flex gawk libtool libtool-bin libncurses-dev curl file git gperf help2man texinfo unzip wget sudo
buildah copy "$kox_builder" entrypoint.sh /entrypoint.sh

# Create kox user (password: kox)
buildah run "$kox_builder" -- useradd -G sudo kox
buildah run "$kox_builder" -- bash -c 'echo "kox:kox" | chpasswd'
buildah run "$kox_builder" -- mkdir -p /home/kox/build
buildah config --workingdir /home/kox "$kox_builder"

# Compile and install koxtoolchain
buildah run "$kox_builder" -- git clone -b "$KOX_VERSION" "https://github.com/koreader/koxtoolchain.git" koxtoolchain
buildah run "$kox_builder" -- chown -R kox:kox /home/kox
buildah config -u kox "$kox_builder" 
buildah run --workingdir /home/kox/koxtoolchain "$kox_builder" -- bash ./gen-tc.sh "$TARGET"
# shellcheck disable=SC2016
buildah run -e "TARGET=$TARGET" "$kox_builder" -- bash -c \
    'echo "source /home/kox/koxtoolchain/refs/x-compile.sh $TARGET env" >> .bashrc'
buildah run "$kox_builder" -- bash -c 'echo ". .bashrc" >> .bash_profile'
buildah run "$kox_builder" -- rm -rf /home/kox/koxtoolchain/build/

# Image configuration for GHCR, set working directory
buildah config -a org.opencontainers.image.authors='Cameron Rodriguez <dev@camrod.me>' \
    -a org.opencontainers.image.title="koxtoolchain container" \
    -a org.opencontainers.image.description="Container image for KOReader cross-compile toolchain" \
    -a org.opencontainers.image.version="$KOX_VERSION" \
    -a org.opencontainers.image.source="https://github.com/koreader/koxtoolchain/tree/container" \
    -a org.opencontainers.image.licenses="AGPL-3.0-or-later" \
    --workingdir /home/kox/build -u root --entrypoint '["/bin/bash", "/entrypoint.sh"]' --cmd '/bin/bash' \
    "$kox_builder"

# Create main and timestamped images
buildah commit "$kox_builder" "ghcr.io/koreader/koxtoolchain:$TARGET-$KOX_VERSION"
buildah tag "ghcr.io/koreader/koxtoolchain:$TARGET-$KOX_VERSION" "ghcr.io/koreader/koxtoolchain:$TARGET-latest"
buildah rm "$kox_builder"