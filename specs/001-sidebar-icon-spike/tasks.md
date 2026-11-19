---

description: "Task list for the sidebar icon feasibility spike"
---

# Tasks: Sidebar Icon Feasibility Spike

**Input**: Design documents from `/specs/001-sidebar-icon-spike/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included. The constitution requires Swift Testing for model, ledger, and adapter logic.
Finder-visible behavior is verified manually with quickstart.md.

**Organization**: Tasks are grouped by user story so each story can be implemented and tested on
its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- **(owner)**: Must be done by the owner in Xcode or Finder; cannot be automated

## Path Conventions

Paths follow plan.md: `README.md` and `PRIVATE_API.md` at the repository root,
`spike/SidebarIconSpike/`, `spike/SpikeFinderSync/`,
`spike/SidebarIconCore/Sources/SidebarIconCore/`, `spike/SidebarIconCore/Tests/SidebarIconCoreTests/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project skeleton, signing, shared container, and the public private-API register

- [ ] T001 (owner) Create `spike/SidebarIconSpike.xcodeproj` in Xcode: macOS App target `SidebarIconSpike` (SwiftUI) plus Finder Sync Extension target `SpikeFinderSync`; select the Apple Developer team for both
- [ ] T002 (owner) Add the App Group `<TEAMID>.com.<owner>.SidebarIcons` to both targets; enable App Sandbox on `spike/SpikeFinderSync/SpikeFinderSync.entitlements` only; turn off App Sandbox and keep Hardened Runtime on `spike/SidebarIconSpike/SidebarIconSpike.entitlements`
- [ ] T003 Create local package `spike/SidebarIconCore/Package.swift` (swift-tools-version 6.0, platform macOS 27, library `SidebarIconCore`, test target `SidebarIconCoreTests` using Swift Testing) and link it to both Xcode targets
- [ ] T004 [P] Add bundled template-style icons `spike/SidebarIconSpike/Resources/Icons/dev.pdf` and `spike/SidebarIconSpike/Resources/Icons/ai.pdf` (single color, square, vector)
- [ ] T005 [P] Add `.gitignore` entries for Xcode output (`DerivedData/`, `*.xcuserstate`, `xcuserdata/`, `.build/`) at repository root
- [ ] T006 [P] Create `PRIVATE_API.md` at repository root (Constitution VI). One entry per planned use, each with the six required fields (symbol/key and framework; status; purpose and calling file; verified/failed macOS builds; risks; reset path and removal path), all marked "planned, unverified": `LSSharedFileListCreate` + `kLSSharedFileListFavoriteItems` + `LSSharedFileListCopySnapshot` + `LSSharedFileListItemCopyResolvedURL` (deprecated since 10.11, SharedFileList); `LSSharedFileListItemCopyProperty` / `LSSharedFileListItemSetProperty` (deprecated since 10.11); property key `com.apple.LSSharedFileList.OverrideIcon.OSType` (undocumented); Finder's lookup of a sidebar icon through a `CFBundleDocumentTypes` / `CFBundleTypeOSTypes` registration (undocumented behavior; `LSRegisterURL` itself is public); `lsregister -u` and `lsregister -dump` (undocumented system tool). Cite research.md R2, R3, R7, R8 as sources
- [ ] T007 [P] Create `README.md` at repository root: one-paragraph purpose, a notice within the first screen that the utility relies on undocumented macOS behavior with a link to `PRIVATE_API.md`, build prerequisites, and a link to `specs/001-sidebar-icon-spike/quickstart.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Model, ledger, container access, and the provider seam that every story uses

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T008 [P] Write tests for the model rules in `spike/SidebarIconCore/Tests/SidebarIconCoreTests/ModelTests.swift`: `folderPath` "Absolute, standardized (`~` expanded, symlinks resolved, no trailing `/`). Unique across mappings"; `osType` "Exactly 4 ASCII characters, format `S[0-9A-Z]{3}`... Unique across mappings"
- [ ] T009 [P] Write tests for the ledger in `spike/SidebarIconCore/Tests/SidebarIconCoreTests/LedgerStoreTests.swift`: entry persisted before apply callback runs; failed apply deletes the entry; failed undo keeps it; reading an empty or missing ledger succeeds
- [ ] T010 [P] Implement `SidebarMapping`, `IconAsset`, `OutsideChange` in `spike/SidebarIconCore/Sources/SidebarIconCore/Model/` per data-model.md (Codable, Sendable; `IconAsset.sourceFormat` enum `pdf`, `png`, `svg`, `icns`; `OutsideChange.kind` enum `iconRegistration`, `sidebarOverride`)
- [ ] T011 Implement path standardization and the `OSTypeAllocator` (`S` + three base-36 characters, skipping codes still referenced by the ledger) in `spike/SidebarIconCore/Sources/SidebarIconCore/Icons/OSTypeAllocator.swift`
- [ ] T012 Implement `ContainerLocator` (App Group URL → `Library/Application Support/SidebarIcons/`, creates `Icons/`) in `spike/SidebarIconCore/Sources/SidebarIconCore/Ledger/ContainerLocator.swift`
- [ ] T013 Implement `LedgerStore` (atomic JSON writes to `ledger.json`, write-before-apply API) in `spike/SidebarIconCore/Sources/SidebarIconCore/Ledger/LedgerStore.swift`
- [ ] T014 Define `SidebarIconProvider`, `MappingStatus`, `ApplyReport`, `ResetReport`, `SidebarIconError` exactly as in `contracts/sidebar-icon-provider.md` in `spike/SidebarIconCore/Sources/SidebarIconCore/Providers/SidebarIconProvider.swift`
- [ ] T015 Implement `FinderRestarter` (terminate `com.apple.finder` via `NSRunningApplication`, wait for relaunch, report time taken) in `spike/SidebarIconCore/Sources/SidebarIconCore/Finder/FinderRestarter.swift`
- [ ] T016 Build the spike window shell with a scrolling status log and the buttons List Favorites, Apply (Path A), Apply (Path B), Use runtime icon for AI, Refresh Finder, Reset in `spike/SidebarIconSpike/SpikeView.swift`; buttons call stubs for now
- [ ] T017 Hard-code the two mappings (`~/dev` → dev.pdf, `~/Cloud Shortcuts/AI` → ai.pdf) in `spike/SidebarIconSpike/SpikeMappings.swift`; log and skip folders that do not exist

**Checkpoint**: `swift test --package-path spike/SidebarIconCore` passes; the app launches and shows the window

---

## Phase 3: User Story 1 - Two Favorites, two built-in custom icons (Priority: P1) 🎯 MVP

**Goal**: Both Favorites show distinct custom icons, persisting across Finder restarts and logout,
with folder icons untouched. Path A is tried first and recorded.

**Independent Test**: quickstart.md steps 1–6

### Path A (public API first, FR-005)

- [ ] T018 [US1] Implement `SpikeFinderSync/FinderSync.swift`: set `FIFinderSyncController.default().directoryURLs` to the two hard-coded roots at startup; log via `os.Logger` (subsystem `com.<owner>.SidebarIcons`)
- [ ] T019 [US1] Implement `FinderSyncProvider` (status = extension enabled + roots watched; apply/reset are no-ops that report "no public sidebar-icon API") in `spike/SidebarIconCore/Sources/SidebarIconCore/Providers/FinderSyncProvider.swift`
- [ ] T020 [US1] (owner) Run quickstart step 1 and record experiment A1 in `specs/001-sidebar-icon-spike/research.md` Findings
- [ ] T021 [US1] (owner approval needed for network) Check Apple's current Finder Sync documentation for any sidebar-icon key or behavior; record A2 in `specs/001-sidebar-icon-spike/research.md`. If A1/A2 find a working public route, implement it in `FinderSyncProvider`, mark every `PRIVATE_API.md` entry "removed — not needed, public route found", and skip T022–T029

### Path B (Launch Services override, isolated adapter)

- [ ] T022 [P] [US1] Write tests for the registration bundle builder in `spike/SidebarIconCore/Tests/SidebarIconCoreTests/IconRegistryBundleTests.swift`: Info.plist has one `CFBundleDocumentTypes` entry per mapping with `CFBundleTypeOSTypes` = `[osType]` and `CFBundleTypeIconFile` = `<assetID>.icns`; output is deterministic
- [ ] T023 [P] [US1] Implement ICNS conversion from PDF/PNG/SVG via ImageIO `CGImageDestination` (16–1024 px, square-padded) in `spike/SidebarIconCore/Sources/SidebarIconCore/Icons/ICNSConverter.swift`
- [ ] T024 [US1] Implement `IconRegistryBundle` builder that writes `IconRegistry.bundle` (Info.plist + Resources/*.icns) into the container in `spike/SidebarIconCore/Sources/SidebarIconCore/Icons/IconRegistryBundle.swift`
- [ ] T025 [US1] Implement read-only `status` in `LaunchServicesOverrideProvider` (list Favorites with `LSSharedFileListCreate(kLSSharedFileListFavoriteItems)`, resolve URLs, read `com.apple.LSSharedFileList.OverrideIcon.OSType`) in `spike/SidebarIconCore/Sources/SidebarIconCore/Providers/LaunchServicesOverrideProvider.swift`; wire to List Favorites; in the same commit, set the calling file in the matching `PRIVATE_API.md` entries
- [ ] T026 [US1] (owner) Run quickstart step 2 and record B1. If Favorites are unavailable, stop: record "no-go", mark the affected `PRIVATE_API.md` entries "removed — failed on <build>", and skip to T039
- [ ] T027 [US1] Implement `apply` in `LaunchServicesOverrideProvider`: ledger entry → `LSRegisterURL(bundle, true)`; for each enabled mapping, ledger entry → `LSSharedFileListItemSetProperty(item, "com.apple.LSSharedFileList.OverrideIcon.OSType", osType)`; skip and report folders not in Favorites; update the matching `PRIVATE_API.md` entries in the same commit
- [ ] T028 [US1] Before registering, check `lsregister -dump` (read-only) for other claims on the allocated codes; record in research.md (R7 check)
- [ ] T029 [US1] (owner) Run quickstart steps 3–6 and record B2, B4, and the folder-icon check in `specs/001-sidebar-icon-spike/research.md`

**Checkpoint**: SC-001 and SC-002 recorded as pass or fail

---

## Phase 4: User Story 2 - One icon chosen at runtime (Priority: P2)

**Goal**: The AI Favorite shows an image picked after the build, without rebuilding.

**Independent Test**: quickstart.md steps 7–8

- [ ] T030 [P] [US2] Write tests for asset import in `spike/SidebarIconCore/Tests/SidebarIconCoreTests/AssetImporterTests.swift`: format detected from content type, not extension; copy lands at `Icons/<uuid>.<ext>`; original file untouched
- [ ] T031 [US2] Implement `AssetImporter` (copy the chosen file into `Icons/`, create `IconAsset`) in `spike/SidebarIconCore/Sources/SidebarIconCore/Icons/AssetImporter.swift`
- [ ] T032 [US2] Wire "Use runtime icon for AI": `NSOpenPanel` (PDF, PNG, SVG) → `AssetImporter` → rebuild `IconRegistry.bundle` → re-register → re-apply; time from click to visible icon in `spike/SidebarIconSpike/SpikeView.swift`
- [ ] T033 [US2] (owner) Run quickstart steps 7–8; record B3, including whether the runtime-generated unsigned bundle is accepted and whether Refresh Finder was needed (research R4 open sub-question); add the result to the icon-registration entry's risks in `PRIVATE_API.md`

**Checkpoint**: SC-003 recorded

---

## Phase 5: User Story 3 - Full reset (Priority: P3)

**Goal**: Reset returns both Favorites to the generic glyph and leaves no trace.

**Independent Test**: quickstart.md steps 9–10

- [ ] T034 [P] [US3] Write tests for reset ordering in `spike/SidebarIconCore/Tests/SidebarIconCoreTests/ResetTests.swift`: overrides cleared before unregistration; reset twice is a no-op; partial failure leaves the failed entries in the ledger
- [ ] T035 [US3] Implement `reset` in `LaunchServicesOverrideProvider`: clear the property on every `sidebarOverride` ledger entry, then `lsregister -u` and delete `IconRegistry.bundle`, removing each ledger entry after success; fill in the reset path of each `PRIVATE_API.md` entry in the same commit
- [ ] T036 [US3] Wire Reset and Refresh Finder buttons in `spike/SidebarIconSpike/SpikeView.swift`; Refresh Finder asks for confirmation first
- [ ] T037 [US3] (owner) Run quickstart steps 9–10; record B6

**Checkpoint**: SC-004 recorded

---

## Phase 6: Polish & Findings

- [ ] T038 (owner) Run quickstart step 11 with a sandboxed build configuration; record B5
- [ ] T039 (owner) Run the spec's edge cases once each (another extension watching a folder, nested roots, missing folder, light/dark and accent color, non-square image); record in research.md
- [ ] T040 Bring `PRIVATE_API.md` up to date with the Findings: set verified and failed macOS builds for every entry, replace "planned, unverified" with the observed status, and mark any use that was tried and abandoned "removed" with the reason (Constitution VI)
- [ ] T041 Complete the Findings table and the "Recommended path for 002" line in `specs/001-sidebar-icon-spike/research.md` (SC-005)
- [ ] T042 Independent code review plus security review of `LaunchServicesOverrideProvider.swift`, `FinderRestarter.swift`, and both entitlements files (constitution: private adapter and sandbox changes); the review fails if any private call in the code has no matching `PRIVATE_API.md` entry, or any entry names a call not in the code
- [ ] T043 Update `specs/002-mapping-manager-v1/spec.md` assumptions with the chosen path, then unblock its `/speckit-plan`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 → T002 → T003; T004–T007 in parallel with T003
- **Foundational (Phase 2)**: depends on Setup; blocks all stories
- **US1 (Phase 3)**: depends on Foundational. Path A (T018–T021) before Path B (T022–T029), per FR-005
- **US2 (Phase 4)**: depends on US1's working provider (T027)
- **US3 (Phase 5)**: depends on T027 (something to reset); can be built in parallel with US2
- **Polish (Phase 6)**: after all stories, or straight away if T026 records "no-go". T040 before T042

### Within Each Story

- Tests are written and fail before the matching implementation
- Ledger writes happen before every outside change (Constitution V)
- Any task that adds or changes a private call updates `PRIVATE_API.md` in the same commit (Constitution VI)
- Every (owner) run records results in research.md before the next phase starts

### Parallel Opportunities

- T004–T007 alongside T003
- T008, T009, T010 together
- T022, T023 together
- After T027: Phase 4 (T030–T033) and Phase 5 (T034–T037) in parallel

## Parallel Example: User Story 1 (Path B)

```text
Task: "T022 Write tests for the registration bundle builder in .../IconRegistryBundleTests.swift"
Task: "T023 Implement ICNS conversion in .../Icons/ICNSConverter.swift"
```

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phases 1–2, then Phase 3.
2. **STOP**: if SC-001 and SC-002 pass, the project is feasible. If B1 or B2 fails, record "no-go"
   and do not start 002.

### Incremental Delivery

1. US1 proves feasibility with bundled icons.
2. US2 proves runtime icons (this decides how 002 handles icons).
3. US3 proves clean removal (required before using 002 on a work machine).
4. T040 brings the register up to date; T041 writes the decision; T043 unblocks 002.

## Notes

- `spike/` is disposable; only `SidebarIconCore` is a reuse candidate for 002. `PRIVATE_API.md` and
  `README.md` are permanent.
- Keep every private-behavior call inside `LaunchServicesOverrideProvider.swift`.
- Rollback at any point: quickstart.md#rollback.
