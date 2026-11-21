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
  1. An **icon registration bundle** (a small, non-launching `.app`-style bundle) declares, per
     code, an exported type tagged with the code (`UTExportedTypeDeclarations`, `UTTypeIconFile`)
     and a `CFBundleDocumentTypes` entry for it (revised 2026-11-20; the first design used only
     `CFBundleTypeOSTypes`, see the revision below). It is registered with `LSRegisterURL`
     (public, in `LSInfo.h`).
  2. The Favorites item gets the property `com.apple.LSSharedFileList.OverrideIcon.OSType` set to
     that code.
- **EXPERIMENT B2**: Register a bundle with two codes and two bundled `.icns`; set the property on
  both Favorites; restart Finder; record the result.
- **Risk**: The property name and behavior are undocumented and may change between macOS releases
  (Constitution II: isolate in one adapter, record the build verified on).
- **Implementation choices to vary if B2 fails** (2026-11-19): the bundle is `IconRegistry.app`
  (application-type, no executable) rather than a plain `.bundle`; the property value is a
  four-character `CFString`; the `.icns` holds 1x and 2x images from 16 to 1024 px.
- **Revision after the first B2 run** (2026-11-20): with document types that list only
  `CFBundleTypeOSTypes`, each code maps to a dynamic `dyn.…` type and icon lookups return the
  generic document icon. The bundle now also exports one type per code
  (`UTExportedTypeDeclarations`, `com.apple.ostype` tag, `UTTypeIconFile`), and the document types
  point to it with `LSItemContentTypes`. A scratch-bundle control test confirmed the icon then
  resolves, with no executable. Next variable if B2 still fails: move the bundle out of the
  protected App Group container.
- **Final design after the B2 experiments** (2026-11-20, 26B131; see the B2 row): the sidebar
  draws a type's *symbol*, not its `.icns`.
  - A type with no symbol shows the generic document glyph. This includes `com.adobe.pdf`, so
    built-in types are no different.
  - A type whose `UTTypeIcons` dictionary names an SF Symbol (`UTTypeSymbolName`, as CoreTypes
    does for the Trash) shows that symbol, tinted like the other sidebar glyphs. A custom symbol
    compiled into the bundle's `Assets.car` also works. `UTTypeSymbolName` at the top level of the
    declaration is ignored.
  - A type whose `UTTypeIcons` names a symbol that does not exist falls back to the type's
    `UTTypeIconFile` and draws it **in full colour**. The registry bundle uses this: per code, one
    exported type with `UTTypeIcons = {UTTypeIconFile, UTTypeSymbolName: <missing name>}`, no
    document types.
  - Icons are cached per type: changing the `.icns` behind an existing type identifier keeps
    showing the old art. The type identifier therefore includes the asset ID, so a new icon is a
    new type; the code (override value) can stay the same.
  - A custom folder icon set with the public `NSWorkspace.setIcon` is not shown in the sidebar
    (folder glyph), so it is no alternative.

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

- **Result** (2026-11-20): drop the extension. Path B icons persist with the app quit and across
  Finder restarts, with no running code. Worse, a Finder Sync extension that watches a folder
  replaces that Favorite's glyph with the containing app's icon, which hides the Path B icon (A1).
- **Decision (original)**: Decide from the spike results. If B2 shows that the property plus registration
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
| A1 | 26B131 | Pass for one icon — public route draws full-colour art | 2026-11-20: with the Finder Sync extension enabled and monitoring `~/dev` and `~/DevDocs` (`directoryURLs`), both Favorites show the containing app's icon in the sidebar. With no app icon this is the generic application glyph (the "A" seen during B2); after adding an `AppIcon` asset to the app (`macOS-dev-folder-icon.png`) both show that full-colour art after a Finder restart. Turning the extension off brings the folder glyphs back. Giving the extension its own, different icon (`git-repo-2-layers.png`) changed nothing: the app's icon is used. Limit: every monitored folder gets the same icon, so per-folder icons would need one app per icon. Not yet tried: changing the app's icon at runtime (`NSWorkspace.setIcon`) |
| A2 | | Not run | Needs network approval; not needed for the decision because A1 settled what Finder Sync does |
| B1 | 26B131 | Pass | 2026-11-20: List Favorites returned all 7 Favorites with resolved paths and display names, plus each mapping's count and override |
| B2 | 26B131 | Pass (final design) | 2026-11-20, extension off, registry types as in R3 "Final design": after Apply, dev shows the dev-folder art and DevDocs the git-repo art, each in full colour, after Apply plus a Finder restart. Applying twice is harmless. Steps that led there, all on DevDocs/dev with the extension off: no symbol → generic document glyph (also for `'PDF '`); `trsh` → Trash glyph; `UTTypeIcons.UTTypeSymbolName` = `hammer` / `books.vertical` → those glyphs; a custom symbol in the bundle's `Assets.car` → that glyph; a missing symbol name → the `.icns` in full colour; a changed `.icns` behind the same type → old art (cache). History of the first design: 2026-11-20, first design (document types with only `CFBundleTypeOSTypes`): after `killall Finder`, dev and DevDocs showed the generic Applications glyph instead of the folder glyph; `NSWorkspace.icon(forFileType:)` returned the generic document icon for S001/S002. A control test showed an exported type (`UTExportedTypeDeclarations` with the ostype tag) makes the lookup resolve. Second design (exported types): the lookup now returns the custom icon for S001/S002 from the App Group container, but the sidebar still shows the Applications glyph. Diagnostics on DevDocs (owner approved, restored afterwards): override `'PDF '` as a `CFString` also showed the Applications glyph, so Finder does not draw a type icon even for a system type; the same code as a `CFNumber` made Finder show no Favorites section at all until the value was restored. Conclusion so far: on 26B131 Finder reads the property, but these runs are confounded: the Finder Sync extension was enabled and monitoring both folders, and A1 later showed the extension alone produces the same glyph. B2 must be re-run with the extension off |
| B3 | 26B131 | Pass | 2026-11-20: Use runtime icon for DevDocs with `git-repo-3-layers-light-blue.png` (chosen through the open panel): the runtime-generated, unsigned bundle was accepted, and the sidebar showed the new art about 3 s after choosing, without a Finder restart. Works because the new asset gets a new type identifier (icon cache, R3) |
| B4 | 26B131 | Pass | 2026-11-20: with the extension off, icons stayed after quitting the app and restarting Finder. Logout/login not tried (owner's session). With the extension on, its app-icon glyph replaces the Path B icon on watched folders (A1), so Path B must not be combined with a Finder Sync extension watching the same folders |
| B5 | 26B131 | Pass (sandbox blocks Path B, as expected) | 2026-11-20: a sandboxed build (App Sandbox plus the App Group) listed 0 Favorites. Feature 002's app (or the helper that does Path B) cannot be sandboxed |
| B6 | 26B131 | Pass (after fix) | 2026-11-20: as first built, Reset reported success but left both overrides, because `LSSharedFileListItemSetProperty(…, NULL)` returns `noErr` without removing the property. Reset now writes `kCFNull` and reads back. Re-run (extension off): Reset removed both overrides (read back as absent), `lsregister -dump` no longer lists the bundle or its types, and after Refresh Finder both Favorites show the folder glyph again (screen capture). Final design re-run: Reset restored both folder glyphs without a Finder restart |
| R7 check | 26B131 | Pass | 2026-11-19, before any registration: a read-only `lsregister -dump` (289,433 lines) has no claim on `'S001'` or `'S002'` (nor on `'D001'`–`'D009'`). Claim records list codes in `bindings:` and point to their bundle by a `(0x…)` reference, matching `LSRegisterDumpParser`. Apply repeats this check every time. 2026-11-20: the check now also reads type declarations (`type id:` records, `tags:` field); on 26B131 system types already tag `'SDIR'`, `'SIDX'`, `'SIT5'`, `'SITX'`, `'SLD8'`, `'SLKX'` but not `'S001'`/`'S002'` |

**Recommended path for 002**: **Path B** (B1–B4, B6 Pass on 26B131), without a Finder Sync
extension (R5, A1).
- **Why B**: it is the only route that gives each Favorite its own icon, chosen at runtime, in full
  colour. It also offers a monochrome SF Symbol glyph per folder as an option (R3).
- **Why not A**: Path A draws the containing app's icon on every watched folder (one icon for all
  folders), and only while the extension is enabled.
- **Costs**:
  - Path B depends on private or undocumented behavior (`PRIVATE_API.md` PA-01–PA-05), including
    the missing-symbol fallback, so each macOS release needs a re-check.
  - The app cannot be sandboxed (B5).
  - Changing an icon needs a new type (icon cache).
