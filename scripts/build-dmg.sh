#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
DIST="${DIST:-dist}"
APP="$DIST/LeoMac监控器.app"
DMG="$DIST/LeoMacMonitor-$VERSION.dmg"
STAGE="$(mktemp -d /tmp/leomac-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

echo "Building LeoMac监控器 ${VERSION}…"
DIST="$DIST" scripts/build-app.sh "$VERSION"

echo "Creating DMG…"
ditto "$APP" "$STAGE/LeoMac监控器.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "LeoMac监控器 $VERSION" \
  -srcfolder "$STAGE" -fs HFS+ -ov -format UDZO "$DMG" >/dev/null

shasum -a 256 "$DMG" > "$DMG.sha256"
echo "Built $DMG"
cat "$DMG.sha256"
