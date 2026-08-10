#!/bin/bash
#
# bump-version.sh — Update the app version in VERSION.json (issue #11, part of #7).
#
# VERSION.json is the single, checked-in source of truth for the app version.
# Project.swift reads it at `tuist generate` time:
#   marketingVersion -> CFBundleShortVersionString  (About box, Sparkle shortVersionString)
#   buildNumber      -> CFBundleVersion             (Sparkle's update-comparison value)
#
# The build number is a monotonic integer that MUST strictly increase every
# release, so every mode of this script increments it.
#
# Usage:
#   scripts/bump-version.sh major        # 1.4.2 -> 2.0.0, build += 1
#   scripts/bump-version.sh minor        # 1.4.2 -> 1.5.0, build += 1
#   scripts/bump-version.sh patch        # 1.4.2 -> 1.4.3, build += 1
#   scripts/bump-version.sh --set 2.1.0  # marketing := 2.1.0, build += 1
#   scripts/bump-version.sh --build-only # marketing unchanged, build += 1
#
#   mise run bump_version -- patch
#
# After bumping, run `tuist clean manifests && tuist generate` (or
# scripts/build-release.sh, which does it for you) for the new version to take
# effect in the Xcode project. The clean is required: Tuist caches evaluated
# manifests keyed on the manifest sources, and VERSION.json is not one of them.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION.json"

# Canonical comment re-emitted on every write (keeps VERSION.json self-documenting).
COMMENT="Single source of truth for the app version (issue #11). Unlike SECRETS.json, this file IS checked in. Bump it with scripts/bump-version.sh; it is read at 'tuist generate' time by Project.swift (marketingVersion -> CFBundleShortVersionString, buildNumber -> CFBundleVersion). buildNumber must strictly increase every release so Sparkle can detect updates."

die() { echo "error: $*" >&2; exit 1; }

usage() {
  sed -n '5,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

# --- Parse arguments -------------------------------------------------------
[ $# -ge 1 ] || usage 1

MODE="$1"
case "$MODE" in
  major|minor|patch|--build-only) [ $# -eq 1 ] || die "$MODE takes no extra arguments." ;;
  --set) [ $# -eq 2 ] || die "--set requires a version, e.g. --set 2.1.0"; NEW_MARKETING="$2" ;;
  -h|--help) usage 0 ;;
  *) die "unknown mode '$MODE'. Run with --help for usage." ;;
esac

# --- Read current values ---------------------------------------------------
[ -f "$VERSION_FILE" ] || die "VERSION.json not found at $VERSION_FILE."

CUR_MARKETING="$(plutil -extract marketingVersion raw -o - "$VERSION_FILE" 2>/dev/null)" \
  || die "key 'marketingVersion' missing from VERSION.json."
CUR_BUILD="$(plutil -extract buildNumber raw -o - "$VERSION_FILE" 2>/dev/null)" \
  || die "key 'buildNumber' missing from VERSION.json."

[[ "$CUR_MARKETING" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "current marketingVersion '$CUR_MARKETING' is not semver MAJOR.MINOR.PATCH."
[[ "$CUR_BUILD" =~ ^[0-9]+$ ]] \
  || die "current buildNumber '$CUR_BUILD' is not an integer."

IFS='.' read -r MAJOR MINOR PATCH <<< "$CUR_MARKETING"

# --- Compute new marketing version -----------------------------------------
case "$MODE" in
  major) NEW_MARKETING="$((MAJOR + 1)).0.0" ;;
  minor) NEW_MARKETING="${MAJOR}.$((MINOR + 1)).0" ;;
  patch) NEW_MARKETING="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
  --build-only) NEW_MARKETING="$CUR_MARKETING" ;;
  --set)
    [[ "$NEW_MARKETING" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || die "--set value '$NEW_MARKETING' is not semver MAJOR.MINOR.PATCH."
    ;;
esac

NEW_BUILD="$((CUR_BUILD + 1))"

# --- Write VERSION.json atomically -----------------------------------------
TMP="$(mktemp "${VERSION_FILE}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<EOF
{
  "//": "$COMMENT",
  "marketingVersion": "$NEW_MARKETING",
  "buildNumber": $NEW_BUILD
}
EOF

# Validate the JSON we just wrote before replacing the real file. (`plutil -lint`
# misparses JSON on some macOS versions, so validate via a no-op JSON convert.)
plutil -convert json -o /dev/null "$TMP" 2>/dev/null || die "internal error: produced invalid JSON."
mv "$TMP" "$VERSION_FILE"
trap - EXIT

echo "VERSION.json updated:"
echo "  marketingVersion: $CUR_MARKETING -> $NEW_MARKETING"
echo "  buildNumber:      $CUR_BUILD -> $NEW_BUILD"
echo
# `tuist generate` alone is NOT enough: Tuist caches evaluated manifests keyed on
# the manifest sources, and VERSION.json is not one of them, so the bump would be
# ignored and the old version generated again. build-release.sh does the clean
# for you and verifies the exported app's version afterwards.
echo "Run 'tuist clean manifests && tuist generate' (or scripts/build-release.sh) to apply."
