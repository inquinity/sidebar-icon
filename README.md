# Sidebar Icons

A small macOS utility, built from source, that gives folders in Finder's sidebar Favorites their
own custom icons. Pick a folder, pick an image, and that Favorite shows your icon instead of the
generic folder glyph. One app can manage any number of folders.

> [!IMPORTANT]
> **This utility relies on undocumented macOS behavior.** macOS has no public API for setting a
> sidebar icon, so the app uses deprecated and undocumented Launch Services behavior. Every such use is listed, with its risks and how to undo it, in
> **[PRIVATE_API.md](PRIVATE_API.md)**. Read it before building or running the utility.

## Status

**The Sidebar Icons app works on macOS 27.2.1 (26B131)**: add, turn off, change and remove
per-folder sidebar icons, preview them first, refresh Finder, and reset everything. The final
verification (light/dark and accent colour, 20 mappings across logout and reboot, leftover audit)
is still open.

| Feature | State |
|---------|-------|
| [001 Sidebar icon spike](specs/001-sidebar-icon-spike/spec.md) | Done; chose Path B (Launch Services override), no extension, app not sandboxed. Retired |
| [002 Mapping manager v1](specs/002-mapping-manager-v1/spec.md) | Stories 1–4 built and checked in Finder; final verification open ([tasks](specs/002-mapping-manager-v1/tasks.md)) |

## Design principles

The full rules are in the [constitution](.specify/memory/constitution.md). In short:

- **Inspectable and boring**: Apple frameworks only. No networking, telemetry, updater, daemon,
  login item, privileged helper, root access, or third-party code.
- **Public API first**: undocumented behavior is used only when an experiment shows the public
  route cannot do the job, and it is isolated in one adapter.
- **Your folders are never modified**: the utility never renames, moves, deletes, or re-icons a
  folder. Removing a mapping removes only the utility's own settings.
- **Everything is reversible**: changes outside the utility happen only when you ask, are recorded
  first, and are undone by Reset.
- **Private API use is public**: see [PRIVATE_API.md](PRIVATE_API.md).

## Requirements

- macOS 27 or later.
- Xcode 27.2 or later.
- An Apple Developer team for code signing. The app stores its data in an App Group container,
  whose identifier must use your team ID prefix (set `DEVELOPMENT_TEAM` in the project).

## Building and running

```bash
cd Packages/SidebarIconCore && swift test
```

```bash
xcodebuild -project app/SidebarIcons.xcodeproj -scheme "Sidebar Icons" -configuration Debug build
```

Or open `app/SidebarIcons.xcodeproj` in Xcode and run the **Sidebar Icons** scheme.

Using it:

1. Make sure the folder is in Finder's sidebar Favorites (drag it there).
2. **Add Folder…**, pick the folder, then a PDF, PNG or SVG image. Check the preview and click
   **Apply**. The icon appears in a few seconds; if it doesn't, click **Refresh Finder…**.
3. Each row has an On/Off switch; right-click a row for **Change Icon…** and **Remove…**.

The [002 quickstart](specs/002-mapping-manager-v1/quickstart.md) has the full manual checklist.

## Undoing everything

1. In the app, click **Reset All…** and confirm. Every Favorite goes back to its normal icon, and
   the app's mappings, copied images and Launch Services registration are removed.
2. Quit the app, delete `Sidebar Icons.app`, and delete its container,
   `~/Library/Group Containers/<team>.com.altmansoftwaredesign.SidebarIcons`.
3. Optionally delete what macOS kept for it (no user data):
   - `~/Library/Preferences/com.altmansoftwaredesign.SidebarIcons.plist` (window positions);
   - the `~/Library/Application Scripts/` folders whose names contain
     `com.altmansoftwaredesign.SidebarIcons`;
   - the cache folder `$(getconf DARWIN_USER_CACHE_DIR)com.altmansoftwaredesign.SidebarIcons`;
   - privacy decisions, if macOS asked about a folder:
     `tccutil reset All com.altmansoftwaredesign.SidebarIcons`;
   - if you ran the spike: `~/Library/Containers/com.altmansoftwaredesign.SidebarIcons` and
     `~/Library/Containers/com.altmansoftwaredesign.SidebarIcons.FinderSync`.

   The full list is in the [data model](specs/002-mapping-manager-v1/data-model.md#files-the-utility-writes-constitution-i-complete-list).

Your folders are never changed. See [PRIVATE_API.md](PRIVATE_API.md) for manual fallbacks.

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
