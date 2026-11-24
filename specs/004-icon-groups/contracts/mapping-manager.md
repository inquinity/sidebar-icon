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

public struct CustomGlyph: Codable, Sendable, Equatable, Identifiable {   // data-model.md
    public var id: UUID
    public var name: String
    public var versionID: UUID
    public var sourceFileName: String?   // <versionID>.svg (wizard only)
    public var templateFileName: String  // <versionID>.template.svg, for the preview
}

public enum GlyphBuildError: Error, Sendable, Equatable {
    case toolUnavailable(String)             // no actool, CLT only, license, first launch
    case compileFailed(String)               // actool's message
    case timedOut
    case missingRequiredGlyph(String)        // no Regular-M
    case templateUnreadable(String)
}

extension ManagerError {
    case unknownSymbol(String)                // FR-003
    case invalidGlyphName(String), glyphNameTaken(String), unknownGlyph, glyphInUse(String)
    case drawingRefused(SVGReadError)         // the reader's guidance (glyph-builder.md)
    case glyphBuild(GlyphBuildError)
    case folderIconNeedsConfirmation(existing: Bool)   // FR-013
    case folderIconFailed(String)             // e.g. access denied
    case folderIconBackupFailed(String), folderIconUnverified(String), folderIconUnsafe(String)
    case folderIconMissing(String), folderArtRefused(FolderArtError)
    case containerLinked(String)              // the data folder is reached through a link
}
```

`MappingRow` gains `style: SidebarStyle`, `folderIcon: FolderIconState` (`notSet`, `set`, `changedElsewhere`, `failed(message)`, `folderMissing`; a refusal by macOS is `failed` with the access-denied text), `folderIconOptedIn`, `resolvesElsewhere` (the stored path now resolves to another folder), and the derived `hasFolderIcon` and `offersRepoint`.

Folder icons follow the mapping: Off and Remove put the folder back, On and Re-point set it again (a replacement the owner confirmed for this mapping is repeated, with a new backup; otherwise a foreign icon is left and the row says so). Apply Now never touches folders.

## Methods

| Method | Story | Outside changes | Behavior |
|--------|-------|-----------------|----------|
| `add(folder:style:)` | 1, 2 | yes | replaces 002's `add(folder:image:)`; image styles import as before |
| `setStyle(_:for:)` | 1, 2, 4 | yes | save, then apply (new type, new registry version if needed; code unchanged) |
| `glyphs() -> [CustomGlyph]` | 2 | none | |
| `glyphToolStatus() -> ToolStatus` | 2 | none | `available(path)` or `unavailable(reason)`; runs `xcrun --find actool` |
| `importGlyph(name:template:) async throws -> ActionResult` | 2 | yes (applies) | manual process: a symbol template file (from the helper script or the SF Symbols app); build the combined car with it; apply mappings using that name. A new import under an existing name makes a new version |
| `createGlyph(name:svg:) async throws -> ActionResult` | 3 | applies, but no mapping uses a new glyph, so the registry is unchanged | validate the name (a name in use throws `glyphNameTaken`); read the SVG (contract glyph-builder.md; a refusal throws `drawingRefused` with the reader's guidance); write the template and keep the SVG as `<versionID>.svg`; build the combined car; save; install the car. A failure before the save leaves `Glyphs/` unchanged |
| `updateGlyph(_:svg:) async throws -> ActionResult` | 3 | yes | as `createGlyph` for an existing glyph: new `versionID`, rebuild, apply (mappings using it switch to the new registry version); the previous version's files are removed by the save |
| `deleteGlyph(_:replacement:)` | 2 | yes | mappings using it get `replacement`; rebuild; apply |
| `setFolderIcon(_:for:confirmReplace:)` | 4 | yes | `FolderArt?` (master URL plus optional overrides keyed by `.iconset` name); the art is checked (`folderArtRefused`), copied into `Icons/`, built in `Build/` and set (ledger first), then saved; a failed save puts the folder back. nil turns it off (restores, FR-014). Throws `folderIconNeedsConfirmation(existing: true)` if the folder has a custom icon that isn't ours and `confirmReplace` is false; `folderIconFailed(path)` when macOS refuses. For a mapping that is Off the art is saved and set on On |
| `folderIconNeedsConfirmation(atPath:)` | 4 | none | read-only, for the sheet's replace warning |
| `resetAll()` | all | yes | as 002, plus: restore every recorded folder icon (fingerprint rule), unregister every recorded `IconRegistry*` version and any unrecorded one in the container, delete `Glyphs/`, `Build/`, `FolderIconBackups/`. A folder that is now a link or not a plain folder is left as it is and its record forgotten. Refused when the data folder is reached through a link (`containerLinked`) |
| `hasFolderIconRecords() -> Bool` | 4 | none | for the Reset All confirmation, also when the configuration is read-only |
| `load()` | all | none | schema 2; a schema 1 file is read-only with the 0.2.0 message (research D1); never writes |

## Guarantees (tested)

- A schema 1 file loads read-only with the 0.2.0 message; nothing is written; Reset All works.
- Same configuration → same registry bundle path (content hash); apply twice changes nothing.
- A style or glyph change never changes a mapping's `osType`.
- After a registry switch, exactly one `IconRegistry*` registration remains recorded.
- A folder icon is recorded before it is set; undo only touches a folder whose fingerprint matches;
  a backup is restored when present.
- Folders without `folderIcon.enabled` are never written to.
- Without `actool`, custom-glyph mappings keep working from the existing car; only create, update
  and delete of glyphs fail, with `toolUnavailable`.
