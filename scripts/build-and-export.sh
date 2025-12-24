#!/bin/bash

# Build and export seeker app
# Usage: ./scripts/build-and-export.sh [release|debug]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Parse arguments
CONFIG="Release"
for arg in "$@"; do
    case $arg in
        release|Release)
            CONFIG="Release"
            ;;
        debug|Debug)
            CONFIG="Debug"
            ;;
    esac
done

# Configuration
SCHEME="seeker"
PROJECT="seeker.xcodeproj"
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/seeker.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

# Get Development Team from environment or auto-detect from first Apple Development certificate
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    # Get the first Apple Development certificate name
    CERT_NAME=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    if [ -z "$CERT_NAME" ]; then
        echo "❌ Error: No Apple Development certificate found."
        echo "   Please sign into Xcode with your Apple ID first, or set DEVELOPMENT_TEAM environment variable."
        exit 1
    fi
    # Extract Team ID (OU field) from certificate
    CERT_ID=$(echo "$CERT_NAME" | grep -oE '\([A-Z0-9]+\)$' | tr -d '()')
    DEVELOPMENT_TEAM=$(security find-certificate -c "$CERT_ID" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | grep -oE 'OU=[A-Z0-9]+' | head -1 | cut -d= -f2)
    if [ -z "$DEVELOPMENT_TEAM" ]; then
        echo "❌ Error: Could not extract Team ID from certificate."
        echo "   Please set DEVELOPMENT_TEAM environment variable manually."
        exit 1
    fi
fi

echo "🔨 Building seeker ($CONFIG)..."
echo "   Team ID: $DEVELOPMENT_TEAM"
echo "   Project: $PROJECT"
echo "   Scheme: $SCHEME"
if [ -n "${MARKETING_VERSION:-}" ]; then
    echo "   Version: $MARKETING_VERSION"
    export MARKETING_VERSION

    # Update MARKETING_VERSION in project file
    echo ""
    echo "📝 Updating MARKETING_VERSION to ${MARKETING_VERSION}..."
    PROJECT_FILE="$PROJECT_ROOT/seeker.xcodeproj/project.pbxproj"

    if [ ! -f "$PROJECT_FILE" ]; then
        echo "❌ Error: Project file not found at ${PROJECT_FILE}"
        exit 1
    fi

    # Update MARKETING_VERSION for main app target (Debug and Release)
    awk -v version="$MARKETING_VERSION" '
    BEGIN {
        in_build_settings = 0
        block_start_line = 0
        block_end_line = 0
        has_main_app_bundle_id = 0
        line_num = 0
        block_count = 0
    }

    {
        line_num++
        line = $0

        if (line ~ /buildSettings = \{/) {
            in_build_settings = 1
            block_start_line = line_num
            has_main_app_bundle_id = 0
        }

        if (in_build_settings && line ~ /PRODUCT_BUNDLE_IDENTIFIER = io\.allsunday\.seeker;/) {
            has_main_app_bundle_id = 1
        }

        if (line ~ /^[[:space:]]*\};/ && in_build_settings) {
            block_end_line = line_num
            if (has_main_app_bundle_id) {
                block_ranges[block_count++] = block_start_line "," block_end_line
            }
            in_build_settings = 0
            has_main_app_bundle_id = 0
        }

        lines[line_num] = line
    }

    END {
        if (in_build_settings && has_main_app_bundle_id) {
            block_ranges[block_count++] = block_start_line "," line_num
        }

        for (i = 1; i <= line_num; i++) {
            in_target_block = 0
            for (j = 0; j < block_count; j++) {
                split(block_ranges[j], range, ",")
                if (i >= range[1] && i <= range[2]) {
                    in_target_block = 1
                    break
                }
            }

            if (in_target_block && lines[i] ~ /^[[:space:]]*MARKETING_VERSION = .*;/) {
                sub(/MARKETING_VERSION = .*;/, "MARKETING_VERSION = " version ";", lines[i])
            }

            print lines[i]
        }
    }
    ' "$PROJECT_FILE" > "${PROJECT_FILE}.tmp" && mv "${PROJECT_FILE}.tmp" "$PROJECT_FILE"

    echo "✅ MARKETING_VERSION updated to ${MARKETING_VERSION}"
fi
echo ""

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Setup code signing
echo "🔐 Using local Apple Development certificate..."
security find-identity -v -p codesigning | grep "Apple Development" | head -3

# Archive the app
echo ""
echo "📦 Creating archive..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Apple Development" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    PROVISIONING_PROFILE_SPECIFIER=""

# Create export options plist
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Apple Development</string>
    <key>teamID</key>
    <string>$DEVELOPMENT_TEAM</string>
</dict>
</plist>
EOF

# Export the app (copy directly from archive, exportArchive often fails for development signing)
echo ""
echo "📤 Exporting app..."
mkdir -p "$EXPORT_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/seeker.app" "$EXPORT_PATH/"

# Verify signing
echo ""
echo "🔏 Verifying code signature..."
codesign --verify --verbose "$EXPORT_PATH/seeker.app"

# Create DMG with Applications shortcut
echo ""
echo "💿 Creating DMG..."
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$EXPORT_PATH/seeker.app" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "Seeker" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$BUILD_DIR/Seeker.dmg"
rm -rf "$DMG_STAGING"

echo ""
echo "✅ Build complete!"
echo "   App location: $EXPORT_PATH/seeker.app"
echo "   DMG location: $BUILD_DIR/Seeker.dmg"
