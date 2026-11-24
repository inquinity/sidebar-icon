# Changelog

All notable changes to Sidebar Icons. Versions follow [Semantic Versioning](https://semver.org/);
before 1.0.0, any release may change how the app stores its data.

## [0.3.0] - 2026-11-24

Icon groups (feature 004): sidebar Favorites can now look like the system's own, outline blue in
the accent colour, and a folder can opt in to matching full-colour art in Finder windows.
Verified on macOS 27.2.1 (26B131).

### Added

- **System glyphs**: any SF Symbol name as a Favorite's icon, with search and a live preview at
  sidebar size in light and dark.
- **Custom glyphs**, drawn like SF Symbols. They need Xcode (its asset tool).
  - **New Custom Glyph…** opens a wizard: it checks for Xcode, takes a name and an outline SVG of
    filled shapes, shows warnings and a preview, and builds the glyph.
  - **Import Glyph…** takes a symbol template you made yourself, with
    `swift run make-symbol-template` or the SF Symbols app (the manual process in
    `specs/004-icon-groups/icon-specification.md`).
  - Importing again under the same name updates every Favorite that uses it, without restarting
    Finder.
- **Folder icons** (opt in per folder, **Folder Icon…**). Full-colour art becomes the folder's own
  Finder icon:
  - the master is a square PNG of at least 1024 pixels, a PDF or an SVG; hand-tuned small sizes
    (PNGs or an `.iconset`) are optional;
  - an existing custom icon is replaced only after you confirm, and it is kept to put back;
  - Off, Remove and Reset All restore the folder's earlier icon, unless something else has
    changed it since;
  - the icon follows a re-pointed folder.

### Changed

- **Breaking**: the configuration is schema 2, and 0.2.0's mappings are not converted. 0.3.0
  says the configuration was made by 0.2.0 and changes nothing until you click Reset All, which
  undoes 0.2.0's changes. Then add your folders again.
- The Launch Services registry is versioned (`IconRegistry-<hash>.app`), with a new bundle for
  each change, because Finder caches a bundle's glyphs by its path. Reset All removes every
  version.
- Full colour is still supported as the legacy style.
- File and command names have no spaces: the app is `sidebar-icons.app` (executable
  `sidebar-icons`), built from `app/sidebar-icons.xcodeproj` with the `sidebar-icons` scheme, and
  the release zip is `sidebar-icons-<version>.zip`. The app still shows its name as "Sidebar
  Icons", and its bundle ID and App Group are unchanged, so its data and permissions carry over.
  Delete the old `Sidebar Icons.app` after installing.

### Known limitations

- Relies on undocumented macOS behavior; see [PRIVATE_API.md](PRIVATE_API.md).
- **Going back to 0.2.0**: 0.2.0 can't read 0.3.0's configuration or its folder-icon records.
  Click Reset All in 0.3.0 before installing 0.2.0 again.
- Custom glyphs need Xcode installed and selected, and a `Regular-M` glyph made of filled shapes;
  strokes are refused. A drawing much wider than tall is scaled down to fit and looks small.
- A restored folder icon looks the same as before but is re-encoded, so sync services copy it
  again.
- The folder's hidden `Icon` file shows as untracked in git while a folder icon is set.

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

[0.3.0]: https://github.com/inquinity/sidebar-icon/releases/tag/v0.3.0
[0.2.0]: https://github.com/inquinity/sidebar-icon/releases/tag/v0.2.0
[0.1.0]: https://github.com/inquinity/sidebar-icon/releases/tag/v0.1.0
