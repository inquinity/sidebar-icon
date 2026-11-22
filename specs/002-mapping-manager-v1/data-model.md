# Data Model: Sidebar Icon Mapping Manager v1

Builds on [001's data model](../001-sidebar-icon-spike/data-model.md); the types below already
exist in `SidebarIconCore` unless marked **new**.

## SidebarMapping (existing)

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | stable for the mapping's life |
| `folderPath` | String | standardized (`PathStandardizer`) when added; unique across mappings, comparing resolved paths (FR-004, symlink and `~` cases). On load only the stored form is checked (absolute, no `~`, trailing `/`, `.` or `..`), so a later rename or link never makes the config unreadable |
| `iconAssetID` | UUID | refers to an `IconAsset` in the same config |
| `osType` | String | `S` + 3 base-36 chars; unique; allocated once on Add (research D4) and kept |
| `enabled` | Bool | default true; Off keeps the mapping (FR-005) |

## IconAsset (existing; now immutable)

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | new for every pick (research D5) |
| `sourceFormat` | pdf, png, svg, icns | detected from content (`AssetImporter`), not extension |
| `fileName` | String | `<id>.<format>`; plain name only, no `/`, `..`, or leading `.` (001 review) |
| `icnsFileName` | String? | `<id>.icns`; written via temp + move, rebuilt if missing or unreadable |

Two mappings may use the same image: each gets its own asset copy (spec edge case).

## AppConfiguration (**new**)

```text
config.json
{
  "schemaVersion": 1,
  "mappings": [SidebarMapping],
  "assets":   [IconAsset]
}
```

- Valid when `SidebarMapping.validate` returns no problems and every `iconAssetID` resolves.
- An asset no mapping refers to is removed on the next save, and its files are deleted.
- `schemaVersion` greater than 1, or unreadable JSON: the app shows the error, makes no writes,
  and keeps Reset All available.

## MappingState (**new**, derived, never stored)

| Value | Meaning | Offered action |
|-------|---------|----------------|
| `applied` | override set to this code, bundle registered | — |
| `off` | disabled | Turn On (Story 2) |
| `notInSidebar` | folder exists, not in Favorites | Apply Now (after adding it in Finder) |
| `folderMissing` | folder does not exist | Re-point / Remove (Story 2) |
| `notApplied` | in Favorites, override absent | Apply Now |
| `error(String)` | duplicate Favorite, foreign override, code claimed elsewhere, last apply failed (outranks a still-set override), or the stored path now resolves elsewhere | shows reason; Apply Now |

Derivation is in research D7. Computing it is read-only.

## Change record (existing `OutsideChange` in `ledger.json`)

Kinds: `iconRegistration` (target is the container's `IconRegistry.app`) and `sidebarOverride`
(target is the folder path, with `osType`). Each record is written before its change and removed
after a successful undo. The spike and the app share this file (research D2).

## State transitions (one mapping)

```text
            Add (folder+image) ──► applied | notInSidebar | folderMissing | error
applied ──Turn Off──► off ──Turn On──► applied
any ──Change Icon──► (new asset, same code) ──► applied
any ──Remove (confirm)──► gone (override cleared, asset files deleted, config entry removed)
any ──Reset All (confirm)──► gone (config emptied; every ledger entry undone)
notInSidebar / notApplied ──Apply Now or Refresh Finder──► applied
```

## Files the utility writes (Constitution I: complete list)

All of them are inside `~/Library/Group Containers/45GJWJVQN2.com.altmansoftwaredesign.SidebarIcons/Library/Application Support/SidebarIcons/`:

| Path | Purpose | Removed by |
|------|---------|------------|
| `config.json` (+ `config.json.tmp` during save) | mappings and assets | Reset All deletes it; deleting the container removes it |
| `ledger.json` (+ `ledger.json.tmp` during save) | change records | emptied by Reset All; deleting the container removes it |
| `Icons/<id>.<format>` | copied image | Remove, Reset All |
| `Icons/<id>.icns` (+ `.tmp` during conversion) | converted icon | Remove, Reset All |
| `IconRegistry.app/` (+ `.IconRegistry.app.staging-<uuid>/` while writing) | registry bundle | Reset All (also removes staging folders left by a crash and a bundle that was never recorded), or when no enabled mapping is left |

Outside the container (all undone by Reset All):
- the `com.apple.LSSharedFileList.OverrideIcon.OSType` property on each mapped Favorite;
- the Launch Services registration of `IconRegistry.app` and its exported types.

Written by macOS on the app's behalf (no user data; removed by deleting them after uninstalling,
see the README). Seen on 26B131, 2026-11-21:
- `~/Library/Preferences/com.altmansoftwaredesign.SidebarIcons.plist`: window frames and the
  open panel's last folder and size (shared with the spike, which has the same bundle ID);
- `~/Library/Application Scripts/com.altmansoftwaredesign.SidebarIcons` and
  `~/Library/Application Scripts/45GJWJVQN2.com.altmansoftwaredesign.SidebarIcons` (empty folders
  macOS creates for the app and its App Group);
- the per-user cache folder `$(getconf DARWIN_USER_CACHE_DIR)com.altmansoftwaredesign.SidebarIcons`;
- the app's own Launch Services registration, as for any app (dropped when the app is deleted);
- possibly privacy (TCC) decisions, if macOS asked for access to a protected folder
  (`tccutil reset All com.altmansoftwaredesign.SidebarIcons`, run by the owner);
- possibly Icon Services' cached renderings of the `sidebaricons.icon.*` types, until the system
  purges its icon cache. No Saved Application State folder was found.

Left by the retired spike only (not created by the app): the sandbox containers
`~/Library/Containers/com.altmansoftwaredesign.SidebarIcons` (sandboxed build, experiment B5) and
`~/Library/Containers/com.altmansoftwaredesign.SidebarIcons.FinderSync` (Finder Sync extension),
`~/Library/Application Scripts/com.altmansoftwaredesign.SidebarIcons.FinderSync`, and the cache
folder `…/C/com.altmansoftwaredesign.SidebarIcons.FinderSync`.
