# Quickstart: build, run and verify Sidebar Icons v1

Finder rendering can't be tested automatically, so these manual checks are the acceptance test
for the stories. The package logic is covered by `swift test`.

## Prerequisites

- macOS 27.2.1 (26B131) or later, and Xcode 27.2 signed in to team 45GJWJVQN2.
- `~/dev` and `~/DevDocs` are in Finder's sidebar Favorites, plus a third test folder for Story 2.
- **The spike is retired**: if it ever ran on this Mac, open it once, click **Reset**, then quit
  it. Never run the spike and the app at the same time; they share one ledger (research D2).
- The spike's Finder Sync extension is off (`pluginkit -m -i com.altmansoftwaredesign.SidebarIcons.FinderSync`
  shows `-`). A watching extension hides the icons (001 A1).

## Build and test

```bash
cd Packages/SidebarIconCore && swift test
```

```bash
xcodebuild -project app/SidebarIcons.xcodeproj -scheme "Sidebar Icons" -configuration Debug build
```

Both must succeed: all tests pass, and the build reports `BUILD SUCCEEDED`.

## Manual checks

Record each result (pass/fail, macOS build, notes) in the build log, and fold failures into
`tasks.md`.

**Starter (Stories 1 and 4)**

1. **Add**: Add Folder… → `~/dev` → pick a PNG. Within 10 s the Favorite shows the image in full
   colour, and the row says Applied (Story 1 scenario 1, SC-001).
2. **Persist**: quit and reopen the app. The row is unchanged and the icon is still there
   (scenario 2).
3. **Original independence**: move or delete the original PNG. The icon and the preview are
   unaffected (scenario 3).
4. **Duplicate**: add `~/dev` again, and also as `/Users/<you>/dev/`. It's refused, naming the
   existing mapping (scenario 4, FR-004).
5. **Refresh**: click Refresh Finder… and confirm. Finder restarts once, and the icons are still
   there (Story 4 scenario 1).
6. **Reset All**: confirm. The list is empty, and both Favorites show the folder glyph (after a
   refresh at most). `lsregister -dump | grep -c 'Group Containers/45GJWJVQN2.com.altmansoftwaredesign.SidebarIcons'`
   prints `0` (scenario 2). Searching our container path rather than `IconRegistry.app` keeps the
   check exact even if another copy of the bundle was ever registered elsewhere.

**Story 2**

7. **Three mappings**: add `~/dev`, `~/DevDocs` and the third folder. Each shows its own icon.
8. **Off/On**: turn one off; it returns to the folder glyph and stays listed. Turn it on; the icon
   returns.
9. **Remove**: remove one and confirm. Its glyph returns, its `Icons/` files are gone, and the
   folder is unchanged.

**Story 3**

10. **Preview**: pick a non-square, detailed image. The preview shows light and dark versions with
    a warning, and doesn't block the choice.

**Verification**

11. **Light/dark/accent**: switch the system appearance and the accent colour. The icons are still
    drawn in full colour, and the preview matches the sidebar.
12. **Scale and persistence** (FR-011, FR-013, SC-002): with 20 mappings, log out and back in,
    then reboot. All 20 Favorites still show their icons.
13. **Leftovers** (SC-004): Reset All, quit, delete the app and the container. Then:
    - `lsregister -dump` has no `IconRegistry` and no `sidebaricons.icon` type;
    - no Favorite carries an override (List Favorites in the spike, or the app before deletion);
    - no file of this utility remains.
14. **Folders untouched** (SC-005): across the whole pass, no mapped folder's name, location,
    contents, permissions or Finder icon changed.

## Rollback

See [plan.md › Rollback](plan.md#rollback).
