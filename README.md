KOReader Cross Compile ToolChain
================================

Build scripts to help generate cross toolchains for various platforms supported
by KOReader.


Dependencies
------------

* gperf
* help2man
* bison
* texinfo
* flex
* gawk
* libncurses5-dev


Usage
-----
The build script takes platform name as its first argument. For example, to
build a cross toolchina for legacy non-touch kindle devices, type:

```
./gen-tc.sh kindle
```

You can use `./gen-tc.sh -h` to get a list of supported platforms.

After the build is finished, you should be able to find your cross toolchains
under `~/x-tools` directory.
