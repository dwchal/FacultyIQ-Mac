#!/bin/zsh
# Build FacultyIQ.app from the Swift package (release build, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/FacultyIQ.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FacultyIQ "$APP/Contents/MacOS/FacultyIQ"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built $PWD/$APP"
echo "Run it with: open $APP    (or copy to /Applications)"
