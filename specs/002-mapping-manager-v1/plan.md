# Implementation Plan: Sidebar Icon Mapping Manager v1

**Branch**: `002-mapping-manager-v1` | **Date**: 2026-11-20 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-mapping-manager-v1/spec.md`

## Summary

A single-window macOS app, **Sidebar Icons**, that keeps a list of folder → icon mappings and
makes each Finder sidebar Favorite show its own full-colour icon.

- **Mechanism**: the one proven by spike 001 (Path B). The sidebar override code plus a
  runtime-generated `IconRegistry.app` that exports one type per icon, so the app needs no
  extension and no running code.
- **Engine**: the spike's tested `SidebarIconCore` package becomes the engine, moved to
  `Packages/`. 002 adds a configuration store and a `MappingManager` that the SwiftUI window
  drives.
- **Starter scope**, built first: Story 1 (Add Folder + Pick Icon, applied at once, persists) and
  Story 4 (Refresh Finder, Reset All). Stories 2 (on/off, remove, change icon) and 3 (preview
  sheet, warnings) follow on the same design.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency), Xcode 27.2

**Primary Dependencies**: SwiftUI, AppKit (`NSOpenPanel`, `NSWorkspace`, `NSRunningApplication`),
ImageIO, CoreServices (`LSSharedFileList`, `LSRegisterURL`); no third-party code

**Storage**: App Group container `45GJWJVQN2.com.altmansoftwaredesign.SidebarIcons`, holding:
- `config.json` (versioned);
- `ledger.json` (change records);
- `Icons/` (copied images and `.icns` files);
- `IconRegistry.app` (the registry bundle).

**Testing**: Swift Testing for the package (config store, manager, allocator, provider through
`FakeLaunchServices`). A written manual checklist (quickstart) covers what Finder shows.

**Target Platform**: macOS 27+, verified on 27.2.1 (26B131)

**Project Type**: desktop app (SwiftUI) plus a local Swift package

**Performance Goals**:
- Add or apply shows the icon within 10 s, typically about 3 s with no Finder restart (001 B3).
- Status for 20 mappings in under 1 s (one Favorites snapshot plus one `lsregister -dump`).

**Constraints**:
- Not sandboxed (001 B5). Hardened runtime.
- No network, daemon, login item or helper.
- Outside changes only on explicit actions (research D6).

**Scale/Scope**: 1 user; at least 20 mappings (FR-013); one window plus an About window

## Constitution Check

*GATE: checked before Phase 0 and again after Phase 1 design.*

| Principle | Check | Result |
|-----------|-------|--------|
| I. Inspectable and Boring | Swift and Apple frameworks only; one app target, one package; no network, telemetry, updater, daemon, login item or helper. Every file written is listed in data-model.md "Files". | Pass |
| II. Public API first, private behind one adapter | Public API was shown insufficient by 001 (A1, folder icon, R1). All private behavior stays in `LaunchServicesOverrideProvider.swift`; the GUI and `MappingManager` use only the `SidebarIconProvider` protocol. `.sfl*` files are never touched. | Pass |
| III. User data never modified | Folders are only read for existence. Images are copied into `Icons/`, and originals are never needed again. The folder's own Finder icon is never set (001 tried `NSWorkspace.setIcon` only in a reverted experiment). | Pass |
| IV. Prove before building | Every behavior this plan depends on passed in 001 on 26B131 (B1–B4, B6). FR-011 logout/reboot is a verification step, not a new assumption (research D10). | Pass |
| V. Explicit, reversible side effects | Outside changes only from the actions in research D6; the ledger is written before each change; Reset All undoes everything, including the spike's leftovers (shared ledger). | Pass |
| VI. Private API documented | No new private use; `PRIVATE_API.md` call sites are updated for the package move. The About window names the register (D11). | Pass |
| Sandbox SHOULD | The main app is not sandboxed. | Justified in Complexity Tracking |

Re-check after Phase 1 design: unchanged, Pass. The contracts add no private calls, and the data
model lists every file.

## Project Structure

### Documentation (this feature)

```text
specs/002-mapping-manager-v1/
├── spec.md
├── plan.md              # this file
├── research.md          # D1–D11
├── data-model.md        # config, entities, status, files on disk
├── quickstart.md        # build, run, manual checklist incl. logout/reboot
├── contracts/
│   ├── mapping-manager.md   # engine API the GUI uses
│   └── ui.md                # window, actions, confirmations, messages
└── tasks.md             # next step (/speckit-tasks)
```

### Source Code (repository root)

```text
Packages/SidebarIconCore/                 # moved from spike/SidebarIconCore (git mv)
├── Package.swift
├── Sources/SidebarIconCore/
│   ├── Config/
│   │   ├── AppConfiguration.swift        # NEW: versioned config model
│   │   └── ConfigStore.swift             # NEW: atomic load/save, schema check
│   ├── Manager/
│   │   ├── MappingManager.swift          # NEW: add/apply/remove/reset orchestration
│   │   └── MappingState.swift            # NEW: per-mapping status enum (research D7)
│   ├── Icons/ …                          # existing; allocator gains claimed-code skipping,
│   │                                     # ICNS write becomes temp+move with validation
│   ├── Providers/ …                      # existing adapter (unchanged API) + "no enabled
│   │                                     # mapping left" unregisters the bundle
│   ├── Ledger/ …  Model/ …  Finder/ …    # existing
│   └── SidebarIconCoreInfo.swift         # + verifiedBuilds
└── Tests/SidebarIconCoreTests/           # existing 80 tests + ConfigStore/Manager tests

app/
├── SidebarIcons.xcodeproj                # NEW: one app target "Sidebar Icons"
└── SidebarIcons/
    ├── SidebarIconsApp.swift             # Window + About
    ├── AppModel.swift                    # @MainActor @Observable wrapper over MappingManager
    ├── MappingListView.swift             # rows: icon (light/dark), folder, status, actions
    ├── AddMappingFlow.swift              # NSOpenPanel folder → image, errors
    ├── AboutView.swift                   # Constitution VI text
    ├── Assets.xcassets                   # app icon
    └── SidebarIcons.entitlements         # App Group only

spike/                                    # retired harness; project now references
                                          # ../Packages/SidebarIconCore
```

**Structure Decision**:
- One package, `Packages/SidebarIconCore`, holds every rule and every outside change, so all of it
  is unit-tested.
- The app is a thin SwiftUI layer over `MappingManager`.
- The spike project stays and builds against the moved package, so the experiments can be re-run
  on new macOS builds.

## Phasing

1. **Starter** (P1 and P4):
   - Package move.
   - `ConfigStore`, `MappingManager` add/apply/status/refresh/reset.
   - Allocator and `.icns` hardening.
   - App window with the list, Add, Refresh Finder, Reset All, and About.
   - Quickstart checks 1–6.
2. **Story 2**: turn on/off, remove (confirm), change icon; unregister when no enabled mapping is
   left. Quickstart checks 7–9.
3. **Story 3**: preview sheet before apply, with the non-square/detail warning. Quickstart check 10.
4. **Verification**: 20 mappings, logout, reboot (SC-002, FR-011); light/dark and accent colour;
   leftover checklist after Reset All and app deletion (SC-004).

## Rollback

- In the app, click **Reset All** and confirm, then **Refresh Finder**. Every Favorite shows its
  folder glyph, and `lsregister -dump` lists no `IconRegistry.app`.
- Quit the app, then delete `Sidebar Icons.app` and the container
  `~/Library/Group Containers/45GJWJVQN2.com.altmansoftwaredesign.SidebarIcons`.
- If the app can't run: open the spike app and click Reset; it shares the ledger.
- Manual fallback: remove each Favorite and drag its folder back in.
- There is no extension to disable.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Main app not sandboxed (Constitution: main app SHOULD be sandboxed) | 001 B5: a sandboxed build lists 0 Favorites, so Path B cannot run sandboxed | A sandboxed app plus a non-sandboxed helper: adds a second signed binary and IPC, and a helper that runs with the same privileges anyway; Constitution I prefers fewer moving parts |
| Package moved to `Packages/` and shared by the spike and the app | One tested engine | Copying the package: two engines drift; keeping it under `spike/`: the shipped app would depend on the experiment folder |
