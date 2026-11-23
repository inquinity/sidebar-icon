# Research: Sidebar Icon Mapping Manager v1

**Feature**: 002-mapping-manager-v1 | **Date**: 2026-11-20

The sidebar mechanism itself was settled by the 001 spike on macOS 27.2.1 (26B131); see
[001 research Findings](../001-sidebar-icon-spike/research.md#findings) and
[PRIVATE_API.md](../../PRIVATE_API.md). This file records only the decisions 002 adds on top.
There are no open NEEDS CLARIFICATION items.

## D1 — Where the app lives

- **Decision**:
  - Move the engine package from `spike/SidebarIconCore` to `Packages/SidebarIconCore`, and point
    the spike's Xcode project at the new path.
  - Create a new Xcode project at `app/SidebarIcons.xcodeproj` with one app target,
    **Sidebar Icons**, that depends on the package.
  - No extension target.
- **Rationale**: one engine shared by the spike (kept for re-running experiments on new macOS
  builds) and the app, with no copy to drift. A top-level `Packages/` makes the dependency
  direction obvious; `spike/` stays disposable.
- **Alternatives considered**:
  - Add an app target to the spike project. Rejected: it mixes the experiment harness, its
    extension and its test-only icons into the shipped app's project.
  - Copy the package. Rejected: two engines that will drift.

## D2 — Identity, signing and the shared container

- **Decision**:
  - The app takes the approved bundle ID `com.altmansoftwaredesign.SidebarIcons` and App Group
    `45GJWJVQN2.com.altmansoftwaredesign.SidebarIcons`, team 45GJWJVQN2.
  - Not sandboxed, hardened runtime, App Group entitlement only.
  - The spike keeps the same IDs. It is retired: it is run again only to re-check a new macOS
    build, never at the same time as the app.
- **Rationale**: the bundle ID was approved for the app (001 R6). Sharing the container and ledger
  means the app's Reset All also undoes anything the spike left behind.
- **Consequence**: the spike and the app must not run at the same time (one ledger writer). The
  quickstart starts with a spike Reset.
- **Alternatives considered**: giving the app a new ID and container. Rejected: it would split the
  ledger, so neither Reset would see the other's changes.

- **Changed in 0.2.0 (F021)**: the identifiers are lowercase: bundle ID
  `com.altmansoftwaredesign.sidebaricons`, App Group `45GJWJVQN2.com.altmansoftwaredesign.sidebaricons`,
  registry bundle `com.altmansoftwaredesign.sidebaricons.iconregistry` (and the spike's extension
  `….sidebaricons.findersync`). The container moved with them; 0.1.0 was never installed outside
  development, and its data was removed by the T041 leftover audit, so nothing is migrated.

## D3 — Configuration persistence

- **Decision**:
  - Store one versioned JSON file, `config.json`, in the container (`ContainerLocator.configURL`):
    `{schemaVersion: 1, mappings: [SidebarMapping], assets: [IconAsset]}`.
  - Writes are atomic (write a temp file, then replace).
  - A file with an unknown `schemaVersion` or invalid JSON is reported. It is never overwritten:
    the app opens read-only, with Reset All available.
  - The model is `ConfigStore` in the package.
- **Rationale**: Constitution storage rule (one versioned JSON plus assets). Atomic writes keep a
  crash from losing the list.
- **Alternatives considered**: `UserDefaults` (rejected: not in the container, so it can't be
  listed or removed with it); SwiftData (rejected: more machinery than a 20-item list needs).

## D4 — Type codes for N mappings

- **Decision**: the code is allocated once, when a mapping is added, and kept for its life.
  - `OSTypeAllocator.allocate` excludes codes already in `config.json`, codes still in the ledger,
    and codes claimed by any other registered bundle or type: the R7 dump check from 001, which on
    26B131 includes `SDIR`, `SIDX`, `SIT5`, `SITX`, `SLD8` and `SLKX`.
  - The allocator retries past a claimed code instead of failing the whole apply (open review item
    from 001). It checks a window of 32 candidates per `lsregister -dump` and moves to the next
    window if all are claimed.
  - If a code becomes claimed after it was allocated, apply skips only that mapping
    (`codeClaimedElsewhere`, shown on its row) and applies the rest.
- **Rationale**: a stable code means the Favorite's override never has to change when only the
  icon changes. The icon cache is handled by the type identifier instead (D5). 46,656 codes is
  far beyond the 20 that FR-013 needs.
- **Alternatives considered**: a new code for every apply. Rejected: it needs override churn on
  every change.

## D5 — Changing an icon, and the `.icns` cache

- **Decision**: icon assets are **immutable**.
  - Picking a new image always creates a new `IconAsset` (new UUID). The old asset is deleted
    after the new one is applied.
  - The registry type identifier contains the asset ID, so Finder's per-type icon cache never
    shows stale art (001 B3).
  - The converted `<assetID>.icns` is written to a temp file and moved into place. On use, a
    `.icns` that is missing or that ImageIO cannot open is rebuilt from the copied source.
- **Rationale**: this closes the 001 review finding: with immutable assets, the `.icns` is never
  rebuilt for a replaced source, and a truncated file is caught.
- **Alternatives considered**: comparing modification dates of the source and the `.icns`.
  Rejected: immutability removes the case entirely.

## D6 — When outside changes happen (Constitution V)

- **Decision**: only these explicit owner actions change anything outside the container:
  - **Add** (folder plus image): applies all enabled mappings.
  - **Change Icon** (Story 2).
  - **Turn On / Turn Off** and **Remove** (Story 2).
  - **Apply Now**: shown when a mapping is "Not in sidebar" or "Not applied".
  - **Refresh Finder**: re-applies, then restarts Finder, after confirmation.
  - **Reset All**: after confirmation.

  Launching the app only reads the config, the ledger and the Favorites list, and shows status.
- **Spec note**: the spec's edge case ("apply automatically once the folder appears in Favorites,
  on the next launch or refresh") is met on **refresh**, and by the Apply Now button. Applying on
  launch would be a silent outside change (Constitution V), so it is not done.
- **Alternatives considered**: watching the Favorites list and applying automatically. Rejected:
  silent side effect, and a polling daemon (Constitution I).

## D7 — Status per mapping (FR-008)

- **Decision**: status is computed from `LaunchServicesOverrideProvider.status` plus the config.

  | Status | Condition |
  |--------|-----------|
  | Applied | enabled, folder exists, in Favorites once, active override is the mapping's code, and the bundle is registered |
  | Off | disabled |
  | Not in sidebar | enabled, folder exists, in Favorites 0 times |
  | Folder missing | the folder doesn't exist |
  | Error (reason) | in Favorites more than once, another tool's override, the code claimed elsewhere, or the last apply failed for this mapping |
  | Not applied | enabled and in Favorites, but the override is absent (for example after an outside reset). Offers Apply Now |
- **Rationale**: every value is observable read-only, without restarting Finder.

## D8 — Unsupported macOS builds

- **Decision**:
  - The engine keeps a list of verified builds (`SidebarIconCoreInfo.verifiedBuilds`, starting
    with `26B131`).
  - On another build the window shows a non-blocking banner: "Not yet verified on this macOS
    build; icons may not appear. Reset All always works."
  - If the Favorites list can't be read (B1 fails), Add and Apply are disabled, and Reset All
    stays enabled (FR-010).
- **Rationale**: Finder's rendering can't be detected automatically. The banner is honest, and
  Reset is never blocked.

## D9 — Preview (FR-007, Story 3; starter shows a basic version)

- **Decision**:
  - Render the image at the sidebar's sizes (16 pt and 20 pt) on two swatches with fixed light
    and dark sidebar colours, at the screen's own scale. (As built: fixed colours instead of
    `.environment(\.colorScheme)`, because `NSColor`-based colours don't follow that environment
    reliably; no separate 1x/2x rows.)
  - The starter list shows the 20 pt light/dark pair per row. Story 3 adds the pre-apply sheet and
    the non-square/detail warning (aspect ratio outside 0.8–1.25, or more than about 64 distinct
    colour clusters at 16 px).
- **Rationale**: the sidebar draws the `.icns` in full colour (001 B2), so a plain image render is
  faithful.
- **Open check**: compare the preview with the real sidebar in light and dark mode and with a
  non-default accent colour (001 T039 leftover; in the quickstart).

## D10 — Persistence across logout and reboot (FR-011, SC-002)

- **Decision**: no code is needed. The override is stored in Finder's Favorites list and the
  registry bundle stays registered in Launch Services, and both survive logout and reboot by
  design. Verified manually by the quickstart (logout, then reboot, with 3 and then 20 mappings).
- **Risk**: the Launch Services database can be rebuilt (for example `lsregister -kill`, or some
  OS updates), which would drop the registration. The **Refresh Finder** action re-registers
  before restarting, and status shows "Not applied" when the bundle is missing.

## D11 — Constitution VI in the app

- **Decision**:
  - The About window says the app relies on undocumented macOS behavior and names
    `PRIVATE_API.md` (its path in the repository).
  - The adapter stays in `LaunchServicesOverrideProvider.swift`; the GUI only sees the
    `SidebarIconProvider` protocol through `MappingManager`.

## Starter review (2026-11-21)

Independent code and security review of the starter (T001–T025). All findings fixed, with
regression tests in `ReviewFixTests.swift`:

| # | Finding | Fix |
|---|---------|-----|
| 1 | A renamed or linked mapped folder made `config.json` unreadable (load re-resolved paths) | Load/save check only the stored form; the row shows an error instead |
| 2 | Actor reentrancy let two actions interleave and race the ledger; `start()` could clear `busy` | `MappingManager` runs one action at a time (`busy`); `start()` skips while busy |
| 3 | One claimed code stopped every mapping from applying | Only the claimed mapping is skipped; its row shows why (last failure outranks a still-set override) |
| 4 | Allocator could return an unchecked 33rd code | Windows of 32 are checked until an unclaimed code is found |
| 5 | Add could report an error after saving | Post-save apply failures are returned as "Saved, but not applied" |
| 6 | Reset All's partial-failure messages could be lost | Follow-up errors are appended, not thrown |
| 7 | No flush before the config rename | `F_FULLFSYNC` on the temp file |
| 8 | A symlinked `Icons/` was followed | Imports, conversions and deletions refuse a linked `Icons/` |
| 9 | Reset All left staging folders or an unrecorded bundle | Removed (bundle unregistered first) after a successful reset |
| 10 | Refresh hint shown after every apply | Shown only when an override actually changed |
| 11 | Contracts out of date | Contracts, data model and UI contract updated |
| 12 | Read-only mode looked like an empty list | Separate read-only empty state |
| 13 | `.icns` usability checked only the first image | Every representation must decode |

Security: entitlements are the App Group only; hardened runtime with no exceptions; not
sandboxed by design (plan Complexity Tracking); deletions limited to plain names in a real
`Icons/` and to the container's own bundle. Open by decision: an unreadable `ledger.json` still
stops Reset All (nothing can be undone safely without it).

## Verification

Quickstart checks run with live control on macOS 27.2.1 (26B131), Debug build, 2026-11-21.
Screenshots are in the session scratchpad (`checks/`).

| Check | Result | Notes |
|-------|--------|-------|
| Before | Pass | Reset All in the app cleared the spike's leftovers through the shared ledger (D2): `dev` and `DevDocs` lost S001/S002 without a Finder restart |
| 1 Add | Pass | `~/dev` + PNG: Favorite override set to `S003` 6 s after the pick, full-colour icon in the sidebar with no restart, row Applied with light/dark previews. Exact time to visible not measured (seen at 12 s), so SC-001 (10 s) is likely but unproven. `S001`/`S002` were skipped as claimed (see below) |
| 2 Persist | Pass | Quit and relaunch: row unchanged (Applied), icon still shown |
| 3 Original | Pass | Original PNG deleted, app relaunched: preview and sidebar icon unchanged |
| 4 Duplicate | Pass | `~/dev` and `/Users/robert/dev/` refused: "~/dev is already mapped. Change its icon instead."; nothing changed. The refusal comes only after the image is picked |
| 5 Refresh | Pass | Confirmation wording per ui.md; Finder restarted once (new pid); icon still shown; about 15–20 s end to end |
| 6 Reset All | Pass | List empty; both Favorites show the folder glyph with no refresh; our bundle and its `S003` type gone from `lsregister -dump` |

**Finding: stale test registrations (fixed).** `lsregister -dump` listed 10 `IconRegistry.app`
bundles in deleted `SidebarIconCoreTests-*` temp folders, whose type declarations tagged `S001`
and `S002`. The app treated those codes as claimed elsewhere and allocated past them (check 1 got
`S003`).

- **Cause** (probed): `FileManager.replaceItemAt` registers an `.app` with Launch Services as a
  side effect. `IconRegistryBundle.write` used it for every rewrite, so each test that wrote the
  bundle twice left a registration nobody recorded. Creating a bundle or renaming it into place
  does not register it.
- **Fix**: `IconRegistryBundle.write` swaps the new version in with `renamex_np(RENAME_SWAP)`
  (still atomic). Registration is only the adapter's explicit `LSRegisterURL`, after the ledger
  entry; a probe confirmed that `LSRegisterURL` after a swap picks up the new types. Two full
  `swift test` runs then added no registrations.
- **Cleanup** (owner approved, 2026-11-21): the 10 entries, plus two from the probes, were removed
  with `lsregister -u <path>`, which works for a path that no longer exists. Afterwards the dump
  lists no `IconRegistry.app`, and `S001`/`S002` are unclaimed.
- **Checked in Finder** (live control, 26B131): Add `~/dev` (first write, `S001`), then Add
  `~/DevDocs`, which rewrote the bundle through the swap (`S002`). Both Favorites showed their
  icons in full colour with no Finder restart; `lsregister -dump` listed one registry bundle
  declaring both types. Reset All then cleared both and left no `IconRegistry.app` in the dump.

## Story 2 checkpoint (2026-11-21)

**Finder checks** (live control, 26B131, Debug build; quickstart 7–9 plus Change Icon). Third
test folder: `~/Documents`.

| Check | Result | Notes |
|-------|--------|-------|
| 7 Three mappings | Pass | `dev`, `DevDocs`, `Documents` each showed its own icon |
| 8 Off/On | Pass | Off: `DevDocs` back to the folder glyph, row kept as Off; On: icon back. No Finder restart |
| 9 Remove | Pass | Confirmation per ui.md; `Documents` back to its glyph and gone from the list; others unchanged; no folder's modification time changed. Deleted asset files verified by unit tests only (the container is not readable from the shell) |
| Change Icon | Pass | `dev` switched art in the sidebar, kept `S001`, no Finder restart |
| Cleanup | Pass | Reset All: no overrides, no `IconRegistry.app` in `lsregister -dump` |

Found while writing tests: a mapping moved to another Favorite left its code on the old one, with
no ledger record (Reset All could not undo it). Fixed by clearing unwanted overrides before
setting new ones.

**Review** (independent): 1 important, 7 minor.

| # | Finding | Outcome |
|---|---------|---------|
| 1 | A registration failure stopped Off/Remove from clearing, while the row said Off | Fixed: clearing runs before registration |
| 2 | A failed clear dropped the code from the bundle and the row said Off | Fixed: codes still recorded stay declared; the row shows an error |
| 3 | No retry after removing the last mapping with a failed clear (Reset All works) | Follow-up F003 |
| 4 | Story 2 actions threw after saving | Fixed: "Saved, but not applied: …" |
| 5 | Change Icon asked for a refresh when another mapping applied | Fixed |
| 6 | Rare double ledger entry could clear a needed icon | Follow-up F004 |
| 7 | Contract drift | Fixed |
| 8 | Re-point only on Folder missing | Follow-up F005 |
| — | Check-then-use window before `lsregister -u` (not new) | Follow-up F006 |

Regression tests: `Story2ReviewFixTests`. 147 tests pass. Fixes #1, #2 reorder adapter calls
already exercised by the Finder checks above (clear, register, set); not re-run in Finder.

## Story 3 checkpoint (2026-11-21)

`PreviewAdvice` warns, never blocks: aspect ratio in points outside 0.8–1.25, or more than 64
colour clusters at 16 px (3 bits per channel, pixels at least about 80 % opaque). The preview
sheet appears after the image pick in Add Folder… and Change Icon….

**Review** (independent): no important findings. The reviewer checked the pixel decoding with a
scratch program and surveyed false positives: none of the six images in `folder-icon/` warn;
across 505 system icons and wallpapers the median is 12 clusters and only photos and 2 app icons
exceed 64. Fixed: a decoding test that pins exactly 4 clusters (#1); the aspect ratio now uses the
point size the renderer fits (#3); contract and D9 updated (#5). Logged: F008–F011.

**App check (T035)**: run with live control (26B131). The display locked twice during the first
attempt, which stops live control (the app then has no window and a full-screen capture is
black); the remaining steps were run later with `caffeinate -d` keeping the display on.

| Step | Result | Notes |
|------|--------|-------|
| Preview, light and dark | Pass | Sheet shows the image beside the folder name at 16 and 20 pt on both swatches |
| Non-square warning | Pass | 300 × 200 block image: "This image isn't square…"; Apply enabled |
| Detail warning | Pass | 256 × 256 image of 16 × 16 colour blocks: "This image has a lot of detail…"; Apply enabled |
| Cancel saves nothing | Pass | Sheet closed, no row added, no override on `~/dev` |
| Apply despite a warning | Pass | Detailed image applied to `~/dev` (`S001`); the sidebar showed the same block art as the preview |
| Alert after Apply: not an image | Pass | Preview already said "This file can't be shown as an image; adding it will fail."; after Apply the alert appeared once the sheet closed; nothing saved |
| Alert after Apply: duplicate | Pass | "~/dev is already mapped. Change its icon instead." appeared after the sheet closed; existing mapping unchanged |
| Cleanup | Pass | Reset All: no overrides, no `IconRegistry.app` in the dump |

Note: Finder stopped accepting Apple events from this session ("Not authorized", -1743); sidebar
captures now open the window with `open <folder>` and locate it through Accessibility.

Observation: the busy 300 × 200 block image got only the non-square warning. Shrunk to 16 px its
12-px blocks blend into fewer than 64 colour clusters, so it doesn't count as detailed (the
reviewer predicted this for busy art). Logged as F012 for the owner to judge.

## Final review (T038, 2026-11-21)

Independent code and security review of everything 002 changed (`210fe9e..HEAD`). Verdict: no
blocking defects; not done until the owner checks T039–T041 pass. 153 tests passed; the app
builds and signs with hardened runtime and only the App Group entitlement (plus Xcode's Debug
`get-task-allow`).

| # | Finding | Outcome |
|---|---------|---------|
| I-1 | `ledger.json` not flushed before the rename; an empty ledger read as "nothing recorded", so Reset All could "succeed" after a crash while overrides stay set | Fixed: temp file, `F_FULLFSYNC`, rename; an empty ledger is an error |
| I-2 | The data model's complete list of files missed what macOS writes for the app | Fixed: listed what exists on 26B131 (preferences plist, Application Scripts folders, cache folder) and what may exist (privacy records, icon cache); README undo steps and quickstart 13 updated |
| I-3 | A mapped folder in a privacy-protected location may prompt, and show Folder missing if denied (untested) | Quickstart 13 step added; code change F013 after the live check |
| M-1 | A link above `Icons/` (container path) would redirect Reset All's deletes | Follow-up F014 |
| M-2 | A failed Off showed plain Off after a relaunch | Fixed: derived from the ledger |
| M-3 | The bundle can keep a removed icon's type until the next rewrite (recorded; Reset All cleans it) | Follow-up F015 |
| M-4 | A symlinked image was copied as a link | Fixed: the link's target is copied |
| M-5 | `PRIVATE_API.md` still had spike-era text (PA-01, PA-02, PA-05) | Fixed |
| M-6 | Running the spike after the app clears the app's icons | README: Reset All in the app before running the spike |
| M-7 | Debug build for daily use; Developer ID wording | Follow-up F016 |
| M-8 | `load()` not guarded by `exclusive` (unreachable from the app) | Follow-up F017 |
| Questions | Finder quit via Apple Event; Recent Items/xattrs; remote resources in SVG/PDF; Finder-extension conflict edge case | Follow-ups F018–F020 |

FR/SC status from the review: FR-011, FR-013 and SC-002 need T040; SC-004 and SC-005 need T041;
SC-001 is likely but unproven (icon seen at 12 s, override set at 6 s); SC-003 has no timing yet.

## Final verification (owner)

| Check | Result | Notes |
|-------|--------|-------|
| 11 Light/dark/accent (T039) | Pass | Run by the owner, 2026-11-22 |
| 12 Scale and persistence (T040) | Pass | 2026-11-22: 22 mappings (20 test folders `~/Sidebar Icons Test/Test 01…20` with numbered icons, plus `dev` and `DevDocs`), codes `S001`–`S00M`; all shown in order. The owner combined logout with a reboot: all icons persisted. After the reboot `lsregister -dump` still listed the registry bundle with all 22 types (FR-011, FR-013, SC-002) |
| 13a Protected folder (T041, final review I-3) | Pass | 2026-11-22: a subfolder of `~/Documents` was mapped; the app, launched directly (not from Xcode), was quit and reopened. No privacy prompt appeared, the row said Applied, the icon showed, and Sidebar Icons is not listed in Privacy & Security → Files & Folders. The app only resolves paths and reads the Favorites list, which macOS doesn't gate on 26B131. F013 closed |
| 13 Leftovers (T041, SC-004) | Pass | 2026-11-22: after the owner's Reset All, 0 Favorites with an override and no `IconRegistry.app` or `sidebaricons.icon` type in `lsregister -dump`. The app's build folders, its preferences plist, its Application Scripts folders, its cache folder and the test material were moved to the Trash; the app's own and 4 stale scratch-build registrations were removed with `lsregister -u`; the 21 test Favorites were removed from the sidebar (7 original Favorites remain). macOS refused to let a shell move three protected containers: the app's group container and the spike's two sandbox containers; the owner moved them to the Trash in Finder (selected in their parent folder, ⌘⌫). Afterwards no `SidebarIcons` container remains |
| 14 Folders untouched (T041, SC-005) | Pass | `~/dev`, `~/DevDocs`, `~/Documents` and `~/Documents/PrivacyTest`: no `Icon\r` file, no custom-icon Finder flag, permissions and owner unchanged; nothing was renamed or moved (the test folders were the only folders created, and they were removed) |

