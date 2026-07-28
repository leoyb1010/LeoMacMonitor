#!/usr/bin/env bash
#
#  File:      build-app.sh
#  Created:   2026-06-12
#  Updated:   2026-07-21
#  Developer: Leo Yuan
#  Overview:  Builds a local LeoMac monitor app from the SwiftPM executable.
#  Notes:     This is for development/local install. It does not notarize or create
#             a DMG; use scripts/package.sh for Developer ID distribution.
#             Embeds Sparkle.framework (ad-hoc signed) so the bundle actually launches —
#             the SPM binary links @rpath/Sparkle.framework.
#
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
SOURCE_APP="LeoMacMonitor"
APP_EXECUTABLE="LeoMacMonitor"
DISPLAY_NAME="${DISPLAY_NAME:-LeoMac监控器}"
BUNDLE_ID="${BUNDLE_ID:-com.leoyuan.LeoMacMonitor}"
CONFIG="${CONFIG:-release}"
# Signing identity. Default is ad-hoc ("-") for a throwaway local install. For features gated by
# macOS Local Network / TCC privacy (the Fleet view's mDNS + HTTP), ad-hoc signatures have an
# unstable designated requirement that TCC won't track — set SIGN_ID to a Developer ID Application
# identity so the app gets a stable identity and the Local Network prompt actually appears:
#   SIGN_ID="Apple Development: leo yuan (54UB8X9C5F)" scripts/build-app.sh
SIGN_ID="${SIGN_ID:--}"
TEAM_ID="${TEAM_ID:-48H5Y3LNUK}"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
DIST="${DIST:-dist}"
APPDIR="$DIST/$DISPLAY_NAME.app"
ICON="Sources/$SOURCE_APP/Resources/AppIcon.icns"
BRAND_BADGE="Sources/$SOURCE_APP/Resources/LeoFamilyBadge.png"

echo "Building $DISPLAY_NAME ($CONFIG)..."
xcrun swift build -c "$CONFIG" --product "$SOURCE_APP"
xcrun swift build -c "$CONFIG" --product LeoMacMonitorWidget

BIN_DIR="$(xcrun swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$SOURCE_APP"
WIDGET_BIN="$BIN_DIR/LeoMacMonitorWidget"

echo "Assembling $APPDIR..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"

cp "$BIN" "$APPDIR/Contents/MacOS/$APP_EXECUTABLE"
cp "$ICON" "$APPDIR/Contents/Resources/AppIcon.icns"
[ -f "$BRAND_BADGE" ] && cp "$BRAND_BADGE" "$APPDIR/Contents/Resources/LeoFamilyBadge.png"
# SwiftUI resolves app-localized UI strings from the main bundle. SwiftPM keeps resources in a
# nested bundle, so copy localization folders to Contents/Resources as well for packaged builds.
for locale in Sources/$SOURCE_APP/Resources/*.lproj; do
  [ -d "$locale" ] && cp -R "$locale" "$APPDIR/Contents/Resources/"
done

cat > "$APPDIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_EXECUTABLE</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>$BUNDLE_ID.dashboard</string>
    <key>CFBundleURLSchemes</key><array><string>leomacmonitor</string></array>
  </dict></array>
  <key>NSLocalNetworkUsageDescription</key><string>LeoMac监控器需要发现局域网中的监控节点，以便显示其他 Mac 或 Linux 设备。</string>
  <key>NSBonjourServices</key>
  <array><string>_leomacmon._tcp</string></array>
</dict>
</plist>
PLIST

echo "Embedding WidgetKit extension..."
WIDGET_APP="$APPDIR/Contents/PlugIns/LeoMacMonitorWidget.appex"
mkdir -p "$WIDGET_APP/Contents/MacOS"
cp "$WIDGET_BIN" "$WIDGET_APP/Contents/MacOS/LeoMacMonitorWidget"
cat > "$WIDGET_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>LeoMac监控组件</string>
  <key>CFBundleDisplayName</key><string>LeoMac监控器</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID.Widget</string>
  <key>CFBundleExecutable</key><string>LeoMacMonitorWidget</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>DTPlatformName</key><string>macosx</string>
  <key>DTPlatformVersion</key><string>$SDK_VERSION</string>
  <key>DTSDKName</key><string>macosx$SDK_VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
PLIST

echo "Embedding Sparkle.framework..."
mkdir -p "$APPDIR/Contents/Frameworks"
cp -R "$BIN_DIR/Sparkle.framework" "$APPDIR/Contents/Frameworks/"
# Downloads may carry Finder/quarantine xattrs that make nested code signing fail.
xattr -cr "$APPDIR/Contents/Frameworks/Sparkle.framework"
# The SPM binary links @rpath/Sparkle.framework; point rpath at the bundle's Frameworks.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APPDIR/Contents/MacOS/$APP_EXECUTABLE" 2>/dev/null || true

# Finder metadata on copied images or the embedded extension invalidates Developer ID/development
# signatures. Clear it once across the assembled tree before signing anything inside-out.
xattr -cr "$APPDIR"

echo "Signing (identity: $SIGN_ID)..."
# The embedded extension must be signed before its containing app, with the same identity.
WIDGET_ENTITLEMENTS="$DIST/widget-entitlements.plist"
cat > "$WIDGET_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.application-identifier</key><string>$TEAM_ID.$BUNDLE_ID.Widget</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM_ID</string>
</dict></plist>
PLIST
codesign --force --sign "$SIGN_ID" --timestamp=none --entitlements "$WIDGET_ENTITLEMENTS" "$WIDGET_APP"
# Sparkle: sign nested helpers (deep -> shallow), then the framework, then the app last.
SPARKLE_FW="$APPDIR/Contents/Frameworks/Sparkle.framework"
SPV="$SPARKLE_FW/Versions/$(ls "$SPARKLE_FW/Versions" | grep -v Current | head -1)"
for nested in \
  "$SPV/XPCServices/Installer.xpc" \
  "$SPV/XPCServices/Downloader.xpc" \
  "$SPV/Autoupdate" \
  "$SPV/Updater.app"; do
  [ -e "$nested" ] && codesign --force --sign "$SIGN_ID" --timestamp=none "$nested"
done
codesign --force --sign "$SIGN_ID" --timestamp=none "$SPARKLE_FW"
codesign --force --sign "$SIGN_ID" --timestamp=none "$APPDIR"
codesign --verify --strict --verbose=2 "$APPDIR"

echo "Built $APPDIR"
echo "  Open with: open \"$APPDIR\""
