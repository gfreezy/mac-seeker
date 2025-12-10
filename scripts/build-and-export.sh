#!/bin/bash

# Build and export seeker app for CI
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
CERT_DIR="$PROJECT_ROOT/.github/certs"
KEYCHAIN_NAME="build.keychain"
KEYCHAIN_PASSWORD=""
CERT_PASSWORD="ci"
SIGN_IDENTITY="Seeker CI"

echo "🔨 Building seeker ($CONFIG)..."
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
    # Strategy: Two-pass processing - first pass identifies config blocks with main app bundle ID,
    # second pass updates MARKETING_VERSION in those blocks
    awk -v version="$MARKETING_VERSION" '
    BEGIN {
        # First pass: identify line ranges for main app config blocks
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

        # Track buildSettings block boundaries
        if (line ~ /buildSettings = \{/) {
            in_build_settings = 1
            block_start_line = line_num
            has_main_app_bundle_id = 0
        }

        # Check for main app bundle identifier
        if (in_build_settings && line ~ /PRODUCT_BUNDLE_IDENTIFIER = io\.allsunday\.seeker;/) {
            has_main_app_bundle_id = 1
        }

        # Track end of buildSettings block
        if (line ~ /^[[:space:]]*\};/ && in_build_settings) {
            block_end_line = line_num
            if (has_main_app_bundle_id) {
                block_ranges[block_count++] = block_start_line "," block_end_line
            }
            in_build_settings = 0
            has_main_app_bundle_id = 0
        }

        # Store all lines for second pass
        lines[line_num] = line
    }

    END {
        # Handle last block if needed (in case file ends without closing brace)
        if (in_build_settings && has_main_app_bundle_id) {
            block_ranges[block_count++] = block_start_line "," line_num
        }

        # Second pass: update MARKETING_VERSION in identified blocks
        for (i = 1; i <= line_num; i++) {
            # Check if this line is in any main app config block
            in_target_block = 0
            for (j = 0; j < block_count; j++) {
                split(block_ranges[j], range, ",")
                if (i >= range[1] && i <= range[2]) {
                    in_target_block = 1
                    break
                }
            }

            # Update MARKETING_VERSION if in target block
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

# Setup code signing - create temporary keychain
echo "🔐 Setting up code signing..."
security delete-keychain "$KEYCHAIN_NAME" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
security set-keychain-settings "$KEYCHAIN_NAME"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
security import "$CERT_DIR/signing.p12" -k "$KEYCHAIN_NAME" -P "$CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
# Add to search list without changing default
security list-keychains -d user -s "$KEYCHAIN_NAME" $(security list-keychains -d user | tr -d '"')

# Cleanup keychain on exit
cleanup() {
    echo ""
    echo "🧹 Cleaning up temporary keychain..."
    security delete-keychain "$KEYCHAIN_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# Verify certificate
security find-identity -v -p codesigning "$KEYCHAIN_NAME"

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
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_NAME"

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
    <string>$SIGN_IDENTITY</string>
</dict>
</plist>
EOF

# Export the app
echo ""
echo "📤 Exporting app..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    2>/dev/null || {
    # If export fails, copy app directly from archive
    echo "⚠️  Export failed, copying app from archive..."
    mkdir -p "$EXPORT_PATH"
    cp -R "$ARCHIVE_PATH/Products/Applications/seeker.app" "$EXPORT_PATH/"
}

# Re-sign the app to ensure proper signing
echo ""
echo "🔏 Re-signing app..."
codesign --force --deep --sign "$SIGN_IDENTITY" --keychain "$KEYCHAIN_NAME" "$EXPORT_PATH/seeker.app"
codesign --verify --verbose "$EXPORT_PATH/seeker.app"

# Create DMG
echo ""
echo "💿 Creating DMG..."
hdiutil create -volname "Seeker" \
    -srcfolder "$EXPORT_PATH/seeker.app" \
    -ov -format UDZO \
    "$BUILD_DIR/Seeker.dmg"

echo ""
echo "✅ Build complete!"
echo "   App location: $EXPORT_PATH/seeker.app"
echo "   DMG location: $BUILD_DIR/Seeker.dmg"
