# Quickstart: Running the Sidebar Icon Spike

**Feature**: 001-sidebar-icon-spike

Validation guide for the spike. Record every result in the Findings table in
[research.md](research.md).

## Prerequisites

- macOS 27 (current test machine: 27.2.1, build 26B131), Xcode 27.2.
- Apple Developer team selected in Xcode for both targets (Signing & Capabilities).
- `~/dev` and `~/DevDocs` exist and have been dragged into Finder's sidebar Favorites.
- Optional safety copy before any Path B step: a screenshot of the sidebar and the output of the
  spike's read-only "List Favorites" action saved to a text file.

## Build and run

1. Open `spike/SidebarIconSpike.xcodeproj` and build the `SidebarIconSpike` scheme.
2. Run the core tests from the command line:
   `swift test --package-path spike/SidebarIconCore`
3. Launch the app from Xcode. Enable the extension when prompted, or open
   System Settings → General → Login Items & Extensions → File Providers / Finder extensions.

## Scenarios

| Step | Action in the spike window | Expected | Spec ref | Research ID |
|------|----------------------------|----------|----------|-------------|
| 1 | Observe sidebar with extension enabled, no other action | Record what the Favorites show | US1 | A1 |
| 2 | **List Favorites** (read-only) | Both folders listed with resolved paths | — | B1 |
| 3 | **Apply (Path B)** with bundled icons | Two different custom icons | US1-1 | B2 |
| 4 | **Refresh Finder** ×3, then log out and in | Icons still showing | US1-2, US1-3, SC-002 | B2 |
| 5 | Check both folders in a Finder window and Get Info | Folder icons unchanged | US1-4 | — |
| 6 | Disable the extension in System Settings, Refresh Finder | Record: do icons persist? | — | B4 |
| 7 | **Use runtime icon for DevDocs**, first copy `folder-icon/git-repo-3-layers-light-blue.png` to `~/Desktop`, then choose that copy | DevDocs icon changes within 10 s, or after Refresh Finder (record which) | US2-1, SC-003 | B3 |
| 8 | Delete the `~/Desktop` copy chosen in step 7 (never the original in `folder-icon/`), Refresh Finder | Runtime icon still showing | US2-3 | B3 |
| 9 | **Reset**, then Refresh Finder | Generic glyph on both; ledger empty | US3-1, SC-004 | B6 |
| 10 | Read the Reset log line "lsregister -dump lists IconRegistry.app"; then delete the app and container | "no" | US3-2 | B6 |
| 11 | Repeat step 2 from a sandboxed build configuration | Record: blocked or allowed | — | B5 |

Use **Copy Log** after each step and paste the relevant lines into the Findings notes.

Edge cases from the spec (another extension watching a folder, nested folders, missing folder,
dark mode and accent color, non-square image) are each run once after step 9 and recorded.

## Rollback

1. Run **Reset** in the spike, then **Refresh Finder**.
2. Disable the extension in System Settings.
3. Delete the app and its App Group container
   (`~/Library/Group Containers/<TEAMID>.com.altmansoftwaredesign.SidebarIcons`).
4. If an icon override is still showing: remove the Favorite and drag the folder back in.
