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

**Story 2, custom glyph**
3. Without Xcode selected (or simulate `toolUnavailable`): the wizard explains and offers a system
   glyph.
4. The stroked SVG is refused with the Outline Stroke guidance; nothing saved.
5. A filled SVG builds; the glyph shows outline blue at system size (compare with a system glyph:
   within 10 %, SC-002) within 30 s (SC-004).
6. Change the drawing: the new glyph shows without a restart; 20 other custom mappings keep theirs.

**Story 3, folder icon**
7. Opt in with a 1024 PNG: Finder list, column and icon views show the art; `Icon\r` exists.
8. With an `.iconset` override for 16 pt: list view uses the hand-tuned image.
9. A folder that already has a custom icon: a warning; Replace keeps a backup; Off restores the
   previous icon.
10. Change the folder's icon in Get Info, then Remove: the app leaves it and says so.
11. A git repository folder: `git status` shows `Icon\r` while set, clean after Off.

**Story 4, upgrade**
12. Start 0.3.0 with a 0.2.0 configuration: every mapping still shows its icon, style "Full colour";
    `config.schema1.json` exists after the first change.

**Reset and leftovers (SC-005, SC-007)**
13. Reset All with every style and folder icons set: no overrides, no `IconRegistry*` in
    `lsregister -dump`, no `Icon\r` or icon flag left by the app, previous custom icons back.
14. Folders never opted in: modification date and contents unchanged across the whole pass.

## Rollback

See [plan.md › Rollback](plan.md#rollback).
