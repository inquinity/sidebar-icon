# Feature Specification: Sidebar Icon Mapping Manager v1

**Feature Branch**: `002-mapping-manager-v1`

**Created**: 2026-11-17

**Status**: Draft — planning blocked until 001's findings name a path (Constitution IV)

**Input**: User description: "A small macOS utility to manage any number of folder → sidebar icon
mappings: Add Folder, Pick Icon, Enable/Disable, Remove, Preview, Refresh Finder. Settings persist,
chosen icons are copied into the utility's own storage, and nothing outside the utility is changed
without an explicit action. Source: Finder_Sidebar_Custom_Icons_Utility.md, Phases 3–4 and
'Suggested v1 scope'."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Give a Favorite a custom sidebar icon (Priority: P1)

The owner opens the utility, clicks Add Folder, picks `~/dev`, clicks Pick Icon, chooses an image,
and the `~/dev` Favorite in Finder's sidebar shows that image.

**Why this priority**: This is the whole purpose of the utility.

**Independent Test**: Starting from an empty configuration, add one mapping and look at the
Finder sidebar.

**Acceptance Scenarios**:

1. **Given** `~/dev` is in Favorites and the utility has no mappings, **When** the owner adds `~/dev`
   and picks an icon, **Then** the Favorite shows the icon within 10 seconds, or after the owner
   clicks Refresh Finder if the utility says a refresh is needed.
2. **Given** a mapping exists, **When** the utility is quit and reopened, **Then** the mapping is
   still listed with the same folder, icon, and enabled state.
3. **Given** a mapping exists, **When** the original image file is moved or deleted, **Then** the
   sidebar icon and the utility's preview are unaffected.
4. **Given** `~/dev` is already mapped, **When** the owner adds `~/dev` again, **Then** the utility
   refuses with a message naming the existing mapping.

---

### User Story 2 - Manage several mappings (Priority: P2)

The owner keeps three mappings (`~/dev`, `~/Cloud Shortcuts/AI`, `~/Cloud Shortcuts/QEC`) in one
list, turns one off temporarily, and removes another.

**Why this priority**: Supporting many mappings from one utility is the stated goal; turning one off
without losing it is part of the v1 scope.

**Independent Test**: Create three mappings, disable one, remove one, and check the sidebar after
each step.

**Acceptance Scenarios**:

1. **Given** three enabled mappings, **When** the owner views the sidebar, **Then** each Favorite shows
   its own icon.
2. **Given** an enabled mapping, **When** the owner turns it off, **Then** that Favorite returns to the
   generic glyph and the mapping stays in the list, turned off.
3. **Given** a turned-off mapping, **When** the owner turns it on again, **Then** the custom icon
   returns.
4. **Given** a mapping, **When** the owner removes it and confirms, **Then** it leaves the list, its
   Favorite returns to the generic glyph, its copied icon is deleted, and the folder itself is
   untouched.

---

### User Story 3 - Preview before committing (Priority: P3)

When picking an icon, the owner sees how it will look at sidebar size, in light and dark
appearance, before it is applied.

**Why this priority**: Sidebar glyphs are tiny; a preview avoids trial and error with Finder.

**Independent Test**: Pick several images (simple, detailed, non-square) and compare the preview to
the result in Finder.

**Acceptance Scenarios**:

1. **Given** the owner picks an image, **When** the preview appears, **Then** it shows the image at
   sidebar size in both light and dark appearance.
2. **Given** a non-square or very detailed image, **When** previewed, **Then** the utility shows a
   warning that it may not read well at sidebar size, without blocking the choice.

---

### User Story 4 - Refresh and remove everything (Priority: P4)

The owner can restart Finder on demand, and can reset the utility so every Favorite goes back to
normal and nothing the utility created remains.

**Why this priority**: Finder may cache icons, and the owner must be able to remove all traces from
a work machine.

**Independent Test**: With mappings applied, run Reset All, then Refresh Finder, then inspect the
sidebar and the system for leftovers.

**Acceptance Scenarios**:

1. **Given** the owner clicks Refresh Finder, **When** they confirm, **Then** Finder restarts once and
   the custom icons are showing afterwards.
2. **Given** mappings are applied, **When** the owner clicks Reset All and confirms, **Then** every
   Favorite the utility changed shows the generic glyph after a refresh, and the list is empty.
3. **Given** Reset All has run, **When** the utility and its storage are deleted, **Then** no
   registration, property, or file created by the utility remains.

---

### Edge Cases

- The chosen folder is not in Favorites: save the mapping, show "Not in sidebar," and apply it
  automatically once the folder appears in Favorites (on the next launch or refresh).
- The folder no longer exists: show "Folder missing"; do not create it; keep the mapping.
- The folder is renamed or moved: show "Folder missing" for the old path; the owner can re-point it.
- The same folder through two different paths (symlink, `~` vs. full path): treated as a duplicate.
- The chosen image cannot be read or converted: show an error; no mapping is saved.
- Two mappings use the same image: allowed; each mapping keeps its own copy.
- A macOS update stops the sidebar mechanism from working: the utility detects this on launch,
  shows a clear "not supported on this macOS build" state, and still allows Reset All.
- Another Finder extension watches the same folder: show the conflict if it can be detected.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Users MUST be able to add a mapping by choosing exactly one folder and one image.
- **FR-002**: The utility MUST accept PDF, PNG (with transparency), and SVG images.
- **FR-003**: The utility MUST copy each chosen image into its own storage and MUST NOT depend on or
  modify the original afterwards.
- **FR-004**: The utility MUST reject a mapping whose folder is already mapped, comparing resolved
  locations rather than raw text.
- **FR-005**: Users MUST be able to turn a mapping off and on without losing it.
- **FR-006**: Removing a mapping MUST remove only the utility's configuration, copied image, and
  outside changes for that mapping. It MUST NOT rename, move, delete, or change the folder or its
  own Finder icon.
- **FR-007**: The utility MUST show a sidebar-size preview of each mapping's icon in light and dark
  appearance.
- **FR-008**: The utility MUST show each mapping's status: Applied, Off, Not in sidebar, Folder
  missing, or Error (with a reason).
- **FR-009**: Refresh Finder MUST run only when the owner clicks it and confirms.
- **FR-010**: Reset All MUST undo every outside change the utility made, using a record kept before
  each change, and MUST be available even when the sidebar mechanism is unsupported.
- **FR-011**: Mappings MUST persist across app relaunch, Finder restart, logout, and reboot.
- **FR-012**: The utility MUST meet every constraint in Constitution Principle I (no networking,
  telemetry, updater, daemon, login item, privileged helper, or third-party code).
- **FR-013**: The utility MUST support at least 20 mappings with no change in behavior.

### Key Entities

- **Sidebar mapping**: folder, icon, on/off, status. Same shape as in 001's data model.
- **Icon asset**: the utility's own copy of a chosen image (plus any converted form).
- **Change record**: one entry per outside change, written before the change, removed after undo.
- **Configuration**: the versioned list of mappings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A first-time user can add a mapping and see the icon in the sidebar in under
  1 minute, with at most one Refresh Finder.
- **SC-002**: With 20 mappings, all 20 Favorites show their own icons after a reboot.
- **SC-003**: Turning a mapping off or on changes the sidebar within 10 seconds, or after one
  Refresh Finder when the utility says one is needed.
- **SC-004**: After Reset All and deletion of the app, 0 changes made by the utility remain on the
  manual leftover checklist.
- **SC-005**: Over a full test pass, 0 user folders have changed name, location, contents,
  permissions, or folder icon.

## Assumptions

- **Depends on 001**: which sidebar mechanism is used (Path A or B), whether a Finder Sync extension
  is needed (research R5), and whether the app can be sandboxed (research B5) all come from 001's
  findings. This spec does not change between paths; the plan does.
- The owner adds folders to Favorites in Finder; v1 does not add sidebar items itself.
- macOS 27 or later; Apple Developer team signing; local builds from source only, no distribution.
- Single user, single Mac; no import/export, presets, drag-and-drop, or automatic template
  conversion in v1 (doc Phase 5 items are out of scope).
- Folder references are stored as resolved paths, not app-scoped security bookmarks.
