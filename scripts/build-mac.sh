#!/bin/sh
# Builds Perch for this Mac, installs it in ~/Applications and opens it. Needs Xcode and xcodegen
# (brew install xcodegen).
#
#   scripts/build-mac.sh [--replace]
#
# If ~/Applications/Perch.app is another build of Perch (a different bundle identifier, such as a build
# from another copy of the source), it stops and changes nothing. --replace puts this build there instead.
set -eu
cd "$(dirname "$0")/.."
REPLACE=0
for argument in "$@"; do
  case "$argument" in
    --replace) REPLACE=1 ;;
    *) echo "Usage: scripts/build-mac.sh [--replace]" >&2; exit 2 ;;
  esac
done
DEST="$HOME/Applications/Perch.app"
identifier() { /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true; }
# Says whether this build may go where another Perch is installed, before and after building.
check_installed() {
  [ -d "$DEST" ] && [ "$REPLACE" = 0 ] || return 0
  installed="$(identifier "$DEST")"
  [ -n "$1" ] && [ "$installed" != "$1" ] || return 0
  echo "~/Applications/Perch.app is another build of Perch ($installed); this one is $1." >&2
  echo "Nothing was changed. Run scripts/build-mac.sh --replace to put this build there instead." >&2
  exit 1
}

xcodegen generate --quiet
check_installed "$(xcodebuild -project Perch.xcodeproj -scheme PerchMac -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '$1 ~ /^ *PRODUCT_BUNDLE_IDENTIFIER$/ {print $2; exit}')"
echo "Building Perch. The first build takes a few minutes; later ones are quick."
xcodebuild -project Perch.xcodeproj -scheme PerchMac -configuration Release -destination "platform=macOS,arch=arm64" \
  -derivedDataPath .build/release -allowProvisioningUpdates build 2>/dev/null \
  | awk '/^(Compiling|SwiftCompile|CompileSwift) /{n++; if (n % 25 == 0) printf "."} /error:|BUILD/{print ""; print}' || true
APP=.build/release/Build/Products/Release/Perch.app
[ -d "$APP" ] || { echo "Build failed." >&2; exit 1; }
BUILT="$(identifier "$APP")"
check_installed "$BUILT"
mkdir -p "$HOME/Applications"
# Another build's files never mix with this one's.
if [ -d "$DEST" ] && [ "$(identifier "$DEST")" != "$BUILT" ]; then rm -rf "$DEST"; fi
ditto "$APP" "$DEST"
open "$DEST"
echo "Installed to ~/Applications/Perch.app"
