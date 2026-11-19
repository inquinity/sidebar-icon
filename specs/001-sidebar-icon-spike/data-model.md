# Data Model: Sidebar Icon Feasibility Spike

**Feature**: 001-sidebar-icon-spike

The spike uses the same model shapes that feature 002 will persist, so the core package can be
reused. In the spike the mappings are hard-coded (FR-010); only the ledger is written to disk.

## SidebarMapping

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | Stable for the mapping's lifetime |
| `folderPath` | String | Absolute, standardized (`~` expanded, symlinks resolved, no trailing `/`). Unique across mappings |
| `iconAssetID` | UUID | References one `IconAsset` |
| `osType` | String | Exactly 4 ASCII characters, format `S[0-9A-Z]{3}` (research R7). Unique across mappings. Assigned once, never reused while the ledger references it |
| `enabled` | Bool | Disabled mappings are not applied and are removed from Finder on the next apply |

No security-scoped bookmarks: the extension cannot resolve the app's bookmarks (Constitution,
Platform and Toolchain Constraints).

## IconAsset

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | File name stem in the container |
| `sourceFormat` | enum `pdf`, `png`, `svg`, `icns` | Taken from the chosen file's type, not its extension |
| `fileName` | String | `<id>.<ext>`, stored in `Icons/` inside the App Group container |
| `icnsFileName` | String? | `<id>.icns`, generated for Path B only |

## OutsideChange (ledger entry)

Every effect outside the container is written to `ledger.json` **before** it is applied, and
removed after it is undone (Constitution V). Reset walks the ledger.

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | |
| `kind` | enum `iconRegistration`, `sidebarOverride` | |
| `target` | String | Bundle path (`iconRegistration`) or folder path (`sidebarOverride`) |
| `osType` | String? | Required for `sidebarOverride` |
| `appliedAt` | Date | ISO 8601 |
| `macOSBuild` | String | For the findings record |

## State transitions

```text
SidebarMapping:   configured ──apply──▶ applied ──disable/remove──▶ configured
                       ▲                    │
                       └──────reset─────────┘

OutsideChange:    pending (written) ──apply ok──▶ active ──undo ok──▶ (deleted)
                       │                                 │
                       └─apply failed─▶ (deleted)        └─undo failed─▶ active (reported)
```

## Container layout

```text
<App Group container>/Library/Application Support/SidebarIcons/
├── config.json            # schemaVersion + mappings (002; hard-coded in 001)
├── ledger.json            # OutsideChange entries
├── Icons/<uuid>.<ext>     # copied originals
└── IconRegistry.bundle/   # Path B registration bundle (Info.plist + Resources/*.icns)
```
