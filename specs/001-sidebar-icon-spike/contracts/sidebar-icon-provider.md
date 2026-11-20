# Contract: SidebarIconProvider

**Feature**: 001-sidebar-icon-spike

The single seam between configuration/GUI code and whatever mechanism actually puts an icon in the
sidebar (Constitution II). The spike implements it twice (`FinderSyncProvider` for Path A,
`LaunchServicesOverrideProvider` for Path B); feature 002 keeps whichever the findings choose.

## Interface (Swift, shape only)

```swift
public protocol SidebarIconProvider: Sendable {
    /// Short identifier written to the findings record, e.g. "finder-sync" or "ls-override".
    var mechanism: String { get }

    /// Read-only. Reports, per mapping, whether its folder is currently in Favorites,
    /// whether an override is active, and which code/icon is in effect.
    func status(for mappings: [SidebarMapping]) async throws -> [MappingStatus]

    /// Makes the sidebar match `mappings` (enabled ones applied, others cleared).
    /// Must write ledger entries before each outside change. Idempotent.
    func apply(_ mappings: [SidebarMapping], assets: [IconAsset]) async throws -> ApplyReport

    /// Undoes every ledger entry this provider owns. Idempotent; safe with an empty ledger.
    func reset() async throws -> ResetReport
}
```

## Behavioral rules

| Rule | Source |
|------|--------|
| `status` makes no changes of any kind | FR-007 |
| `apply` never touches a folder, its contents, or its own Finder icon | FR-003, Principle III |
| `apply` skips (and reports) folders that are missing or not in Favorites | Spec edge cases |
| `apply` and `reset` never restart Finder; that is a separate, explicit user action | Principle V |
| `reset` after `reset` is a no-op and succeeds | SC-004 |
| No implementation reads or writes `.sfl*` files | FR-006, Principle II |

## Errors

`SidebarIconError` cases: `favoritesUnavailable` (B1 fails), `folderNotInFavorites(path)`,
`folderMissing(path)`, `registrationFailed(OSStatus)`, `propertyRejected(path, OSStatus)`,
`assetConversionFailed(id)`, `ledgerIOFailed(underlying)`. Each maps to a plain-language message in
the spike UI.

Added during implementation (2026-11-19):

- `folderInFavoritesMoreThanOnce(path)`: the spec's duplicate-Favorite edge case; the folder is
  reported and left unchanged.
- `codeClaimedElsewhere(code, owners)`: research R7; another registered bundle claims a code, so
  `apply` stops before any outside change.
- `invalidMapping(detail)`: the mappings break a data-model rule; `apply` changes nothing.
- `toolFailed(detail)`: `lsregister` could not run or exited with an error.
- `foreignOverride(path, code)`: the Favorite already carries an override this utility did not
  set; `apply` leaves it alone (independent review, 2026-11-20).
- `unexpectedLedgerTarget(target)`: a ledger entry names something other than this utility's own
  change (for example a registration path outside the container); `reset` leaves it alone.

`underlying` in `ledgerIOFailed` is carried as a description string so the error stays
`Sendable` and `Equatable`.
