Prebuilt versions of the toolchains.

To use them, download the appropriate archive and unpack it in your `${HOME}`,
so that the toolchain ends up in (here, for `kindlepw2`)
 `${HOME}/x-tools/arm-kindlepw2-linux-gnueabi`.  Then add `${HOME}/x-tools/*/bin`
to your `PATH`.

The `x-compile.sh` script included in this repo can do that (and more) for you.
Using `kindlepw2` as an example toolchain again:
- if you need a persistent custom sysroot (e.g., if you intend to build a full dependency chain):
`source ${PWD}/refs/x-compile.sh kindlepw2 env`
- if you just need a compiler:
`source ${PWD}/refs/x-compile.sh kindlepw2 env bare`
