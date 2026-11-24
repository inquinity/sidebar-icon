# Contract: UI changes (0.3.0)

Extends [002's UI contract](../../002-mapping-manager-v1/contracts/ui.md).

## Row

`[16 pt sidebar preview, tinted][folder-icon preview or —]  name  ~/path  style  state  [On/Off]`

Context menu: **Change Icon…** (style picker), **Folder Icon…** (opt-in sheet), Remove…, Re-point….

## Style picker (sheet; Add Folder… and Change Icon…)

Tabs:

1. **System glyph**: a name field with suggestions (research D6). Typing shows "✓ available" or
   "Not a system glyph on this Mac". Preview: the glyph at 16 and 20 pt in the accent colour on
   light and dark sidebar swatches, beside the folder name.
2. **Custom glyph**: a list of existing glyphs with previews; **New Custom Glyph…** opens the
   wizard. If the tool is unavailable, the tab says why and the list is still usable.
3. **Full colour**: pick an image (002 flow and preview, with warnings).

Buttons: Cancel, Apply.

## Glyph wizard (sheet)

| Step | Content |
|------|---------|
| 1 Check | "Checking for Xcode's asset tool…" → ✓ path, or the message from glyph-builder.md, with **Use a system glyph instead**, **Check Again** and a pointer to the manual process (which also needs Xcode) |
| 2 Name | Field; lowercase letters, digits, dots and hyphens; uniqueness checked as you type |
| 3 Drawing | Open panel (SVG). Refusals show the element and the guidance; warnings (proportions, detail) don't block |
| 4 Folder art (optional) | "Also use full-colour art for this folder's Finder icon" → Choose Art… (the master). Set after the picker applies the glyph; if the folder already has a custom icon, the opt-in sheet opens with the art chosen and the replace warning. Small sizes are added later with Folder Icon…. Not shown for New Drawing… |
| 5 Preview | Tinted glyph at 16/20 pt, light and dark, next to a system glyph for size comparison |
| 6 Build | Progress; on success, applies to the mapping. On failure, nothing is saved |

## Folder icon opt-in (sheet)

Opened from **Folder Icon…** in a row's context menu (or by the wizard's step 4 when the folder already has a custom icon). The row shows a folder badge: set, on but not set (mapping Off), changed elsewhere, or failed (with the reason as help text).

- Title: **Use full-colour art as this folder's Finder icon**.
- Text: "Sidebar Icons will add a hidden file named Icon to the folder and mark the folder as having
  a custom icon. The folder's modification date changes. Git shows the file as untracked; sync
  services copy it. Turning this off, Remove and Reset All put the folder's icon back."
- If the folder has a custom icon already: "This folder already has a custom icon. Replace it? The
  current icon is kept and restored when you turn this off." The Replace button is destructive.
- Pickers: master art (required); optional small sizes (individual PNGs or an `.iconset` folder);
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
