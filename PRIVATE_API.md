# Private and Undocumented API Register

This file lists every private, undocumented, or deprecated-and-unsupported Apple API, property
key, file, or behavior that Sidebar Icons uses or has tried. It is required by
[Constitution Principle VI](.specify/memory/constitution.md) and is updated in the same commit as
any code that adds, changes, or removes such a use.

If you are deciding whether to build or run this utility, start here.

## Current status

Every entry below is **in use** by the **Sidebar Icons** app (feature 002) and by the retired
spike, through the same adapter:
`Packages/SidebarIconCore/Sources/SidebarIconCore/Providers/LaunchServicesOverrideProvider.swift`.
No other file calls them. Each call runs only on an explicit action in the app window (Add, Apply
Now, turn On/Off, Change Icon, Remove, Re-point, Refresh Finder, Reset All); opening the app only
reads the Favorites list and runs a read-only `lsregister -dump`.

- **Spike verification**: macOS 27.2.1 (26B131), 2026-11-20, experiments B1–B6
  ([001 research Findings](specs/001-sidebar-icon-spike/research.md#findings)).
- **App's first verified build**: macOS 27.2.1 (26B131), 2026-11-21, quickstart checks 1–10
  ([002 research Verification](specs/002-mapping-manager-v1/research.md#verification)). The app
  shows a warning banner on any other build (`SidebarIconCoreInfo.verifiedBuilds`).
- **Since 0.3.0 (feature 004)**: system and custom glyphs go through the same entries (PA-04
  gains the symbol name and a compiled `Assets.car`). Verified with a Developer ID build of the
  app on 27.2.1 (26B131), 2026-11-23: proof P-1 and the batched check T034
  ([004 research](specs/004-icon-groups/research.md)).

## What this utility never does

These are prohibited by the constitution and are not in this register because they are not used:

- Reading or editing Finder's sidebar store files (`~/Library/Application Support/com.apple.sharedfilelist/*.sfl*`).
- Modifying a user's folder, its contents or permissions. Since 0.3.0 a folder's own Finder icon
  can be set, but only for a folder you opt in (Folder Icon…). That uses the public
  `NSWorkspace.setIcon(_:forFile:options:)`, so it is not in this register; how it is recorded,
  backed up and undone is in [004 research D8](specs/004-icon-groups/research.md).
- Privileged helpers, root access, SIP changes, code injection into Finder, or network access.

## Status legend

| Status | Meaning |
|--------|---------|
| planned, unverified | Intended for use; not yet run on any macOS build |
| implemented, unverified | Called by spike code that builds; not yet run on any macOS build |
| in use | Called by shipped or spike code; verified on the builds listed |
| removed | Tried or planned and then dropped; the reason is recorded |

## Summary

| ID | What | Kind | Status |
|----|------|------|--------|
| [PA-01](#pa-01-sidebar-favorites-list-access) | Sidebar Favorites list access (`LSSharedFileList` list calls) | Deprecated API | in use (26B131) |
| [PA-02](#pa-02-sidebar-item-property-read-and-write) | Sidebar item property read and write | Deprecated API | in use (26B131) |
| [PA-03](#pa-03-overrideiconostype-property-key) | `com.apple.LSSharedFileList.OverrideIcon.OSType` property key | Undocumented key | in use (26B131) |
| [PA-04](#pa-04-finder-icon-lookup-through-a-registered-type-code) | Finder icon lookup through a registered type code | Undocumented behavior | in use (26B131) |
| [PA-05](#pa-05-lsregister-command-line-tool) | `lsregister` command-line tool | Undocumented tool | in use (26B131) |

All entries belong to "Path B" (the Launch Services override route), which the spike chose
because no public route works (001 research Findings). If a public route appears in a later macOS,
every entry will be marked **removed**.

---

## PA-01: Sidebar Favorites list access

- **Symbol and framework**: `LSSharedFileListCreate`, `kLSSharedFileListFavoriteItems`,
  `LSSharedFileListCopySnapshot`, `LSSharedFileListItemCopyResolvedURL`,
  `LSSharedFileListItemCopyDisplayName` in `SharedFileList.framework` (part of CoreServices),
  with the resolution flags `kLSSharedFileListNoUserInteraction` and
  `kLSSharedFileListDoNotMountVolumes` (type `LSSharedFileListResolutionFlags`) and the
  `LSSharedFileList` / `LSSharedFileListItem` types, all deprecated in the same release.
  The display name is read so Favorites that are not files (AirDrop, Recents) still show in the
  B1 listing.
- **Status**: Deprecated since macOS 10.11 (`API_DEPRECATED("No longer supported", macos(10.5, 10.11))`).
  Still declared in the MacOSX27.2 SDK header `LSSharedFileList.h` and exported by
  `CoreServices.tbd` and `SharedFileList.tbd`, so code still links.
- **Purpose and calling file**: Read-only listing of the Finder sidebar Favorites to find the
  item that matches each mapped folder. Called only from `SystemLaunchServices` in
  `Packages/SidebarIconCore/Sources/SidebarIconCore/Providers/LaunchServicesOverrideProvider.swift`
  Runs in the app when the window opens and after every action (read-only status), and
  before Add and each apply. In the retired spike: List Favorites, Apply, Use runtime icon, Reset.
- **macOS builds**: Verified on 27.2.1 (26B131), 2026-11-20 (B1: all 7 Favorites listed). From a
  sandboxed build the list is empty (B5), so the caller must not be sandboxed.
- **Risks**:
  - The call may return an empty list on current macOS, which would end Path B (spike "no-go").
  - Apple could remove the symbols; an app that links them directly would then fail to launch.
  - The App Sandbox blocks these calls (B5: a sandboxed build lists 0 Favorites), so the app is
    not sandboxed (002 plan, Complexity Tracking).
- **Reset and removal**: Read-only, so there is nothing to undo. Removing it means deleting
  the Path B adapter; the utility then cannot find sidebar items.

## PA-02: Sidebar item property read and write

- **Symbol and framework**: `LSSharedFileListItemCopyProperty`,
  `LSSharedFileListItemSetProperty` in `SharedFileList.framework`.
- **Status**: Deprecated since macOS 10.11; still declared in the MacOSX27.2 SDK and exported.
- **Purpose and calling file**: Read the current icon override on a Favorite (status), and set or
  clear it (apply and reset). Only the property in PA-03 is written. Called only from
  `SystemLaunchServices` in `LaunchServicesOverrideProvider.swift` (tasks T025, T027, T035).
- **How it is called**: The value is written as a four-character `CFString` (for example `S001`);
  the read side also accepts a number or 4-byte data in case Finder stores it differently. To
  clear, the spike writes `kCFNull`, then reads the Favorites again and reports
  `overrideNotCleared` if the code is still there. (The first build passed `NULL` through a
  nullable function-pointer cast; on 26B131 that returns `noErr` but leaves the property, so it
  was removed.)
- **Safeguards**: Apply never writes over an override it did not set: a Favorite that already
  carries another value (for example another tool's `D001`) is skipped and reported. Clearing
  (apply for a disabled mapping, and reset) matches Favorites by the code this utility set, not by
  path, so a moved or renamed folder is still found, and a Favorite whose value was since changed
  by someone else is left alone.
- **macOS builds**: 27.2.1 (26B131), 2026-11-20: read, write (`CFString`) and clear with
  `kCFNull` verified by reading back. Clearing with `NULL` failed silently (B6). Writing a
  `CFNumber` made Finder show no Favorites section until the value was restored. Finder draws
  the icon (B2, and 002 quickstart checks 1–10 on 2026-11-21).
- **Risks**:
  - Finder owns the Favorites list and may ignore, overwrite, or drop the property.
  - Writes go through Apple's own API, never through the store files, so a failure should leave
    the sidebar unchanged rather than damaged; no damage was seen in the spike or the 002 checks.
  - Every write is recorded in the utility's change ledger before it is made.
  - The value type (`CFString`) is an assumption from the design notes. A `CFNumber` is not
    safe: on 26B131 it made the whole Favorites section disappear until a string was written back.
  - Clearing with `kCFNull` relies on behavior the header does not document; the read-back check
    catches a silent failure.
- **Reset and removal**: Reset clears the property on every Favorite that still carries a code
  recorded in the ledger, wherever its folder now lives. If the
  utility is deleted without running reset, removing the Favorite and adding the folder back
  restores the default icon (see [quickstart rollback](specs/001-sidebar-icon-spike/quickstart.md#rollback)).

## PA-03: OverrideIcon.OSType property key

- **Symbol and framework**: Sidebar item property key
  `com.apple.LSSharedFileList.OverrideIcon.OSType`; value is a four-character type code.
- **Status**: Undocumented. Known only from the observed behavior of existing third-party
  sidebar-icon utilities.
- **Purpose and calling file**: Tells Finder to draw a Favorite with the icon registered for the
  given code (see PA-04). Set and cleared only from `SystemLaunchServices` in
  `LaunchServicesOverrideProvider.swift`.
  This project uses codes `S001`–`SZZZ` to avoid the `D001`-style codes other utilities may use.
- **macOS builds**: Verified on 27.2.1 (26B131), 2026-11-20 (B2): Finder reads the code and draws
  the matching type's icon in the sidebar. A `CFNumber` value is not safe (see PA-02).
- **Risks**: Apple may rename or stop honoring the key in any release. The expected failure is
  harmless: Favorites fall back to the generic folder icon.
- **Reset and removal**: Reset removes the property (PA-02). Removing the dependency means
  dropping custom sidebar icons unless a public route appears.

## PA-04: Finder icon lookup through a registered type code

- **Symbol and framework**: Launch Services registration of a small bundle whose `Info.plist`
  declares only `UTExportedTypeDeclarations`, one per code:
  - identifier `com.altmansoftwaredesign.sidebaricons.icon.<code>.<style key>`, where the style
    key is the asset ID (full colour), `sf.<symbol name>` (system glyph) or `glyph.<version id>`
    (custom glyph);
  - a `com.apple.ostype` tag with the code;
  - `UTTypeIcons`, per style (since 0.3.0):
    - full colour: `{UTTypeIconFile: <asset id>.icns, UTTypeSymbolName: <a name no symbol has>}`;
    - system glyph: `{UTTypeSymbolName: <SF Symbol name>}`;
    - custom glyph: `{UTTypeSymbolName: <glyph name>.<version id>}`, with the symbol compiled by
      Xcode's `actool` into the bundle's `Contents/Resources/Assets.car`.

  `CFBundleVersion` is derived from the content and a format revision (a hash, not an increasing
  number; re-registration goes by path). Registration uses `LSRegisterURL` (public, `LSInfo.h`).
  The bundle is application-type (`CFBundlePackageType` `APPL`, `LSUIElement`, no executable) and
  is never launched. Since 0.3.0 it is **versioned**: `IconRegistry-<content hash>.app` with the
  identifier `com.altmansoftwaredesign.sidebaricons.iconregistry.<content hash>`, where the hash
  is the first 8 hex digits of a SHA-256 over the entries and the `Assets.car`. 0.2.0 used a
  single `IconRegistry.app` with the base identifier.
- **Status**: Undocumented behavior. `LSRegisterURL` and the Info.plist keys are public, but two
  things the utility relies on are not documented:
  - Finder's sidebar draws the type's icon for the PA-03 code.
  - It draws the `.icns` in full colour when the named symbol does not exist. With a real SF
    Symbol name it draws that symbol as a glyph tinted like the system glyphs (outline blue with
    the default accent), and with no symbol, a generic document glyph.
  - It also looks the symbol name up in the registering bundle's `Assets.car`, so a custom symbol
    compiled there is drawn tinted like an SF Symbol (004 spike S1, S4).
  - It caches that `Assets.car` per bundle path: rewriting the car in place shows the old glyph
    until Finder restarts (S4b). A new bundle path with the same codes shows the new glyph.
- **Purpose and calling file**: Maps each type code to the icon chosen for a folder. The bundle
  is written to the utility's own App Group container as `IconRegistry-<hash>.app` (one current
  version; the previous one is unregistered and deleted after each switch). Built by
  `Packages/SidebarIconCore/Sources/SidebarIconCore/Icons/IconRegistryBundle.swift` (public file
  writes only) and registered by `SystemLaunchServices` in `LaunchServicesOverrideProvider.swift`
  (tasks T024, T027).
- **macOS builds**: Verified on 27.2.1 (26B131), 2026-11-20:
  - B2: each Favorite shows its own art in full colour.
  - B3: a runtime-generated, unsigned bundle is accepted, and a new icon appears about 3 s after
    Apply, with no Finder restart.
  - B4: icons persist with the app quit and across Finder restarts.
  - B6: reset restores the folder glyphs.
  - 004 spike, 2026-11-22: SF Symbol names and custom symbols from an `actool`-built
    `Assets.car` are drawn at system glyph size and tint; a new versioned bundle with the same
    codes switches glyphs within seconds without restarting Finder (S1–S4b).
  - 004 app, Developer ID build, 2026-11-23: `actool` runs from the signed, hardened app and its
    custom glyph shows outline blue (P-1); with 20 custom-glyph mappings, changing one switches
    the registry version and leaves the other 19 unchanged, with one version left registered
    (T034).

  Failed earlier on the same build:
  - Document types with only `CFBundleTypeOSTypes`: the codes became `dyn.…` types, so no icon.
  - An exported type with a top-level `UTTypeIconFile`: generic document glyph.
  - A new `.icns` behind an existing type identifier: the old art stayed (icon cache), which is
    why the asset ID is in the identifier.
- **Risks**:
  - The full-colour result depends on a fallback for a missing symbol; Apple could change it to a
    generic glyph in any release. Since 0.3.0 the glyph styles are the main design and full colour
    is the legacy style.
  - Icons are cached per type identifier; a changed icon must get a new identifier.
  - Custom glyphs are cached per bundle path, so each change gets a new bundle path; codes stay
    stable, so the sidebar overrides (PA-02/PA-03) are not rewritten when only a style changes.
    An existing version is reused only if its `Info.plist`, `.icns` files and `Assets.car` match
    the content exactly and it holds no other file; otherwise it is rewritten before registering. A failed registration
    deletes only a bundle that call created and no ledger entry records.
  - Before older versions are retired, any recorded override whose code the new version doesn't
    declare (icon unavailable, or code claimed elsewhere) is cleared, so no Favorite is left
    pointing at an unregistered code. A claim with no readable path counts as the utility's own
    only for 0.2.0's identifier or a version the ledger records.
  - Custom symbols need a "Regular-M" glyph made of filled paths; `actool` refuses strokes. The
    compiled-car format is Apple's and undocumented; the utility only ever produces it with
    `actool` and never parses it.
  - A Finder Sync extension watching the same folder replaces the glyph with its app's icon (A1),
    so the utility must not ship one for these folders.
  - Another app could register the same type code; apply checks for this before registering
    (R7) and leaves that code out of the bundle, skipping only its mapping
    (`codeClaimedElsewhere`); the other mappings are still applied.
  - A `.app` with no executable is flagged `launch-disabled` and `unsupported-format` by Launch
    Services; the control test showed icon lookup still works for it.
  - `FileManager.replaceItemAt` registers an `.app` as a side effect, so the bundle is rewritten
    with an atomic `renamex_np(RENAME_SWAP)` instead, and the only registration is the explicit
    `LSRegisterURL` after the ledger entry (002 research, Verification).
  - The bundle lives in the App Group container, which macOS protects from other processes
    (a shell read gets "Operation not permitted"); the icon service still reads the `.icns` there
    (B2).
  - System types already use codes in this project's `S` range (`SDIR`, `SIDX`, `SIT5`, `SITX`,
    `SLD8`, `SLKX` on 26B131); the R7 check now also catches type declarations, so such a code
    is refused rather than overridden. Since 002 the allocator skips claimed codes when a mapping
    is added (research D4).
- **Reset and removal**: Reset unregisters every recorded bundle version (PA-05) and deletes it
  from the container. After switching to a new version, apply does the same for the previous
  versions, once the overrides point at the new one.
  Since 002, apply does the same when no enabled mapping is left and no override is still
  recorded (for example after removing or turning off the last mapping). Apply clears unwanted
  overrides first, before registering and before setting new ones, so a mapping moved to another
  Favorite never leaves its code on the old one, and a failed registration can't stop Off or
  Remove. A code whose clear failed stays declared in the bundle until it is cleared.
  Reset only ever unregisters or deletes a bundle named `IconRegistry.app` or
  `IconRegistry-*.app` directly in the utility's own container (never a symbolic link); a ledger
  entry naming any other path is reported and left untouched. Since 002, after a successful reset
  the app also removes registry staging folders left by a crash and bundles at its own paths
  that the ledger never recorded (unregistered first; a symbolic link is removed as a link and
  never unregistered).

## PA-05: lsregister command-line tool

- **Symbol and framework**: `/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister`,
  options `-dump` and `-u`.
- **Status**: Undocumented system tool. Present on macOS 27.2.1 (build 26B131); its `-h` output
  lists `-u` ("unregister instead of register") and `-dump`.
- **Purpose and calling file**: `-dump` (read-only) checks whether another bundle already claims
  one of this project's type codes: when a mapping is added (to allocate a free code) and
  before each registration. It is also read to show status (whether the bundle is still
  registered), on launch and after actions, when an override is set. `-u` unregisters
  `IconRegistry.app`, because there is no public unregister call: in Reset All, in apply when no
  mapping needs the bundle any more (the last one removed or turned off), and after a successful
  Reset All for a bundle the ledger never recorded. Run with `Process` (fixed path, argument list,
  empty environment, no shell) only from `SystemLaunchServices` in
  `LaunchServicesOverrideProvider.swift`; the output is parsed by
  `LSRegisterDumpParser` in the same file, which reads only `bundle id`, `path`, `identifier`,
  `claim id`, `type id`, `bundle`, `bindings`, and `tags` fields. A code counts as taken when a
  document claim binds it or a type declaration tags it.
- **macOS builds**: Tool presence confirmed on 27.2.1 (26B131). On 2026-11-19 a manual,
  read-only `-dump` on 26B131 found no claim on `S001` or `S002` (R7 check, research Findings);
  the dump uses the record shapes the parser expects. Used by the utility on 26B131, 2026-11-20:
  the R7 check ran on every Apply, and after `-u` the dump listed neither the bundle nor any of
  its exported types (B6).
- **Risks**: Apple may move the tool or change its options. Its output format is not stable,
  so the utility only searches it for this project's bundle path and codes.
- **Reset and removal**: The tool is the reset path for PA-04. If it is missing or fails, reset
  reports the failure and keeps both the bundle and its ledger entry, so nothing is left
  registered without a record; the overrides are still cleared first. Deleting the bundle by hand
  would leave a stale Launch Services entry until the database is rebuilt. `lsregister` runs
  from its fixed path with an empty environment and an argument list, never through a shell.
