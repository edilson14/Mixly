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

# Step 1: Clean and Build
echo ""
echo "📦 Step 1: Building Release..."
xcodebuild clean -scheme "$SCHEME" > /dev/null 2>&1
xcodebuild build \
    -scheme "$SCHEME" \
    -configuration "$BUILD_CONFIG" \
    -derivedDataPath ./build \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    > /dev/null 2>&1

APP_PATH="./build/Products/$BUILD_CONFIG/Mixly.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build failed: $APP_PATH not found"
    exit 1
fi

echo "✅ Build succeeded"

# Step 2: Notarization (optional, skip if no app-specific password)
echo ""
echo "🔐 Step 2: Notarization (optional)"
echo "   If you want to notarize, run:"
echo "   xcrun notarytool submit '$APP_PATH' \\"
echo "     --apple-id '$APPLE_ID' \\"
echo "     --team-id '$TEAM_ID' \\"
echo "     --wait"
echo ""

# Step 3: Create DMG
echo "📀 Step 3: Creating DMG..."
DMG_STAGING="/tmp/mixly_dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

cp -r "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Create DMG
hdiutil create \
    -volname "Mixly" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    "Mixly.dmg" \
    > /dev/null 2>&1

# Calculate size
DMG_SIZE=$(du -h "Mixly.dmg" | cut -f1)
echo "✅ DMG created: Mixly.dmg ($DMG_SIZE)"

# Cleanup
rm -rf "$DMG_STAGING"

echo ""
echo "✨ Distribution package ready!"
echo ""
echo "📊 Summary:"
echo "   • App: $APP_PATH"
echo "   • DMG: ./Mixly.dmg"
echo "   • Bundle ID: sound.Mixly"
echo "   • Team ID: $TEAM_ID"
echo ""
echo "📤 Next: Share ./Mixly.dmg or upload to your distribution point"
