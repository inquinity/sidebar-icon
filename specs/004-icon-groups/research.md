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
