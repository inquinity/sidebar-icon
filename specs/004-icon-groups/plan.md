# Implementation Plan: Icon Groups (0.3.0)

**Branch**: `004-icon-groups` | **Date**: 2026-11-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-icon-groups/spec.md`; spike results and decisions
in [research.md](research.md); owner-facing resource list in
[icon-specification.md](icon-specification.md).

## Summary

Sidebar Favorites get **outline glyphs tinted like the system ones** instead of full-colour art,
and each folder can opt in to **matching full-colour art as its own Finder icon**.

- **Sidebar**: each mapping has a style:
  - a **system glyph** (SF Symbol name), which needs no tools;
  - a **custom glyph**, built by a wizard with Xcode's `actool` into a combined `Assets.car`;
  - **full colour**, the 0.2.0 style, kept.

  The registry becomes a **versioned bundle per change** (`IconRegistry-<content hash>.app`),
  because Finder caches a bundle's `Assets.car` per path (spike S4b). Override codes stay stable.
- **Folder icon (opt-in)**: set with the public `NSWorkspace.setIcon` from the full-colour art
  (1024 master plus optional hand-tuned sizes). Recorded in the ledger with a fingerprint, so undo
  only touches an icon that is still ours. An existing custom icon is kept and restored.
- **Compatibility**: no migration (owner addendum). A 0.2.0 configuration (schema 1) is reported and
  left untouched; Reset All still undoes everything it recorded.
- **Order** (owner addendum, 2026-11-23): foundation, then system glyph (under a day on top of the
  foundation), then the **manual process** (directions + helper script + Import Glyph…), then the
  **`actool` wizard**, then the opt-in **folder icon**.
- **Release**: 0.3.0 through `scripts/release.sh`.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency), Xcode 27.2 (build); macOS 27+ (run)

**Primary Dependencies**: Apple frameworks only:
- SwiftUI and AppKit (`NSOpenPanel`, `NSImage(systemSymbolName:)`, `NSWorkspace.setIcon`);
- ImageIO; CoreServices (existing adapter);
- Foundation `XMLParser` (SVG reading).

Optional at runtime, wizard only: Xcode's `actool`, found with `/usr/bin/xcrun --find actool`.

**Storage**: the App Group container, as in 002:
- `config.json` (schema 2);
- `ledger.json`;
- `Icons/` (art, `.icns`);
- `Glyphs/` (custom glyph SVG sources and generated templates);
- `Build/` (temporary catalogs);
- `IconRegistry-<hash>.app` (current registry; earlier ones removed after each switch);
- `FolderIconBackups/` (previous custom folder icons as `.icns`).

**Testing**:
- Swift Testing for the package: schema 2 and the 0.2.0 refusal, glyph template writer, SVG validation, registry
  versioning, folder-icon ownership logic, manager actions with fakes.
- A fake `actool` runner and a fake folder-icon writer for tests.
- The Finder-visible checks are manual (quickstart).

**Target Platform**: macOS 27.2.1 (26B131) verified; others show the existing banner

**Project Type**: desktop app plus local Swift package (unchanged layout)

**Performance Goals**:
- A system glyph is visible within 10 s (SC-001).
- A wizard build plus registration is visible within 30 s (SC-004); `actool` takes about 1 s per
  catalog (spike).
- With 20 custom glyphs, the full car rebuilds in under 10 s.

**Constraints**:
- Not sandboxed, hardened runtime, Developer ID (003).
- No network.
- Outside changes only on explicit actions (002 D6).
- Folder writes only for opted-in folders.

**Scale/Scope**: 20+ mappings; 20+ custom glyphs; one window with three sheets (style picker,
glyph wizard, folder-art opt-in)

## Constitution Check

*GATE: before Phase 0 and again after Phase 1 design.*

| Principle | Check | Result |
|-----------|-------|--------|
| I. Inspectable and Boring | Apple frameworks only; no network, helper or daemon. **`actool` is an optional Apple developer tool** run only by the wizard, on an explicit action; nothing else needs it. Every file written is listed in data-model.md | **Pass** (amendment A applied: constitution 1.2.0, 2026-11-23) |
| II. Public API first; private behind one adapter | Folder icons use public `NSWorkspace.setIcon` (option 1), in `FolderIconProvider` (public, not the private adapter). Sidebar glyphs extend option-2 behavior already proven (S1, S4b) and stay in `LaunchServicesOverrideProvider` | Pass |
| III. User data never modified | The opt-in folder icon writes `Icon\r` into the folder and sets its icon flag, which the current text forbids except when "the user explicitly asks in a separate, clearly labeled action", and that covers only changing an *existing* custom icon | **Pass** (amendment A applied: constitution 1.2.0, 2026-11-23) |
| IV. Prove before building | S1–S6 passed (research.md). Not proven yet: **P-1** `actool` launched from the signed, hardened app; **P-2** `setIcon` from the app on a folder under `~/Documents` (privacy prompt); **P-3** dark mode and a non-default accent colour with custom glyphs (owner) | **Gated**: tasks for P2/P3 work MUST NOT start until P-1/P-2 pass; P-3 is recorded before release |
| V. Explicit, reversible side effects | New outside changes: registry versions (ledger `iconRegistration` per path) and folder icons (new ledger kind `folderIcon` with fingerprint and backup). All undone by Remove/Off/Reset All; applied only on explicit actions | Pass |
| VI. Private API documented | PA-04 gains: Finder draws a registered type's `UTTypeSymbolName` from the registering bundle's `Assets.car` and caches it per bundle path; versioned bundles. Updated in the same commit as the adapter change | Pass (task) |

**Amendment A** (constitution 1.1.0 → **1.2.0**, MINOR: materially expanded guidance):
- Principle I permits optional Apple developer tools (for example `actool`), invoked only on an
  explicit user action, with a working path that does not need them.
- Principle III permits setting a folder's own Finder icon only as a separate, clearly labeled,
  per-folder opt-in. The change must be recorded before it is made and fingerprinted, and undone
  only while it is still the utility's. A previous custom icon must be kept and restored. Nothing
  else in the folder may change.

Re-check after Phase 1 design: unchanged. The contracts keep all sidebar-registry behavior in
the adapter and folder writes in `FolderIconProvider`. data-model.md lists every file and the new
`folderIcon` ledger kind. The quickstart holds proofs P-1 to P-3.

The owner approved the amendment on 2026-11-23; it is applied in `.specify/memory/constitution.md`
(1.2.0, with a Sync Impact Report).

## Project Structure

### Documentation (this feature)

```text
specs/004-icon-groups/
├── spec.md
├── plan.md                 # this file
├── research.md             # spike S1–S7 + plan decisions D1–D10
├── icon-specification.md   # what the owner creates per folder
├── data-model.md           # schema 2, entities, ledger kinds, files written
├── quickstart.md           # build, proofs P-1–P-3, manual checks
├── contracts/
│   ├── mapping-manager.md  # engine API changes
│   ├── glyph-builder.md    # SVG rules, template, actool runner
│   └── ui.md               # style picker, symbol search, wizard, folder-art opt-in
├── checklists/requirements.md
└── tasks.md                # next: /speckit-tasks
```

### Source Code (repository root)

```text
Packages/SidebarIconCore/Sources/SidebarIconCore/
├── Config/
│   ├── AppConfiguration.swift        # schema 2: styles, glyphs, folder icons
│   └── ConfigStore.swift             # schema 2; schema 1 reported as "made by 0.2.0"
├── Glyphs/                           # NEW (also used by scripts/make-symbol-template)
│   ├── SVGShapeReader.swift          # paths + rect/circle/ellipse/polygon → path data; refuses strokes etc.
│   ├── SymbolTemplateWriter.swift    # Regular/Ultralight/Black-M, 150-unit box (S2, S2b)
│   ├── AssetCatalogWriter.swift      # temporary .xcassets with one .symbolset per glyph
│   └── ActoolRunner.swift            # xcrun --find actool; Process; env; timeout; error parsing
├── Icons/
│   ├── IconRegistryBundle.swift      # + symbol styles, Assets.car, content hash, versioned path
│   └── FolderArtBuilder.swift        # NEW: master + overrides/.iconset → .icns (ImageIO)
├── Providers/
│   ├── LaunchServicesOverrideProvider.swift  # versioned registry switch; own-bundle matching for IconRegistry-*.app
│   └── FolderIconProvider.swift      # NEW: NSWorkspace.setIcon, fingerprint, backup/restore (public API)
├── Model/ …                          # SidebarStyle, CustomGlyph, FolderIconSetting; OutsideChange.Kind.folderIcon
└── Manager/MappingManager.swift      # setStyle, glyph CRUD, buildGlyphs, setFolderIcon; reset covers all

app/SidebarIcons/
├── StylePickerView.swift             # NEW: system / custom / full colour, with tinted previews
├── SymbolSearchView.swift            # NEW: name field, validation, curated suggestions
├── GlyphWizard.swift                 # NEW: actool check → name → SVG + art → preview → build
├── FolderArtOptInView.swift          # NEW: labeled opt-in, effects explained, art + sizes
└── MappingListView.swift / AppModel.swift  # style column, actions
```

**Structure Decision**: same two-part layout as 002. New engine areas get their own folders
(`Glyphs/`). Folder icons get a separate public-API provider, so the private adapter does not grow
beyond sidebar behavior (Principle II).

## Phasing

Owner order (addendum 2026-11-23); system glyph first because it is under a day once the foundation
exists.

0. **Gate 0**:
   - amendment A approved (owner, 2026-11-23) and applied (T001);
   - proof P-1 (`actool` from the signed, hardened app) before Story 2's import ships;
   - proof P-2 (`setIcon` on a `~/Documents` subfolder from the app) before Story 4.
1. **Foundation**: schema 2 (no migration; schema 1 refused with a message), the `SidebarStyle`
   model, type declarations per style, versioned registry bundles.
2. **US1, system glyph**: SF Symbol validation and search, the style picker.
3. **US2, manual process**:
   - the SVG reader and template writer in the package;
   - `scripts/make-symbol-template`, a CLI over them;
   - directions in icon-specification.md;
   - the `actool` runner and combined car;
   - **Import Glyph…** with name and template;
   - glyph versions and deletion.
4. **US3, wizard**: the guided sheet (tool check, name, plain SVG, preview, build) on top of US2's
   engine.
5. **US4, folder icon**:
   - art builder with overrides or `.iconset`;
   - `FolderIconProvider` with fingerprint and backup;
   - the opt-in sheet;
   - Remove, Off and Reset All restore.
6. **Verification and release**:
   - quickstart checks and P-3 (owner);
   - code and security reviews;
   - `PRIVATE_API.md`, README and CHANGELOG;
   - `scripts/release.sh all` for **0.3.0**.

## Rollback

- In the app: Reset All, which undoes overrides, every `IconRegistry*` version and every folder
  icon the app set, then restores backed-up icons.
- Then quit, delete the app and the container, and follow README "Undoing everything".
- Installing 0.2.0 again: it reads schema 2 as unreadable (read-only mode, Reset All still works).
  There is no downgrade path for mappings; reset first.
- A folder icon left by a crash: the ledger keeps it; Reset All restores it. By hand: Finder
  **Get Info → select the icon → Delete**.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Principle III (folder writes) | The owner wants Finder windows to match the sidebar; macOS only shows a folder's own icon from `Icon\r` plus the flag | Leaving folders alone: no matching Finder icon (the spike showed the sidebar ignores `setIcon`, so the two can't be combined) |
| Principle I (`actool`) | Custom tinted glyphs need a compiled `Assets.car`; only `actool` produces one | Hand-writing `Assets.car`: undocumented binary format; SF Symbols only: no personal glyphs |
| A new registry bundle per change | Finder caches `Assets.car` per bundle path (S4b); rewriting in place shows stale glyphs until Finder restarts | Restarting Finder after every glyph change: disruptive, and against "no restart" (SC-004) |
