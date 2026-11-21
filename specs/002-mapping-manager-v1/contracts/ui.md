# Contract: Sidebar Icons window

One window (`Window`, not `WindowGroup`, so there is a single model and a single ledger writer),
plus the standard About window.

## Layout

```text
┌ Sidebar Icons ─────────────────────────────────────────────┐
│ [banner: only if the build is unverified or Favorites can't be read]
│ ┌──────────────────────────────────────────────────────────┐
│ │ [☀︎icon][☾icon]  dev        ~/dev          ● Applied       │
│ │ [☀︎icon][☾icon]  DevDocs    ~/DevDocs      ○ Not in sidebar│
│ └──────────────────────────────────────────────────────────┘
│ [+ Add Folder…]                [Refresh Finder…] [Reset All…]│
│ status line: last action result                              │
└────────────────────────────────────────────────────────────┘
```

- **Row**: 20 pt preview on a light and a dark swatch (FR-007, research D9), folder name, path
  (abbreviated with `~`) and state (data-model `MappingState`).
  - Rows in `notInSidebar`, `notApplied` or `error` show **Apply Now**.
  - Story 2 adds a row toggle (On/Off), a context menu with Change Icon… and Remove…, and
    Re-point… for `folderMissing`.
- **Empty state**: "No mappings yet. Add a folder that is in Finder's sidebar Favorites."
- **Read-only empty state**: "Mappings can't be shown": config.json can't be read, nothing will be
  changed, and Reset All undoes every recorded change.

## Actions

| Control | Flow | Confirmation |
|---------|------|--------------|
| Add Folder… | Open panel (folders only), then open panel (PDF, PNG, SVG) titled "Choose an icon for <folder>", then the **preview sheet** (Story 3). Apply → `add`; Cancel saves nothing. On error, an alert with the message; nothing saved. | none (the action itself is explicit) |
| Change Icon… (Story 2) | Open panel for the image, then the preview sheet; Apply → `changeIcon` | none |
| Apply Now | `applyNow` | none |
| Refresh Finder… | `refreshFinder` | "Restart Finder? Finder windows close and reopen; a copy in progress may be interrupted." |
| Reset All… | `resetAll` | "Remove all custom sidebar icons and delete this app's mappings and copied images? Your folders are not changed." (destructive style) |
| Remove… (Story 2) | `remove` | "Remove the mapping for <folder>? The folder itself is not changed." |

While an action runs, controls are disabled and a progress indicator shows. Reset All stays
enabled in read-only and unsupported modes (FR-010). Refresh Finder also stays enabled; in
read-only mode it only restarts Finder.

## Messages (plain language)

- Duplicate: "~/dev is already mapped. Change its icon instead."
- Not in sidebar after Add: "Saved. ~/dev isn't in Finder's sidebar Favorites yet; drag it there,
  then click Apply Now."
- Needs refresh: "If the icon hasn't changed, click Refresh Finder."
- Adapter errors use `SidebarIconError.message`.

## About window

App name and version, then:

> Sidebar Icons relies on undocumented macOS behavior to show custom icons in Finder's sidebar.
> Every such use is listed in PRIVATE_API.md in the project's source repository. Reset All removes
> every change the app made.

## Preview sheet (Story 3)

Shown after an image is picked in Add Folder… or Change Icon…. The image beside the folder name,
as a sidebar row, at 16 pt and 20 pt on a light and a dark sidebar swatch (fixed colours, at the
screen's own scale). Warnings from `PreviewAdvice` (not square: aspect ratio in points outside
0.8–1.25; too detailed: more than 64 colour clusters at 16 px) are shown but never block Apply.
Cancel (or Escape) saves nothing.

