#!/bin/bash
#
# create-dmg.sh — Assemble, sign, notarize, and staple the distributable
# ScoreEdit disk image (issue #8, part of the scripted release pipeline in #9).
#
# Consumes the Developer ID-signed app produced by build-release.sh
# (dist/build/export/ScoreEdit.app) and produces a ready-to-ship .dmg with a
# custom Finder window: the app on the left, an Applications shortcut on the
# right, and the background art from dmg/background.tiff behind them.
#
# Pipeline:
#   1. Stage the app + an /Applications symlink + the hidden .background art.
#   2. Create a read-write UDRW image and mount it.
#   3. Drive Finder (via osascript) to set the window size, icon size,
#      background picture, and the two icon positions.
#   4. Detach, then convert to a compressed read-only UDZO image.
#   5. Code-sign the .dmg with the same Developer ID as the app.
#   6. Notarize with notarytool (keychain profile named in SECRETS.json) and
#      staple the ticket.
#
# CANONICAL LAYOUT — must match dmg/background.tiff (see make-dmg-background.sh):
#   Window content 600 x 400, icon size 128,
#   ScoreEdit.app at (150, 205), Applications at (450, 205).
#
# The Finder step (3) requires macOS Automation permission the first time it
# runs ("Terminal wants to control Finder" — click OK).
#
# Notarization credentials are NOT stored in this repo. Create a keychain
# profile once, then put its name in SECRETS.json under "notaryProfile":
#
#   xcrun notarytool store-credentials ScoreEdit \
#     --apple-id "you@example.com" --team-id D3DPVGA48J \
#     --password "<app-specific-password>"
#
# Output (git-ignored, under dist/build/):
#   dist/build/ScoreEdit-<marketingVersion>.dmg
#
# Usage:
#   scripts/create-dmg.sh                # build, sign, notarize, staple
#   scripts/create-dmg.sh --skip-notarize# build + sign only (dev iteration)
#   mise run create_dmg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP="$REPO_ROOT/dist/build/export/ScoreEdit.app"
BACKGROUND="$REPO_ROOT/dmg/background.tiff"
VERSION_FILE="$REPO_ROOT/VERSION.json"
SECRETS_FILE="$REPO_ROOT/SECRETS.json"

BUILD_DIR="$REPO_ROOT/dist/build"
STAGING="$BUILD_DIR/dmg-staging"
RW_DMG="$BUILD_DIR/ScoreEdit-rw.dmg"

VOLNAME="ScoreEdit"
# Finder addresses mounted disks by their /Volumes path, so the image must be
# mounted there (not at a private mountpoint) for the layout step to find it.
MOUNTPOINT="/Volumes/$VOLNAME"
DEV=""   # device node of the mounted image, set at attach time

# Canonical layout (keep in sync with make-dmg-background.sh)
WIN_W=600 ; WIN_H=400 ; ICON_SIZE=128
APP_X=150 ; APP_Y=205
APPLICATIONS_X=450 ; APPLICATIONS_Y=205

SKIP_NOTARIZE=0
case "${1:-}" in
  --skip-notarize) SKIP_NOTARIZE=1 ;;
  "") ;;
  -h|--help) sed -n '2,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "error: unknown argument '$1' (see --help)" >&2; exit 1 ;;
esac

die() { echo "error: $*" >&2; exit 1; }

# --- Preconditions ---------------------------------------------------------
command -v hdiutil  >/dev/null 2>&1 || die "hdiutil not found (ships with macOS)."
command -v osascript>/dev/null 2>&1 || die "osascript not found (ships with macOS)."
command -v codesign >/dev/null 2>&1 || die "codesign not found (install Xcode)."
[ -d "$APP" ]        || die "app not found: $APP. Run scripts/build-release.sh (mise run build_release) first."
[ -f "$BACKGROUND" ] || die "background not found: $BACKGROUND. Run scripts/make-dmg-background.sh first."
[ -f "$VERSION_FILE" ] || die "VERSION.json not found (see issue #11)."

MARKETING_VERSION="$(plutil -extract marketingVersion raw -o - "$VERSION_FILE")" \
  || die "could not read marketingVersion from VERSION.json."
FINAL_DMG="$BUILD_DIR/ScoreEdit-$MARKETING_VERSION.dmg"

# Guard against a stale export: the app baked into the DMG must match the
# version we are naming it after. (build-release.sh regenerates from VERSION.json;
# if the export predates a version bump they can silently disagree.)
APP_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist" 2>/dev/null)" \
  || die "could not read CFBundleShortVersionString from the exported app."
[ "$APP_VERSION" = "$MARKETING_VERSION" ] \
  || die "version mismatch: exported app is $APP_VERSION but VERSION.json is $MARKETING_VERSION. Re-run scripts/build-release.sh (mise run build_release) to rebuild the app."

# Derive the signing identity from the app so the .dmg is signed with the
# exact same Developer ID Application certificate.
SIGN_ID="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application.*\)$/\1/p' | head -1)"
[ -n "$SIGN_ID" ] || die "could not determine the app's 'Developer ID Application' signing identity."

# Notary profile (unless skipping) — a name, not a secret.
if [ "$SKIP_NOTARIZE" -eq 0 ]; then
  [ -f "$SECRETS_FILE" ] || die "SECRETS.json not found. Copy SECRETS.example.json and set notaryProfile, or pass --skip-notarize."
  NOTARY_PROFILE="$(plutil -extract notaryProfile raw -o - "$SECRETS_FILE" 2>/dev/null)" \
    || die "key 'notaryProfile' missing from SECRETS.json. See SECRETS.example.json, or pass --skip-notarize."
  [ -n "$NOTARY_PROFILE" ] || die "'notaryProfile' in SECRETS.json is empty."
fi

echo "==> Packaging ScoreEdit $MARKETING_VERSION"
echo "    signing identity: $SIGN_ID"

# --- Cleanup helper (idempotent + trap) ------------------------------------
# Detach by device node when we know it; otherwise fall back to the mountpoint.
detach_image() {
  if [ -n "$DEV" ]; then
    hdiutil detach "$DEV" -quiet 2>/dev/null || hdiutil detach "$DEV" -force -quiet 2>/dev/null || true
    DEV=""
  elif [ -d "$MOUNTPOINT" ]; then
    hdiutil detach "$MOUNTPOINT" -quiet 2>/dev/null || hdiutil detach "$MOUNTPOINT" -force -quiet 2>/dev/null || true
  fi
}
cleanup() { detach_image; }
trap cleanup EXIT

# Clear any stale mount from a previous run, then reset state.
detach_image
rm -rf "$STAGING" "$RW_DMG" "$FINAL_DMG"
mkdir -p "$STAGING"

# --- 1. Stage contents -----------------------------------------------------
echo "==> Staging disk image contents"
ditto "$APP" "$STAGING/ScoreEdit.app"          # ditto preserves the signature
ln -s /Applications "$STAGING/Applications"
mkdir "$STAGING/.background"
cp "$BACKGROUND" "$STAGING/.background/background.tiff"

# --- 2. Create + mount a read-write image ----------------------------------
echo "==> Creating read-write image"
hdiutil create \
  -srcfolder "$STAGING" \
  -volname "$VOLNAME" \
  -fs HFS+ \
  -format UDRW \
  -ov "$RW_DMG" >/dev/null

echo "==> Mounting"
ATTACH_OUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
DEV="$(printf '%s\n' "$ATTACH_OUT" | awk '/\/Volumes\//{print $1; exit}')"
[ -n "$DEV" ] || die "could not determine device node after attaching $RW_DMG."
[ -d "$MOUNTPOINT" ] || die "image did not mount at expected path $MOUNTPOINT."

# --- 3. Arrange the Finder window ------------------------------------------
# Positions/sizes are in the icon view's coordinate space, matching the
# background art. Requires Automation permission the first time.
echo "==> Arranging Finder window (may prompt for Automation permission)"
osascript <<OSA
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, $((200 + WIN_W)), $((120 + WIN_H))}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $ICON_SIZE
    set background picture of opts to file ".background:background.tiff"
    set position of item "ScoreEdit.app" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$APPLICATIONS_X, $APPLICATIONS_Y}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

sync

# --- 4. Detach + convert to compressed read-only ---------------------------
echo "==> Detaching"
detach_image

echo "==> Converting to compressed image (UDZO)"
hdiutil convert "$RW_DMG" \
  -format UDZO -imagekey zlib-level=9 \
  -o "$FINAL_DMG" >/dev/null
rm -f "$RW_DMG"

# --- 5. Sign the .dmg ------------------------------------------------------
echo "==> Signing the disk image"
codesign --force --sign "$SIGN_ID" --timestamp "$FINAL_DMG"
codesign --verify --verbose=2 "$FINAL_DMG"

# --- 6. Notarize + staple --------------------------------------------------
if [ "$SKIP_NOTARIZE" -eq 1 ]; then
  echo
  echo "==> Built (unnotarized): $FINAL_DMG"
  echo "    Re-run without --skip-notarize to notarize and staple."
  exit 0
fi

echo "==> Submitting for notarization (profile: $NOTARY_PROFILE) — this can take a few minutes"
xcrun notarytool submit "$FINAL_DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling the notarization ticket"
xcrun stapler staple "$FINAL_DMG"

echo "==> Validating"
xcrun stapler validate "$FINAL_DMG"
spctl -a -t open --context context:primary-signature -vv "$FINAL_DMG" 2>&1 || true

echo
echo "==> Release disk image ready:"
echo "    $FINAL_DMG"
