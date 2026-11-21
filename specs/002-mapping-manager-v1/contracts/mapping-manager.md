# Contract: MappingManager (engine API used by the GUI)

`MappingManager` is an actor in `SidebarIconCore` and is the only engine object the app talks
to. It owns `ConfigStore` and the Path B adapter, built over a `LaunchServicesSystem`
(`SystemLaunchServices` in production, `FakeLaunchServices` in tests). Every method that changes
something outside the container is named for an explicit owner action (research D6).

Actions (`add`, `applyNow`, `refreshFinder`, `resetAll`, and the Story 2 methods) run one at a
time: a second action while one is running throws `busy`. The adapter's methods suspend, so actor
isolation alone would not stop two from interleaving, and the ledger must have one writer.

## Types

```swift
public struct MappingRow: Sendable, Equatable, Identifiable {
    public var id: UUID                 // mapping id
    public var folderPath: String
    public var displayName: String      // last path component
    public var iconFile: URL            // copied image, for preview
    public var enabled: Bool
    public var osType: String
    public var state: MappingState      // data-model.md
}

public struct ActionResult: Sendable, Equatable {
    public var rows: [MappingRow]       // fresh status after the action
    public var messages: [String]       // plain-language notes for the log/alert
    public var needsRefresh: Bool       // true if the owner should click Refresh Finder
}

public enum ManagerError: Error, Sendable, Equatable {
    case configUnreadable(String)       // D3: read-only mode
    case saveFailed(String)
    case duplicateFolder(existing: String)       // FR-004, names the existing mapping
    case notAFolder(String)
    case imageUnreadable(String)        // conversion failed, nothing saved
    case favoritesUnavailable           // B1 fails: Add/Apply disabled, Reset All allowed
    case readOnly                       // a change was asked for in read-only mode
    case busy                           // another action is running
    case unknownMapping                 // Story 2
    case sidebar(SidebarIconError)      // passes through the adapter's error and message
    public var message: String          // plain language, from contracts/ui.md
}
```

## Methods

| Method | Story | Outside changes | Behavior |
|--------|-------|-----------------|----------|
| `init(container:system:restartFinder:)` / `load() throws` | all | none | reads config; `configUnreadable` → read-only (`readOnlyReason` set) |
| `rows() async -> [MappingRow]` | all | none | read-only status (research D7); unreadable Favorites give `error` rows and set `favoritesReadable = false` instead of throwing. A mapping whose stored path now resolves elsewhere (renamed, replaced by a link) is an `error` row; the config stays readable |
| `add(folder: URL, image: URL) async throws -> ActionResult` | 1 | yes | validate folder (exists, is a directory, not already mapped by resolved path); copy and convert the image (fails → nothing saved); allocate a code (D4); save config; apply all enabled. Once saved, an apply failure is returned as a message ("Saved, but not applied: …"), not thrown |
| `applyNow() async throws -> ActionResult` | 1 | yes | apply all enabled (registers, sets overrides) |
| `refreshFinder() async throws -> ActionResult` | 4 | yes | `applyNow` (skipped in read-only mode), then `FinderRestarter.restart()`; a failed restart is a message |
| `resetAll() async throws -> ActionResult` | 4 | yes | `provider.reset()`; on success delete `config.json` (even unreadable), `Icons/`, registry staging folders and an unrecorded `IconRegistry.app` (unregistered first); partial failure keeps the config entries whose changes are still recorded |
| `setEnabled(_:for:) async throws -> ActionResult` | 2 | yes | save, then apply all. An Off mapping whose override could not be cleared shows `error`, not `off` |
| `changeIcon(for:image:) async throws -> ActionResult` | 2 | yes | new asset (D5; unreadable image → nothing changes), save (the old asset's files are deleted here; the registry bundle keeps its own copy until rewritten), then apply. Refresh hint only if this mapping was applied |
| `remove(_:) async throws -> ActionResult` | 2 | yes | drop the mapping and delete its asset files (save), then apply, which clears its override; when no enabled mapping and no recorded override is left, apply unregisters and deletes the bundle |
| `repoint(_:to:) async throws -> ActionResult` | 2 | yes | same folder checks as `add` (FR-004, excluding itself); keeps code and icon; save, then apply (the old Favorite's override is cleared first) |
| `macOSBuildVerified: Bool`, `readOnlyReason`, `favoritesReadable` | all | none | D3/D8 banners |

## Guarantees (tested)

- `add` with an unreadable image leaves `config.json`, `Icons/` and the ledger unchanged.
- `add` of the same folder by another spelling (`~`, symlink, trailing slash) throws
  `duplicateFolder` naming the existing path.
- Codes are unique across the config and the ledger, and skip codes claimed elsewhere; only
  codes checked against `lsregister -dump` are handed out.
- A code claimed by another bundle at apply time skips only its mapping (`codeClaimedElsewhere`);
  the others are applied.
- A second action while one runs throws `busy` and changes nothing.
- Once a Story 2 action has saved, an apply failure is returned as "Saved, but not applied: …",
  never thrown.
- Off and Remove clear the override even if registering the remaining icons fails.
- `resetAll` on an empty ledger and config succeeds and changes nothing.
- No method writes outside the container except through the provider; the provider is the only
  caller of private API (Constitution II).
- Every method is safe to call twice.
