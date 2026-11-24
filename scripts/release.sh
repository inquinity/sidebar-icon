#!/usr/bin/env bash
#
# Builds, notarizes and verifies a release of the Sidebar Icons app, one stage at a time:
#
#   check -> build -> notarize -> verify      (or: all)
#
# The result is build.noindex/release/<version>/sidebar-icons-<version>.zip: the Developer ID signed,
# notarized and stapled app with LICENSE and PRIVATE_API.md, ready to copy to another Mac. Nothing is
# published or pushed. The version is MARKETING_VERSION in app/sidebar-icons.xcodeproj.
#
# The notary profile (a `xcrun notarytool store-credentials` keychain profile) comes from
# SIDEBARICONS_NOTARY_PROFILE or NOTARY_PROFILE in the local, git-ignored Secrets.xcconfig. The signing
# identity comes from SIDEBARICONS_SIGNING_IDENTITY, SIGNING_IDENTITY in Secrets.xcconfig, or the keychain's
# only "Developer ID Application" identity. The script never prints or logs either (a failed build's log
# excerpt has signing lines removed); it refuses to run with xtrace, which would show them.
#
# Usage: scripts/release.sh <stage> [--dry-run] [--help]

set -euo pipefail
set +x

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_CYAN="\e[36m"          # Available for general use
COLOR_BLUE="\e[34m"          # Available for general use; does not show on screen well
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "%b%s%b\n" "$color" "$message" "$COLOR_RESET"
}

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# File and command names have no spaces; "Sidebar Icons" is only the name the app shows.
project="${repository_root}/app/sidebar-icons.xcodeproj"
scheme="sidebar-icons"
executable_name="sidebar-icons"
app_name="${executable_name}.app"
bundle_identifier="com.altmansoftwaredesign.sidebaricons"
team_identifier="45GJWJVQN2"
app_group="${team_identifier}.${bundle_identifier}"
stages="check build notarize verify"

stage=""
dry_run=false
dry_run_note=""
temporary_directory=""
unmet_gates=0

usage() {
    print_colored "$COLOR_YELLOW" "Usage: scripts/release.sh <stage> [--dry-run] [--help]"
    print_colored "$COLOR_YELLOW" "Stages, in order (or \"all\"): ${stages}"
    print_colored "$COLOR_YELLOW" "  check     clean tree, annotated tag v<version> on HEAD, CHANGELOG entry, tests, identity, notary profile"
    print_colored "$COLOR_YELLOW" "  build     Release build signed with Developer ID; signature, entitlement and linkage checks; zip and SHA-256"
    print_colored "$COLOR_YELLOW" "  notarize  submit the zip to Apple's notary service, wait (up to 30 minutes), staple, zip again"
    print_colored "$COLOR_YELLOW" "  verify    unpack a quarantined copy as another Mac would and check Gatekeeper accepts it"
    print_colored "$COLOR_YELLOW" "  --dry-run with check: list every unmet gate; with build: sign ad hoc, contact nothing"
    print_colored "$COLOR_YELLOW" "Credentials: SIDEBARICONS_NOTARY_PROFILE / NOTARY_PROFILE and optionally SIDEBARICONS_SIGNING_IDENTITY /"
    print_colored "$COLOR_YELLOW" "SIGNING_IDENTITY, from the environment or the git-ignored Secrets.xcconfig. Never printed."
}

die() {
    print_colored "$COLOR_RED" "Error: $1" >&2
    exit 1
}

cleanup() {
    if [[ -n "$temporary_directory" && -d "$temporary_directory" ]]; then
        rm -rf "$temporary_directory"
    fi
}
trap cleanup EXIT

# --- Arguments -------------------------------------------------------------------------------------

while (($# > 0)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --dry-run|-n) dry_run=true; dry_run_note=" (dry run)"; shift ;;
        -*) usage; die "unknown option: $1" ;;
        *)
            [[ -z "$stage" ]] || die "only one stage at a time (got \"${stage}\" and \"$1\")"
            stage="$1"; shift ;;
    esac
done
[[ -n "$stage" ]] || { usage; exit 1; }
[[ " ${stages} all " == *" ${stage} "* ]] || die "unknown stage \"${stage}\" (stages: ${stages}, all)"
if "$dry_run" && [[ "$stage" == "notarize" || "$stage" == "verify" || "$stage" == "all" ]]; then
    die "--dry-run applies to check and build only (notarize and verify need a real build)"
fi

cd "$repository_root"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/sidebar-icons-release.XXXXXX")"

# --- Version and paths -----------------------------------------------------------------------------

# The app's MARKETING_VERSION; both configurations must agree.
project_version() {
    local versions
    versions="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \(.*\);$/\1/p' "${project}/project.pbxproj" | sort -u)"
    [[ "$(grep -c . <<<"$versions")" == "1" ]] || die "the configurations disagree on MARKETING_VERSION: $(tr '\n' ' ' <<<"$versions")"
    printf "%s" "$versions"
}

version="$(project_version)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "MARKETING_VERSION \"${version}\" is not MAJOR.MINOR.PATCH"
tag="v${version}"
# A dry run builds into its own folder, so it can never replace a real (signed, notarized) release.
artifact_directory="${repository_root}/build.noindex/release/${version}"
"$dry_run" && artifact_directory="${artifact_directory}-dry-run"
payload="${artifact_directory}/payload"
derived_data="${repository_root}/build.noindex/DerivedData"
"$dry_run" && derived_data="${derived_data}-dry-run"
zip_name="sidebar-icons-${version}.zip"
zip_path="${artifact_directory}/${zip_name}"
procedure_log="${artifact_directory}/release.log"
mkdir -p "$artifact_directory"

log_result() {
    printf -- "- %s %s%s: %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$stage" "$dry_run_note" "$1" >>"$procedure_log"
    print_colored "$COLOR_GREEN" "$1"
}

require_command() {
    command -v "$1" >/dev/null || die "the command \"$1\" is needed"
}

require_file() {
    [[ -f "$1" ]] || die "${1#"${repository_root}"/} is missing: run the $2 stage first"
}

# gate <description> <command...>: must pass. Under --dry-run every unmet gate is listed instead of stopping.
gate() {
    local description=$1
    shift
    if "$@"; then
        print_colored "$COLOR_GREEN" "PASS  ${description}"
    elif "$dry_run"; then
        print_colored "$COLOR_RED" "FAIL  ${description}"
        unmet_gates=$((unmet_gates + 1))
    else
        die "gate not met: ${description}"
    fi
}

recorded_sha256() { awk '{print $1}' "${zip_path}.sha256"; }

# --- Credentials (never printed) ---------------------------------------------------------------------

# A value from the local, git-ignored Secrets.xcconfig, or nothing.
local_secret() {
    local secrets="${repository_root}/Secrets.xcconfig"
    [[ -f "$secrets" ]] || return 0
    awk -F' *= *' -v key="$1" '$1 == key { print $2; exit }' "$secrets"
}

resolve_signing_identity() {
    [[ -n "${SIDEBARICONS_SIGNING_IDENTITY:-}" ]] && return 0
    SIDEBARICONS_SIGNING_IDENTITY="$(local_secret SIGNING_IDENTITY)"
    if [[ -z "$SIDEBARICONS_SIGNING_IDENTITY" ]]; then
        local identities
        identities="$(security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | sort -u)"
        [[ "$(grep -c . <<<"$identities")" == "1" ]] && SIDEBARICONS_SIGNING_IDENTITY="$identities"
    fi
    return 0
}

resolve_notary_profile() {
    [[ -n "${SIDEBARICONS_NOTARY_PROFILE:-}" ]] && return 0
    SIDEBARICONS_NOTARY_PROFILE="$(local_secret NOTARY_PROFILE)"
    return 0
}

signing_identity_usable() {
    resolve_signing_identity
    [[ -n "${SIDEBARICONS_SIGNING_IDENTITY:-}" ]] || return 1
    security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"${SIDEBARICONS_SIGNING_IDENTITY}\""
}

notary_profile_usable() {
    resolve_notary_profile
    [[ -n "${SIDEBARICONS_NOTARY_PROFILE:-}" ]] || return 1
    xcrun notarytool history --keychain-profile "$SIDEBARICONS_NOTARY_PROFILE" >/dev/null 2>&1
}

# --- Gates -----------------------------------------------------------------------------------------

# No uncommitted change to tracked files, and no untracked file where Xcode or SwiftPM would build it
# (app/ is a file-system-synchronized group). Untracked files elsewhere (for example artwork) are allowed.
tree_is_clean() {
    [[ -z "$(git status --porcelain --untracked-files=no)" ]] \
        && [[ -z "$(git status --porcelain --untracked-files=all -- app Packages)" ]]
}

tag_is_annotated_on_head() {
    [[ "$(git cat-file -t "$tag" 2>/dev/null)" == "tag" ]] \
        && [[ "$(git rev-parse "${tag}^{commit}" 2>/dev/null)" == "$(git rev-parse HEAD)" ]]
}

changelog_has_entry() { grep -qE "^## \[${version//./\\.}\]" CHANGELOG.md; }

tests_pass() {
    if (cd Packages/SidebarIconCore && swift test) >"${temporary_directory}/test.log" 2>&1; then
        return 0
    fi
    tail -n 20 "${temporary_directory}/test.log" >&2
    return 1
}

# --- Stages ----------------------------------------------------------------------------------------

stage_check() {
    require_command xcodebuild
    gate "no uncommitted changes, and no untracked files in app/ or Packages/" tree_is_clean
    gate "${tag} is an annotated tag on HEAD" tag_is_annotated_on_head
    gate "CHANGELOG.md has an entry for ${version}" changelog_has_entry
    gate "swift test passes" tests_pass
    gate "a Developer ID Application signing identity is available" signing_identity_usable
    gate "the notary profile can sign in to Apple's notary service" notary_profile_usable
    if "$dry_run" && ((unmet_gates > 0)); then
        print_colored "$COLOR_RED" "${unmet_gates} gate(s) unmet."
        exit 1
    fi
    log_result "all gates met for ${version} at $(git rev-parse --short HEAD)"
}

stage_build() {
    require_command xcodebuild
    require_command codesign
    require_command ditto
    local signing_overrides=()
    if "$dry_run"; then
        # A real signature asks Apple's timestamp server; a dry run contacts nothing.
        print_colored "$COLOR_YELLOW" "Dry run: signing ad hoc."
        signing_overrides=(CODE_SIGN_IDENTITY=- OTHER_CODE_SIGN_FLAGS=)
    else
        tree_is_clean || die "the working tree is not clean: commit first, then run check again"
        tag_is_annotated_on_head || die "${tag} is not an annotated tag on HEAD: run the check stage"
        signing_identity_usable || die "no usable Developer ID Application identity: set SIGNING_IDENTITY in Secrets.xcconfig"
        signing_overrides=(CODE_SIGN_IDENTITY="$SIDEBARICONS_SIGNING_IDENTITY")
    fi

    print_colored "$COLOR_BRIGHTYELLOW" "Building Sidebar Icons ${version} (Release)..."
    xcodebuild -project "$project" -scheme "$scheme" -configuration Release -derivedDataPath "$derived_data" \
        "${signing_overrides[@]}" clean build >"${temporary_directory}/build.log" 2>&1 \
        || { grep -vE 'Signing Identity|codesign .*--sign|CODE_SIGN_IDENTITY' "${temporary_directory}/build.log" | tail -n 30 >&2
             die "the Release build failed"; }
    local built="${derived_data}/Build/Products/Release/${app_name}"
    [[ -d "$built" ]] || die "the build produced no ${app_name}"

    rm -rf "$payload"
    mkdir -p "$payload"
    ditto "$built" "${payload}/${app_name}"
    cp LICENSE PRIVATE_API.md "$payload/"
    local app="${payload}/${app_name}"
    local executable="${app}/Contents/MacOS/${executable_name}"

    [[ "$(plutil -extract CFBundleShortVersionString raw -o - "${app}/Contents/Info.plist")" == "$version" ]] \
        || die "the app's Info.plist does not carry version ${version}"
    [[ "$(plutil -extract CFBundleIdentifier raw -o - "${app}/Contents/Info.plist")" == "$bundle_identifier" ]] \
        || die "the app's bundle identifier is not ${bundle_identifier}"
    log_result "built ${app_name} ${version} for $(lipo -archs "$executable")"

    # Only system libraries, and none for networking or private frameworks (Constitution I).
    local libraries
    libraries="$(otool -L "$executable" | tail -n +2 | awk '{print $1}')"
    if grep -vE '^(/usr/lib/|/System/Library/Frameworks/)' <<<"$libraries" | grep -q .; then
        die "the app links a library outside /usr/lib and /System/Library/Frameworks"
    fi
    if grep -qE 'Network\.framework|CFNetwork|WebKit|NetworkExtension|libcurl|PrivateFrameworks' <<<"$libraries"; then
        die "the app links a networking or private framework"
    fi
    log_result "the app links only allowed system libraries"

    # No build folder, home folder or user name inside the executable. The strings go to a file first: with
    # pipefail, `strings | grep -q` reports failure when grep stops early (SIGPIPE), hiding a match.
    local needle executable_strings="${temporary_directory}/strings.txt"
    strings -a "$executable" >"$executable_strings"
    for needle in "$repository_root" "$HOME" "$(id -un)"; do
        if grep -F "$needle" "$executable_strings" >/dev/null; then
            die "the executable contains the build folder, the home folder or the user name"
        fi
    done
    log_result "no build folder, home folder or user name in the executable"

    codesign --verify --deep --strict "$app" || die "the app's signature does not verify"
    # Exactly the App Group entitlement: no get-task-allow, nothing else.
    local entitlements
    entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || true)"
    [[ "$entitlements" == "{\"com.apple.security.application-groups\":[\"${app_group}\"]}" ]] \
        || die "the app's entitlements are not exactly the App Group ${app_group}: ${entitlements}"
    if ! "$dry_run"; then
        local details
        details="$(codesign -dvv "$app" 2>&1)"
        grep -q "Authority=Developer ID Application" <<<"$details" || die "the app is not signed with a Developer ID Application identity"
        grep -qE "flags=.*runtime" <<<"$details" || die "the app's signature lacks the hardened runtime"
        grep -q "^Timestamp=" <<<"$details" || die "the app's signature has no secure timestamp"
        grep -qx "TeamIdentifier=${team_identifier}" <<<"$details" || die "the app is not signed by team ${team_identifier} (its App Group needs that team)"
        log_result "signed with Developer ID Application, hardened runtime, secure timestamp; entitlements: App Group only"
    else
        log_result "signed ad hoc; entitlements: App Group only"
    fi

    make_zip
    # A new build voids an earlier notarization and verification: they are tied to a zip by its SHA-256.
    rm -f "${artifact_directory}/notarization.json" "${artifact_directory}/notarized.sha256" "${artifact_directory}/verified.sha256"
    log_result "${zip_name}: SHA-256 $(recorded_sha256)"
}

# The payload folder's contents, without extended attributes or resource forks.
make_zip() {
    rm -f "$zip_path" "${zip_path}.sha256"
    ditto -c -k --norsrc --noextattr --noqtn "$payload" "$zip_path"
    if zipinfo -1 "$zip_path" | grep -E '(^|/)(\._|\.DS_Store)' >/dev/null; then
        die "the zip holds resource-fork or Finder files"
    fi
    (cd "$artifact_directory" && shasum -a 256 "$zip_name" >"${zip_name}.sha256")
}

stage_notarize() {
    require_file "$zip_path" build
    notary_profile_usable || die "no usable notary profile: set NOTARY_PROFILE in Secrets.xcconfig to a notarytool keychain profile"
    local details
    details="$(codesign -dvv "${payload}/${app_name}" 2>&1)"
    grep -q "Authority=Developer ID Application" <<<"$details" && grep -qx "TeamIdentifier=${team_identifier}" <<<"$details" \
        || die "the payload is not the Developer ID build: run the build stage (without --dry-run) again"
    print_colored "$COLOR_BRIGHTYELLOW" "Submitting ${zip_name} to Apple's notary service (waiting up to 30 minutes)..."
    local result="${artifact_directory}/notarization.json"
    xcrun notarytool submit "$zip_path" --keychain-profile "$SIDEBARICONS_NOTARY_PROFILE" --wait --timeout 30m \
        --output-format json >"$result" || true
    local status submission
    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || printf 'unknown')"
    submission="$(plutil -extract id raw -o - "$result" 2>/dev/null || printf 'unknown')"
    if [[ "$status" != "Accepted" ]]; then
        if [[ "$submission" != "unknown" ]]; then
            xcrun notarytool log "$submission" --keychain-profile "$SIDEBARICONS_NOTARY_PROFILE" || true
        fi
        die "notarization ended with status \"${status}\" (submission ${submission})"
    fi
    log_result "notarized: status Accepted, submission ${submission:0:8}…"

    # Staple the ticket so the app passes Gatekeeper offline, then zip again: the deliverable is the stapled app.
    local app="${payload}/${app_name}"
    [[ -d "$app" ]] || die "no payload folder: run the build stage again"
    local staple_attempt stapled=false
    for staple_attempt in 1 2 3 4 5 6; do
        if xcrun stapler staple "$app"; then stapled=true; break; fi
        # The ticket can take a little while to reach Apple's ticket service after "Accepted".
        ((staple_attempt < 6)) || break
        print_colored "$COLOR_YELLOW" "Stapling failed (try ${staple_attempt} of 6); the ticket may not be available yet..."
        sleep 20
    done
    "$stapled" || die "the ticket could not be stapled: run the notarize stage again later"
    xcrun stapler validate "$app" >/dev/null || die "the stapled ticket does not validate"
    codesign --verify --deep --strict "$app" || die "stapling broke the app's signature"
    make_zip
    recorded_sha256 >"${artifact_directory}/notarized.sha256"
    log_result "stapled the ticket and zipped again: SHA-256 $(recorded_sha256)"
}

stage_verify() {
    require_file "$zip_path" build
    require_file "${artifact_directory}/notarization.json" notarize
    [[ "$(cat "${artifact_directory}/notarized.sha256" 2>/dev/null)" == "$(recorded_sha256)" ]] \
        || die "this zip is not the notarized and stapled one: run build and notarize again"
    (cd "$artifact_directory" && shasum -a 256 -c "${zip_name}.sha256" >/dev/null) || die "the zip no longer matches its SHA-256"
    local unpacked="${temporary_directory}/unpacked"
    ditto -x -k "$zip_path" "$unpacked"
    local app="${unpacked}/${app_name}"
    [[ -d "$app" ]] || die "the zip holds no ${app_name}"
    # Mark it as downloaded, as a browser or AirDrop would, so Gatekeeper treats it like a copy from elsewhere.
    xattr -rw com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");sidebar-icons-release;" "$app"
    codesign --verify --deep --strict "$app" || die "the unpacked app's signature does not verify"
    xcrun stapler validate "$app" >/dev/null || die "the unpacked app has no valid notarization ticket"
    spctl --assess --type execute --verbose=2 "$app" 2>"${temporary_directory}/spctl.log" \
        || die "Gatekeeper rejects the unpacked app: $(tr '\n' ';' <"${temporary_directory}/spctl.log")"
    grep -q "Notarized Developer ID" "${temporary_directory}/spctl.log" \
        || die "Gatekeeper accepts the app but not as Notarized Developer ID"
    log_result "the quarantined copy: signature verifies, ticket stapled, Gatekeeper accepts it (Notarized Developer ID)"
    if command -v syspolicy_check >/dev/null; then
        syspolicy_check distribution "$app" >"${temporary_directory}/syspolicy.log" 2>&1 \
            || die "syspolicy_check distribution found: $(tr '\n' ';' <"${temporary_directory}/syspolicy.log" | cut -c1-300)"
        log_result "syspolicy_check distribution: no issues"
    fi
    recorded_sha256 >"${artifact_directory}/verified.sha256"
    log_result "ready to copy: ${zip_path#"${repository_root}"/} (SHA-256 $(recorded_sha256))"
    print_colored "$COLOR_GREEN" "On the other Mac: unzip it, move \"${app_name}\" to /Applications, and open it."
}

# --- Main ------------------------------------------------------------------------------------------

run_stage() {
    stage="$1"
    print_colored "$COLOR_BRIGHTYELLOW" "== ${stage} ${version}${dry_run_note}"
    "stage_$1"
}

if [[ "$stage" == "all" ]]; then
    for each_stage in $stages; do
        run_stage "$each_stage"
    done
else
    run_stage "$stage"
fi
