# Quickstart: build, prove and verify Icon Groups (0.3.0)

The package logic is covered by `swift test`; what Finder shows is checked by hand below. Record
each result (pass/fail, macOS build, notes) in research.md and fold failures into tasks.md.

## Prerequisites

- macOS 27.2.1 (26B131) or later; Xcode 27.2 (for building, and for the custom-glyph checks).
- Test folders in sidebar Favorites; one inside `~/Documents` for P-2; one git repository.
- Resources per [icon-specification.md](icon-specification.md): one filled-path outline SVG, one
  stroked SVG (to see the refusal), one 1024 × 1024 PNG, an `.iconset` with at least `icon_16x16`.

## Build and test

```bash
cd Packages/SidebarIconCore && swift test
```

```bash
scripts/release.sh build --dry-run
```

## Gate 0: proofs (Principle IV; before P2/P3 tasks)

- **P-1 actool from the hardened app**: a signed Release (or Developer ID dry run) build runs
  `glyphToolStatus()` and builds one glyph. Pass: an `Assets.car` is produced and the glyph shows
  in the sidebar.
- **P-2 folder icon in a protected location**: from the app, set a folder icon on
  `~/Documents/<test>`. Record whether macOS prompts, what each answer does, and that
  `setIcon` returning false is reported as "access denied".
- **P-3 appearance (owner)**: with system and custom glyphs applied, switch Light/Dark and a
  non-default accent colour. Pass: custom glyphs follow like system glyphs.

## Manual checks

**Story 1, system glyph**
1. Add a folder with style System glyph `hammer`: outline blue, system size, within 10 s, no Finder
   restart (SC-001). An invalid name is refused.
2. Change the style to `externaldrive`: updates without a restart; the code is unchanged (ledger).

**Story 2, manual process**
3. Follow icon-specification.md "Manual process": `swift run make-symbol-template` turns the filled
   SVG into a template; the stroked SVG is refused with the Outline Stroke guidance.
4. Import Glyph… with a name and the template: the glyph shows outline blue at system size within
   30 s (SC-002, SC-004); the whole procedure takes under 5 minutes (SC-006).
5. Import a new version under the same name: it replaces the old glyph without a Finder restart.

**Story 3, wizard**
6. Without Xcode selected (or simulate `toolUnavailable`): the wizard explains and offers the other
   paths.
7. A plain filled SVG builds through the wizard; previews show the warnings; 20 other custom
   mappings keep their glyphs when one changes.

**Story 4, folder icon**
8. Opt in with a 1024 PNG: Finder list, column and icon views show the art; `Icon\r` exists.
9. With an `.iconset` override for 16 pt: list view uses the hand-tuned image.
10. A folder that already has a custom icon: a warning; Replace keeps a backup; Off restores the
   previous icon.
11. Change the folder's icon in Get Info, then Remove: the app leaves it and says so.
12. A git repository folder: `git status` shows `Icon\r` while set, clean after Off.

**0.2.0 configuration**
13. Start 0.3.0 with a 0.2.0 configuration: the window says it was made by 0.2.0 and isn't
    converted; nothing changes; Reset All undoes 0.2.0's recorded changes.

**Reset and leftovers (SC-005, SC-007)**
14. Reset All with every style and folder icons set: no overrides, no `IconRegistry*` in
    `lsregister -dump`, no `Icon\r` or icon flag left by the app, previous custom icons back.
15. Folders never opted in: modification date and contents unchanged across the whole pass.

## Rollback

See [plan.md › Rollback](plan.md#rollback).
