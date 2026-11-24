---

description: "Task list for Icon Groups (0.3.0)"
---

# Tasks: Icon Groups (0.3.0)

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md) (S1–S7, D1–D10),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md),
[icon-specification.md](icon-specification.md)

**Tests**: included. Swift Testing for package logic (constitution); Finder-visible behavior is
checked with quickstart.md.

**Order** (owner addendum, 2026-11-23): Foundation → US1 system glyph → US2 manual process → US3
wizard → US4 folder icon → verification and release.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on unfinished tasks).
- **[Story]**: US1–US4 (spec.md).
- **(owner)**: needs the owner; **(live)**: needs live control of the Mac (ask first, announce
  with `say`).

## Path Conventions

- Engine: `Packages/SidebarIconCore/Sources/SidebarIconCore/` (written `Core/` below).
- Tests: `Packages/SidebarIconCore/Tests/SidebarIconCoreTests/` (written `Tests/`).
- App: `app/SidebarIcons/`.

---

## Phase 1: Setup

- [X] T001 Apply constitution amendment A (1.1.0 → 1.2.0, Principles I and III, Sync Impact Report) in `.specify/memory/constitution.md` (owner approved 2026-11-23)
- [X] T002 [P] Add SVG fixtures in `Tests/Fixtures/` and declare them as test resources in `Packages/SidebarIconCore/Package.swift` (`resources: [.copy("Fixtures")]`):
  - `layers-filled.svg` (two even-odd paths, `viewBox="0 0 100 100"`);
  - `shapes.svg` (`rect` with `rx`, `circle`, `ellipse`, `polygon`);
  - `stroked.svg` (`rect fill="none" stroke`, `line`);
  - `text.svg`, `transform.svg` (`<g transform>`), `no-viewbox.svg`, `empty.svg`;
  - `template-regular-m.svg` (a valid template from the spike generator) and `template-s-only.svg`
    (only `Regular-S`).
- [X] T003 [P] Add an executable target `make-symbol-template` (`Sources/make-symbol-template/main.swift`, depends on `SidebarIconCore`) to `Packages/SidebarIconCore/Package.swift`; for now `main.swift` prints usage and exits 64

---

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: schema 2, sidebar styles, per-style type declarations, versioned registry bundles.

- [X] T004 [P] Tests in `Tests/SchemaTwoTests.swift`:
  - `SidebarStyle` round-trips through JSON for all three cases;
  - `AppConfiguration.problems` reports an unresolved `fullColour` asset, an unresolved `customGlyph` glyph, an invalid glyph name (must match `^[a-z0-9][a-z0-9.-]{0,47}$`) and a duplicate glyph name;
  - `ConfigStore.load()` of a schema 1 file throws `configUnreadable` whose message contains "made by Sidebar Icons 0.2.0" and does not modify the file;
  - schema 2 save/load round-trips mappings, assets and glyphs;
  - pruning deletes the files of unreferenced assets and of glyphs no longer listed (`Glyphs/<versionID>.svg`, `Glyphs/<versionID>.template.svg`).
- [X] T005 Add `Core/Model/SidebarStyle.swift` (`enum SidebarStyle: Codable, Sendable, Hashable { systemSymbol(name: String), customGlyph(glyphID: UUID), fullColour(assetID: UUID) }`), `Core/Model/CustomGlyph.swift` (fields per data-model.md: `id`, `name`, `versionID`, `sourceFileName?`, `templateFileName`), and `Core/Model/FolderIconSetting.swift` (`enabled`, `artAssetID`, `overrideAssetIDs: [String: UUID]`, `replaceExisting`). In `Core/Model/SidebarMapping.swift` replace `iconAssetID` with `sidebarStyle` and add `folderIcon: FolderIconSetting?`
- [X] T006 Update `Core/Config/AppConfiguration.swift` (`currentSchemaVersion = 2`, `glyphs: [CustomGlyph]`, `problems` per T004) and `Core/Config/ConfigStore.swift`:
  - a schema 1 file throws `configUnreadable("This configuration was made by Sidebar Icons 0.2.0 and isn't converted. Use Reset All to start fresh.")`;
  - pruning covers style assets, folder-art assets and glyph files.

  Makes T004 pass.
- [X] T007 [P] Tests in `Tests/IconRegistryBundleTests.swift` (rewrite):
  - declarations per style (research D3):
    - `fullColour` → `UTTypeIconFile` + missing symbol;
    - `systemSymbol` → `UTTypeSymbolName = name`;
    - `customGlyph` → `UTTypeSymbolName = "<name>.<versionID lowercased>"`;
  - the type identifier is `com.altmansoftwaredesign.sidebaricons.icon.<code>.<style key>`;
  - `contentHash` is deterministic, changes with any declaration or car byte, and gives a bundle name `IconRegistry-<8 lowercase hex>.app`;
  - `write` copies `Assets.car` into `Contents/Resources/` when given;
  - an invalid or duplicate code throws.
- [X] T008 Rewrite `Core/Icons/IconRegistryBundle.swift`:
  - `Entry` holds `osType` and `style: EntryStyle` (`fullColour(assetID, icnsSource)`, `systemSymbol(name)`, `customGlyph(symbolName, versionID)`);
  - add `contentHash(entries:assetsCar:)` and `bundleName(forHash:)`;
  - `write(_:assetsCar:to:)` uses the same atomic swap as before.

  Makes T007 pass.
- [X] T009 [P] Tests in `Tests/VersionedRegistryTests.swift` (with `FakeLaunchServices`):
  - apply writes `IconRegistry-<hash>.app`, records it, then registers it before setting overrides;
  - a second apply with the same configuration makes no calls;
  - a style change writes a new version, then unregisters and deletes the previous recorded version, including a legacy `IconRegistry.app` entry;
  - each code keeps its value;
  - the claim check counts any `IconRegistry*.app` directly in the container as the app's own;
  - reset undoes every recorded version and deletes unrecorded `IconRegistry*.app` and staging folders.
- [X] T010 Update `Core/Ledger/ContainerLocator.swift` (`registryBundleURL(named:)`, `isOwnRegistryBundle(path:)` = a non-link `IconRegistry*.app` directly in `root`) and `Core/Providers/LaunchServicesOverrideProvider.swift`:
  - build entries from `sidebarStyle`;
  - switch versions per research D2;
  - `foreignOwners` uses `isOwnRegistryBundle`;
  - `undoRegistration` and `removeUnrecordedRegistryFiles` handle every version;
  - add a `assetsCar: URL?` parameter to `apply`.

  Update `PRIVATE_API.md` PA-04 (versioned bundles; Finder caches `Assets.car` per bundle path; codes stable) **in the same commit**. Makes T009 pass.
- [X] T011 Update `Core/Manager/MappingManager.swift` to the new model:
  - `add(folder:style:)`; a `.fullColour` style is created through `addFullColour(folder:image:)`, which keeps 002's import;
  - `setStyle(_:for:)` replaces `changeIcon`;
  - `MappingRow` gains `style`.

  Update the 002 manager tests (`Tests/MappingManager*Tests.swift`, `Tests/ReviewFixTests.swift`) to the new API; all tests pass.
- [X] T012 Update the app to compile against the new engine (`app/SidebarIcons/AppModel.swift`, `AddMappingFlow.swift`, `MappingListView.swift`): Add Folder… and Change Icon… keep working with full-colour images for now; the scheme builds

**Checkpoint**: `swift test` passes; the app builds; full-colour mappings work through versioned registry bundles.

---

## Phase 3: User Story 1 — System glyph (Priority: P1) 🎯 first

**Goal**: pick an SF Symbol by name with a tinted preview; it shows outline blue at system size,
with no Finder restart.

**Independent Test**: quickstart checks 1–2.

- [X] T013 [P] [US1] Tests in `Tests/SystemGlyphTests.swift`:
  - `add(folder:style: .systemSymbol("hammer"))` applies with the declaration `UTTypeSymbolName = "hammer"`;
  - an unknown name (validator returns false) throws `ManagerError.unknownSymbol` and saves nothing;
  - `setStyle` from `fullColour` to `systemSymbol` keeps the `osType`, changes the type identifier and the registry version.
- [X] T014 [US1] In `Core/Manager/MappingManager.swift`, add the `systemSymbol` path to `add` and `setStyle`, with an injectable `isValidSystemSymbol: @Sendable (String) -> Bool` (default: `NSImage(systemSymbolName:accessibilityDescription:) != nil`); add `ManagerError.unknownSymbol(String)` with its message. Makes T013 pass
- [X] T015 [P] [US1] Create `app/SidebarIcons/SymbolCatalog.swift`, a curated list of about 80 SF Symbol names relevant to folders (research D6), and `app/SidebarIcons/SymbolSearchView.swift`:
  - a name field filtering suggestions, with live validation ("✓ available" or "Not a system glyph on this Mac");
  - a preview at 16 and 20 pt tinted with the accent colour on light and dark sidebar swatches (`Image(systemName:)`, `.foregroundStyle(.tint)`).
- [X] T016 [US1] Create `app/SidebarIcons/StylePickerView.swift`, a sheet with tabs System glyph (`SymbolSearchView`), Custom glyph (placeholder until US2) and Full colour (the 002 image flow and `PreviewSheet`), and Cancel/Apply. Wire it into Add Folder… (after the folder pick) and Change Icon… in `AppModel.swift` and `AddMappingFlow.swift`
- [X] T017 [US1] In `app/SidebarIcons/MappingListView.swift`, the row shows the style name and a 16 pt tinted preview for system glyphs (`Image(systemName:)`)

**Checkpoint**: US1 works end to end in the app; verified in the batched live check (T034).

---

## Phase 4: User Story 2 — Manual process: import a hand-made glyph (Priority: P2)

**Goal**: the owner follows the directions (draw with filled shapes, run the helper script or use
the SF Symbols app) and imports the template with Import Glyph…; the glyph shows outline blue.

**Independent Test**: quickstart checks 3–5.

- [X] T018 [P] [US2] Tests in `Tests/SVGShapeReaderTests.swift` using the T002 fixtures, per contracts/glyph-builder.md:
  - accepts `path`, `rect` (with `rx`/`ry`), `circle`, `ellipse`, `polygon`, and `g` without `transform`;
  - refuses `stroked.svg` with the Outline Stroke guidance, `text.svg`, `transform.svg` and `no-viewbox.svg`, and `empty.svg` with `emptySVG`;
  - reports the width ratio.
- [X] T019 [P] [US2] Tests in `Tests/SymbolTemplateWriterTests.swift`:
  - output is deterministic;
  - it contains the groups `Ultralight-M`, `Regular-M` and `Black-M`, the guides `Baseline-S/M/L` and `Capline-S/M/L`, and margin lines;
  - the path transform scales the `viewBox` height to 150 units, from 120 above the baseline to 30 below.
- [X] T020 [P] [US2] Implement `Core/Glyphs/SVGShapeReader.swift` (Foundation `XMLParser`; shape-to-path conversion; refusals with guidance strings from contracts/glyph-builder.md). Makes T018 pass
- [X] T021 [P] [US2] Implement `Core/Glyphs/SymbolTemplateWriter.swift` (research D4; follows the spike generator). Makes T019 pass
- [X] T022 [US2] Implement `Packages/SidebarIconCore/Sources/make-symbol-template/main.swift`:
  - usage `swift run make-symbol-template <input.svg> <output.svg>`;
  - on success, prints the glyph's width ratio and any warnings;
  - on refusal, prints the guidance and exits 65; usage errors exit 64.
- [X] T023 [US2] Add a "Manual process" section to `specs/004-icon-groups/icon-specification.md`:
  - draw with filled shapes;
  - run `swift run --package-path Packages/SidebarIconCore make-symbol-template in.svg out.svg`, or export a custom-symbol template from Apple's SF Symbols app (it must have a Regular-Medium glyph);
  - then use Import Glyph… in the app.
- [X] T024 [P] [US2] Tests in `Tests/ActoolRunnerTests.swift` with a fake `ProcessRunning`:
  - the exact argument list and environment from research D5;
  - a 120 s timeout maps to `timedOut`;
  - XML error output maps to `compileFailed(first error)`;
  - `toolStatus`: no path → unavailable; a path under `/Library/Developer/CommandLineTools` → unavailable (Command Line Tools); the license and first-launch messages map to their plain messages.
- [X] T025 [US2] Implement `Core/Glyphs/ActoolRunner.swift`:
  - a `ProcessRunning` protocol;
  - a real runner with `Process`, a fixed argument list, the D5 environment and a timeout;
  - `ToolStatus` and `GlyphBuildError`.

  Makes T024 pass.
- [X] T026 [US2] Implement `Core/Glyphs/AssetCatalogWriter.swift`:
  - writes `Build/<build id>/Glyphs.xcassets` with one `<name>.<versionID lowercased>.symbolset` per glyph (`"template-rendering-intent": "template"`);
  - checks each template contains `id="Regular-M"` before compiling.

  Also add `Glyphs/Assets.car` and `Glyphs/Assets.key` (sorted version IDs of the glyphs it holds) to data-model.md's file list.
- [X] T027 [P] [US2] Tests in `Tests/ImportGlyphTests.swift` (fake runner that writes a dummy car):
  - `importGlyph(name:template:)` validates the name, copies the template to `Glyphs/<versionID>.template.svg`, builds, saves and applies;
  - a mapping set to `customGlyph` gets the declaration `<name>.<versionID>` and the car in the registry bundle;
  - a second import under the same name makes a new version and a new registry version;
  - a failing build saves nothing;
  - `toolUnavailable` changes nothing;
  - with an unchanged glyph set and no tool available, apply reuses `Glyphs/Assets.car`;
  - `deleteGlyph(_:replacement:)` switches the mappings that use it.
- [X] T028 [US2] In `Core/Manager/MappingManager.swift`, add `glyphs()`, `glyphToolStatus()`, `importGlyph(name:template:)` and `deleteGlyph(_:replacement:)`, and the `customGlyph` path in `add`/`setStyle`:
  - apply rebuilds the combined car only when the glyph set changes (compare `Glyphs/Assets.key`), otherwise reuses `Glyphs/Assets.car`;
  - passes the car to the provider;
  - `resetAll` deletes `Glyphs/` and `Build/`.

  Makes T027 pass.
- [X] T029 [US2] In `app/SidebarIcons/StylePickerView.swift`, Custom glyph tab:
  - the list of glyphs with a tinted preview (`NSImage(symbolName:bundle:variableValue:)` from the current registry bundle);
  - **Import Glyph…** (name field and an open panel for the template), and Delete….
  - The tool status is shown when unavailable.
- [X] T030 [US2] (live) Proof **P-1**: build the app with the Developer ID Release settings, run it, Import Glyph… with the `make-symbol-template` output for `layers-filled.svg`. Pass: an `Assets.car` is built from the signed, hardened app and the Favorite shows the glyph outline blue. Record the result in research.md

**Checkpoint**: US2 works with the owner's own drawings.

---

## Phase 5: User Story 3 — Wizard (Priority: P3)

**Goal**: the same result as US2 without running the script: plain SVG in, glyph out, with checks
and previews.

**Independent Test**: quickstart checks 6–7.

- [X] T031 [P] [US3] Tests in `Tests/CreateGlyphTests.swift`:
  - `createGlyph(name:svg:)` runs reader → writer → import and keeps the source as `Glyphs/<versionID>.svg`;
  - refusals return `unsupportedSVG` with guidance;
  - `updateGlyph(_:svg:)` makes a new version and switches the mappings that use it.
- [X] T032 [US3] In `Core/Manager/MappingManager.swift`, add `createGlyph(name:svg:)` and `updateGlyph(_:svg:)` on top of the T028 import path. Makes T031 pass
- [X] T033 [US3] Create `app/SidebarIcons/GlyphWizard.swift`, a sheet with steps per contracts/ui.md:
  1. tool check, with fallbacks to a system glyph or the manual process;
  2. name;
  3. drawing (refusal guidance and non-blocking warnings);
  4. optional folder art (disabled until US4);
  5. preview (the plain SVG rendered as a template image at 16/20 pt, beside a system glyph for scale);
  6. build.

  Open it from **New Custom Glyph…** in the Custom glyph tab.

---

## Batched live check (US1–US3)

- [X] T034 (live) Quickstart checks 1–7 on 26B131 (system glyph, manual import, wizard, a glyph change without a Finder restart, and a 20-glyph check with generated test glyphs); record the results in research.md; clean up test Favorites and folders afterwards

---

## Phase 6: User Story 4 — Matching folder icon (Priority: P4)

**Goal**: opt-in full-colour art as the folder's own Finder icon; reversible; existing custom icons
kept.

**Independent Test**: quickstart checks 8–12.

- [X] T035 [P] [US4] Tests in `Tests/FolderArtBuilderTests.swift`:
  - a master (PNG ≥ 1024 px, PDF, SVG) produces a 10-representation `.icns`;
  - an override replaces exactly its representation;
  - an `.iconset` folder is read by Apple file names (`icon_16x16.png` … `icon_512x512@2x.png`);
  - a wrong pixel size is refused.
- [X] T036 [P] [US4] Tests in `Tests/FolderIconProviderTests.swift` with a fake `FolderIconWriting`:
  - the ledger entry (`folderIcon`) is written before `setIcon`, then gets the fingerprint;
  - an existing custom icon without `confirmReplace` throws `folderIconNeedsConfirmation(existing: true)`;
  - with confirmation, a backup `.icns` is written to `FolderIconBackups/`;
  - undo with a matching fingerprint restores the backup or clears the icon;
  - a mismatch leaves the folder and notes it;
  - `setIcon` returning false → `folderIconFailed` and no ledger entry left.
- [X] T037 [US4] Implement `Core/Icons/FolderArtBuilder.swift` (research D7; reuse `ICNSConverter.render`). Makes T035 pass
- [X] T038 [US4] Implement:
  - `Core/Providers/FolderIconProvider.swift`: `FolderIconWriting` protocol; real implementation with `NSWorkspace.setIcon`, `NSWorkspace.icon(forFile:)`, the `FinderInfo` flag check, and the SHA-256 of `Icon\r`'s `com.apple.ResourceFork`;
  - `OutsideChange.Kind.folderIcon` with `fingerprint` and `backupFileName` in `Core/Model/OutsideChange.swift`.

  Makes T036 pass.
- [X] T039 [US4] In `Core/Manager/MappingManager.swift`:
  - add `setFolderIcon(_:for:confirmReplace:)`;
  - Remove, Off, `setFolderIcon(nil)` and `resetAll` restore folder icons by the fingerprint rule;
  - `MappingRow.folderIcon` state (`notSet`, `set`, `changedElsewhere`, `accessDenied`, `failed`);
  - `resetAll` deletes `FolderIconBackups/`.

  Add manager tests to `Tests/FolderIconProviderTests.swift`.
- [X] T040 [US4] Create `app/SidebarIcons/FolderArtOptInView.swift`, the opt-in sheet with the exact texts from contracts/ui.md:
  - the replace warning;
  - pickers for the master and for small sizes or an `.iconset`;
  - a preview at 16, 32, 128 and 512 pt.

  Add **Folder Icon…** to the row context menu and a row badge. Enable step 4 of the wizard.
- [X] T041 [US4] (live, owner for the prompt) Proof **P-2** and quickstart checks 8–12:
  - a folder under `~/Documents`: record the privacy prompt and each answer;
  - Finder views;
  - an `.iconset` override;
  - replace with a backup, and restore;
  - a change made elsewhere is left alone;
  - git status.

  Record the results in research.md.

---

## Phase 7: Polish, verification and release

- [X] T042 [P] Review `PRIVATE_API.md` (PA-04 now covers glyph cars, versioned bundles, the caching behaviour and the verified build) and `README.md` (style picker, manual process, wizard, folder icon, the 0.2.0 reset note)
- [X] T043 [P] Add a CHANGELOG 0.3.0 entry: Added (system glyphs, custom glyphs (manual process and wizard), folder icons); Changed (registry versions; no migration from 0.2.0: reset first); Known limitations
- [X] T044 Independent code review of `Core/Glyphs/`, `Core/Icons/`, `Core/Providers/`, `Core/Manager/`, `Core/Config/` and `app/SidebarIcons/`, plus a security review (the private adapter, `Process`/`actool`, folder writes, symlinks in the container). Fix the findings; record them in research.md
- [X] T045 (owner) Proof **P-3**: dark mode and a non-default accent colour with system and custom glyphs (quickstart)
- [X] T046 ~~ (live) Quickstart checks 13–15 (0.2.0 configuration refused; Reset All leaves nothing; folders that were not opted in are untouched); also check a wide custom glyph stays inside the sidebar slot (width cap, 29422c8)~~
  **Skipped by the owner (2026-11-24):** Sidebar Icons has not left this machine, so there are no other 0.2.0 installs to check. Not verified live as a result: Reset All's leftover audit for 0.3.0 and the wide-glyph cap in Finder (package tests cover the logic, not what Finder shows).
- [X] T047 Release 0.3.0:
  - add any newly verified build to `SidebarIconCoreInfo.verifiedBuilds`;
  - set `MARKETING_VERSION` to 0.3.0; date the CHANGELOG entry; update the README status (004 released);
  - commit and tag `v0.3.0`;
  - run `scripts/release.sh all`, install and smoke-test;
  - merge to `main`; push on the owner's go-ahead.

  **Done 2026-11-24, then redone the same day.** The first build (tag on `268f6e6`, never pushed)
  was superseded at the owner's request so that 0.3.0 also includes:
  - the Glyph Library window and the simpler wizard (`ca87e9c`);
  - the UI text audit (`f5c9c6e`).

  The tag was moved, and the release ran again:
  - 26B131 was already the verified build.
  - The annotated tag `v0.3.0` is on `f5c9c6e`.
  - `scripts/release.sh all` ran from the main checkout:
    - every check gate passed;
    - Developer ID, hardened runtime, App Group only;
    - notarized (Accepted) and stapled;
    - a quarantined copy is accepted by Gatekeeper ("Notarized Developer ID"), and
      `syspolicy_check` found no issues.
  - Zip `build.noindex/release/0.3.0/sidebar-icons-0.3.0.zip`, SHA-256 `7864c6d4…8332`.
  - It replaced `/Applications/sidebar-icons.app` (the earlier build went to the Trash). The smoke
    test passed:
    - it reports 0.3.0 and is accepted by `spctl`;
    - the View menu has Main and Glyph Library, and the main window has the Glyph Library button;
    - it opens without the unverified-build banner and loads the owner's mappings.
  - `main` fast-forwarded locally. Not pushed: waiting for the owner.

---

## Dependencies & Execution Order

- **Setup (T001–T003)**: T001 done; T002 and T003 in parallel.
- **Foundation (T004–T012)** blocks every story. T004 → T005 → T006; T007 → T008; T009 → T010;
  then T011 → T012.
- **US1 (T013–T017)** after the foundation. T013 → T014; T015 in parallel with T014; T016 → T017.
- **US2 (T018–T030)** after the foundation; it reuses US1's style picker (T016).
  - T018/T019 → T020/T021 → T022 → T023.
  - T024 → T025 → T026.
  - T027 → T028 → T029.
  - T030 (P-1) gates shipping US2.
- **US3 (T031–T033)** after T028.
- **T034** (batched live check) after T033.
- **US4 (T035–T041)** after the foundation; T040 enables the wizard's folder-art step; T041 (P-2)
  gates shipping US4.
- **Polish (T042–T047)** last; T045 and T047's push wait for the owner.

## Parallel Examples

```text
Foundation tests: T004 | T007 | T009
US1:              T015 (SymbolSearchView) alongside T014 (engine)
US2:              T018 + T019 + T024, then T020 + T021
US4:              T035 + T036
Polish:           T042 + T043
```

## Implementation Strategy

1. Foundation, then US1, giving outline-blue system glyphs (could ship as 0.3.0-beta).
2. US2, so the owner makes custom glyphs by hand (after the P-1 proof).
3. US3, the wizard; then the batched live check T034.
4. US4, folder icons (after the P-2 proof).
5. Reviews, owner proof P-3, release 0.3.0.

Stop points that need the owner: live-control permission (T030, T034, T041), the privacy
prompt (T041), appearance (T045), and the push (T047).
