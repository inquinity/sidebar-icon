# Feature Specification: Sidebar Icon Feasibility Spike

**Feature Branch**: `001-sidebar-icon-spike`

**Created**: 2026-11-17

**Status**: Draft

**Input**: User description: "Prove, before any GUI work, that a locally built utility can give two
Finder sidebar Favorites two different custom icons, keep them after Finder restarts, leave the
folders' own icons alone, and then show one icon that was chosen at runtime rather than built in.
Determine whether public Finder APIs are enough (Path A) or whether the Launch Services sidebar
override is required (Path B). Source: Finder_Sidebar_Custom_Icons_Utility.md, Phases 1–2."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Two Favorites, two built-in custom icons (Priority: P1)

The owner adds `~/dev` and `~/Cloud Shortcuts/AI` to Finder's sidebar Favorites, installs and
enables the proof-of-concept build, and sees each Favorite show its own custom icon (one
development icon, one AI icon) instead of the generic folder glyph. One installed component serves
both folders.

**Why this priority**: If two different custom sidebar icons cannot be shown at all, nothing else
in the project is possible. This is the go/no-go result.

**Independent Test**: Build and enable the proof of concept with both icons bundled; inspect the
Finder sidebar; restart Finder; inspect again.

**Acceptance Scenarios**:

1. **Given** both folders are in Favorites and the proof of concept is enabled, **When** a new Finder
   window opens, **Then** each Favorite shows its assigned custom icon and the two icons differ.
2. **Given** the custom icons are showing, **When** Finder is restarted, **Then** both icons are still
   showing within 10 seconds of the sidebar appearing.
3. **Given** the custom icons are showing, **When** the user logs out and back in, **Then** both icons
   are still showing.
4. **Given** either folder had a custom Finder folder icon before the test, **When** the proof of
   concept is enabled, **Then** that folder icon is unchanged in Finder windows, the path bar, and Get
   Info.

---

### User Story 2 - One icon chosen at runtime (Priority: P2)

The owner replaces the AI icon with an image file that is not part of the build: it is placed in the
utility's own storage area after installation. The sidebar shows that new image for
`~/Cloud Shortcuts/AI` without rebuilding the app.

**Why this priority**: The finished utility lets users pick any icon. This story proves that icons
do not have to be compiled in, and it is the experiment that decides between Path A and Path B.

**Independent Test**: With Story 1 working, put a new image in the utility's storage, trigger the
utility's refresh, and inspect the sidebar.

**Acceptance Scenarios**:

1. **Given** Story 1 passes, **When** a new image is placed in the utility's storage and a refresh is
   triggered, **Then** the AI Favorite shows the new image and the dev Favorite is unchanged.
2. **Given** the runtime image is showing, **When** Finder is restarted, **Then** the runtime image is
   still showing.
3. **Given** the runtime image is showing, **When** the original source file the image was copied
   from is deleted, **Then** the sidebar still shows the runtime image.

---

### User Story 3 - Full reset (Priority: P3)

The owner runs the proof of concept's reset. Both Favorites go back to the generic folder glyph and
nothing the proof of concept registered or set remains.

**Why this priority**: The constitution requires every outside effect to be reversible, and the
owner must be able to remove all traces from a work machine.

**Independent Test**: Run reset, restart Finder, inspect the sidebar, and check that the documented
registrations and properties are gone.

**Acceptance Scenarios**:

1. **Given** custom icons are showing, **When** reset runs and Finder is restarted, **Then** both
   Favorites show the generic folder glyph.
2. **Given** reset has run, **When** the app and its storage are deleted, **Then** no registration,
   property, or file created by the proof of concept remains on the system.

---

### Edge Cases

- A configured folder is in Favorites twice, or not in Favorites at all: the proof of concept must
  report it and change nothing for that folder.
- A configured folder does not exist: report it; do not create it.
- Another installed Finder extension already watches one of the folders (for example a cloud sync
  tool): record which one wins and whether the icon still appears.
- Nested folders are both configured (for example `~/dev` and `~/dev/tools`): record the behavior.
- The runtime image is very large, not square, or a multi-color image: record how Finder renders it.
- The Finder extension is disabled in System Settings while icons are showing: record whether the
  icons disappear, and when.
- Light and dark appearance, and sidebar accent/tint settings: record how the icons render in each.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The proof of concept MUST show a distinct custom sidebar icon for each of two
  configured Favorites at the same time, using one installed utility.
- **FR-002**: Icons MUST persist across Finder restarts and across logout/login without user action.
- **FR-003**: The proof of concept MUST NOT change any folder's own Finder icon, name, location,
  contents, or permissions.
- **FR-004**: At least one sidebar icon MUST come from an image file added to the utility's storage
  after the build, not from the built app.
- **FR-005**: The proof of concept MUST first attempt the public-API route (Path A) and record the
  result before attempting the Launch Services override route (Path B).
- **FR-006**: The proof of concept MUST NOT read or write Finder's sidebar store files.
- **FR-007**: Every change outside the utility's own storage MUST be made only by an explicit user
  action and MUST be undone by reset.
- **FR-008**: The proof of concept MUST produce a written findings record covering: which path works,
  the macOS build tested, every acceptance scenario's result, every edge case's observed behavior,
  and the exact list of outside changes made and how reset removes them.
- **FR-009**: The proof of concept MUST work with no network access and no administrator password.
- **FR-010**: The two folders and their icons MAY be fixed in the build; no configuration screen is
  required.

### Key Entities

- **Sidebar mapping**: one Favorite folder paired with one icon image, enabled or disabled.
- **Icon asset**: an image file the utility owns, either built in or copied into its storage.
- **Outside change**: anything the utility registers or sets outside its own storage (for Path B, an
  icon type registration or a sidebar item property); each one has a matching undo.
- **Findings record**: the written result of the spike, which gates feature 002's plan.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 2 of 2 configured Favorites show their own distinct custom icon on macOS 27.
- **SC-002**: Icons survive 3 consecutive Finder restarts and 1 logout/login with no user action.
- **SC-003**: The runtime-chosen icon appears within 10 seconds of refresh without rebuilding.
- **SC-004**: After reset and Finder restart, 0 of 2 Favorites show a custom icon and 0 outside
  changes remain on the documented checklist.
- **SC-005**: The findings record names exactly one recommended path (A or B) with evidence for each
  acceptance scenario, so feature 002 can be planned without repeating the experiment.

## Assumptions

- The owner adds the two folders to Favorites by hand; the spike does not add sidebar items.
- Testing happens on the owner's macOS 27 machine. macOS 26 is tested only if a 26 machine or VM is
  already available; it is not required.
- The owner has an Apple Developer team, so all components can be signed and share storage without
  system prompts.
- Path B relies on undocumented behavior observed in existing sidebar-icon utilities; it is
  acceptable for this project if it is isolated and fully reversible (Constitution Principle II).
- Simple single-color icon artwork is used for the main test; multi-color images are an edge case.
- The spike's code is disposable. Feature 002 may reuse parts of it but is not required to.
