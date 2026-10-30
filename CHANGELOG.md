# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.21.1] - 2026-10-31

### Fixed

- Fix built-in character actions changing

## [0.21.0] - 2020-08-26

### Added

- Add "Compatibility" configuration

### Changed

- Change following configurations
- Improve interruptions behaviour
- Improve keybinds configurations
- Improve mouse overrides

## [0.20.1] - 2020-08-25

### Fixed

- Fix issue with `TEST` global

## [0.20.0] - 2020-08-25

### Added

- Add "Hide Changelog" configuration
- Add tests and documentation

### Changed

- Refactor most of the existing code
- Split configuration into sections

### Removed

- Remove "Mobs" configuration in favour of the "All" behaviour

## [0.19.0] - 2019-10-04

### Changed

- Change mod icon
- Improve compatibility with some other mods
- Improve debug output

### Removed

- Remove pushing support for birds

### Fixed

- Fix `PlayerActionPicker:DoGetMouseActions()` override

## [0.18.0] - 2019-09-27

### Added

- Add support for `BLINK`, `EQUIP` and `READ` interruptions
- Add support for pushing interruptions

### Changed

- Improve the following behaviour

### Fixed

- Fix issue forcing original actions in some cases
- Fix pausing behaviour related to following interruptions

## [0.17.0] - 2019-09-23

### Changed

- Improve debug output
- Improve leader approaching behaviour in the default mode
- Improve the target distance calculation
- Optimize requests while following

### Fixed

- Fix following interruptions when lag compensation is off
- Fix jumping on/off a boat issues while following

## [0.16.0] - 2019-09-21

### Added

- Add support for the following interruptions

### Fixed

- Fix client/server position mismatch during interruptions
- Fix some movement issues when lag compensation is off

## [0.15.0] - 2019-09-21

### Added

- Add "Following Method" configuration
- Add "Push Mass Checking" configuration

### Changed

- Improve the pathfinding precision

### Fixed

- Fix selection issue with ActionQueue Reborn

## [0.14.0] - 2019-09-20

### Added

- Add support for pushing players as a ghost

### Changed

- Improve compatibility with some other mods
- Improve debug output

### Removed

- Remove pending tasks in favour of the custom threads

### Fixed

- Fix keeping the target distance behaviour

## [0.13.0] - 2019-09-17

### Added

- Add support for "Balloon" when "Mobs" is set to "All"

### Changed

- Improve clicking behaviour

### Removed

- Remove pushing support for "Shadow Creatures"

### Fixed

- Fix actions not showing on dedicated when "Mobs" is set to "All"
- Fix distance calculation between follower and leader

## [0.12.0] - 2019-09-16

### Added

- Add "Mobs" configuration
- Add stopping on `CONTROL_ACTION`
- Add support for all known mobs

### Changed

- Rename configuration `pushing_lag_compensation` to `push_lag_compensation`

### Fixed

- Fix actions not showing in "Woodie's Weregoose" form
- Fix actions not showing when a player becomes a ghost

## [0.11.0] - 2019-09-06

### Added

- Add support for "Beefalo/Baby Beefalo"

### Fixed

- Fix an action not showing when "Push with RMB" is enabled
- Fix behaviour when the leader doesn't exist anymore

## [0.10.0] - 2019-09-05

### Changed

- Improve debug output
- Improve mod icon quality
- Improve the pushing lag compensation behaviour

### Fixed

- Fix lag compensation state restoration after pushing

## [0.9.0] - 2019-08-25

### Added

- Add support for "Balloon"
- Add support for pushing lag compensation
- Add support for pushing with RMB

### Changed

- Improve debug output

## [0.8.0] - 2019-08-23

### Added

- Add support for more animals

### Changed

- Change mod icon
- Improve compatibility with some other mods
- Improve debug output

## [0.7.0] - 2019-08-22

### Added

- Add support for "Abigail" and "Big Bernie"
- Add support for "Catcoon", "Koalefant", "Volt Goat" and "Mosling"
- Add support for stopping following/pushing on LMB click

## [0.6.0] - 2019-08-20

### Added

- Add "Keep Target Distance" configuration
- Add support for "Bunnymen"

### Changed

- Improve compatibility with some other mods
- Revert "Action Key" and "Push Key" configurations

## [0.5.0] - 2019-08-19

### Added

- Add "Action Key" and "Push Key" configurations

### Changed

- Change default action and push keys

### Fixed

- Fix crash when entering/leaving a cave

## [0.4.0] - 2019-08-19

### Added

- Add actions: `FOLLOW`, `PUSH`, `TENTFOLLOW` and `TENTPUSH`
- Add support for disabled lag compensation

### Changed

- Move input handlers into modmain
- Separate follow and push behaviours

### Fixed

- Fix crash when lag compensation has been turned off

## [0.3.0] - 2019-08-18

### Added

- Add support for following/pushing a Tent sleeper
- Add support for pushing

## [0.2.0] - 2019-08-17

### Removed

- Remove leader initialization if a leader didn't change

### Fixed

- Fix delay after approaching a leader
- Fix delay before following a new leader

## 0.1.0 - 2019-08-15

First release.

[unreleased]: https://github.com/dstmodders/mod-keep-following/compare/v0.21.1...HEAD
[0.21.1]: https://github.com/dstmodders/mod-keep-following/compare/v0.21.0...v0.21.1
[0.21.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.20.1...v0.21.0
[0.20.1]: https://github.com/dstmodders/mod-keep-following/compare/v0.20.0...v0.20.1
[0.20.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.19.0...v0.20.0
[0.19.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.18.0...v0.19.0
[0.18.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.17.0...v0.18.0
[0.17.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/dstmodders/mod-keep-following/compare/v0.1.0...v0.2.0
