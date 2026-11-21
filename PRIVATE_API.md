# Private and Undocumented API Register

This file lists every private, undocumented, or deprecated-and-unsupported Apple API, property
key, file, or behavior that Sidebar Icons uses or has tried. It is required by
[Constitution Principle VI](.specify/memory/constitution.md) and is updated in the same commit as
any code that adds, changes, or removes such a use.

If you are deciding whether to build or run this utility, start here.

## Current status

**Nothing in this register is shipped yet.** The project is in its feasibility spike
([specs/001-sidebar-icon-spike](specs/001-sidebar-icon-spike/spec.md)). Every entry below is
**in use** by the spike and was verified on macOS 27.2.1 (26B131) on 2026-11-20 by the spike's
experiments B1–B6. Each call runs only when the owner presses a button in the spike window. The
spike recommends this route (Path B) for feature 002; see the research Findings.

Entries are updated as the spike's experiments run; results are recorded in the Findings table
in [research.md](specs/001-sidebar-icon-spike/research.md).

## What this utility never does

These are prohibited by the constitution and are not in this register because they are not used:

- Reading or editing Finder's sidebar store files (`~/Library/Application Support/com.apple.sharedfilelist/*.sfl*`).
- Modifying a user's folder, its contents, permissions, or its own Finder icon.
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

All entries belong to "Path B" (the Launch Services override route) in the spike. If the spike
finds a working public route instead, every entry will be marked **removed**.

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
  `spike/SidebarIconCore/Sources/SidebarIconCore/Providers/LaunchServicesOverrideProvider.swift`
  (tasks T025, T027, T035). Runs when the owner presses List Favorites, Apply (Path B), Use
  runtime icon, or Reset.
- **macOS builds**: Verified on 27.2.1 (26B131), 2026-11-20 (B1: all 7 Favorites listed). From a
  sandboxed build the list is empty (B5), so the caller must not be sandboxed.
- **Risks**:
  - The call may return an empty list on current macOS, which would end Path B (spike "no-go").
  - Apple could remove the symbols; an app that links them directly would then fail to launch.
  - The App Sandbox is expected to block these calls, so the host app is not sandboxed during
    the spike (see the plan's Complexity Tracking). Experiment B5 checks this.
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
  `CFNumber` made Finder show no Favorites section until the value was restored. Whether Finder
  draws the icon (B2) is not yet established.
- **Risks**:
  - Finder owns the Favorites list and may ignore, overwrite, or drop the property.
  - Writes go through Apple's own API, never through the store files, so a failure should leave
    the sidebar unchanged rather than damaged. This is to be confirmed by the spike.
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
  - identifier `com.altmansoftwaredesign.sidebaricons.icon.<code>.<asset id>`;
  - a `com.apple.ostype` tag with the code;
  - `UTTypeIcons` = `{UTTypeIconFile: <asset id>.icns, UTTypeSymbolName: <a name no symbol has>}`.

  `CFBundleVersion` is derived from the mapping and a format revision (a hash, not an increasing
  number; re-registration goes by path). Registration uses `LSRegisterURL` (public, `LSInfo.h`).
  The bundle is application-type (`IconRegistry.app`, `CFBundlePackageType` `APPL`,
  `LSUIElement`, no executable, identifier `com.altmansoftwaredesign.SidebarIcons.IconRegistry`).
  It is never launched.
- **Status**: Undocumented behavior. `LSRegisterURL` and the Info.plist keys are public, but two
  things the utility relies on are not documented:
  - Finder's sidebar draws the type's icon for the PA-03 code.
  - It draws the `.icns` in full colour when the named symbol does not exist. With a real SF
    Symbol name it draws that symbol as a monochrome glyph, and with no symbol, a generic
    document glyph.
- **Purpose and calling file**: Maps each type code to the icon chosen for a folder. The bundle
  is written to the utility's own App Group container as `IconRegistry.app`. Built by
  `spike/SidebarIconCore/Sources/SidebarIconCore/Icons/IconRegistryBundle.swift` (public file
  writes only) and registered by `SystemLaunchServices` in `LaunchServicesOverrideProvider.swift`
  (tasks T024, T027).
- **macOS builds**: Verified on 27.2.1 (26B131), 2026-11-20:
  - B2: each Favorite shows its own art in full colour.
  - B3: a runtime-generated, unsigned bundle is accepted, and a new icon appears about 3 s after
    Apply, with no Finder restart.
  - B4: icons persist with the app quit and across Finder restarts.
  - B6: reset restores the folder glyphs.

  Failed earlier on the same build:
  - Document types with only `CFBundleTypeOSTypes`: the codes became `dyn.…` types, so no icon.
  - An exported type with a top-level `UTTypeIconFile`: generic document glyph.
  - A new `.icns` behind an existing type identifier: the old art stayed (icon cache), which is
    why the asset ID is in the identifier.
- **Risks**:
  - The full-colour result depends on a fallback for a missing symbol; Apple could change it to a
    generic glyph in any release. The monochrome SF Symbol variant is the fallback design.
  - Icons are cached per type identifier; a changed icon must get a new identifier.
  - A Finder Sync extension watching the same folder replaces the glyph with its app's icon (A1),
    so the utility must not ship one for these folders.
  - Another app could register the same type code; the spike checks for this before
    registering (R7) and stops without changing anything if one does.
  - A `.app` with no executable is flagged `launch-disabled` and `unsupported-format` by Launch
    Services; the control test showed icon lookup still works for it.
  - The bundle lives in the App Group container, which macOS protects from other processes
    (a shell read gets "Operation not permitted"); the icon service still reads the `.icns` there
    (B2).
  - System types already use codes in this project's `S` range (`SDIR`, `SIDX`, `SIT5`, `SITX`,
    `SLD8`, `SLKX` on 26B131); the R7 check now also catches type declarations, so such a code
    is refused rather than overridden. The allocator does not skip these codes yet; sequential
    allocation from `S001` will not reach them in practice, and if it did, apply stops with
    `codeClaimedElsewhere` (to revisit in 002).
- **Reset and removal**: Reset unregisters the bundle (PA-05) and deletes it from the container.
  Reset only ever unregisters or deletes the bundle at the utility's own container path; a ledger
  entry naming any other path is reported and left untouched.

## PA-05: lsregister command-line tool

- **Symbol and framework**: `/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister`,
  options `-dump` and `-u`.
- **Status**: Undocumented system tool. Present on macOS 27.2.1 (build 26B131); its `-h` output
  lists `-u` ("unregister instead of register") and `-dump`.
- **Purpose and calling file**: `-dump` (read-only) checks whether another bundle already claims
  one of this project's type codes before registering. `-u` unregisters `IconRegistry.app`
  during reset, because there is no public unregister call. After reset, `-dump` is read again to
  confirm the bundle is no longer listed (B6). Run with `Process` only from `SystemLaunchServices`
  in `LaunchServicesOverrideProvider.swift` (tasks T028, T035); the output is parsed by
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
