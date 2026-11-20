# Private and Undocumented API Register

This file lists every private, undocumented, or deprecated-and-unsupported Apple API, property
key, file, or behavior that Sidebar Icons uses or has tried. It is required by
[Constitution Principle VI](.specify/memory/constitution.md) and is updated in the same commit as
any code that adds, changes, or removes such a use.

If you are deciding whether to build or run this utility, start here.

## Current status

**Nothing in this register is shipped or verified yet.** The project is in its feasibility spike
([specs/001-sidebar-icon-spike](specs/001-sidebar-icon-spike/spec.md)). Every entry below is
**implemented, unverified**: the spike's code that makes these calls is written and builds on
Xcode 27.2, but none of it has been run against Finder yet. Each call runs only when the owner
presses a button in the spike window. Evidence so far comes from the macOS 27.2 SDK headers, link
stubs, the compiler's deprecation warnings, and one read-only `lsregister -dump` check (R7).

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
| [PA-01](#pa-01-sidebar-favorites-list-access) | Sidebar Favorites list access (`LSSharedFileList` list calls) | Deprecated API | implemented, unverified |
| [PA-02](#pa-02-sidebar-item-property-read-and-write) | Sidebar item property read and write | Deprecated API | implemented, unverified |
| [PA-03](#pa-03-overrideiconostype-property-key) | `com.apple.LSSharedFileList.OverrideIcon.OSType` property key | Undocumented key | implemented, unverified |
| [PA-04](#pa-04-finder-icon-lookup-through-a-registered-type-code) | Finder icon lookup through a registered type code | Undocumented behavior | implemented, unverified |
| [PA-05](#pa-05-lsregister-command-line-tool) | `lsregister` command-line tool | Undocumented tool | implemented, unverified |

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
- **macOS builds**: Verified on: none yet. Failed on: none yet. To be tested by experiment B1.
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
  clear, the spike passes `NULL`. The SDK header is inside `CF_ASSUME_NONNULL`, so Swift imports
  the value parameter as non-optional; the spike calls the same C function through a function
  pointer whose last parameter is nullable (identical C ABI). Whether `NULL` really removes the
  property is checked by experiment B6.
- **Safeguards**: Apply never writes over an override it did not set: a Favorite that already
  carries another value (for example another tool's `D001`) is skipped and reported. Clearing
  (apply for a disabled mapping, and reset) matches Favorites by the code this utility set, not by
  path, so a moved or renamed folder is still found, and a Favorite whose value was since changed
  by someone else is left alone.
- **macOS builds**: Verified on: none yet. Failed on: none yet. To be tested by experiments B1,
  B2, B6.
- **Risks**:
  - Finder owns the Favorites list and may ignore, overwrite, or drop the property.
  - Writes go through Apple's own API, never through the store files, so a failure should leave
    the sidebar unchanged rather than damaged. This is to be confirmed by the spike.
  - Every write is recorded in the utility's change ledger before it is made.
  - The value type (`CFString`) is an assumption from the design notes; if B2 fails, a number
    is the next thing to try, and this entry will say so.
  - Passing `NULL` relies on behavior the header does not document.
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
- **macOS builds**: Verified on: none yet. Failed on: none yet. To be tested by experiment B2.
- **Risks**: Apple may rename or stop honoring the key in any release. The expected failure is
  harmless: Favorites fall back to the generic folder icon.
- **Reset and removal**: Reset removes the property (PA-02). Removing the dependency means
  dropping custom sidebar icons unless a public route appears.

## PA-04: Finder icon lookup through a registered type code

- **Symbol and framework**: Launch Services registration of a small bundle whose `Info.plist`
  declares `CFBundleDocumentTypes` entries, each with one `CFBundleTypeOSTypes` code and a
  `CFBundleTypeIconFile` `.icns`. Registration uses `LSRegisterURL` (public, `LSInfo.h`).
  The bundle is application-type (`IconRegistry.app`, `CFBundlePackageType` `APPL`,
  `LSUIElement`, no executable, identifier `com.altmansoftwaredesign.SidebarIcons.IconRegistry`)
  because Launch Services binds document-type claims to applications. It is never launched.
- **Status**: Undocumented behavior. `LSRegisterURL` and the Info.plist keys are public (the
  OSType key is a legacy key), but Finder using this registration to draw a *sidebar* icon for
  the PA-03 code is not documented.
- **Purpose and calling file**: Maps each type code to the icon chosen for a folder. The bundle
  is written to the utility's own App Group container as `IconRegistry.app`. Built by
  `spike/SidebarIconCore/Sources/SidebarIconCore/Icons/IconRegistryBundle.swift` (public file
  writes only) and registered by `SystemLaunchServices` in `LaunchServicesOverrideProvider.swift`
  (tasks T024, T027).
- **macOS builds**: Verified on: none yet. Failed on: none yet. To be tested by experiments B2
  and B3.
- **Risks**:
  - Launch Services may not accept a bundle that is generated at runtime and not code-signed
    (open question R4; tested by B3).
  - Finder and Launch Services cache icons, so changes may need an explicit Finder restart.
  - Another app could register the same type code; the spike checks for this before
    registering (R7) and stops without changing anything if one does.
  - A `.app` with no executable may be treated differently from a normal app; if B2 fails, this
    is one of the variables to change.
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
  `claim id`, `bundle`, and `bindings` fields.
- **macOS builds**: Tool presence confirmed on 27.2.1 (26B131). On 2026-11-19 a manual,
  read-only `-dump` on 26B131 found no claim on `S001` or `S002` (R7 check, research Findings);
  the dump uses the record shapes the parser expects. Use by the utility: verified on none yet.
  To be tested by experiments B2 and B6.
- **Risks**: Apple may move the tool or change its options. Its output format is not stable,
  so the utility only searches it for this project's bundle path and codes.
- **Reset and removal**: The tool is the reset path for PA-04. If it disappears, reset falls back
  to deleting the bundle, which leaves a stale Launch Services entry until the database is
  rebuilt; the register will be updated if that happens.
