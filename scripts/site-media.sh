#!/bin/bash
# Makes the website's looping clips (site/media) from the Debug app's off-screen snapshot runner, on a
# dated copy of the demo notebook. Nothing is drawn on the screen, and nothing is read from your own
# notebook, Keychain, pasteboard or Relay. See Demo/README.md and TESTING.md ("Clips for the website").
#
#   scripts/site-media.sh [--scenes notch-open,tasks] [--work <folder>] [--out <folder>]
#                         [--contact-sheet <file.png>] [--date YYYY-MM-DD] [--no-build]
#
# Needs Xcode (the Debug build and a small Swift helper) and ffmpeg. All the scenes take about a quarter of an
# hour; --scenes makes only those and keeps the other entries in the manifest. --out writes the clips
# somewhere other than site/media (a scratch folder, to try one scene). The frames go in a new temporary
# folder, or in --work, which must be new, empty, or a work folder this script made before: the script
# deletes inside it.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
WORK=""
BUILD=1
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --work) WORK="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --scenes|--out|--contact-sheet|--date) ARGS+=("$1" "$2"); shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
MARKER=".perch-site-media"
if [ -z "$WORK" ]; then
  WORK="$(mktemp -d -t perch-site-media)"
elif [ -e "$WORK" ] && [ ! -f "$WORK/$MARKER" ] && [ -n "$(ls -A "$WORK" 2>/dev/null)" ]; then
  echo "$WORK isn't empty and wasn't made by this script. Give a new or empty folder to --work." >&2
  exit 1
fi
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
touch "$WORK/$MARKER"
echo "Work folder: $WORK"

FFMPEG="$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)"
[ -x "$FFMPEG" ] || { echo "ffmpeg is needed (brew install ffmpeg)." >&2; exit 1; }
PATH="$(dirname "$FFMPEG"):$PATH"

APP="$REPO/.build/debug-app/Build/Products/Debug/Perch.app/Contents/MacOS/Perch"
if [ "$BUILD" = 1 ]; then
  if [ ! -x "$APP" ] || [ -n "$(find Apps Sources Config project.yml -newer "$APP" -type f -print -quit 2>/dev/null)" ]; then
    echo "Building the Debug app..."
    xcodegen generate --quiet
    xcodebuild -project Perch.xcodeproj -scheme PerchMac -configuration Debug -destination "platform=macOS,arch=arm64" \
      -derivedDataPath .build/debug-app CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
      build > "$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log" >&2; exit 1; }
  fi
fi
[ -x "$APP" ] || { echo "No Debug app at $APP. Run without --no-build." >&2; exit 1; }

COMPOSE="$WORK/compose"
if [ ! -x "$COMPOSE" ] || [ scripts/site-media/compose.swift -nt "$COMPOSE" ]; then
  swiftc -O scripts/site-media/compose.swift -o "$COMPOSE"
fi

exec /usr/bin/env python3 scripts/site-media/site_media.py --work "$WORK" --compose "$COMPOSE" ${ARGS[@]+"${ARGS[@]}"}
