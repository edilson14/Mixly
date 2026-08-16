#!/bin/bash
set -e

TEAM_ID="${1:-}"
APPLE_ID="${2:-edytavares66@gmail.com}"
PROJECT_PATH="/Users/edilson14/Documents/MacMixer"
BUILD_CONFIG="Release"
SCHEME="Mixly"

echo "🎯 Mixly Build & Distribution Script"
echo "===================================="

# Check team ID
if [ -z "$TEAM_ID" ]; then
    echo "❌ Usage: ./build_and_distribute.sh TEAM_ID [APPLE_ID]"
    echo "   Example: ./build_and_distribute.sh ABC123DEF4"
    exit 1
fi

cd "$PROJECT_PATH"

# Step 1: Clean and Build (let Xcode auto-sign for development)
echo ""
echo "📦 Step 1: Building Release..."
xcodebuild clean -scheme "$SCHEME" 2>&1 | grep -E "succeed|error" || true
xcodebuild build \
    -scheme "$SCHEME" \
    -configuration "$BUILD_CONFIG" 2>&1 | grep -E "succeed|error" || true

# Find the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Mixly.app" -path "*/Release/*" -type d | head -1)

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build failed: Mixly.app not found in derived data"
    exit 1
fi

echo "✅ Build succeeded: $APP_PATH"

# Step 2: Notarization (optional, skip if no app-specific password)
echo ""
echo "🔐 Step 2: Notarization (optional)"
echo "   If you want to notarize for web distribution, run:"
echo "   xcrun notarytool submit '$APP_PATH' \\"
echo "     --apple-id '$APPLE_ID' \\"
echo "     --team-id '$TEAM_ID' \\"
echo "     --password 'your-app-password' \\"
echo "     --wait"
echo ""
echo "   Then staple:"
echo "   xcrun stapler staple '$APP_PATH'"
echo ""

# Step 3: Create DMG
echo "📀 Step 3: Creating DMG..."
DMG_STAGING="/tmp/mixly_dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

cp -r "$APP_PATH" "$DMG_STAGING/Mixly.app"
ln -s /Applications "$DMG_STAGING/Applications"

# Create DMG (in project root)
cd "$PROJECT_PATH"
hdiutil create \
    -volname "Mixly" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    Mixly.dmg 2>&1 | tail -2 || true

# Verify DMG
if [ -f "Mixly.dmg" ]; then
    DMG_SIZE=$(du -h Mixly.dmg | cut -f1)
    echo "✅ DMG created: Mixly.dmg ($DMG_SIZE)"
else
    echo "❌ DMG creation failed"
    exit 1
fi

# Cleanup
rm -rf "$DMG_STAGING"

echo ""
echo "✨ Distribution package ready!"
echo ""
echo "📊 Summary:"
echo "   • App: $APP_PATH"
echo "   • DMG: ./Mixly.dmg"
echo "   • Bundle ID: sound.Mixly"
echo ""
echo "💡 Next steps:"
echo "   1. For web distribution: Notarize the app (see Step 2 above)"
echo "   2. Share Mixly.dmg with users or upload to your server"
echo "   3. Users drag Mixly.app to Applications folder"
