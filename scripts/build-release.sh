#!/bin/bash
#
# build-release.sh — Produce a Developer ID-signed Release build of ScoreEdit
# (issue #8, part of the scripted release pipeline in #9).
#
# Steps:
#   1. Regenerate the Xcode project from the Tuist manifests.
#   2. Archive the app in the Release configuration.
#   3. Export the archive with the "developer-id" method, which re-signs the
#      app (and its embedded Sparkle framework / XPC services) with the
#      "Developer ID Application" certificate.
#
# The exported ScoreEdit.app is written to dist/build/export/ and is ready for
# the subsequent DMG / notarization steps.
#
# This script is idempotent: it removes the previous archive and export outputs
# before writing new ones, so re-running produces a clean result.
#
# Usage:
#   scripts/build-release.sh
#   mise run build_release

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WORKSPACE="$REPO_ROOT/ScoreEdit.xcworkspace"
SCHEME="ScoreEdit"
CONFIGURATION="Release"

BUILD_DIR="$REPO_ROOT/dist/build"
ARCHIVE_PATH="$BUILD_DIR/ScoreEdit.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"

die() { echo "error: $*" >&2; exit 1; }

# --- Preconditions ---------------------------------------------------------
command -v tuist     >/dev/null 2>&1 || die "tuist not found. Run 'mise install'."
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found. Install Xcode."
[ -f "$EXPORT_OPTIONS" ] || die "export options plist not found: $EXPORT_OPTIONS"

# --- Report the version being built (from VERSION.json, see issue #11) ------
# Project.swift reads VERSION.json at generate time; we echo it here for a clear
# build log and traceability of the produced artifact.
VERSION_FILE="$REPO_ROOT/VERSION.json"
[ -f "$VERSION_FILE" ] || die "VERSION.json not found at $VERSION_FILE (see issue #11)."
MARKETING_VERSION="$(plutil -extract marketingVersion raw -o - "$VERSION_FILE")" \
  || die "could not read marketingVersion from VERSION.json."
BUILD_NUMBER="$(plutil -extract buildNumber raw -o - "$VERSION_FILE")" \
  || die "could not read buildNumber from VERSION.json."
echo "==> Building ScoreEdit $MARKETING_VERSION (build $BUILD_NUMBER)"

# --- 1. Regenerate the Xcode project ---------------------------------------
# Project.swift reads VERSION.json while the manifest is being evaluated, but
# Tuist caches evaluated manifests keyed on the manifest sources alone —
# VERSION.json is not part of that key. A version-only bump therefore leaves the
# cache valid and `tuist generate` reuses the previous version, silently
# producing a DMG named for the new version around an app still carrying the old
# CFBundleVersion (which Sparkle would then never offer as an update). Dropping
# the manifest cache first forces re-evaluation. The version is verified against
# the exported app below.
echo "==> Clearing cached manifests (so VERSION.json is re-read)"
( cd "$REPO_ROOT" && tuist clean manifests )

echo "==> Generating Xcode project (tuist generate)"
( cd "$REPO_ROOT" && tuist generate --no-open )

[ -d "$WORKSPACE" ] || die "workspace not found after generation: $WORKSPACE"

# --- 2. Archive (Release) --------------------------------------------------
echo "==> Archiving $SCHEME ($CONFIGURATION)"
rm -rf "$ARCHIVE_PATH"
mkdir -p "$BUILD_DIR"
xcodebuild archive \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS"

[ -d "$ARCHIVE_PATH" ] || die "archive was not produced at $ARCHIVE_PATH"

# --- 3. Export with Developer ID signing -----------------------------------
echo "==> Exporting archive (developer-id)"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_DIR"

APP="$EXPORT_DIR/ScoreEdit.app"
[ -d "$APP" ] || die "exported app not found at $APP"

# --- 4. Verify the exported app carries the version we set out to build -----
# Everything downstream (the DMG filename, the appcast entry) is named from
# VERSION.json, while the app's real version comes through the generated project.
# If those ever diverge the mismatch is invisible until users fail to get the
# update, so fail the build here instead.
APP_PLIST="$APP/Contents/Info.plist"
[ -f "$APP_PLIST" ] || die "exported app has no Info.plist at $APP_PLIST"
BUILT_MARKETING="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PLIST")" \
  || die "could not read CFBundleShortVersionString from the exported app."
BUILT_BUILD="$(plutil -extract CFBundleVersion raw -o - "$APP_PLIST")" \
  || die "could not read CFBundleVersion from the exported app."
if [ "$BUILT_MARKETING" != "$MARKETING_VERSION" ] || [ "$BUILT_BUILD" != "$BUILD_NUMBER" ]; then
  die "exported app is $BUILT_MARKETING (build $BUILT_BUILD) but VERSION.json says $MARKETING_VERSION (build $BUILD_NUMBER).
     The generated project is stale. Run 'tuist clean manifests' and try again."
fi
echo "==> Verified exported app is $BUILT_MARKETING (build $BUILT_BUILD)"

echo
echo "==> Release build complete:"
echo "    $APP"
echo
echo "Signing identity:"
codesign -dvv "$APP" 2>&1 | grep -E "^(Authority|TeamIdentifier|Identifier)=" || true
