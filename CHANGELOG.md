# Changelog

All notable changes to Sidebar Icons. Versions follow [Semantic Versioning](https://semver.org/);
before 1.0.0, any release may change how the app stores its data.

## [0.2.0] - 2026-11-22

First build for use on other Macs: signed with Developer ID, notarized by Apple and stapled.

### Changed

- **Breaking**: the bundle ID and App Group are now lowercase
  (`com.altmansoftwaredesign.sidebaricons`). On a case-insensitive disk (the macOS default) the
  container folder is the same one, so 0.2.0 would pick up 0.1.0's mappings and records under a
  different app identity. If you ran 0.1.0, click Reset All in it before installing 0.2.0, then
  delete its container (`~/Library/Group Containers/45GJWJVQN2.com.altmansoftwaredesign.SidebarIcons`).

### Added

- `scripts/release.sh`: builds the Release app signed with Developer ID (hardened runtime, secure
  timestamp, App Group as the only entitlement), notarizes and staples it, and checks that a
  quarantined copy passes Gatekeeper. The result is a zip to copy to another Mac.

## [0.1.0] - 2026-11-22

First usable version: feature 002, Sidebar Icons v1. Verified on macOS 27.2.1 (26B131).

### Added

- Add a Finder sidebar Favorite with a PDF, PNG or SVG image; the app keeps its own copy, and
  the Favorite shows the image in full colour within seconds (Story 1).
- Turn a mapping on or off, change its icon, remove it, or re-point it at a moved folder
  (Story 2).
- Preview an image at sidebar size in light and dark before applying it, with a warning for
  non-square or very detailed images (Story 3).
- Refresh Finder, and Reset All, which undoes every change the app made and deletes its data
  (Story 4).
- A banner on macOS builds the mechanism hasn't been verified on.

### Known limitations

- Relies on undocumented macOS behavior; see [PRIVATE_API.md](PRIVATE_API.md).
- Built from source and run as a Debug build; no Release or Developer ID build yet.
- The bundle ID and App Group will change to lowercase before 1.0.0, which moves the app's data.
  Run Reset All before upgrading across that change.
- Open follow-ups are in [specs/002-mapping-manager-v1/tasks.md](specs/002-mapping-manager-v1/tasks.md);
  the ones required for 1.0.0 are listed there under "1.0.0 gate".

[0.2.0]: https://github.com/inquinity/sidebar-icon/releases/tag/v0.2.0
[0.1.0]: https://github.com/inquinity/sidebar-icon/releases/tag/v0.1.0
