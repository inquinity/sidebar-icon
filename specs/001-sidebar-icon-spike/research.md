# Research: Sidebar Icon Feasibility Spike

**Feature**: 001-sidebar-icon-spike | **Date**: 2026-11-17

Desk research was done against the local Xcode 27.2 SDK (MacOSX27.2.sdk) on macOS 27.2.1 (26B131).
Items marked **EXPERIMENT** can only be settled by running the spike; their results are appended
in the "Findings" section at the end of this file during implementation (FR-008).

## R1 — Is there a public API for a per-folder sidebar icon? (Path A)

- **Decision**: Treat Path A as unlikely, but still run the experiment first (FR-005).
- **Evidence**:
  - `FinderSync.framework/Headers/FinderSync.h` exposes only `directoryURLs`, badges
    (`setBadgeImage:label:forBadgeIdentifier:`, `setBadgeIdentifier:forURL:`), menus (including
    `FIMenuKindContextualMenuForSidebar`), the toolbar item (`toolbarItemImage`), and
    `extensionEnabled` / `showExtensionManagementInterface`. No sidebar-image property or method.
  - Xcode's "Finder Sync Extension" template ships an empty `NSExtensionAttributes` dictionary, so no
    documented Info.plist key for a sidebar icon is in the template.
- **EXPERIMENT A1**: Watch both folders with a Finder Sync extension and record what the Favorites
  show (generic glyph, containing-app icon, or anything else).
- **EXPERIMENT A2**: Check Apple's current Finder Sync documentation for any sidebar-icon key or
  behavior. This needs network access: ask the owner first (Constitution I covers the shipped app,
  not research; the owner's agent rules still require approval).
- **Alternatives considered**: Badges on the root folder. Rejected: badges overlay items in Finder
  windows, not the sidebar glyph, so they do not meet FR-001.

## R2 — Can the Path B APIs be called on macOS 27?

- **Decision**: Path B uses `LSSharedFileList` calls, which are deprecated since macOS 10.11 but still
  declared and exported.
- **Evidence**: `SharedFileList.framework/Headers/LSSharedFileList.h` still declares
  `LSSharedFileListCreate`, `kLSSharedFileListFavoriteItems`, `LSSharedFileListCopySnapshot`,
  `LSSharedFileListItemCopyResolvedURL`, `LSSharedFileListItemCopyProperty`, and
  `LSSharedFileListItemSetProperty` (all `API_DEPRECATED("No longer supported", macos(10.5, 10.11))`).
  The symbols are exported by `CoreServices.tbd` and `SharedFileList.tbd`, so the code links.
- **EXPERIMENT B1 (read-only)**: List Favorites with `kLSSharedFileListFavoriteItems` and resolve each
  URL. If this returns nothing on macOS 27, Path B is dead and the spike stops with a "no-go" finding.
- **Alternatives considered**: Editing `~/Library/Application Support/com.apple.sharedfilelist/*.sfl*`
  directly. Prohibited by Constitution II.

## R3 — How does Finder map a sidebar item to a custom icon under Path B?

- **Decision**: Two parts, based on how existing sidebar-icon utilities behave (doc section "Private
  Launch Services mechanism"):
  1. An **icon registration bundle** (a small, non-launching `.app`-style bundle) declares
     `CFBundleDocumentTypes` entries, each with one `CFBundleTypeOSTypes` code and a
     `CFBundleTypeIconFile` `.icns`. It is registered with `LSRegisterURL` (public, in `LSInfo.h`).
  2. The Favorites item gets the property `com.apple.LSSharedFileList.OverrideIcon.OSType` set to
     that code.
- **EXPERIMENT B2**: Register a bundle with two codes and two bundled `.icns`; set the property on
  both Favorites; restart Finder; record the result.
- **Risk**: The property name and behavior are undocumented and may change between macOS releases
  (Constitution II: isolate in one adapter, record the build verified on).

## R4 — Runtime-chosen icons under each path (Story 2)

- **Path A**: the extension would load an `NSImage` from the App Group container.
- **Path B decision**: the app generates or updates the icon registration bundle inside its own
  container at runtime: it converts the chosen image to `.icns` with ImageIO
  (`CGImageDestination`, ICNS type), writes `Info.plist`, then calls `LSRegisterURL(url, true)`.
- **EXPERIMENT B3**: Replace one `.icns` at runtime, re-register, and record whether Finder updates
  without a restart, after a Finder restart, or only after a logout.
- **Open sub-question**: whether a bundle that is generated at runtime and not code-signed is
  accepted by Launch Services for icon lookup. If not, fall back to a fixed, signed registration
  bundle whose `.icns` resources are replaced (this breaks the bundle's seal, so record whether
  Launch Services cares).

## R5 — Is the Finder Sync extension needed at all under Path B?

- **Decision**: Decide from the spike results. If B2 shows that the property plus registration
  persist across Finder restarts and logout with no running code, feature 002 drops the extension.
  It would add an enablement step and a sandbox boundary with no benefit (Constitution I).
- **EXPERIMENT B4**: With the extension disabled, confirm Path B icons persist (SC-002).

## R6 — Sandbox and signing

- **Decision**:
  - Finder Sync extension: sandboxed (the system requires it).
  - Spike host app: **not sandboxed**, hardened runtime, Developer ID signed. The deprecated
    `LSSharedFileList` calls and `LSRegisterURL` on a bundle in the app's own container are not
    expected to work inside the App Sandbox. Recorded in Complexity Tracking.
  - **EXPERIMENT B5**: Run probe B1 once from a sandboxed build to confirm the sandbox blocks it. If it
    works, feature 002 keeps the app sandboxed.
  - Bundle identifiers (approved by the owner on 2026-11-19): app
    `com.altmansoftwaredesign.SidebarIcons`, extension
    `com.altmansoftwaredesign.SidebarIcons.FinderSync`, Path B registration bundle
    `com.altmansoftwaredesign.SidebarIcons.IconRegistry`.
  - App Group: `<TEAMID>.com.altmansoftwaredesign.SidebarIcons` (team-ID prefix, so no container-access prompt).
- **Alternatives considered**: A separate non-sandboxed command-line helper next to a sandboxed app.
  Rejected for the spike (more moving parts); it may be reconsidered in 002 if B5 shows a sandboxed
  app is otherwise viable.

## R7 — OSType code allocation

- **Decision**: Use a project-specific prefix instead of `D001`-style codes, which other sidebar
  utilities may already use. Format: `S` + three base-36 characters (`S001`...`SZZZ`), which allows
  46,656 mappings and is unlikely to collide.
- **EXPERIMENT**: Before registering, check whether any other registered bundle already claims the
  code (use `lsregister -dump` read-only and search). Record the result.

## R8 — Refresh and reset mechanics

- **Decision**:
  - Refresh: first re-set the property and re-register; restart Finder only on an explicit
    "Refresh Finder" action (`NSRunningApplication` terminate for `com.apple.finder`; launchd
    relaunches it). This replaces `killall Finder`.
  - Reset: clear the property on every Favorite the utility changed (ledger in the data model),
    unregister the registration bundle (`lsregister -u <path>` from the system's
    LaunchServices support directory, then delete the bundle), then offer Refresh Finder.
- **EXPERIMENT B6**: Confirm reset leaves no trace (SC-004): property absent, `lsregister -dump` has
  no entry for the bundle path, sidebar shows the generic glyph.

## R9 — macOS 26

- **Decision**: Not a target for the spike. If a macOS 26 machine or VM is already available, run
  B1 and B2 there too and record the results; it costs only an extra test run.

## Findings

*(Filled during implementation. One row per experiment.)*

| ID | macOS build | Result | Notes |
|----|-------------|--------|-------|
| A1 | | | |
| A2 | | | |
| B1 | | | |
| B2 | | | |
| B3 | | | |
| B4 | | | |
| B5 | | | |
| B6 | | | |
| R7 check | | | |

**Recommended path for 002**: _(A or B, with links to the rows above)_
