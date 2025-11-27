#!/bin/bash

# Build and export seeker app
# Usage: ./scripts/build-and-export.sh [release|debug]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Configuration
SCHEME="seeker"
PROJECT="seeker.xcodeproj"
CONFIG="${1:-Release}"
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/seeker.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"

echo "🔨 Building seeker ($CONFIG)..."
echo "   Project: $PROJECT"
echo "   Scheme: $SCHEME"
echo ""

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Archive the app
echo "📦 Creating archive..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

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
    <string>-</string>
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

echo ""
echo "✅ Build complete!"
echo "   App location: $EXPORT_PATH/seeker.app"
echo ""

# Open the export folder
open "$EXPORT_PATH"
