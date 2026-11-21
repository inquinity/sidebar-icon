---

description: "Task list for Sidebar Icon Mapping Manager v1"
---

# Tasks: Sidebar Icon Mapping Manager v1

**Input**: Design documents from `/specs/002-mapping-manager-v1/`

**Prerequisites**: plan.md, spec.md, research.md (D1–D11), data-model.md, contracts/, quickstart.md

**Tests**: Included. The constitution requires Swift Testing for model, configuration, and adapter
logic. Finder-visible behavior is verified manually with quickstart.md.

**Order**:
1. The starter MVP: User Story 1 and User Story 4 (plan.md Phasing 1).
2. Story 2.
3. Story 3.
4. Verification.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US4)
- **(owner)**: Must be done by the owner in Xcode, Finder or System Settings

## Path Conventions

- Engine: `Packages/SidebarIconCore/Sources/SidebarIconCore/` (abbreviated `Core/` below).
- Tests: `Packages/SidebarIconCore/Tests/SidebarIconCoreTests/` (abbreviated `Tests/`).
- App: `app/SidebarIcons/`, project `app/SidebarIcons.xcodeproj`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Move the engine, create the app project.

- [X] T001 Move the package with `git mv spike/SidebarIconCore Packages/SidebarIconCore` (research D1). Update the `XCLocalSwiftPackageReference` `relativePath` in `spike/SidebarIconSpike.xcodeproj/project.pbxproj` to `../Packages/SidebarIconCore`. Verify `swift test` in `Packages/SidebarIconCore` (80 tests pass) and `xcodebuild -project spike/SidebarIconSpike.xcodeproj -scheme SidebarIconSpike build`
- [X] T002 Update every path that names `spike/SidebarIconCore` to `Packages/SidebarIconCore`: `PRIVATE_API.md` calling-file lines (PA-01–PA-05), `README.md`, and `specs/001-sidebar-icon-spike/plan.md` (add a note that the package moved in 002; leave historical tasks as they are)
- [X] T003 Create `app/SidebarIcons.xcodeproj` (objectVersion 77, file-system-synchronized group `SidebarIcons`) with one macOS App target `Sidebar Icons`:
  - product name `Sidebar Icons`, bundle ID `com.altmansoftwaredesign.SidebarIcons`;
  - `MACOSX_DEPLOYMENT_TARGET` 27.0, Swift 6 with strict concurrency;
  - `DEVELOPMENT_TEAM` 45GJWJVQN2, hardened runtime on, App Sandbox off;
  - `CODE_SIGN_ENTITLEMENTS` `SidebarIcons/SidebarIcons.entitlements`;
  - `ASSETCATALOG_COMPILER_APPICON_NAME` AppIcon;
  - a local package dependency on `../Packages/SidebarIconCore` (product `SidebarIconCore`);
  - a shared scheme `Sidebar Icons`.

  Verify with `xcodebuild … build`
- [X] T004 [P] Create `app/SidebarIcons/SidebarIcons.entitlements` with only `com.apple.security.application-groups` = `$(TeamIdentifierPrefix)com.altmansoftwaredesign.SidebarIcons` (no sandbox key; plan Complexity Tracking)
- [X] T005 [P] Create `app/SidebarIcons/Assets.xcassets` with an `AppIcon` (mac sizes 16–512 at 1x and 2x) generated from `folder-icon/macOS-dev-folder-icon.png` with `sips`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Config store, status model, allocator and `.icns` hardening, verified-build list.
These are needed by every story.

**⚠️ CRITICAL**: No story work can begin until this phase is complete.

- [X] T006 [P] Write tests in `Tests/ConfigStoreTests.swift`:
  - a missing file loads as empty, `schemaVersion: 1`;
  - save then load round-trips mappings and assets;
  - a save is atomic: a leftover `config.json.tmp` from a failed save leaves `config.json` intact;
  - "`schemaVersion` greater than 1, or unreadable JSON" throws `configUnreadable` and does not overwrite the file;
  - an asset no mapping refers to is dropped on save, and its files are deleted.
- [X] T007 [P] Write tests in `Tests/AllocatorClaimsTests.swift`: allocation skips codes in the config, codes in the ledger, and codes claimed elsewhere (feed `S001` as claimed → returns `S002`); it fails only when the range is exhausted
- [X] T008 [P] Write tests in `Tests/ICNSHardeningTests.swift`:
  - conversion writes through `<id>.icns.tmp` and leaves no `.tmp` behind;
  - a zero-byte or unreadable `<id>.icns` is rebuilt on next use;
  - an existing valid `.icns` is reused.
- [X] T009 Implement `Core/Config/AppConfiguration.swift`: `Codable` `{schemaVersion: Int, mappings: [SidebarMapping], assets: [IconAsset]}`. "Valid when `SidebarMapping.validate` returns no problems and every `iconAssetID` resolves"
- [X] T010 Implement `Core/Config/ConfigStore.swift`: `load()` and `save(_:)` at `ContainerLocator.configURL`. Write `config.json.tmp`, then `FileManager.replaceItemAt`. Throw `configUnreadable(String)` for unknown schema or invalid JSON. On save, prune unreferenced assets and delete their `Icons/` files (makes T006 pass)
- [X] T011 Extend `Core/Icons/OSTypeAllocator.swift`: `allocate(_:excluding:isClaimed:)`, where `isClaimed: (String) throws -> Bool` is backed by `system.claims(on:)`; skip claimed codes instead of failing (research D4; makes T007 pass)
- [X] T012 Harden `LaunchServicesOverrideProvider.icnsFile(for:)` in `Core/Providers/LaunchServicesOverrideProvider.swift` and `Core/Icons/ICNSConverter.swift`. Convert to `<id>.icns.tmp`, then move into place. Treat an existing `.icns` that `CGImageSourceCreateWithURL` cannot open, or that has 0 images, as missing (research D5; makes T008 pass)
- [X] T013 [P] Implement `Core/Manager/MappingState.swift`: `enum MappingState { applied, off, notInSidebar, folderMissing, notApplied, error(String) }`, with a pure function `state(for:status:bundleRegistered:lastFailure:)` following research D7. Add its tests in `Tests/MappingStateTests.swift`, one case per table row
- [X] T014 [P] Add `verifiedBuilds: Set<String> = ["26B131"]` and `isVerified(build:)` to `Core/SidebarIconCoreInfo.swift` (research D8); test it in `Tests/ModelTests.swift`

**Checkpoint**: `swift test` passes; the engine has config, state and hardened assets.

---

## Phase 3: User Story 1 — Give a Favorite a custom sidebar icon (Priority: P1) 🎯 MVP part 1

**Goal**: Add Folder → Pick Icon applies the icon in full colour and the mapping persists.

**Independent Test**: quickstart checks 1–4.

### Tests for User Story 1

- [X] T015 [P] [US1] Write tests in `Tests/MappingManagerAddTests.swift` using `FakeLaunchServices` (move the fake and `ProviderFixture` into `Tests/TestSupport.swift` so both suites share them):
  - `add` saves the mapping and asset and applies them (fake shows the override);
  - `add` with an unreadable image leaves `config.json`, `Icons/` and the ledger unchanged;
  - `add` of the same folder as `~/x`, `/path/x/` or through a symlink throws `duplicateFolder(existing:)`;
  - `add` of a file (not a directory) throws `notAFolder`;
  - a folder not in Favorites is saved, and its row state is `notInSidebar`;
  - `rows()` makes no outside calls (fake `calls` stays empty);
  - reloading a new `MappingManager` from the same container returns the same rows (persistence).

### Implementation for User Story 1

- [X] T016 [US1] Implement `Core/Manager/MappingManager.swift` per `contracts/mapping-manager.md`:
  - types `MappingRow`, `ActionResult`, `ManagerError`;
  - `init(container:provider:system:)`, `load()`, `rows()`, `add(folder:image:)`, `applyNow()`, `macOSBuildVerified`.

  `add` must, in order:
  1. standardize the path, and compare resolved paths for duplicates (FR-004);
  2. import with `AssetImporter`, then convert to `.icns`; on failure, delete the copy and throw `imageUnreadable`;
  3. allocate a code (T011);
  4. save the config;
  5. call `provider.apply`.

  Makes T015 pass.
- [X] T017 [US1] Create `app/SidebarIcons/AppModel.swift`: an `@MainActor @Observable` wrapper over `MappingManager`, with `rows`, `busy`, `statusLine`, `alert`, `readOnly`, `unverifiedBuild` and `favoritesUnavailable`; it runs each action in a `Task`, maps `ManagerError` to messages from `contracts/ui.md`, and refreshes `rows` after every action and on launch (read-only)
- [X] T018 [P] [US1] Create `app/SidebarIcons/AddMappingFlow.swift`: `NSOpenPanel` for a directory, then `NSOpenPanel` for `.pdf`, `.png` or `.svg` titled "Choose an icon for <folder>"; cancelling either step does nothing
- [X] T019 [P] [US1] Create `app/SidebarIcons/MappingListView.swift`:
  - each row shows a 20 pt preview on a light and a dark swatch (`.environment(\.colorScheme, …)`), the folder name, the `~` path, and a state badge;
  - Apply Now shows for `notInSidebar` and `notApplied`;
  - empty-state text from `contracts/ui.md`;
  - the banner for an unverified build or unreadable Favorites (research D8).
- [X] T020 [US1] Create `app/SidebarIcons/SidebarIconsApp.swift` with a single `Window("Sidebar Icons", id: "main")` hosting the list, an "Add Folder…" button, the progress indicator and the status line; disable Add and Apply when `readOnly` or `favoritesUnavailable`
- [X] T021 [P] [US1] Create `app/SidebarIcons/AboutView.swift` and replace the standard About panel (`CommandGroup(replacing: .appInfo)`) with a window showing the name, the version and the Constitution VI text from `contracts/ui.md`
- [X] T022 [US1] (owner) Run quickstart checks 1–4 and record the results in `specs/002-mapping-manager-v1/research.md` under a new "Verification" table

**Checkpoint**: Story 1 works on its own.

---

## Phase 4: User Story 4 — Refresh and remove everything (Priority: P4) 🎯 MVP part 2

**Goal**: Refresh Finder (re-apply, then restart) and Reset All (undo everything, empty the list).

**Independent Test**: quickstart checks 5–6.

### Tests for User Story 4

- [X] T023 [P] [US4] Write tests in `Tests/MappingManagerResetTests.swift`:
  - `resetAll` undoes every ledger entry (fake shows no overrides, the bundle is gone), empties the config and deletes `Icons/`;
  - a partial failure keeps the config entries whose ledger entries remain, and reports them;
  - `resetAll` with empty state makes no calls;
  - `resetAll` works when the config is unreadable (FR-010).

### Implementation for User Story 4

- [X] T024 [US4] Add `resetAll()` and `refreshFinder()` to `Core/Manager/MappingManager.swift`. `refreshFinder` calls `applyNow`, then `FinderRestarter.restart()` on the main actor; `resetAll` follows the contract. Makes T023 pass
- [X] T025 [US4] Add "Refresh Finder…" and "Reset All…" buttons to `app/SidebarIcons/SidebarIconsApp.swift`, with the confirmation dialogs and wording from `contracts/ui.md` (Reset All uses a destructive role). Reset All stays enabled in read-only and unverified modes
- [X] T026 [US4] (owner) Run quickstart checks 5–6 and record the results in the research.md Verification table

**Checkpoint**: the starter MVP (Stories 1 and 4) is complete. Review, merge to `main` on the owner's go-ahead.

---

## Phase 5: User Story 2 — Manage several mappings (Priority: P2)

**Goal**: Turn On/Off, Remove, Change Icon and Re-point, across three or more mappings.

**Independent Test**: quickstart checks 7–9.

- [X] T027 [P] [US2] Write tests in `Tests/MappingManagerManageTests.swift`:
  - `setEnabled(false)` clears only that override and keeps the mapping;
  - `setEnabled(true)` restores it;
  - `remove` clears the override, deletes that asset's files and leaves other mappings;
  - removing the last enabled mapping unregisters and deletes `IconRegistry.app`;
  - `changeIcon` keeps the code, creates a new asset (new type id) and deletes the old asset files after apply;
  - two mappings using the same source image each get their own asset.
- [X] T028 [US2] In `Core/Providers/LaunchServicesOverrideProvider.swift`, when `apply` is called with no enabled mapping and a registration exists in the ledger, unregister and delete the bundle (the same path as reset's registration step) and record it in `ApplyReport.cleared`. Update `PRIVATE_API.md` PA-04 "Reset and removal" in the same commit (Constitution VI)
- [X] T029 [US2] Add `setEnabled(_:for:)`, `remove(_:)`, `changeIcon(for:image:)` and `repoint(_:to:)` to `Core/Manager/MappingManager.swift`. `repoint` updates `folderPath` after the duplicate check and re-applies. Makes T027 pass
- [X] T030 [US2] In `app/SidebarIcons/MappingListView.swift`, add:
  - a row toggle (On/Off);
  - a context menu with Change Icon…, Remove… (confirmation from `contracts/ui.md`) and Re-point… (for `folderMissing`).
- [X] T031 [US2] (owner) Run quickstart checks 7–9 and record the results

---

## Phase 6: User Story 3 — Preview before committing (Priority: P3)

**Goal**: A sidebar-size light/dark preview with warnings, before applying.

**Independent Test**: quickstart check 10.

- [X] T032 [P] [US3] Write tests in `Tests/PreviewHeuristicsTests.swift` for `PreviewAdvice.evaluate(imageAt:)`:
  - it warns when the aspect ratio is outside 0.8–1.25;
  - it warns on high detail at 16 px (more than about 64 distinct colour clusters);
  - it never blocks (returns warnings only).
- [X] T033 [US3] Implement `Core/Icons/PreviewAdvice.swift` (ImageIO plus a 16×16 downsample; no new dependencies)
- [X] T034 [US3] Create `app/SidebarIcons/PreviewSheet.swift`, shown after the image pick in Add and Change Icon:
  - 16 pt and 20 pt previews on light and dark sidebar swatches;
  - the warnings from `PreviewAdvice`;
  - Apply and Cancel buttons (Cancel saves nothing).
- [ ] T035 [US3] (owner) Run quickstart check 10 and record the result

---

## Phase 7: Polish and Verification

- [ ] T036 [P] Update `README.md`: status (002 in progress → done), build steps for `app/SidebarIcons.xcodeproj`, and that the spike is retired and must not run alongside the app
- [ ] T037 [P] Update `PRIVATE_API.md` "Current status" to name the shipped app as the caller (same adapter file), and record the app's first verified build
- [ ] T038 Independent code review of `Core/Manager/`, `Core/Config/` and `app/SidebarIcons/`, plus a security review of `app/SidebarIcons/SidebarIcons.entitlements`, the signing settings and any adapter change (constitution). Fix the findings; record them in `specs/002-mapping-manager-v1/research.md`
- [ ] T039 (owner) Run quickstart check 11 (light/dark and accent colour)
- [ ] T040 (owner) Run quickstart check 12 (20 mappings; logout; reboot; FR-011, FR-013, SC-002)
- [ ] T041 (owner) Run quickstart checks 13–14 (leftovers after Reset All and deletion; folders untouched; SC-004, SC-005)
- [ ] T042 Mark the spec Status "Done" with the verified macOS build and merge to `main` on the owner's go-ahead (no PR; branch workflow)

---

## Follow-ups (found during the work; not blocking a story)

Reviewed at each checkpoint; the owner decides whether to schedule them.

- [ ] F001 Add Folder refuses an already-mapped folder only after the image is picked; check right after the folder pick in `app/SidebarIcons/AddMappingFlow.swift` (quickstart check 4)
- [ ] F002 Refresh Finder takes about 15–20 s, mostly repeated `lsregister -dump` runs (claims, apply, status); share one dump per action in `Core/Manager/MappingManager.swift` and the adapter (quickstart check 5)
- [ ] F003 After removing the last mapping with a failed clear, only Reset All retries; let Refresh Finder apply when the ledger still has entries in `Core/Manager/MappingManager.swift` (Story 2 review #3)
- [ ] F004 Rare: two ledger entries with one code (after a re-point whose old clear failed) can clear an icon an enabled mapping still needs; skip that clear in `Core/Providers/LaunchServicesOverrideProvider.swift` (review #6)
- [ ] F005 Offer Re-point… on Off rows and on "now resolves to" error rows, not only Folder missing, in `app/SidebarIcons/MappingListView.swift` (review #8)
- [ ] F006 Narrow the check-then-use window between `refuseSymbolicLink` and `lsregister -u` (open the bundle directory with `O_NOFOLLOW` or re-check right before), `Core/Providers/LaunchServicesOverrideProvider.swift` (review, security)
- [ ] F007 Remove the redundant `await`s in the `exclusive` closures (about ten compiler warnings), `Core/Manager/MappingManager.swift`
- [ ] F008 Decode the picked image once into `PendingIcon` and run `PreviewAdvice.evaluate` off the main thread; a very large PDF freezes the window for about 0.5 s, `app/SidebarIcons/AppModel.swift`, `PreviewSheet.swift` (Story 3 review #2)
- [ ] F009 Apply in the preview sheet clears it before checking `busy`; unreachable today, but guard or alert in `app/SidebarIcons/AppModel.swift` (review #4)
- [ ] F010 Thin, faint line art (few pixels at least 80 % opaque at 16 px) is never flagged; consider a low-coverage warning in `Core/Icons/PreviewAdvice.swift` (review question; not in the spec)
- [ ] F011 Decide whether the image picker should accept `.icns` (the converter supports it) in `app/SidebarIcons/AddMappingFlow.swift` (review question)

---

## Dependencies and Execution Order

- **Setup (T001–T005)**:
  - T001 comes first (the package move); T002 follows it.
  - T003 needs T001.
  - T004 and T005 can run in parallel once T003 exists.
- **Foundational (T006–T014)** needs Setup.
  - Tests T006–T008 run in parallel; then T009, then T010; T011 and T012 can run in parallel.
  - T013 and T014 can run in parallel at any time.
- **US1 (T015–T022)** needs Foundational.
  - T015, then T016, then T017.
  - T018, T019 and T021 run in parallel after T017; then T020; then T022.
- **US4 (T023–T026)** needs T016 and T020 (it adds to the same manager and window).
- **US2 (T027–T031)** needs the MVP.
  - T028 changes the adapter, so it needs a security review in T038.
- **US3 (T032–T035)** needs the MVP and can run in parallel with US2, except that T034 touches the Add flow from T018.
- **Polish (T036–T042)** comes after the stories it covers.

## Parallel Examples

```text
Foundational: T006 ConfigStoreTests | T007 AllocatorClaimsTests | T008 ICNSHardeningTests | T013 MappingState | T014 verifiedBuilds
US1 UI:       T018 AddMappingFlow    | T019 MappingListView      | T021 AboutView
Story 2 / 3:  T027 manage tests      | T032 preview heuristics tests
```

## Implementation Strategy

- **Starter MVP**: Phases 1–4 (T001–T026), giving a working app that adds mappings, persists them,
  refreshes Finder and resets everything. Stop, run quickstart checks 1–6, review, and merge to
  `main`.
- **Increment 2**: Story 2 (T027–T031), so several mappings can be managed.
- **Increment 3**: Story 3 (T032–T035), adding the preview and warnings.
- **Finish**: T036–T042 (docs, reviews, the 20-mapping and reboot checks, leftover audit).
