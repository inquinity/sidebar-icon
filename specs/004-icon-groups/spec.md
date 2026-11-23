# Feature Specification: Icon Groups (outline sidebar glyphs and matching folder icons)

**Feature Branch**: `004-icon-groups`

**Created**: 2026-11-22

**Status**: Approved with addendum (2026-11-23), target release 0.3.0

**Input**: User description: "Sidebar Favorites should show outline-blue glyphs like the system ones
instead of full-colour art, and each folder can optionally get matching full-colour art as its own
Finder icon (opt-in per folder). Two workflows: users with Xcode build their own glyphs with a
wizard; users without Xcode pick an SF Symbol. Existing full-colour mappings keep working;
everything is reversible."

**Owner addendum (2026-11-23)**: no migration of 0.2.0 configurations. Order: a manual process
(owner follows directions, the app imports the glyph), then the `actool` wizard, then system
glyphs, except that system glyphs come first because they take under a day once the shared
foundation exists. The owner is the primary user and has Xcode.

Background: [research.md](research.md) (spike results, 26B131) and
[icon-specification.md](icon-specification.md) (the resources the owner creates per folder).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Give a Favorite an outline glyph from the system set (Priority: P1)

The owner picks a sidebar Favorite and chooses one of the glyphs macOS already provides (an SF
Symbol), searching by name and seeing a live preview tinted the way the sidebar draws it. The
Favorite then shows that glyph in the sidebar, outline blue and the same size as Desktop, Documents
and the other system Favorites.

**Why this priority**: It delivers the main goal (sidebar icons that match the system look) on any
Mac, with nothing to draw and no developer tools, and it is already proven by the spike.

**Independent Test**: On a Mac without Xcode, map a Favorite to a system glyph; it appears outline
blue at system size without restarting Finder.

**Acceptance Scenarios**:

1. **Given** a folder in Favorites, **When** the owner types a glyph name, **Then** the app shows
   whether the name exists and previews the glyph tinted, in light and dark appearance.
2. **Given** a valid glyph is chosen, **When** the owner applies it, **Then** within 10 seconds the
   Favorite shows that glyph in the accent colour, the same size as the system Favorites, with no
   Finder restart.
3. **Given** a name that is not an available glyph, **When** the owner tries to apply it, **Then**
   the app refuses and explains, and nothing changes.
4. **Given** the Favorite is selected in the sidebar, **When** the owner looks at it, **Then** the
   glyph behaves like the system ones (highlighted row, glyph in the accent colour).

---

### User Story 2 - Import a custom glyph made by hand (Priority: P2)

The owner, who has Xcode, makes a custom outline glyph by following written directions: draw the
outline with filled shapes, turn it into a symbol template (with the included helper script, or
Apple's SF Symbols app), then choose **Import Glyph…** in the app, give it a name, and pick the
template. The app builds the glyph and applies it; the Favorite shows it outline blue, like a
system glyph.

**Why this priority**: It gives the primary user personal glyphs soonest, using steps they can
follow by hand, before the wizard automates them.

**Independent Test**: Follow the directions for one drawing, import the template; the Favorite
shows the custom glyph outline blue at system size without restarting Finder.

**Acceptance Scenarios**:

1. **Given** the directions and a filled-shape drawing, **When** the owner runs the helper script,
   **Then** it writes a symbol template, or refuses the drawing and explains why (strokes, text,
   images).
2. **Given** a symbol template, **When** the owner imports it with a unique name, **Then** within 30
   seconds the Favorite shows the glyph in the accent colour at system size, with no Finder
   restart.
3. **Given** a template the build tool rejects (for example, no Regular-weight Medium glyph),
   **When** the owner imports it, **Then** the app shows the tool's reason and nothing is saved.
4. **Given** Xcode's build tool is not available, **When** the owner chooses Import Glyph…, **Then**
   the app says so and how to fix it, and nothing changes.
5. **Given** imported glyphs, **When** the owner imports a new version under the same name, **Then**
   mappings using it show the new glyph without a Finder restart.

---

### User Story 3 - Build a custom outline glyph with a wizard (Priority: P3)

A developer with Xcode installed wants their own outline glyph (for example a git-repository or
dev-folder shape). A wizard walks them through it: it checks that the needed Xcode tool is
available, asks for a glyph name, asks for the outline drawing and (optionally) the folder art,
shows a preview, and builds the glyph. The Favorite then shows the custom glyph outline blue, like
a system glyph.

**Why this priority**: It automates the manual process of Story 2 (template generation, tool
checks, previews), so it follows it.

**Independent Test**: On a Mac with Xcode, run the wizard with a filled-path outline drawing; the
Favorite shows the custom glyph outline blue at system size without restarting Finder.

**Acceptance Scenarios**:

1. **Given** Xcode's asset tool is not available, **When** the owner starts the wizard, **Then** it
   says so, explains how to get it, and offers the system-glyph path (Story 1) or the manual process (Story 2) instead.
2. **Given** the tool is available, **When** the owner enters a glyph name already used by another
   of their glyphs, **Then** the wizard asks for a different name.
3. **Given** an outline drawing made only of filled shapes, **When** the owner selects it, **Then**
   the wizard previews it tinted at sidebar size in light and dark appearance.
4. **Given** a drawing that uses strokes, text, images or no shapes at all, **When** the owner
   selects it, **Then** the wizard refuses it and explains how to convert strokes to shapes in a
   drawing app; nothing is saved.
5. **Given** the owner confirms, **When** the wizard builds the glyph, **Then** within 30 seconds the
   Favorite shows the custom glyph in the accent colour at system size, with no Finder restart.
6. **Given** the owner later changes a custom glyph's drawing, **When** they apply it, **Then** the
   new glyph replaces the old one in the sidebar without a Finder restart.

---

### User Story 4 - Give the folder a matching Finder icon (Priority: P4)

When setting up a Favorite (with either kind of glyph), the owner can also choose full-colour art,
the colour counterpart of the glyph, as the folder's own icon, so Finder windows, Get Info and open
dialogs show the same design. This is a separate, clearly labeled choice per folder, because it
writes a small hidden file into the folder.

**Why this priority**: It completes the look but changes the folder itself, so it is opt-in. The
owner's order covers the glyph paths; the folder icon comes after them.

**Independent Test**: Opt one folder in with a 1024 × 1024 image; its Finder icon shows the art at
every size; Remove restores the plain folder icon and leaves nothing behind in the folder.

**Acceptance Scenarios**:

1. **Given** a mapping, **When** the owner turns on "Also set this folder's Finder icon" and picks
   art, **Then** the app shows what will happen (a hidden file in the folder, the folder's
   modification date changes) before applying.
2. **Given** the owner applies it, **When** they open a Finder window showing the folder, **Then**
   the folder shows the art in list, column and icon views.
3. **Given** the owner also supplied hand-tuned small sizes (individual images or a complete icon
   set), **When** the folder is shown at those sizes, **Then** the hand-tuned versions are used.
4. **Given** a folder that already has a custom icon set by something else, **When** the owner
   tries to opt in, **Then** the app warns and only replaces it if the owner explicitly confirms;
   the previous icon is kept so it can be restored.
5. **Given** the owner turns the option off, removes the mapping, or uses Reset All, **When** that
   completes, **Then** the folder's icon goes back to what it was before (the plain folder icon, or
   its earlier custom icon), and the hidden file is gone if the app created it.

---

### Edge Cases

- The asset tool was available when a custom glyph was built but is gone later (Xcode removed, or
  the app is used on another Mac): already-built glyphs keep working; only building or changing a
  custom glyph needs the tool.
- A Mac that never had Xcode: the custom-glyph wizard is unavailable with an explanation; system
  glyphs, folder art and the full-colour style work.
- The outline drawing is very wide, very tall, or very detailed: the preview warns that it may look
  small or blurred at sidebar size; the owner can still continue.
- A folder in a protected location (Documents, Desktop) and folder art opted in: macOS may ask the
  owner to allow access; if refused, the folder icon is not set, the sidebar glyph still works, and
  the row says why.
- The folder is a git repository or inside a synced folder (iCloud Drive, Dropbox, OneDrive): the
  opt-in explanation mentions that the hidden file is visible to git and is synced; the app does
  not change any git or sync settings.
- The folder's custom icon was changed by someone else after the app set it: Remove and Reset All
  leave it alone (it is no longer the app's) and say so.
- A glyph name used by a system glyph and also by a custom glyph: custom glyph names are kept
  separate from system names, so the right one is shown.
- Many custom glyphs (20 or more): they are built together; changing one does not disturb the
  others.
- A 0.2.0 configuration is found: the app shows that it was made by 0.2.0 and isn't migrated, and
  offers Reset All; nothing else changes.
- The macOS build is not one the feature was verified on: the existing non-blocking warning banner
  is shown.

## Requirements *(mandatory)*

### Functional Requirements

**Sidebar glyphs**

- **FR-001**: The app MUST let the owner choose, per mapping, one sidebar style: a system glyph
  (by name), a custom glyph, or full colour (the 0.2.0 style, still selectable).
- **FR-002**: The app MUST show system and custom glyphs in the sidebar drawn the way the system
  Favorites are drawn (tinted with the accent colour, same size class), and MUST preview them that
  way, in light and dark appearance, before applying.
- **FR-003**: The app MUST validate a system glyph name as the owner types and refuse unknown names.
- **FR-004**: A changed glyph MUST appear in the sidebar without restarting Finder.

**Manual custom glyphs (Xcode)**

- **FR-020**: The project MUST include written directions and a helper script that turn a
  filled-shape SVG into a symbol template, with the same rules and messages as the wizard (FR-007,
  FR-008).
- **FR-021**: The app MUST import a symbol template under a name (FR-006 rules), build it, and apply
  it; a template the build tool rejects MUST show the tool's reason and save nothing.

**Custom glyph wizard (Xcode)**

- **FR-005**: The wizard MUST check that Xcode's asset tool is available before asking for anything
  and, if it is not, explain how to install it and offer the system-glyph path.
- **FR-006**: The wizard MUST ask for a glyph name, require it to be unique among the owner's
  custom glyphs and limited to lowercase letters, digits, dots and hyphens.
- **FR-007**: The wizard MUST accept an outline drawing (SVG) made of filled shapes, and MUST refuse
  drawings with strokes, text, embedded images or no shapes, with guidance on converting strokes.
- **FR-008**: The wizard MUST scale the drawing so the glyph matches the size of the system glyphs,
  and MUST warn (without blocking) when its proportions or detail may not read well at sidebar size.
- **FR-009**: The wizard MUST keep each glyph's drawing in the app's own storage so all custom
  glyphs can be rebuilt together, and already-built glyphs MUST keep working when the tool is
  unavailable.
- **FR-010**: The owner MUST be able to change or delete a custom glyph; deleting one used by a
  mapping MUST ask which glyph the mapping should use instead, or switch it to the folder default.

**Folder icon (opt-in)**

- **FR-011**: Setting the folder's own Finder icon MUST be a separate, clearly labeled choice per
  mapping, off by default, that explains the hidden file and the modification-date change before
  it is applied.
- **FR-012**: The app MUST accept folder art as a full-colour 1024 × 1024 PNG, PDF or SVG, and
  optionally hand-tuned small sizes (individual images or a complete icon set); sizes not supplied
  MUST be rendered from the master.
- **FR-013**: The app MUST NOT replace a folder's existing custom icon unless the owner explicitly
  confirms, and MUST keep the previous icon so it can be restored.
- **FR-014**: Turning the option off, Remove and Reset All MUST restore the folder's previous icon
  (plain, or the earlier custom icon), and remove the hidden file the app created, but only if the
  folder's icon is still the one the app set; otherwise they MUST leave it and say so.
- **FR-015**: Every folder icon the app sets MUST be recorded before it is set, like every other
  change outside the app's storage (Constitution V).

**Compatibility and reversibility**

- **FR-016**: 0.3.0 MUST NOT migrate a 0.2.0 configuration. If it finds one, it MUST say so, change
  nothing, and keep Reset All available, which undoes everything 0.2.0 recorded.
- **FR-017**: Reset All MUST undo every change 0.3.0 can make: sidebar overrides, all registered
  glyph and icon definitions (including earlier versions), and folder icons, and MUST delete the
  stored drawings, art and built glyphs.
- **FR-018**: The app MUST NOT change anything in a folder other than the hidden icon file and the
  folder's icon flag, and only for folders opted in (FR-011).
- **FR-019**: The documentation MUST list every file the feature writes, inside and outside the
  app's storage, and every new use of undocumented macOS behavior.

### Key Entities

- **Icon group**: what a mapping shows: one sidebar style (system glyph, custom glyph or full
  colour) and, optionally, folder art with the opt-in flag.
- **Custom glyph**: a named outline drawing owned by the app, with versions; used by one or more
  mappings.
- **Folder art**: a full-colour master image plus optional hand-tuned small sizes.
- **Folder icon record**: that the app set a folder's icon, what it set (so it can tell whether the
  icon is still its own), and the previous custom icon, if any, to restore.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With a system glyph, a Favorite shows the new glyph within 10 seconds, without
  restarting Finder, on a Mac without developer tools.
- **SC-002**: Side by side, a custom or system glyph is within 10 % of the height of the system
  Favorites' glyphs and uses the same tint, in light and dark appearance and with a non-default
  accent colour.
- **SC-003**: A developer with a prepared outline drawing completes the wizard and sees the custom
  glyph in the sidebar in under 3 minutes.
- **SC-004**: Changing a custom glyph shows the new one within 30 seconds, without restarting
  Finder, while 20 other custom-glyph mappings keep their glyphs.
- **SC-005**: After Reset All (and deleting the app and its storage), no sidebar override, no
  registered definition from the app, and no hidden icon file or icon flag set by the app remains
  on any folder; folders that had their own custom icon before show it again.
- **SC-006**: Following the directions, the owner turns a prepared drawing into a glyph in the
  sidebar in under 5 minutes.
- **SC-007**: For folders not opted in to a folder icon, nothing about the folder changes (name,
  location, contents, permissions, icon, modification date).

## Assumptions

- The custom-glyph wizard needs Xcode's asset tool on the Mac that builds the glyph; the Command
  Line Tools alone do not include it (spike S7). Building is the only step that needs it.
- Outline drawings are SVG files with filled shapes; converting strokes is done by the owner in a
  drawing app (icon-specification.md lists the commands for common apps).
- No migration from 0.2.0 (owner addendum): the owner resets 0.2.0 before upgrading; the full-colour
  sidebar style stays available as a choice because the engine already has it.
- A folder with an existing custom icon is left alone unless the owner explicitly replaces it; the
  previous icon is restored on Remove or Reset All.
- Folder icons are set with the public macOS mechanism; the sidebar glyphs extend the existing
  undocumented sidebar mechanism (PRIVATE_API.md) and need the same per-release re-check.
- The constitution's Principle III (user data never modified) is amended to allow the opt-in folder
  icon under the conditions in FR-011 to FR-015; Principle I notes the optional Xcode tool.
- The app stays unsandboxed (002 decision); macOS may still ask for access to folders in protected
  locations when a folder icon is set there.
- Dark mode and accent-colour behaviour of custom glyphs is expected to match system glyphs (same
  rendering), to be confirmed by the owner during verification.
