#!/bin/bash
# Builds an unsigned .ipa for sideloading. No Apple Developer account, no
# signing identity, no provisioning profile — the signing service (or AltStore/
# SideStore) applies those afterwards.
#
#   ./build-ipa.sh            → build/GymLogger.ipa
#   ./build-ipa.sh ~/Desktop  → ~/Desktop/GymLogger.ipa
set -euo pipefail

cd "$(dirname "$0")"
OUT_DIR="${1:-build}"
DERIVED="$(mktemp -d)"
# Build number = commit count, so Settings › General › About on the phone (or
# the signing service's app list) tells you exactly which build is installed.
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
trap 'rm -rf "$DERIVED"' EXIT

echo "Building GymLogger (Release, unsigned, arm64 device)…"
xcodebuild \
  -project GymLogger.xcodeproj \
  -scheme GymLogger \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build > "$DERIVED/build.log" 2>&1 || { tail -40 "$DERIVED/build.log"; exit 1; }

APP="$DERIVED/Build/Products/Release-iphoneos/GymLogger.app"
[ -d "$APP" ] || { echo "No .app produced — see $DERIVED/build.log"; exit 1; }

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
STAGE="$DERIVED/stage"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"

# An .ipa is just a zip with the .app inside Payload/.
rm -f "$OUT_DIR/GymLogger.ipa"
( cd "$STAGE" && zip -qry "$OUT_DIR/GymLogger.ipa" Payload )

echo
echo "→ $OUT_DIR/GymLogger.ipa  ($(du -h "$OUT_DIR/GymLogger.ipa" | cut -f1))"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" | sed 's/^/   bundle id:  /'
/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion'  "$APP/Info.plist" | sed 's/^/   minimum iOS: /'
echo "   version:    $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")) · commit $COMMIT"
echo "   unsigned — hand this to your signing service."
