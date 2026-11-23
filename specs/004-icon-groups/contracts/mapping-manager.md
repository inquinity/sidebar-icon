# Contract: MappingManager changes (0.3.0)

Extends [002's contract](../../002-mapping-manager-v1/contracts/mapping-manager.md). Every action
still runs through `exclusive` (one at a time), returns an `ActionResult`, and reports a post-save
apply failure as "Saved, but not applied: …".

## Types

```swift
public enum SidebarStyle: Codable, Sendable, Equatable {
    case systemSymbol(name: String)
    case customGlyph(glyphID: UUID)
    case fullColour(assetID: UUID)
}

public struct GlyphRow: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var versionID: UUID
    public var templateFile: URL     // for the preview
    public var usedBy: [UUID]        // mapping ids
}

public enum GlyphBuildError: Error, Sendable, Equatable {
    case toolUnavailable(reason: String)     // no actool, CLT only, license, first launch
    case invalidName(String)
    case duplicateName(String)
    case unsupportedSVG(element: String, guidance: String)
    case emptySVG
    case compileFailed(String)               // actool's message
    case timedOut
}

extension ManagerError {
    case glyph(GlyphBuildError)
    case unknownSymbol(String)                // FR-003
    case folderIconNeedsConfirmation(existing: Bool)   // FR-013
    case folderIconFailed(String)             // e.g. access denied
}
```

`MappingRow` gains `style: SidebarStyle`, `folderIcon: FolderIconState`.

## Methods

| Method | Story | Outside changes | Behavior |
|--------|-------|-----------------|----------|
| `add(folder:style:)` | 1, 2 | yes | replaces 002's `add(folder:image:)`; image styles import as before |
| `setStyle(_:for:)` | 1, 2, 4 | yes | save, then apply (new type, new registry version if needed; code unchanged) |
| `glyphs() -> [GlyphRow]` | 2 | none | |
| `glyphToolStatus() async -> ToolStatus` | 2 | none | `available(path)` or `unavailable(reason)`; runs `xcrun --find actool` |
| `createGlyph(name:svg:) async throws -> GlyphRow` | 2 | none (container only) | validate name; read SVG (contract glyph-builder.md); write template; build the combined car to check it compiles; save |
| `updateGlyph(_:svg:)` | 2 | yes | new `versionID`, rebuild, apply (mappings using it switch to the new registry version) |
| `deleteGlyph(_:replacement:)` | 2 | yes | mappings using it get `replacement`; rebuild; apply |
| `setFolderIcon(_:for:confirmReplace:)` | 3 | yes | `FolderIconSetting?`; nil or `enabled = false` turns it off (restores). Throws `folderIconNeedsConfirmation(existing: true)` if the folder has a custom icon and `confirmReplace` is false |
| `resetAll()` | all | yes | as 002, plus: restore every recorded folder icon (fingerprint rule), unregister every recorded `IconRegistry*` version and any unrecorded one in the container, delete `Glyphs/`, `Build/`, `FolderIconBackups/`, `config.schema1.json` |
| `load()` | all | none | migrates schema 1 in memory; never writes |

## Guarantees (tested)

- Migration: a schema 1 file loads with every mapping `fullColour(sameAsset)`; the first save writes
  schema 2 and `config.schema1.json` with the original bytes; loading never writes.
- Same configuration → same registry bundle path (content hash); apply twice changes nothing.
- A style or glyph change never changes a mapping's `osType`.
- After a registry switch, exactly one `IconRegistry*` registration remains recorded.
- A folder icon is recorded before it is set; undo only touches a folder whose fingerprint matches;
  a backup is restored when present.
- Folders without `folderIcon.enabled` are never written to.
- Without `actool`, custom-glyph mappings keep working from the existing car; only create, update
  and delete of glyphs fail, with `toolUnavailable`.
