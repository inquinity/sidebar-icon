# Research: Icon groups (0.3.0) — spike

**Feature**: 004-icon-groups | **Date**: 2026-11-22 | **macOS**: 27.2.1 (26B131), Xcode 27.2

The owner wants sidebar Favorites drawn **outline blue** like the system glyphs (not full colour),
and the folder's own Finder icon set to matching full-colour art. Two workflows:

1. **Developers with Xcode**: a wizard checks for `actool`, takes a glyph name and the images, and
   builds the combined `Assets.car`.
2. **Everyone else**: the best alternative without Xcode: an SF Symbol for the sidebar.

This spike tested what the design depends on (Constitution IV). All scratch artifacts (test
Favorites, registry bundles, folders) were removed afterwards; nothing of the installed app was
touched.

## Findings

| # | Question | Result | Evidence |
|---|----------|--------|----------|
| S1 | Does a custom symbol in a **runtime-compiled** `Assets.car`, in a registry bundle, draw tinted in the sidebar? | **Yes** | Within 5 s, no Finder restart: the custom glyph drew in the accent colour, like `hammer` and the system Favorites |
| S2 | Can the wizard take a **plain SVG** and make the symbol template `actool` needs? | **Yes, for filled paths** | A generator wraps `<path>` elements into the template (guides, margins, glyph groups). `actool` requires at least a **`Regular-M`** glyph ("must have a glyph for Regular weight Medium size"); a `Regular-M`-only template compiles. **Stroke-only art** (rect/line with `stroke`) has no fill geometry and must be converted to filled paths first ("Outline Stroke" in the drawing app) |
| S2b | Glyph size | **Box ≈ 2× cap height** | Art fitted to 88 units (cap height 70.5) drew at text size, much smaller than system glyphs, whatever S/M/L sizes were present. Fitted to 150 units it matched `hammer` and the system glyphs |
| S3 | SF Symbol by name (`UTTypeIcons.UTTypeSymbolName = "hammer"`) | **Yes** (re-confirmed) | Tinted like the system glyphs; needs no `Assets.car` and no Xcode |
| S4 | One combined `Assets.car` with several symbols | **Yes** | Two custom symbols in one car compiled and both drew |
| S4b | Changing a glyph without restarting Finder | **Only with a new bundle path** | Finder keeps a registry bundle's `Assets.car` loaded. Rewriting the car in place (new type IDs, even new symbol names, even a new override code) kept the old glyph or fell back to a generic document glyph until Finder restarted. A **new bundle at a new path** (new car, new symbol name) showed at once — and kept working when the **same override code** moved to the new bundle and the old bundle was unregistered |
| S5 | Selected Favorite | **Same as system glyphs** | Grey row highlight; the custom glyph stays in the accent colour |
| S5b | Dark mode, accent colour | **Owner to check** | Changing system appearance settings is not done by the agent. Custom glyphs use the same template rendering as SF Symbols, so they are expected to follow both |
| S6 | Folder's own Finder icon via public `NSWorkspace.setIcon` | **Works; reversible** | Set: creates hidden `Icon\r` (0-byte data fork, ~800 KB resource fork with the icon) and the folder's custom-icon flag (`FinderInfo` `0x0400`); Finder windows show the full-colour art. Clear (`setIcon(nil)`): removes `Icon\r` and the flag; no extended attribute left. The folder's **modification time changes** on set and on clear |
| S6b | Git repositories | **Untracked file while set** | `git status` shows `?? "Icon\r"`; clean again after clear. A global `.gitignore` entry `Icon?` hides it |
| S6c | Folders in protected locations (`~/Documents`, `~/Desktop`) | **Not tested** | Writing `Icon\r` there needs Files & Folders access. A scratch tool run from the shell inherits the terminal's access, so only the real app can show the prompt; check during implementation |
| S7 | `actool` available | **Xcode only** | `xcrun --find actool` → Xcode; the Command Line Tools have no `actool`. Running it from the hardened, notarized app (via `Process`) is not tested yet |

## Design consequences for 0.3.0

1. **Icon group per mapping**: a sidebar glyph (SF Symbol name, or a custom symbol built by the
   wizard) plus optional full-colour art for the folder's Finder icon. The full-colour sidebar mode
   (the missing-symbol fallback) can be kept for existing mappings or dropped; owner decision.
2. **Wizard (Xcode users)**: check `xcrun --find actool` → glyph name → pick a **filled-path SVG**
   (refuse strokes with "Outline Stroke" guidance) and the full-colour image → preview → build.
   Fit the art to a ~150-unit box; emit at least `Regular-M` (three weights of the same geometry is
   fine). Keep each glyph's source in the container so the combined car can be rebuilt.
3. **Registry as versioned bundles**: every change writes a **new** registry bundle at a new path
   (for example `IconRegistry-<version>.app`) with the combined car and all types, registers it,
   then unregisters and deletes the previous one. Override codes stay stable. Symbol names include
   the asset ID. The ledger records each bundle path; Reset All removes every `IconRegistry*.app`.
4. **Without Xcode**: SF Symbol names, validated with a live tinted preview
   (`NSImage(systemSymbolName:)`); custom glyphs already built stay usable because the compiled car
   is kept in the container.
5. **Folder icon (opt-in)**: `NSWorkspace.setIcon` with the full-colour art; recorded in the
   ledger; Remove and Reset All clear it only if the folder's icon is still the one we set. A
   folder that already has a custom icon is left alone unless the owner explicitly replaces it
   (then the old icon must be kept to restore). Document the side effects: modification time,
   `Icon\r` in git and sync services, the privacy prompt for protected locations.
6. **Constitution**: Principle III must be amended for the opt-in folder icon (it currently forbids
   changing folder contents and existing custom icons). Principle I: `actool` is an optional
   Apple developer tool used only by the wizard.
7. **PRIVATE_API.md**: PA-04 gains "Finder draws a registered type's `UTTypeSymbolName` from the
   registering bundle's `Assets.car`, and caches that car per bundle path". `NSWorkspace.setIcon`
   is public API.

What to create per folder is in [icon-specification.md](icon-specification.md).

## Open checks (before or during implementation)

- Dark mode and a non-default accent colour with custom glyphs (owner).
- `actool` launched from the notarized, hardened app.
- `setIcon` from the app on a folder under `~/Documents` (privacy prompt and its answer).
- A folder that already has a custom icon (detect, refuse or back up and restore).

---

# Plan decisions (2026-11-22)

Each decision: what was chosen, why, and what else was considered.

## D1 — Config schema 2, no migration

- **Decision** (owner addendum, 2026-11-23): `config.json` schema 2 adds, per mapping, a
  `sidebarStyle` (`systemSymbol(name)`, `customGlyph(glyphID)` or `fullColour(assetID)`) and an
  optional `folderIcon`, and at the top level a `glyphs` list. **No migration**: a schema 1 file
  (0.2.0) loads as read-only with the message "This configuration was made by Sidebar Icons 0.2.0
  and isn't converted. Use Reset All to start fresh"; Reset All works from the shared ledger.
- **Rationale**: the owner is the only user and resets before upgrading; a migration is code that
  would run once.
- **Alternatives**: in-memory migration with a backup (planned first, dropped by the owner).

## D2 — Versioned registry bundles

- **Decision**: the registry bundle's name carries a content hash: `IconRegistry-<8 hex>.app`. The
  hash covers the type declarations and the `Assets.car` bytes. Apply computes the desired content:
  - if that bundle is already registered and recorded, nothing happens;
  - otherwise it writes the new bundle (staging, then rename), records it, registers it, sets
    overrides, and then unregisters and deletes every other recorded registry version, including
    0.2.0's `IconRegistry.app`.

  Override codes stay the same. "Our own bundle" in the claim check means any `IconRegistry*.app`
  directly in the container.
- **Rationale**: S4b. Finder caches a bundle's `Assets.car` per path, and a new path updates at
  once with the same code. A content hash makes apply idempotent: same content, same path.
- **Alternatives**: a monotonically increasing number (rejected: not idempotent); restarting
  Finder after glyph changes (rejected: SC-004).

## D3 — Type declarations per style

- **Decision**: the type identifier is
  `com.altmansoftwaredesign.sidebaricons.icon.<code>.<style key>`, where the style key is the asset
  ID (full colour), the glyph version ID (custom), or a hash of the symbol name (system).
  `UTTypeIcons` per style:
  - **full colour**: `{UTTypeIconFile: <assetID>.icns, UTTypeSymbolName: <missing name>}` (0.2.0);
  - **custom**: `{UTTypeSymbolName: <glyph name>.<version ID>}`, with the symbol compiled into the
    bundle's `Assets.car`;
  - **system**: `{UTTypeSymbolName: <SF Symbol name>}`.
- **Rationale**: S1, S3; a new style key gives a new type, and Finder's per-type cache can't show
  stale art (001 B3). Versioned symbol names keep custom glyphs distinct from system names.

## D4 — Symbol template writer

- **Decision**: a Swift `SVGShapeReader` (Foundation `XMLParser`) reads the root `viewBox` and
  these filled shapes:
  - `<path>`, which keeps its `fill-rule`;
  - `<rect>` (with `rx`/`ry`), `<circle>`, `<ellipse>` and `<polygon>`, each converted to path data;
  - `<g>` without `transform`.

  It refuses any of the following, naming the element:
  - `stroke` other than `none` together with `fill="none"`;
  - `<text>`, `<image>`, `<use>`, `<line>` and `<polyline>`;
  - gradients, masks and filters;
  - `transform` on any element;
  - an empty result.

  `SymbolTemplateWriter` fits the art to a **150-unit** box (120 units above the baseline, 30
  below). It emits Ultralight-M, Regular-M and Black-M glyphs with the same geometry, plus guides
  and margins, following the template the spike compiled.
- **Rationale**: S2 (filled paths; Regular-M required; strokes have no fill) and S2b (box size).
  Refusing transforms keeps v1 simple; most editors' "Export SVG" can flatten them, and the error
  says so.
- **Alternatives**: converting strokes to fills ourselves (rejected: needs path offsetting, error
  prone); requiring a template from Apple's SF Symbols app (rejected: much harder for the owner).

## D4b — Manual process (owner addendum)

- **Decision**: the template writer and SVG reader live in the package, so `scripts/make-symbol-template`
  (a small Swift command-line target in the package, run with `swift run`) and the wizard share
  them. Directions in icon-specification.md: draw with filled shapes, run the script, then Import
  Glyph… in the app (name and template). Import also accepts a template exported from Apple's SF
  Symbols app, as long as it has a `Regular-M` glyph.
- **Rationale**: the owner gets custom glyphs before the wizard exists, and the wizard later only
  adds guidance around the same engine.

## D5 — Running `actool`

- **Decision**: `ActoolRunner`:
  1. Locate the tool with `/usr/bin/xcrun --find actool`.
  2. Run it with `Process`, using a fixed argument list:
     `--compile <dir> --platform macosx --minimum-deployment-target 27.0 --output-format xml1 --errors --warnings --output-partial-info-plist <file> <catalog>`.
  3. Give it an environment of `PATH=/usr/bin:/bin`, plus `HOME`, `TMPDIR`, and `DEVELOPER_DIR`
     if set.
  4. Stop it after 120 s.
  5. Parse the XML output for errors, and map known failures to plain messages: tool missing
     (Command Line Tools only), Xcode license not accepted, first-launch components missing.

  Builds run in `Build/` inside the container, and only the resulting `Assets.car` is kept, inside
  the new registry bundle.
- **Rationale**: an Apple tool with no shell and a minimal environment, the same discipline as
  `lsregister` (002). Whether it runs from the hardened app is **proof P-1** (Principle IV).
- **Alternatives**: `xcrun actool` directly (rejected: `xcrun` would run whatever tool name it
  resolves; finding the path first allows a check that it is inside a Developer directory).

## D6 — SF Symbol validation and search

- **Decision**: a name is valid when `NSImage(systemSymbolName:accessibilityDescription:)` returns
  an image on the running Mac. The search box suggests from a curated list of about 80 names
  relevant to folders (folder, doc, hammer, terminal, externaldrive, photo, music, film, globe, …),
  filtered as the owner types, and accepts any valid name.
- **Rationale**: there is no public API that lists every symbol; validation is public and exact.
- **Alternatives**: bundling the full name list from the SF Symbols app (rejected: licence and
  staleness).

## D7 — Folder art to `.icns`

- **Decision**: `FolderArtBuilder` makes an `.icns` from:
  - the master (PNG ≥ 1024 px, PDF or SVG), rendered per size as `ICNSConverter` does;
  - optional overrides: individual PNGs, or the matching files of an `.iconset` (Apple's file
    names), each checked for exact pixel size; an override replaces the rendered representation.

  ImageIO only; `iconutil` is not needed.
- **Rationale**: FR-012; one code path for both inputs; reuses 002's proven converter.

## D8 — Folder icon provider

- **Decision**: `FolderIconProvider` (public API, outside the private adapter):
  1. **Before**: read the folder's state. It has a custom icon if `Icon\r` exists or the
     `FinderInfo` custom-icon flag is set. If it does, a replacement needs explicit confirmation,
     and the current icon is saved as `.icns` in `FolderIconBackups/<id>.icns` (from
     `NSWorkspace.icon(forFile:)`).
  2. **Record**: write a ledger entry of kind `folderIcon`, with the folder path, the backup file
     name if any, and (after setting) a **fingerprint**: the SHA-256 of `Icon\r`'s resource fork.
  3. **Set**: `NSWorkspace.setIcon(_:forFile:options:)`; a `false` return is an error (for example,
     access denied) and the entry is removed.
  4. **Undo** (Off, Remove, Reset All): if the current fingerprint matches, restore the backup with
     `setIcon(backup)`, or clear with `setIcon(nil)`, and remove the entry. If it doesn't match,
     leave the folder, keep a note, and remove the entry.
- **Rationale**: FR-013 to FR-015, S6 (set and clear are clean). The fingerprint makes undo safe if
  something else changed the icon since.

## D9 — UI

- **Decision**: the row shows the style (system, custom or full colour) and a folder-icon badge.
  Change Icon… opens the **style picker** sheet:
  - tabs System glyph, Custom glyph and Full colour;
  - a live tinted preview at 16 and 20 pt, in light and dark appearance.

  **New Custom Glyph…** opens the **wizard**: `actool` check, then name, then SVG, then optional
  folder art, then preview, then Build. **Folder icon…** opens the **opt-in sheet**, which explains
  the hidden file, the modification date, git and sync, and a replace warning when needed. Add
  Folder… uses the style picker after the folder pick, instead of going straight to an image.
- **Rationale**: one place to choose a look; the folder icon stays a separate, labeled action
  (Principle III).

## D10 — Verified builds and release

- **Decision**: `SidebarIconCoreInfo.verifiedBuilds` gets each build where quickstart passes (the
  work Mac's build when the owner reports it). Release 0.3.0 with `scripts/release.sh all` after the
  reviews; CHANGELOG says 0.2.0 configurations aren't converted (reset first) and describes the
  folder-icon opt-in.
