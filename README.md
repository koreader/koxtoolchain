# KOReader Cross Compile ToolChains

Build scripts to help generate cross ToolChains for various platforms supported by KOReader.


## Dependencies

* gperf
* help2man
* bison
* texinfo
* flex
* gawk

## For Ubuntu users:

```bash
sudo apt-get install gperf help2man bison texinfo flex gawk
```

## Usage

The build script takes a platform name as its first argument.
For example, to build a cross toolchain for legacy non-touch kindle devices, type:

```
./gen-tc.sh kindle
```

You can use `./gen-tc.sh -h` to get a list of supported platforms.

After the build is finished, you should be able to find your cross ToolChains under the `~/x-tools` directory.

## Notes

Due to a whole lot of legacy baggage, the names of the various Kindle TCs may be slightly confusing (especially compared to KOReader's target names), so, let's disambiguate that:

|     TC    |       Supported Devices       |     Target    |
|:---------:|:-----------------------------:|:-------------:|
|   kindle  |      Kindle 2, DX, DXg, 3     | kindle-legacy |
|  kindle5  |      Kindle 4, Touch, PW1     |     kindle    |
| kindlepw2 | Kindle PW2 & everything since |   kindlepw2   |

No such worries on Kobo & Cervantes, though ;).
