# Release build (feature 003)

**Status**: In progress (2026-11-22) | **Branch**: `003-release-build`

The owner needs Sidebar Icons on a work Mac, copied by hand until a Homebrew tap exists. This
covers 002 follow-ups F016 (Release build and signing) and F021 (lowercase identifiers).

## Decisions (owner, 2026-11-22)

- **Identifiers first (F021)**: lowercase bundle ID and App Group
  (`com.altmansoftwaredesign.sidebaricons`) before the first install outside development, so no
  Mac ever needs a migration. Version 0.2.0 (breaking: new container).
- **Notary profile**: reuse the keychain profile desktop-name-manager uses; its name lives in the
  git-ignored `Secrets.xcconfig` (`NOTARY_PROFILE`) and is never printed.
- **Package**: a zip of the stapled app plus `LICENSE` and `PRIVATE_API.md` (no DMG).
- **Work Mac**: macOS 27 on a build other than 26B131; the unverified-build banner shows there
  until that build is checked and added to `SidebarIconCoreInfo.verifiedBuilds`.

## Design

- Release configuration: `CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = "Developer ID
  Application"`, `OTHER_CODE_SIGN_FLAGS = --timestamp`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`
  (no `get-task-allow`), hardened runtime, no provisioning profile (the team-prefixed App Group
  needs none on macOS). Debug keeps automatic development signing.
- `scripts/release.sh`, modelled on desktop-name-manager's: `check` (clean tree, annotated tag,
  CHANGELOG entry, tests, identity, notary profile) → `build` (signature, entitlement, linkage and
  path-leak checks; zip; SHA-256) → `notarize` (`notarytool submit --wait`, staple with retries,
  zip again) → `verify` (quarantined copy: signature, stapled ticket, Gatekeeper "Notarized
  Developer ID", `syspolicy_check distribution`). Nothing is published or pushed.

## Verification

1. `scripts/release.sh all` succeeds for the tagged version.
2. On this Mac: install the zip's app in `/Applications`; it opens without a Gatekeeper prompt;
   add one mapping, Refresh Finder, Reset All; uninstall.
3. On the work Mac (owner): copy, unzip, move to `/Applications`, open; add, then Reset All.
4. Independent code and security review of the signing settings, entitlements and script.

## Rollback

Nothing outside the repository changes except the notarization upload and the test install. On any
Mac: Reset All, quit, delete the app and its container. Reverting the branch restores 0.1.0.
