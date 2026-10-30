# mod-keep-following

[![CI]](https://github.com/dstmodders/mod-keep-following/actions/workflows/ci.yml?query=branch%3Av0.21)
[![CD]](https://github.com/dstmodders/mod-keep-following/actions/workflows/cd.yml?query=branch%3Av0.21)
[![Codecov]](https://codecov.io/gh/dstmodders/mod-keep-following/branch/v0.21)

[![Keep Following](preview.gif)](https://steamcommunity.com/sharedfiles/filedetails/?id=1835465557)

## Overview

Mod for the game [Don't Starve Together] which is available through the
[Steam Workshop] and allows players to follow/push others or one of the
supported entities.

| Default Keys                                        | Actions                                        |
| --------------------------------------------------- | ---------------------------------------------- |
| <kbd>Shift</kbd> + <kbd>LMB</kbd>                   | to keep following                              |
| <kbd>Shift</kbd> + <kbd>Ctrl</kbd> + <kbd>LMB</kbd> | to keep pushing and ignore the target distance |

To stop following use <kbd>WASD</kbd> movement keys, <kbd>Space</kbd> (in-game
action key) or click <kbd>LMB</kbd>.

You can also use the above key combinations on a Tent/Siesta Lean-to used by
another player to keep following or pushing him.

## Configuration

Don't like the default behaviour? Choose your own configuration to match your
needs:

| Configuration               | Default       | Description                                                           |
| --------------------------- | ------------- | --------------------------------------------------------------------- |
| **Action key**              | _Shift_       | Key used for both following and pushing                               |
| **Push key**                | _Ctrl_        | Key used in combination with an action key for pushing                |
| **Compatibility**           | _Recommended_ | Which compatibility mode should be used?                              |
| **Follow method**           | _Default_     | Which follow method should be used?                                   |
| **Follow distance**         | _2.5m_        | How close can you approach the leader?                                |
| **Follow distance keeping** | _No_          | Should the follower keep the distance from the leader?                |
| **Push with RMB**           | _No_          | Should the RMB in combination with an action key be used for pushing? |
| **Push mass checking**      | _Yes_         | Should the mass difference checking be enabled?                       |
| **Push lag compensation**   | _Yes_         | Should the lag compensation be automatically disabled while pushing?  |
| **Hide changelog**          | _Yes_         | Should the changelog in the mod description be hidden?                |
| **Debug**                   | _No_          | Should the debug mode be enabled?                                     |

## Documentation

The [LDoc] documentation generator has been used for generating documentation,
and the most recent version can be found here:
https://docs.dstmodders.com/keep-following/v0.21/

## License

Released under the [MIT License](https://opensource.org/licenses/MIT).

[cd]: https://img.shields.io/github/actions/workflow/status/dstmodders/mod-keep-following/cd.yml?branch=v0.21&label=cd&logo=github
[ci]: https://img.shields.io/github/actions/workflow/status/dstmodders/mod-keep-following/ci.yml?branch=v0.21&label=ci&logo=github
[codecov]: https://img.shields.io/codecov/c/github/dstmodders/mod-keep-following/v0.21?logo=codecov&label=codecov
[don't starve together]: https://www.klei.com/games/dont-starve-together
[ldoc]: https://stevedonovan.github.io/ldoc/
[steam workshop]: https://steamcommunity.com/sharedfiles/filedetails/?id=1835465557
