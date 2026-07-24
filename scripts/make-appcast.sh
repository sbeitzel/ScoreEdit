#!/bin/bash
#
# make-appcast.sh — Generate/refresh the Sparkle appcast (and delta updates)
# for the notarized ScoreEdit disk image (issue #8, part of the scripted
# release pipeline in #9).
#
# Sparkle's `generate_appcast` scans a directory of release archives (our
# .dmgs), signs each with the EdDSA private key (the one matching the app's
# SUPublicEDKey), computes binary delta updates against the previous versions
# present, and writes/updates appcast.xml in that directory.
#
# THE SIGNING KEY
#   The private EdDSA key is NOT stored in the login Keychain here; it is
#   fetched at run time from 1Password via the `op` CLI and piped to
#   generate_appcast on stdin (--ed-key-file -), so it never touches disk.
#   Put the 1Password secret reference in SECRETS.json under
#   "sparkle_ed_key_op_ref" (e.g. "op://Personal/Sparkle private key/text").
#   You must be signed in to `op` (run `op signin`) before invoking this.
#
# THE UPDATES DIRECTORY
#   generate_appcast needs the older DMGs on hand to build deltas, so releases
#   accumulate in one "updates" directory that mirrors what is published under
#   the app's download URL. Point SECRETS.json -> "updatesDir" at a persistent
#   local mirror of that web directory. If unset, a throwaway dir under
#   dist/build/ is used (fine for a one-off / dev run, but yields no deltas
#   because no history is kept there).
#
# The download URL prefix and the feed name are derived from the shipped app's
# SUFeedURL (Info.plist), so there is a single source of truth.
#
# Optional release notes: place ScoreEdit-<version>.{html,md,txt} in a
# release-notes/ directory at the repo root; it is copied next to the DMG so
# generate_appcast attaches it to the update.
#
# Outputs (in the updates directory):
#   appcast.xml                    — the signed feed uploaded to SUFeedURL
#   ScoreEdit-<version>.dmg        — the release (copied in)
#   ScoreEdit<old>-<new>.delta     — delta updates (when history is present)
#   old_updates/                   — superseded archives moved aside by Sparkle
#
# Usage:
#   scripts/make-appcast.sh
#   mise run make_appcast

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION_FILE="$REPO_ROOT/VERSION.json"
SECRETS_FILE="$REPO_ROOT/SECRETS.json"
BUILD_DIR="$REPO_ROOT/dist/build"

die() { echo "error: $*" >&2; exit 1; }

# --- Locate Sparkle's generate_appcast (resolved SPM artifact) -------------
GEN="$(find "$REPO_ROOT/Tuist/.build/artifacts" \
        -path '*/sparkle/Sparkle/bin/generate_appcast' -type f 2>/dev/null \
        | grep -v '/index-build/' | head -1)"
[ -n "$GEN" ] && [ -x "$GEN" ] \
  || die "generate_appcast not found under Tuist/.build/artifacts. Run 'tuist install' first."

# --- Resolve the Sparkle EdDSA private key reference (1Password) ------------
command -v op >/dev/null 2>&1 \
  || die "1Password CLI 'op' not found. Install it (brew install 1password-cli) and sign in."
[ -f "$SECRETS_FILE" ] \
  || die "SECRETS.json not found. Copy SECRETS.example.json and set sparkle_ed_key_op_ref."
OP_KEY_REF="$(plutil -extract sparkle_ed_key_op_ref raw -o - "$SECRETS_FILE" 2>/dev/null)" \
  || die "key 'sparkle_ed_key_op_ref' missing from SECRETS.json. See SECRETS.example.json."
[ -n "$OP_KEY_REF" ] || die "'sparkle_ed_key_op_ref' in SECRETS.json is empty."

# --- Locate the notarized DMG for the current version ----------------------
[ -f "$VERSION_FILE" ] || die "VERSION.json not found (see issue #11)."
MARKETING_VERSION="$(plutil -extract marketingVersion raw -o - "$VERSION_FILE")" \
  || die "could not read marketingVersion from VERSION.json."
DMG="$BUILD_DIR/ScoreEdit-$MARKETING_VERSION.dmg"
[ -f "$DMG" ] || die "release DMG not found: $DMG. Run scripts/create-dmg.sh (mise run create_dmg) first."

# Warn (don't fail) if the DMG isn't stapled — Sparkle updates should ship a
# notarized, stapled image so Gatekeeper is happy offline.
if ! xcrun stapler validate "$DMG" >/dev/null 2>&1; then
  echo "warning: $DMG is not stapled/notarized. Run 'mise run create_dmg' (without --skip-notarize)." >&2
fi

# --- Derive the download URL prefix + feed name from the shipped Info.plist -
APP_PLIST="$BUILD_DIR/export/ScoreEdit.app/Contents/Info.plist"
[ -f "$APP_PLIST" ] || die "exported app Info.plist not found: $APP_PLIST. Run 'mise run build_release' first."
FEED_URL="$(plutil -extract SUFeedURL raw -o - "$APP_PLIST" 2>/dev/null)" \
  || die "SUFeedURL missing from the app's Info.plist."
[ -n "$FEED_URL" ] || die "SUFeedURL in the app's Info.plist is empty."
FEED_NAME="${FEED_URL##*/}"                 # e.g. appcast.xml
DOWNLOAD_PREFIX="${FEED_URL%/*}/"           # e.g. https://.../apps/ScoreEdit/

# --- Determine the updates directory ---------------------------------------
UPDATES_DIR=""
if [ -f "$SECRETS_FILE" ]; then
  UPDATES_DIR="$(plutil -extract updatesDir raw -o - "$SECRETS_FILE" 2>/dev/null || true)"
fi
if [ -n "$UPDATES_DIR" ]; then
  case "$UPDATES_DIR" in
    "~/"*) UPDATES_DIR="$HOME/${UPDATES_DIR#\~/}" ;;
    "~")   UPDATES_DIR="$HOME" ;;
  esac
else
  UPDATES_DIR="$BUILD_DIR/updates"
  echo "note: SECRETS.json has no 'updatesDir'; using throwaway $UPDATES_DIR (no delta history)." >&2
fi
mkdir -p "$UPDATES_DIR"

echo "==> Appcast for ScoreEdit $MARKETING_VERSION"
echo "    generate_appcast : $GEN"
echo "    updates dir      : $UPDATES_DIR"
echo "    download prefix  : $DOWNLOAD_PREFIX"
echo "    feed file        : $FEED_NAME"

# --- Stage the DMG (+ optional release notes) into the updates directory ----
cp "$DMG" "$UPDATES_DIR/"
NOTES_SRC=""
for ext in html md txt; do
  cand="$REPO_ROOT/release-notes/ScoreEdit-$MARKETING_VERSION.$ext"
  [ -f "$cand" ] && { NOTES_SRC="$cand"; break; }
done
if [ -n "$NOTES_SRC" ]; then
  cp "$NOTES_SRC" "$UPDATES_DIR/ScoreEdit-$MARKETING_VERSION.${NOTES_SRC##*.}"
  echo "    release notes    : ${NOTES_SRC##*/}"
fi

# --- Generate/refresh the appcast ------------------------------------------
# Fetch the EdDSA private key from 1Password and hand it to generate_appcast on
# stdin (--ed-key-file -). Keeping it in a shell variable avoids writing the
# secret to disk; op failures (not signed in, bad ref) surface here.
echo "==> Fetching Sparkle signing key from 1Password ($OP_KEY_REF)"
ED_KEY="$(op read "$OP_KEY_REF")" \
  || die "failed to read the Sparkle EdDSA key from 1Password. Is 'op' signed in (op signin) and the reference correct?"
[ -n "$ED_KEY" ] || die "1Password returned an empty value for $OP_KEY_REF."

echo "==> Running generate_appcast"
printf '%s\n' "$ED_KEY" | "$GEN" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "$DOWNLOAD_PREFIX" \
  -o "$UPDATES_DIR/$FEED_NAME" \
  "$UPDATES_DIR"

APPCAST="$UPDATES_DIR/$FEED_NAME"
[ -f "$APPCAST" ] || die "generate_appcast did not produce $APPCAST."

echo
echo "==> Appcast written: $APPCAST"
echo "--- latest item ---"
# Show the enclosure line(s) so the signed version/URL is visible at a glance.
grep -E 'sparkle:version|sparkle:shortVersionString|<enclosure|sparkle:deltaFrom|url=' "$APPCAST" | head -20 || true
echo
echo "Files to publish under $DOWNLOAD_PREFIX :"
( cd "$UPDATES_DIR"; shopt -s nullglob; for f in "$FEED_NAME" ScoreEdit-*.dmg *.delta; do [ -e "$f" ] && echo "  $f"; done )
