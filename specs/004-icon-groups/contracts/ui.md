# Contract: UI changes (0.3.0)

Extends [002's UI contract](../../002-mapping-manager-v1/contracts/ui.md).

## Row

`[20 pt preview on a light and a dark sidebar swatch]  name  style  ~/path  [folder-icon badge]  state  [Re-point… | Apply Now]  [On/Off]`

The folder-icon badge shows for an opted-in or recorded folder icon: set, not set (worded for
mapping on or off), changed elsewhere, failed (reason as help text), or folder missing.
Re-point… is offered when the folder is missing or its path now resolves to another folder.

Context menu: **Change Icon…** (style picker), **Folder Icon…** (opt-in sheet), Remove…, Re-point….

## Style picker (sheet; Add Folder… and Change Icon…)

Tabs:

1. **System glyph**: a name field with suggestions (research D6). Typing shows "✓ available" or
   "Not a system glyph on this Mac". Preview: the glyph at 16 and 20 pt in the accent colour on
   light and dark sidebar swatches, beside the folder name.
2. **Custom glyph**: choose a glyph from the Glyph Library, previewed beside the folder name;
   **New Custom Glyph…** opens the wizard with this folder's art step, and the new glyph is applied
   when it finishes. Importing, new drawings and deleting are in the Glyph Library window.
3. **Full colour**: pick an image (002 flow and preview, with warnings).

Buttons: Cancel, Apply.

## Glyph Library (window)

Opened with **View › Glyph Library** (⌘2) or the **Glyph Library** button in the main window;
**View › Main** (⌘1) brings the main window back. One shared model serves both windows.

- A list of custom glyphs: tinted 20 pt preview, name, and how many folders use it. The selected
  glyph is previewed at 16 and 20 pt on light and dark sidebar swatches.
- **New Glyph…** opens the wizard (no folder, so no folder-art step); the new glyph is selected.
- **Import Glyph…** (sheet): name, **Choose Template…** / **Change Template…**, Import. An existing
  name gets a new version.
- **New Drawing…** (also in the row's context menu): the wizard for a new version of the selected
  glyph.
- **Delete…**: confirmation; a glyph in use says how many folders use it, and they get the
  standard folder glyph.
- Errors show where the action started: a failed delete at the top of this window, Import and
  the wizard in their own sheets; none of them raises an alert in the main window. The main
  window's notices (read-only configuration, Favorites unreadable, unverified build) show here too.

## Glyph wizard (sheet)

Before the wizard or Import opens, Xcode's asset tool is checked. When it isn't ready, an alert
**Custom Glyphs Use Xcode** says what to do (install Xcode and open it once, or accept its license)
with a **Close** button, and nothing opens.

| Step | Content |
|------|---------|
| 1 Name | Field; lowercase letters, digits, dots and hyphens; uniqueness checked as you type |
| 2 Drawing | **Choose Drawing…** / **Change Drawing…** (one SVG per glyph). Refusals show the element and the guidance; warnings (proportions, detail) don't block |
| 3 Folder art | Only from the style picker. **Choose Art…** / **Change Art…** (the master, with Clear); the footer shows **Skip** until art is chosen, then **Continue**. Set after the picker applies the glyph; a folder with a custom icon opens the opt-in sheet with the art chosen and the replace warning. Folder Icon… adds small sizes |
| 4 Preview | Tinted glyph at 16/20 pt, light and dark, next to a system glyph for size comparison |
| 5 Build | Progress; the glyph is saved once the build succeeds. From the style picker it is applied to the folder |

New Drawing… shows only Drawing, Preview and Build.

## Folder icon opt-in (sheet)

Opened from **Folder Icon…** in a row's context menu (or by the wizard's folder-art step when the folder already has a custom icon). The row shows a folder badge: set, on but not set (mapping Off), changed elsewhere, or failed (with the reason as help text).

- Title: **Use full-colour art as this folder's Finder icon**.
- Text: "Sidebar Icons will add a hidden file named Icon to the folder and mark the folder as having
  a custom icon. The folder's modification date changes. Git shows the file as untracked; sync
  services copy it. Turning this off, Remove and Reset All put the folder's icon back."
- If the folder has a custom icon already: "This folder already has a custom icon. Replace it? The
  current icon is kept and restored when you turn this off." The Replace button is destructive.
- Pickers: master art (required; **Choose Art…** / **Change Art…**); optional small sizes
  (individual PNGs or an `.iconset` folder);
  preview at 16, 32, 128 and 512 pt.
- Buttons: Cancel, Set Folder Icon.
- Confirmations when a folder icon is opted in or recorded (found in P-2; 002's "not changed"
  wording would be wrong):
  - Remove…: "Remove the mapping for <folder>? Its folder icon is put back as it was; nothing
    else in the folder changes."
  - Reset All…: "Remove all custom sidebar icons and delete this app's mappings and copied images?
    Folder icons set by this app are put back as they were; nothing else in your folders changes."

## Messages

- Access denied: "macOS didn't allow changing this folder. Allow Sidebar Icons in System Settings ›
  Privacy & Security › Files and Folders, then try again. The sidebar glyph is unaffected."
- Changed elsewhere: "This folder's icon was changed by something else, so it was left as it is."
