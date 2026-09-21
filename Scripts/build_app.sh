#!/bin/bash
# Builds Telemetree.app — a real, double-clickable app bundle instead of a
# `swift run` terminal invocation. Needed for a proper Dock icon and for
# distribution via the Homebrew cask.
#
# ponytail: ad-hoc signed only (`codesign -s -`), no Developer ID — that
# costs money and isn't needed yet. Gatekeeper will still warn on first
# open; the Homebrew cask clears that automatically (see the tap's
# Casks/telemetree.rb), same pattern as GhostBar.
#
# Packaging/AppIcon.icns (generated from Packaging/icon-source.svg via
# Packaging/icon-regen.sh) is copied in below if present.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="Telemetree.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Telemetree "$APP/Contents/MacOS/"
cp Packaging/Info.plist "$APP/Contents/"
if [ -f Packaging/AppIcon.icns ]; then
  cp Packaging/AppIcon.icns "$APP/Contents/Resources/"
fi
cp -R .build/release/Telemetree_Telemetree.bundle "$APP/Contents/Resources/"

codesign --force --deep -s - "$APP"

echo "Built $APP"
echo "Move it to /Applications, then right-click > Open the first time (unsigned build)."
