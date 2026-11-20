# Sidebar Icons

A small macOS utility, built from source, that gives folders in Finder's sidebar Favorites their
own custom icons. Pick a folder, pick an image, and that Favorite shows your icon instead of the
generic folder glyph. One app can manage any number of folders.

> [!IMPORTANT]
> **This utility relies on undocumented macOS behavior.** macOS has no public API for setting a
> sidebar icon, so the planned approach uses deprecated and undocumented Launch Services
> behavior. Every such use is listed, with its risks and how to undo it, in
> **[PRIVATE_API.md](PRIVATE_API.md)**. Read it before building or running the utility.

## Status

**Feasibility spike in progress. The spike app builds; its experiments have not been run yet.**

| Feature | State |
|---------|-------|
| [001 Sidebar icon spike](specs/001-sidebar-icon-spike/spec.md) | Code written and unit-tested; owner experiments next. Proves whether custom sidebar icons work on macOS 27, and how |
| [002 Mapping manager v1](specs/002-mapping-manager-v1/spec.md) | Specified. Planning waits on the 001 findings |

## Design principles

The full rules are in the [constitution](.specify/memory/constitution.md). In short:

- **Inspectable and boring**: Apple frameworks only. No networking, telemetry, updater, daemon,
  login item, privileged helper, root access, or third-party code.
- **Public API first**: undocumented behavior is used only when an experiment shows the public
  route cannot do the job, and it is isolated in one adapter.
- **Your folders are never modified**: the utility never renames, moves, deletes, or re-icons a
  folder. Removing a mapping removes only the utility's own settings.
- **Everything is reversible**: changes outside the utility happen only when you ask, are recorded
  first, and are undone by Reset.
- **Private API use is public**: see [PRIVATE_API.md](PRIVATE_API.md).

## Requirements

- macOS 27 or later.
- Xcode 27.2 or later.
- An Apple Developer team for code signing. The app and its Finder extension share an App Group,
  which must use your team ID prefix.

## Building and testing the spike

The spike is not implemented yet. When it is, follow the
[spike quickstart](specs/001-sidebar-icon-spike/quickstart.md) for build steps, the manual test
checklist, and full rollback instructions.

## How this project is planned

The project uses [Spec Kit](https://github.com/github/spec-kit) for spec-driven development:

- `.specify/memory/constitution.md`: project principles and quality gates.
- `specs/NNN-feature/`: spec, plan, research, data model, contracts, quickstart, and tasks for
  each feature.
- [Finder_Sidebar_Custom_Icons_Utility.md](Finder_Sidebar_Custom_Icons_Utility.md): the original
  design notes the specs were built from.

## License

[MIT](LICENSE)
