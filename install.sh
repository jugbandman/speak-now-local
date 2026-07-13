#!/usr/bin/env bash
# Build a Release copy of SpeakNowLocal, bump the build number, install it to
# /Applications (replacing any old copy), and relaunch. Run this whenever you
# want your daily-use app to pick up code changes. Keeps exactly one installed
# copy so the "3 versions in the picker" problem never comes back.
set -euo pipefail
cd "$(dirname "$0")"

PROJ="SpeakNowLocal.xcodeproj"
SCHEME="SpeakNowLocal"
APP="SpeakNowLocal.app"
DEST="/Applications/$APP"
PLIST="SpeakNowLocal/Info.plist"

# Bump build number (CFBundleVersion) so installed copies stay distinguishable.
CUR=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
NEXT=$((CUR + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT" "$PLIST"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
echo "==> Building $VERSION (build $NEXT)"

# Clean Release build into a throwaway dir, then discard it after install.
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath .install-build clean build >/dev/null

BUILT=".install-build/Build/Products/Release/$APP"

echo "==> Installing to $DEST"
osascript -e 'tell application "System Events" to quit application "SpeakNowLocal"' 2>/dev/null || true
pkill -9 -f "$APP" 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"
rm -rf .install-build

# Refresh Launch Services so Spotlight/menu see only the new copy.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST" >/dev/null 2>&1 || true

echo "==> Launching $VERSION (build $NEXT)"
open "$DEST"
echo "Done. Installed at $DEST"
