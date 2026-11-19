# Implementation Plan: Sidebar Icon Feasibility Spike

**Branch**: `001-sidebar-icon-spike` | **Date**: 2026-11-17 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-sidebar-icon-spike/spec.md`

## Summary

Build a disposable macOS app plus Finder Sync extension that hard-codes two Favorites
(`~/dev`, `~/DevDocs`) and tries to give each its own sidebar icon. It tries the public
Finder Sync route first (Path A). The SDK has no public per-folder sidebar-icon API (research R1), so
the spike then tries the Launch Services override route (Path B): register an icon bundle with
project-specific OSType codes and set `com.apple.LSSharedFileList.OverrideIcon.OSType` on each
Favorite through the deprecated, still-exported `LSSharedFileList` API (R2, R3). Both routes sit
behind one `SidebarIconProvider` protocol. Every outside change is written to a ledger so reset can
undo it. Every private or undocumented use is listed in the public `PRIVATE_API.md` register
(Constitution VI). The deliverable is the Findings table in research.md, which picks the path for
feature 002.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency), Xcode 27.2

**Primary Dependencies**: Apple frameworks only: SwiftUI, AppKit, FinderSync, CoreServices
(Launch Services, SharedFileList), ImageIO, UniformTypeIdentifiers

**Storage**: JSON files (`ledger.json`; `config.json` reserved for 002) and copied icon assets in
the team-prefixed App Group container

**Testing**: Swift Testing in a local Swift package (`SidebarIconCore`) for model, ledger, OSType
allocation, and icon conversion; manual Finder checklist in quickstart.md for visible behavior

**Target Platform**: macOS 27+ (macOS 26 only if a test machine is already available, research R9)

**Project Type**: desktop app (host app + Finder Sync app extension + local Swift package)

**Performance Goals**: runtime icon visible within 10 s of refresh (SC-003)

**Constraints**: offline; no admin password; no third-party code; no `.sfl*` access; every outside
change reversible by reset

**Scale/Scope**: 2 hard-coded mappings, 1 runtime icon swap, about 6 experiments

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Pre-research | Post-design | Notes |
|-----------|--------------|-------------|-------|
| I. Inspectable and Boring | Pass | Pass | Apple frameworks only; no network, daemon, helper, or login item. `lsregister` is a system tool, not a dependency |
| II. Public API First, Private Behind One Adapter | Pass | Pass | Path A runs first (FR-005). Path B is confined to `LaunchServicesOverrideProvider` behind `SidebarIconProvider`. No `.sfl*` access |
| III. User Data Is Never Modified | Pass | Pass | Provider contract forbids folder or folder-icon changes; quickstart step 5 verifies |
| IV. Prove Before Building | Pass | Pass | This feature *is* the proof; 002's plan is gated on the Findings table |
| V. Explicit, Reversible Side Effects | Pass | Pass | Ledger written before each change; Finder restart only on an explicit button; reset is idempotent |
| VI. Private API Use Is Publicly Documented | Pass | Pass | `PRIVATE_API.md` is created in Setup with every planned Path B use marked "unverified". Each task that adds a private call updates its entry in the same commit, the Findings fill in verified and failed builds, and review fails adapter changes without a register update. The About-window clause applies to the shipped app (002), not this spike; the README link applies now |
| Platform: App sandbox SHOULD | Deviation | Deviation | Host app not sandboxed; see Complexity Tracking. B5 tests whether 002 can sandbox it |

## Project Structure

### Documentation (this feature)

```text
specs/001-sidebar-icon-spike/
├── plan.md
├── research.md          # includes the Findings table filled during implementation
├── data-model.md
├── quickstart.md
├── contracts/
│   └── sidebar-icon-provider.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
README.md                             # links to PRIVATE_API.md near the top (Constitution VI)
PRIVATE_API.md                        # public register of private/undocumented API use

spike/
├── SidebarIconSpike.xcodeproj
├── SidebarIconSpike/                 # host app (not sandboxed, hardened runtime)
│   ├── SidebarIconSpikeApp.swift
│   ├── SpikeView.swift               # buttons: List Favorites, Apply A, Apply B,
│   │                                 # Use runtime icon, Refresh Finder, Reset; status log
│   ├── (bundled test icons referenced from ../folder-icon/)
│   └── SidebarIconSpike.entitlements # App Group only
├── SpikeFinderSync/                  # Finder Sync extension (sandboxed)
│   ├── FinderSync.swift              # directoryURLs = two hard-coded roots
│   ├── Info.plist
│   └── SpikeFinderSync.entitlements  # sandbox + App Group
└── SidebarIconCore/                  # local Swift package, linked by both targets
    ├── Package.swift
    ├── Sources/SidebarIconCore/
    │   ├── Model/                    # SidebarMapping, IconAsset, OutsideChange
    │   ├── Ledger/                   # LedgerStore (JSON, write-before-apply)
    │   ├── Icons/                    # ICNS conversion, OSType allocator
    │   ├── Providers/
    │   │   ├── SidebarIconProvider.swift
    │   │   ├── FinderSyncProvider.swift            # Path A
    │   │   └── LaunchServicesOverrideProvider.swift # Path B (only file touching private behavior)
    │   └── Finder/FinderRestarter.swift
    └── Tests/SidebarIconCoreTests/
```

**Structure Decision**: Core logic lives in a local Swift package so it can be tested with
`swift test` without Finder, and so feature 002 can reuse it. `PRIVATE_API.md` sits at the repository root, not under
`spike/`, because it outlives the spike and also covers feature 002. The Xcode project is created in Xcode's
UI by the owner (T001), because the signing team and App Group must be chosen with the owner's
account. Spike code lives under `spike/` to show it is disposable.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Host app not sandboxed | Path B needs deprecated `LSSharedFileList` calls and `LSRegisterURL` on a runtime bundle, which the sandbox is not expected to allow (R6) | A sandboxed app cannot run the Path B experiments at all; a separate unsandboxed helper adds a second process for a disposable spike. B5 measures whether 002 can avoid this |
| Use of deprecated/undocumented Launch Services behavior | The SDK has no public per-folder sidebar-icon API (R1), and custom sidebar icons are a firm owner requirement | Path A alone cannot meet FR-001 unless experiments A1/A2 find something unexpected; direct `.sfl*` editing is prohibited |

## Rollback

Reset in the spike, Refresh Finder, disable the extension, delete the app and the App Group
container. Full steps: [quickstart.md#rollback](quickstart.md#rollback).
