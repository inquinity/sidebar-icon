# Sidebar Icons Constitution

## Core Principles

### I. Inspectable and Boring

The utility MUST be small enough to read in one sitting and MUST be built locally from source with
Xcode. It MUST NOT include networking, telemetry, analytics, crash reporting, an auto-updater, a
privileged helper, root access, SIP changes, a long-running daemon, or a login item. It MUST NOT
depend on third-party runtime libraries, Homebrew, or Python. Every file the utility writes MUST be
enumerable from documentation.

Rationale: the target is a work machine, where an opaque third-party tool is not acceptable.

### II. Public API First, Private Behavior Behind One Adapter

Implementation choices MUST follow this order of preference:

1. Public, documented macOS APIs (Finder Sync, AppKit, Launch Services public calls).
2. Undocumented Finder or Launch Services behavior (for example the
   `com.apple.LSSharedFileList.OverrideIcon.OSType` sidebar property and locally registered icon
   types), used only when option 1 is shown by a recorded experiment to be insufficient.
3. Direct reading or editing of Finder's sidebar store (`.sfl*` files) is PROHIBITED.

All option-2 behavior MUST live in a single adapter module with a narrow protocol, so it can be
removed or replaced without touching the GUI or configuration code. Every option-2 use MUST be
publicly documented as Principle VI requires.

Rationale: custom sidebar icons are a firm requirement, and public API alone may not provide them.
Isolating private behavior keeps breakage after a macOS update contained and visible.

### III. User Data Is Never Modified

The utility MUST NOT rename, move, delete, or change the contents or permissions of a user's folder.
It MUST NOT change a folder's existing custom Finder icon unless the user explicitly asks in a
separate, clearly labeled action. Removing a mapping MUST remove only the utility's own
configuration and assets. Icon files chosen by the user MUST be copied into the utility's own
container; originals MUST NOT be modified or required afterwards.

Rationale: the folder icon and the sidebar icon are separate layers, and user data is out of scope.

### IV. Prove Before Building

Any assumption about undocumented or uncertain Finder behavior MUST be validated by a minimal,
runnable proof of concept before dependent features are planned in detail. Each proof MUST record
its result (pass/fail, macOS build, observations) in the feature's `research.md`. Feature plans that
depend on an unproven assumption MUST NOT advance past `/speckit-plan`.

Rationale: whether Finder accepts runtime-supplied sidebar icons is the project's main risk.

### V. Explicit, Reversible Side Effects

Actions with effects outside the utility's own container (restarting Finder, registering icon types
with Launch Services, setting sidebar item properties) MUST be triggered by an explicit user action,
never silently on every configuration change. Every such effect MUST have a matching undo path, and
the utility MUST provide a "reset" that returns all sidebar entries it touched to Finder's default
icon and unregisters everything it registered.

Rationale: users must be able to try the utility and remove every trace of it.

### VI. Private API Use Is Publicly Documented

Every use of a private, undocumented, or deprecated-and-unsupported Apple API, symbol, property
key, file, or behavior MUST be listed in `PRIVATE_API.md` at the repository root. The register is
part of the public source tree; there MUST NOT be a separate, non-public copy. Each entry MUST
state:

- the exact symbol, key, or behavior and the framework or component it belongs to;
- its status (private, undocumented, or deprecated since which macOS version);
- what the utility uses it for and which source file calls it (the Principle II adapter);
- each macOS build it was verified working on, and any build it was observed failing on;
- known risks, including what happens if Apple changes or removes it;
- how reset undoes its effects, and how the dependency could be removed.

The register MUST be updated in the same commit that adds, changes, or removes such a use. The
README MUST link to the register near the top, and the shipped app's About window MUST say that it
relies on undocumented macOS behavior and name the register. Entries for uses that were tried and
abandoned MUST stay, marked "removed," with the reason.

Rationale: on a work machine the owner, and anyone reviewing the tool for them, must be able to see
exactly which unsupported behavior it relies on before building or running it. Hiding that would
make the tool the opaque utility this project exists to replace.

## Platform and Toolchain Constraints

- Target: macOS 27 and later. macOS 26 support MAY be added only if it needs no
  version-conditional code paths or extra private behavior.
- Language and UI: Swift 6 with strict concurrency, SwiftUI for the app window, AppKit where SwiftUI
  has no equivalent (for example `NSOpenPanel`).
- Signing: Apple Developer team (Developer ID) signing for every target. App Group identifiers MUST
  use the team-ID prefix (`<TEAMID>.<reverse-dns>`) so macOS does not show container-access prompts.
- Sandbox: the Finder Sync extension MUST be sandboxed. The main app SHOULD be sandboxed; any
  exemption needed by the private adapter MUST be justified in the plan's Complexity Tracking table.
- Storage: one versioned JSON configuration file plus copied icon assets in the App Group container.
  Folder references MUST NOT rely on app-scoped security-scoped bookmarks, because the extension
  cannot resolve them.
- Tests: Swift Testing for model, configuration, and adapter logic. Finder-visible behavior is
  verified by a written manual checklist, because Finder rendering cannot be automated reliably.

## Development Workflow and Quality Gates

- Work follows the Spec Kit flow: specify → clarify → plan → tasks → implement, one feature per
  branch under `specs/NNN-name/`.
- Every plan MUST complete the Constitution Check against Principles I–VI before Phase 0 and again
  after Phase 1 design.
- Behavior-changing work requires an independent review. Changes to the private adapter, signing,
  entitlements, or sandbox settings also require a security review.
- A review MUST fail any change that touches the private adapter without a matching
  `PRIVATE_API.md` update (Principle VI).
- Every feature MUST include a rollback note: how to disable the extension, run reset, and remove
  the app and its container.
- Commits follow Conventional Commits in the imperative mood.

## Governance

This constitution overrides other project practice. Amendments require a written rationale, an
updated Sync Impact Report, and a version bump: MAJOR for removing or redefining a principle, MINOR
for a new principle or materially expanded guidance, PATCH for clarifications. Reviews of every plan
and pull request MUST check compliance; any deviation MUST appear in Complexity Tracking with the
simpler alternative that was rejected and why.

**Version**: 1.1.0 | **Ratified**: 2026-11-17 | **Last Amended**: 2026-11-17
