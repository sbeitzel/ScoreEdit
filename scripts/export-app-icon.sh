#!/bin/bash
#
# export-app-icon.sh — Render the ScoreEdit app icon to a PNG for the marketing
# website (issue #13, part of #7).
#
# The app icon is authored as an Icon Composer document
# (ScoreEdit/Resources/ScoreEdit.icon). This script renders it to a flat PNG
# using `ictool`, the command-line renderer bundled with Icon Composer inside
# Xcode. Re-run it whenever the icon changes (see #12) to refresh the website
# artwork in one repeatable step.
#
# The output path is machine-specific, so it is read from SECRETS.json
# (key: iconExportPath; see issue #10) rather than hardcoded here.
#
# Usage:
#   scripts/export-app-icon.sh [size]
#
#   size  Output edge length in pixels (square). Default: 1024.

set -euo pipefail

SIZE="${1:-1024}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SECRETS_FILE="$REPO_ROOT/SECRETS.json"
ICON_SOURCE="$REPO_ROOT/ScoreEdit/Resources/ScoreEdit.icon"

die() { echo "error: $*" >&2; exit 1; }

# --- Locate ictool (bundled with Icon Composer, inside the selected Xcode) ---
DEVELOPER_DIR="$(xcode-select -p 2>/dev/null)" \
  || die "Xcode command line tools not found (xcode-select -p failed)."
XCODE_CONTENTS="$(dirname "$DEVELOPER_DIR")"
ICTOOL="$XCODE_CONTENTS/Applications/Icon Composer.app/Contents/Executables/ictool"
[ -x "$ICTOOL" ] \
  || die "ictool not found at '$ICTOOL'. Icon Composer ships with Xcode 26+; make sure the full Xcode (not just the Command Line Tools) is selected via xcode-select."

# --- Validate inputs ---
[ -d "$ICON_SOURCE" ] || die "icon source not found: $ICON_SOURCE"
[ -f "$SECRETS_FILE" ] \
  || die "SECRETS.json not found at $SECRETS_FILE. Copy SECRETS.example.json to SECRETS.json and set iconExportPath."

# --- Read the destination path from SECRETS.json (plutil: no jq dependency) ---
DEST_RAW="$(plutil -extract iconExportPath raw -o - "$SECRETS_FILE" 2>/dev/null)" \
  || die "key 'iconExportPath' is missing from $SECRETS_FILE. See SECRETS.example.json."
[ -n "$DEST_RAW" ] || die "'iconExportPath' in $SECRETS_FILE is empty."

# Expand a leading ~ to $HOME.
case "$DEST_RAW" in
  "~/"*) DEST="$HOME/${DEST_RAW#\~/}" ;;
  "~")   DEST="$HOME" ;;
  *)     DEST="$DEST_RAW" ;;
esac

# --- Render ---
mkdir -p "$(dirname "$DEST")"
"$ICTOOL" "$ICON_SOURCE" \
  --export-image \
  --output-file "$DEST" \
  --platform macOS \
  --rendition Default \
  --width "$SIZE" \
  --height "$SIZE" \
  --scale 1

echo "Exported ${SIZE}x${SIZE} app icon to: $DEST"
