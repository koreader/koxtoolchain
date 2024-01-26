# KOReader Cross Compile ToolChains

Build scripts to help generate cross ToolChains for various platforms supported by KOReader.


## Dependencies

* git
* ncurses
* gperf
* help2man
* bison
* texinfo
* flex
* gawk
* unzip

## For Arch users:
```bash
sudo pacman -S base-devel curl git gperf help2man unzip wget
```

## For Debian/Ubuntu users:

```bash
sudo apt-get install build-essential autoconf automake bison flex gawk libtool libtool-bin libncurses-dev curl file git gperf help2man texinfo unzip wget
```

## Usage

The build script takes a platform name as its first argument.
For example, to build a cross toolchain for legacy non-touch kindle devices, type:

```
./gen-tc.sh kindle
```

You can use `./gen-tc.sh -h` to get a list of supported platforms.

After the build is finished, you should be able to find your cross ToolChains under the `~/x-tools` directory.

The [reference script](/refs/x-compile.sh) can be used to automatically setup a cross-compilation environment (`PATH`, `*FLAGS` & all that jazz), as mentioned at the end of a TC build.  
For example, for a Kobo TC:
```shell
source refs/x-compile.sh kobo env
```

## Container image

You can also use a container with the precompiled toolchain. Pull the relevant image from the [GitHub Container Registry](https://ghcr.io/koreader/koxtoolchain). Alternatively, build the image locally using the [source script](./buildah-koxtoolchain.sh) (requires [Buildah](https://buildah.io/), run `./buildah-koxtoolchain.sh -h` for instructions).

To use the containerized toolchain (for example, Kobo):

```bash
podman pull ghcr.io/koreader/koxtoolchain:kobo-latest
podman run --rm -it -v <source_folder>:/home/kox/build koxtoolchain:kobo-latest
  
kox@containerID$ <build_command>
```

For systems with SELinux enforcing (ex. Fedora), use this launch command instead:

```bash
podman run --rm -it -v <source_folder>:/home/kox/build:z koxtoolchain:kobo-latest
```

## Notes

Due to a whole lot of legacy baggage, the names of the various Kindle TCs may be slightly confusing (especially compared to KOReader's target names), so, let's disambiguate that:

|     TC    |       Supported Devices       |     Target    |
|:---------:|:-----------------------------:|:-------------:|
|   kindle  |      Kindle 2, DX, DXg, 3     | kindle-legacy |
|  kindle5  |      Kindle 4, Touch, PW1     |     kindle    |
| kindlepw2 | Kindle PW2 & everything since |   kindlepw2   |

No such worries on Kobo & Cervantes, though ;).  

The nickel TC is a Kobo variant that mimics Kobo's own TC (as of FW >= 4.6). It is *not* recommended for general purpose stuff, only use it if you have a specific need for it (which should essentially be limited to working with Kobo's nickel, or Kobo's kernels).

The pocketbook TC aims for maximum backward compatibility while still keeping inkview support.

The remarkable TC aims for FW >= 2.x compatibility.

The bookeen TC has only been tested on AWA13 devices, but *should* theoretically handle OMAP3611 ones, too.

## Known Issues

Only actively tested on Linux hosts.  
May work on macOS with some efforts, if you follow crosstool-ng's recommendations on the subject. This is only bound to get worse.  
May work on Windows with even more efforts, but I wouldn't bother.  
When in doubt, use a Debian VM.

<!-- kate: indent-mode cstyle; indent-width 4; replace-tabs on; remove-trailing-spaces none; -->
