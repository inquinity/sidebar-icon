# Roadmap

Where Sidebar Icons is going, and what each step needs. This file is for planning: move items
between sections, add dates and owners, and strike what you drop. Shipped changes are in
[CHANGELOG.md](CHANGELOG.md); the detailed work lives in `specs/NNN-feature/`.

## Where we are

**0.3.1** (2026-11-24, on macOS 27.2.1 build 26B131) is released, notarized and installed.

- Sidebar Favorites show outline-blue system glyphs, your own custom glyphs, or full-colour images.
- A Glyph Library window holds the custom glyphs; a wizard builds them from an SVG (needs Xcode).
- A folder can opt in to full-colour art as its own Finder icon, with backup and restore.
- Everything is undone by Remove, Off and Reset All.

## Constraints that shape every item

From the [constitution](.specify/memory/constitution.md) and [PRIVATE_API.md](PRIVATE_API.md):

- Apple frameworks only; no networking, telemetry, updater, daemon, login item or helper.
- Undocumented macOS behavior is isolated in one adapter and listed publicly. A new macOS build can
  break it, so every macOS release is a risk to plan for.
- Every outside change is recorded first and reversible.
- The app's text states what it does now, never history or what it doesn't do.
- Prove a risky mechanism with an experiment before building on it.

## Next: 1.0.0

1.0.0 means the install is stable. The bundle ID and App Group are settled (lowercase), and the
data format is one the app will keep reading. The gate comes from
[the 002 tasks](specs/002-mapping-manager-v1/tasks.md) ("1.0.0 gate"); status below is what the
0.3.x work covered. Tick items in the 002 file after confirming.

**Must be done**

- [x] F001 Refuse an already-mapped folder right after the folder is picked (after 0.3.1).
- [x] F002 Share one `lsregister -dump` per action (after 0.3.1). *Measure Refresh Finder on a Developer ID build.*
- [x] F003 After removing the last mapping with a failed clear, Refresh Finder retries it (after 0.3.1).
- [x] F015 The registry bundle is rewritten whenever the needed codes change (after 0.3.1).
- [x] F017 `MappingManager.load()` runs through `exclusive` (after 0.3.1).
- [x] F005 Re-point… on Off rows and on rows whose path now resolves elsewhere (0.3.0, 0.3.1).
- [x] F014 Refuse a data folder reached through a link (0.3.0, final security review M1).
- [x] F016, F021 Developer ID release builds; lowercase bundle ID and App Group.

**Decide: do, drop, or defer past 1.0.0** (record the reason in research.md)

- [ ] F010 Warn about thin, faint line art that vanishes at 16 px.
- [ ] F011 Let the image picker accept `.icns`.
- [ ] F012 Warn about busy art whose detail blends away at 16 px.
- [ ] F018 Does Refresh Finder's polite quit work from the hardened app, or always fall back to
      SIGTERM after 5 s? Does it leave an Automation privacy record?
- [ ] F019 Do the open panels add chosen items to Recent Items, and can an SVG or PDF make the
      renderer fetch remote resources?
- [ ] F020 Show a conflict when another Finder extension watches the same folder, if detectable.

**Release checklist for 1.0.0**

- [ ] The 0.2.0-format check no longer matters (the app has not left this machine), so retire the
      "earlier format" refusal path only if you decide to.
- [ ] Verify on every macOS build you intend to support; add each to `verifiedBuilds`.
- [ ] A full Reset All leftover audit on a Developer ID build (T046 was skipped in 0.3.0).
- [ ] README, PRIVATE_API.md and CHANGELOG reviewed against the shipped behavior.

## Candidates after 1.0.0

Rough size: S under a day, M a few days, L a week or more. Order is not a commitment.

| Idea | Why | Size | Notes |
|------|-----|------|-------|
| Follow a renamed or moved folder automatically | Today the row says "Folder missing" until you Re-point | M | Store a stable folder reference; ask before updating. Test how Finder's Favorites behave on rename first |
| One library for everything made | The Glyph Library holds custom glyphs only; images and folder art stay with each mapping | M | Reuse an image or art across folders. Needs a design call first |
| Re-use folder art across folders | Same art for several folders is common | S–M | Falls out of the unified library |
| Folder-icon sizes in the sheet | The sheet doesn't show the art already in use when you reopen it | S | Known; changing only small sizes means choosing the master again |
| Install packaging (disk image) | The zip is fine for one Mac | S | Only if the app leaves this machine |
| GitHub release page with the notarized zip | The tags are public, the builds are not | S | Publishes publicly; decide when |
| Group mappings, bulk Apply | Many folders at once | M | Only if the folder count grows |
| Support more macOS builds | One verified build today | S per build | Each new build needs the live checks |

## Parking lot

Ideas not yet worth sizing. Add freely.

- Icon packs (import a set of glyphs and art together).
- Per-folder light and dark art.
- A menu bar item for Refresh Finder.
- Export and import of the mapping list (as a file, never a service).

## Not planned

Out of bounds under the constitution, so they would need an amendment first:

- Networking, update checks, telemetry, accounts.
- Background daemons, login items, privileged helpers, or reading Finder's sidebar store files.
- Modifying a folder beyond the opt-in icon file and its custom-icon flag.

## How to use this file

1. Pick the next milestone and move its items to a dated section here.
2. Run `/speckit-specify` for each feature that needs a spec; link it from the item.
3. When a release ships, move its items to the CHANGELOG and tick them here.
