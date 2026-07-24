#!/bin/bash
#
# make-dmg-background.sh — Generate the DMG window background image (issue #8,
# part of the scripted release pipeline in #9).
#
# The distributable .dmg opens to a Finder window showing two icons:
#
#       [ ScoreEdit.app ]        -->        [ Applications ]
#
# This script draws the background art behind that window: a light "glass"
# panel echoing the app icon, the app name, and an arrow pointing from the app
# toward the Applications shortcut. It renders an SVG source to PNG at both
# @1x and @2x and bundles them into a single multi-resolution TIFF, which is
# what the DMG layout step points Finder at so the picture stays crisp on
# Retina displays.
#
# CANONICAL LAYOUT (must match the Finder icon placement in the create-dmg
# step). All values are in window points:
#
#   Window content size : 600 x 400
#   Icon size           : 128
#   App icon center     : (150, 205)
#   Applications center : (450, 205)
#   Arrow               : centered at (300, 205), between the two icons
#
# Outputs (checked in, so the DMG step needs no render toolchain):
#   dmg/background.svg      — editable source (regenerated on every run)
#   dmg/background.png      — 600 x 400  (@1x)
#   dmg/background@2x.png   — 1200 x 800 (@2x)
#   dmg/background.tiff     — multi-resolution, referenced by the DMG layout
#
# Usage:
#   scripts/make-dmg-background.sh
#   mise run make_dmg_background

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DMG_DIR="$REPO_ROOT/dmg"

SVG="$DMG_DIR/background.svg"
PNG_1X="$DMG_DIR/background.png"
PNG_2X="$DMG_DIR/background@2x.png"
TIFF="$DMG_DIR/background.tiff"

die() { echo "error: $*" >&2; exit 1; }

command -v rsvg-convert >/dev/null 2>&1 \
  || die "rsvg-convert not found. Install with: brew install librsvg"
command -v tiffutil >/dev/null 2>&1 \
  || die "tiffutil not found (ships with macOS)."

mkdir -p "$DMG_DIR"

# --- 1. Write the SVG source (viewBox is the @1x point grid) ---------------
cat > "$SVG" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400" viewBox="0 0 600 400">
  <defs>
    <linearGradient id="panel" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0"   stop-color="#fbfbfc"/>
      <stop offset="0.5" stop-color="#f2f2f4"/>
      <stop offset="1"   stop-color="#e7e7ea"/>
    </linearGradient>
    <linearGradient id="arrow" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#9a9aa0"/>
      <stop offset="1" stop-color="#5c5c62"/>
    </linearGradient>
  </defs>

  <!-- Background panel -->
  <rect x="0" y="0" width="600" height="400" fill="url(#panel)"/>

  <!-- Subtle staff-line motif behind the title, echoing the app icon -->
  <g stroke="#c9c9cf" stroke-width="1.25" opacity="0.7">
    <line x1="180" y1="64"  x2="420" y2="64"/>
    <line x1="180" y1="72"  x2="420" y2="72"/>
    <line x1="180" y1="80"  x2="420" y2="80"/>
    <line x1="180" y1="88"  x2="420" y2="88"/>
    <line x1="180" y1="96"  x2="420" y2="96"/>
  </g>

  <!-- Title (baseline sits one staff line (8px) lower than the top line) -->
  <text x="300" y="94" text-anchor="middle"
        font-family="Helvetica Neue, Helvetica, Arial, sans-serif"
        font-size="34" font-weight="600" fill="#2b2b2e">ScoreEdit</text>

  <!-- Arrow from the app toward Applications, centered at (300, 205) -->
  <g fill="url(#arrow)">
    <path d="M 262 197 H 320 V 185 L 348 205 L 320 225 V 213 H 262 Z"/>
  </g>

  <!-- Install hint -->
  <text x="300" y="360" text-anchor="middle"
        font-family="Helvetica Neue, Helvetica, Arial, sans-serif"
        font-size="15" fill="#8a8a90">Drag ScoreEdit into your Applications folder</text>
</svg>
SVG

# --- 2. Render @1x and @2x --------------------------------------------------
echo "==> Rendering background PNGs"
rsvg-convert --width 600  --height 400 "$SVG" --output "$PNG_1X"
rsvg-convert --width 1200 --height 800 "$SVG" --output "$PNG_2X"

# --- 3. Bundle into a multi-resolution TIFF ---------------------------------
# tiffutil pairs the images by resolution; -cathidpicheck asserts the second is
# exactly 2x the first so Finder treats it as the @2x rendition.
echo "==> Building multi-resolution TIFF"
tiffutil -cathidpicheck "$PNG_1X" "$PNG_2X" -out "$TIFF" >/dev/null

echo
echo "==> DMG background written:"
echo "    $SVG"
echo "    $PNG_1X"
echo "    $PNG_2X"
echo "    $TIFF"
