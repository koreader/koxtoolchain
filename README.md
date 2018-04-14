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

For ubuntu user:

```bash
sudo apt-get install gperf help2man bison texinfo flex gawk
```

Usage
-----
The build script takes platform name as its first argument. For example, to
build a cross toolchina for legacy non-touch kindle devices, type:

```
./gen-tc.sh kindlepw2
```

You can use `./gen-tc.sh -h` to get a list of supported platforms.

After the build is finished, you should be able to find your cross toolchains
under `~/x-tools` directory.
