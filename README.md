# Sidebar Icons

A small macOS utility, built from source, that gives folders in Finder's sidebar Favorites their
own icons. Pick a folder and a style, and that Favorite shows your icon instead of the generic
folder glyph:

- **System glyph**: any SF Symbol, drawn outline blue like the system's own Favorites.
- **Custom glyph**: your own drawing, drawn the same way (needs Xcode).
- **Full colour**: a PDF, PNG or SVG image, as in 0.1.0 and 0.2.0.

Optionally, a folder you opt in also gets matching full-colour art as its own icon in Finder
windows. One app can manage any number of folders.

> [!IMPORTANT]
> **This utility relies on undocumented macOS behavior.** macOS has no public API for setting a
> sidebar icon, so the app uses deprecated and undocumented Launch Services behavior. Every such use is listed, with its risks and how to undo it, in
> **[PRIVATE_API.md](PRIVATE_API.md)**. Read it before building or running the utility.

## Status

**Version 0.3.0, icon groups**: system and custom glyphs and opt-in folder icons, on top of
0.1.0's add, turn off, change, remove, preview, refresh and reset. The live checks P-1, T034 and
P-2 passed on macOS 27.2.1 (26B131); see the [004 tasks](specs/004-icon-groups/tasks.md) for
what is left before the release. What 1.0.0 still needs is the "1.0.0 gate" in the [002
tasks](specs/002-mapping-manager-v1/tasks.md); changes are in [CHANGELOG.md](CHANGELOG.md).

> [!NOTE]
> **Upgrading from 0.2.0**: 0.3.0 doesn't convert 0.2.0's mappings. It shows that the
> configuration was made by 0.2.0 and changes nothing until you click **Reset All…**, which undoes
> 0.2.0's changes; then add your folders again.

| Feature | State |
|---------|-------|
| [001 Sidebar icon spike](specs/001-sidebar-icon-spike/spec.md) | Done; chose Path B (Launch Services override), no extension, app not sandboxed. Retired |
| [002 Mapping manager v1](specs/002-mapping-manager-v1/spec.md) | Done, verified on 26B131; follow-ups in [tasks](specs/002-mapping-manager-v1/tasks.md) |
| [004 Icon groups](specs/004-icon-groups/spec.md) | Built; P-1, T034 and P-2 verified on 26B131; appearance check and release pending ([tasks](specs/004-icon-groups/tasks.md)) |

## Design principles

The full rules are in the [constitution](.specify/memory/constitution.md). In short:

- **Inspectable and boring**: Apple frameworks only, plus Xcode's asset tool when you make a
  custom glyph. No networking, telemetry, updater, daemon, login item, privileged helper, root
  access, or third-party code.
- **Public API first**: undocumented behavior is used only when an experiment shows the public
  route cannot do the job, and it is isolated in one adapter.
- **Your folders are not modified**: the utility never renames, moves or deletes a folder or
  changes its contents. The one exception is a folder's own Finder icon, and only for a folder you
  opt in: the icon is recorded first, any icon it had is kept, and Off, Remove and Reset All put it
  back while it is still the one the app set. Removing a mapping otherwise removes only the
  utility's own settings.
- **Everything is reversible**: changes outside the utility happen only when you ask, are recorded
  first, and are undone by Reset.
- **Private API use is public**: see [PRIVATE_API.md](PRIVATE_API.md).

## Requirements

- macOS 27 or later.
- Xcode 27.2 or later, to build the app. To make **custom glyphs**, Xcode must also be installed
  and selected (`xcode-select -p` shows a path inside `Xcode.app`) and opened once; the Command
  Line Tools alone don't include the asset tool. System glyphs, full colour and folder icons work
  without it.
- An Apple Developer team for code signing. The app stores its data in an App Group container,
  whose identifier must use your team ID prefix (set `DEVELOPMENT_TEAM` in the project).

## Building and running

```bash
cd Packages/SidebarIconCore && swift test
```

```bash
xcodebuild -project app/sidebar-icons.xcodeproj -scheme sidebar-icons -configuration Debug build
```

Or open `app/sidebar-icons.xcodeproj` in Xcode and run the **sidebar-icons** scheme. The built app
is `sidebar-icons.app`; file and command names have no spaces, and the app itself shows its
name as "Sidebar Icons".

Using it:

1. Make sure the folder is in Finder's sidebar Favorites (drag it there).
2. **Add Folder…** and pick the folder. Choose a style:
   - **System glyph**: type or pick an SF Symbol name; the preview shows it in light and dark.
   - **Custom glyph**: pick a glyph you made (below).
   - **Full colour**: pick a PDF, PNG or SVG image.

   Click **Apply**. The icon appears in a few seconds; if it doesn't, click **Refresh Finder…**.
3. Each row has an On/Off switch; right-click a row for **Change Icon…**, **Folder Icon…**,
   **Remove…** and **Re-point…**.

**Custom glyphs.** On the **Custom glyph** tab, **New Custom Glyph…** opens a wizard: it checks
for Xcode, asks for a name and an outline drawing (an SVG of filled shapes), and can take folder
art too. It previews the glyph at sidebar size and builds it. **Import Glyph…** takes a symbol
template you made yourself. [icon-specification.md](specs/004-icon-groups/icon-specification.md)
says what to draw and has the manual process.

**Folder icons.** **Folder Icon…** sets full-colour art (a square PNG of at least 1024 pixels, a
PDF or an SVG, with optional hand-tuned small sizes or an `.iconset`) as the folder's own Finder
icon. This adds a hidden file named `Icon` to the folder, which git shows as untracked and sync
services copy. If the folder already has a custom icon, the app asks before replacing it and
keeps the old one to put back. If something else changes the icon later, the app leaves it alone.

The [004 quickstart](specs/004-icon-groups/quickstart.md) has the manual checklist.

## Installing on another Mac

Release builds are signed with Developer ID and notarized, so they open on any Mac running macOS 27.
The first time, macOS still asks for the usual confirmation for an app downloaded or copied from
elsewhere. To make one (needs the Developer ID Application certificate and a notarytool
keychain profile named in a git-ignored `Secrets.xcconfig` as `NOTARY_PROFILE = <profile>`):

```bash
scripts/release.sh all
```

It runs `check`, `build`, `notarize` and `verify`, and leaves
`build.noindex/release/<version>/sidebar-icons-<version>.zip`. Copy that zip to the other Mac and
double-click it: it unpacks to a folder with **sidebar-icons.app**, `LICENSE` and `PRIVATE_API.md`.
Move **sidebar-icons.app** to `/Applications`, and open it. On a macOS build other
than the verified one, the window shows a non-blocking warning banner.

Anyone without the Developer ID certificate can still build and run the Debug configuration from
Xcode.

## Undoing everything

1. In the app, click **Reset All…** and confirm. Every Favorite goes back to its normal icon,
   folder icons the app set go back to what they were, and the app's mappings, copied images,
   glyphs and Launch Services registrations are removed.
2. Quit the app, delete `sidebar-icons.app` (0.2.0 and earlier: `Sidebar Icons.app`), and delete its container,
   `~/Library/Group Containers/<team>.com.altmansoftwaredesign.sidebaricons`.
3. Optionally delete what macOS kept for it (no user data):
   - `~/Library/Preferences/com.altmansoftwaredesign.sidebaricons.plist` (window positions);
   - the `~/Library/Application Scripts/` folders whose names contain
     `com.altmansoftwaredesign.sidebaricons`;
   - the cache folder `$(getconf DARWIN_USER_CACHE_DIR)com.altmansoftwaredesign.sidebaricons`;
   - privacy decisions, if macOS asked about a folder:
     `tccutil reset All com.altmansoftwaredesign.sidebaricons`;
   - if you ran the spike: `~/Library/Containers/com.altmansoftwaredesign.sidebaricons` and
     `~/Library/Containers/com.altmansoftwaredesign.sidebaricons.findersync`.

   The full list is in the [004 data model](specs/004-icon-groups/data-model.md#files-the-utility-writes-constitution-i-complete-list).

Apart from opted-in folder icons, which Reset All puts back, your folders are never changed. See [PRIVATE_API.md](PRIVATE_API.md) for manual fallbacks.

## The retired spike

`spike/` holds the feasibility spike app. It shares the app's container and change ledger, so
**never run the spike and the app at the same time**, and click **Reset All** in the app before
running the spike: the spike's Apply only knows its own mappings and clears the app's icons. It is kept only to re-run the experiments on
a new macOS build ([spike quickstart](specs/001-sidebar-icon-spike/quickstart.md)).

## How this project is planned

The project uses [Spec Kit](https://github.com/github/spec-kit) for spec-driven development:

- `.specify/memory/constitution.md`: project principles and quality gates.
- `specs/NNN-feature/`: spec, plan, research, data model, contracts, quickstart, and tasks for
  each feature.
- [Finder_Sidebar_Custom_Icons_Utility.md](Finder_Sidebar_Custom_Icons_Utility.md): the original
  design notes the specs were built from.

## License

[MIT](LICENSE)
