# Installation

## Steam Workshop

The easiest way to install this mod is by subscribing to it using the Steam
Workshop: [https://steamcommunity.com/sharedfiles/filedetails/?id=1835465557][]

This way the mod can be automatically updated upon a new version release by
using the in-game **Mods** submenu.

## Manually

If you would like to install the mod manually for example on devices where you
don't have access to the [Steam Workshop][] you can:

1. Download either the **Source code** or **Workshop** version from the [Releases][] page.
2. Unpack the archive and move it to the game mods' directory.

Keep in mind, that you will need to manually update the mod each time a new
version has been released.

### Linux (Steam)

The mods' directory path on Linux installed through [Steam][]:

```text
/home/<your username>/.steam/steam/steamapps/common/Don't Starve Together/mods
```

### Windows (Steam)

The mods' directory path on Windows installed through [Steam][]:

```text
C:\Program Files (x86)\Steam\steamapps\common\Don't Starve Together\mods
```

## Makefile

_Currently, only Linux is supported. However, the Windows support is also
considered to be added either by incorporating the [CMake][] or just adding the
[NMake][] equivalent._

Since this project uses [Makefile][] it includes the rule to install the mod for
the game installed throughout [Steam][] as well:

```shell script
$ make install
```

[cmake]: https://cmake.org/
[https://steamcommunity.com/sharedfiles/filedetails/?id=1835465557]: https://steamcommunity.com/sharedfiles/filedetails/?id=1835465557
[makefile]: https://en.wikipedia.org/wiki/Makefile
[nmake]: https://msdn.microsoft.com/en-us/library/dd9y37ha.aspx
[releases]: https://github.com/victorpopkov/dst-mod-keep-following/releases
[steam workshop]: https://steamcommunity.com/app/322330/workshop/
[steam]: https://store.steampowered.com/