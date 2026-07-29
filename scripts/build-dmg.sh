#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-2.2.0}"
OUTPUT_DIST="${DIST:-dist}"
APP_DIST="$(mktemp -d /tmp/leomac-release-app.XXXXXX)"
APP="$APP_DIST/LeoMac监控器.app"
DMG="$OUTPUT_DIST/LeoMacMonitor-$VERSION.dmg"
STAGE="$(mktemp -d /tmp/leomac-dmg.XXXXXX)"
trap 'rm -rf "$STAGE" "$APP_DIST"' EXIT

echo "Building LeoMac监控器 ${VERSION}…"
DIST="$APP_DIST" scripts/build-app.sh "$VERSION"

echo "Creating DMG…"
mkdir -p "$OUTPUT_DIST"
ditto "$APP" "$STAGE/LeoMac监控器.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "LeoMac监控器 $VERSION" \
  -srcfolder "$STAGE" -fs HFS+ -ov -format UDZO "$DMG" >/dev/null

(cd "$OUTPUT_DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Built $DMG"
cat "$DMG.sha256"
