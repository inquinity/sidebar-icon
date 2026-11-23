# Data Model: Icon Groups (0.3.0)

Builds on [002's data model](../002-mapping-manager-v1/data-model.md). Types marked **new** or
**changed**; everything else is unchanged.

## AppConfiguration (changed: schema 2)

```text
config.json
{
  "schemaVersion": 2,
  "mappings": [SidebarMapping],
  "assets":   [IconAsset],
  "glyphs":   [CustomGlyph]          // new
}
```

- Valid when 002's rules hold, every `sidebarStyle` reference resolves (asset or glyph), every
  `folderIcon.artAssetID` resolves, and glyph names are unique.
- **Migration from schema 1** (research D1): each mapping gets `sidebarStyle = fullColour(iconAssetID)`
  and no `folderIcon`; `glyphs` is empty. The original file is copied once to
  `config.schema1.json` before the first schema-2 save.
- Schema greater than 2 or invalid: read-only, Reset All available (002 D3).

## SidebarMapping (changed)

| Field | Type | Rules |
|-------|------|-------|
| `id`, `folderPath`, `osType`, `enabled` | as 002 | unchanged; `osType` stays stable across style changes |
| `sidebarStyle` | SidebarStyle | **new**; replaces `iconAssetID` (kept only in schema 1) |
| `folderIcon` | FolderIconSetting? | **new**; nil means the folder is not touched |

## SidebarStyle (new)

| Case | Payload | Registry declaration (research D3) |
|------|---------|------------------------------------|
| `systemSymbol` | `name: String` (valid on this Mac when chosen) | `UTTypeSymbolName = name` |
| `customGlyph` | `glyphID: UUID` | `UTTypeSymbolName = <glyph name>.<version id>`, symbol in the bundle's `Assets.car` |
| `fullColour` | `assetID: UUID` | `UTTypeIconFile = <assetID>.icns`, `UTTypeSymbolName = <missing>` (0.2.0) |

## CustomGlyph (new)

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | stable |
| `name` | String | `^[a-z0-9][a-z0-9.-]{0,47}$`; unique among glyphs |
| `versionID` | UUID | new on every change of the drawing (cache key, research D2/D3) |
| `sourceFileName` | String | `Glyphs/<versionID>.svg`, a copy of the owner's SVG; plain name only |
| `templateFileName` | String | `Glyphs/<versionID>.template.svg`, generated (research D4) |
| `widthRatio`, `detailWarning` | Double, Bool | from the reader, for the preview's warnings |

Deleting a glyph used by mappings asks for a replacement style first (FR-010).

## FolderIconSetting (new)

| Field | Type | Rules |
|-------|------|-------|
| `enabled` | Bool | the opt-in (FR-011); off by default |
| `artAssetID` | UUID | the master art (`IconAsset`, PNG ≥ 1024 px, PDF or SVG) |
| `overrideAssetIDs` | [String: UUID] | optional hand-tuned sizes keyed by `.iconset` file name (`icon_16x16`, `icon_16x16@2x`, …) |
| `replaceExisting` | Bool | true only after the owner confirmed replacing a custom icon (FR-013) |

## IconAsset (changed)

Adds `role`: `sidebarArt` (0.2.0 full colour), `folderArtMaster`, `folderArtSize(name)`. Immutable
as in 002 (new pick, new ID).

## Change record (changed: `ledger.json`)

| Kind | Target | Extra fields | Undo |
|------|--------|--------------|------|
| `iconRegistration` | a registry bundle path (`IconRegistry.app` or `IconRegistry-<hash>.app` in the container) | — | `lsregister -u` and delete (only bundles in the container, never links) |
| `sidebarOverride` | folder path | `osType` | clear the override by code (002) |
| `folderIcon` (**new**) | folder path | `fingerprint` (SHA-256 of `Icon\r`'s resource fork after setting), `backupFileName` (optional) | if the fingerprint still matches: restore the backup or clear the icon; else leave it and note |

## MappingState (changed)

Adds per-row detail: `folderIcon` = `notSet`, `set`, `changedElsewhere`, `accessDenied`, `failed(String)`.
A custom glyph whose built car is missing shows `notApplied` with "Rebuild needs Xcode" when
`actool` is unavailable.

## State transitions (one mapping)

```text
Add ──(style picker)──► applied with style S
any ──Change style──► (same code, new type, maybe new registry version) ──► applied
custom glyph ──Change drawing──► (new versionID, new registry version) ──► applied
any ──Folder icon on (confirm)──► folderIcon set (ledger before set)
folderIcon set ──Off / Remove / Reset All──► restored (backup or plain) | left (changed elsewhere)
```

## Files the utility writes (Constitution I: complete list)

Inside the container (`…/45GJWJVQN2.com.altmansoftwaredesign.sidebaricons/Library/Application Support/SidebarIcons/`):

| Path | Purpose | Removed by |
|------|---------|------------|
| `config.json` (+ `.tmp`) | schema 2 | Reset All |
| `config.schema1.json` | one-time pre-migration backup | Reset All |
| `ledger.json` (+ `.tmp`) | change records | emptied by Reset All |
| `Icons/<id>.<ext>`, `Icons/<id>.icns` (+ `.tmp`) | sidebar art (full colour), folder art master and sizes, built `.icns` | Remove, Reset All |
| `Glyphs/<versionID>.svg`, `Glyphs/<versionID>.template.svg` | custom glyph sources and templates | glyph delete, Reset All |
| `Build/` | temporary asset catalogs and `actool` output during a build | deleted after each build; Reset All |
| `IconRegistry-<hash>.app/` (+ `.…staging-<uuid>/`) | the current registry version (earlier ones removed after a switch) | Reset All |
| `FolderIconBackups/<id>.icns` | a folder's previous custom icon | used and deleted on restore; Reset All |

Outside the container (all undone by Reset All):
- the sidebar override property on each mapped Favorite (002);
- the Launch Services registration of each `IconRegistry*.app` version (002, now versioned);
- **for opted-in folders only**: `Icon\r` inside the folder and the folder's custom-icon flag (and
  its modification date changes on set and restore).

Written by macOS for the app: as in 002 (preferences plist, Application Scripts folders, cache
folder), plus possibly a privacy (Files & Folders) decision if a protected folder was opted in.
