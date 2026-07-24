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

echo
echo "==> Release build complete:"
echo "    $APP"
echo
echo "Signing identity:"
codesign -dvv "$APP" 2>&1 | grep -E "^(Authority|TeamIdentifier|Identifier)=" || true
