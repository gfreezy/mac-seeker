#!/bin/bash

# Build and export seeker app
# Usage: ./scripts/build-and-export.sh [release|debug]
#
# Signing modes:
#   - Default: sign with a local "Apple Development" certificate from the
#     login keychain (for local builds where you're signed into Xcode).
#   - SELF_SIGN=1: generate a throwaway self-signed code-signing certificate
#     at build time, import it into a temporary keychain, sign with it, then
#     destroy the keychain. No private key is ever committed to the repo.
#     This is what CI uses.

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

# Signing mode: SELF_SIGN=1 uses a runtime-generated self-signed certificate.
SELF_SIGN="${SELF_SIGN:-0}"

# Self-sign settings (only used when SELF_SIGN=1)
KEYCHAIN_PATH="$BUILD_DIR/seeker-ci.keychain-db"
KEYCHAIN_PASSWORD="ci"
CERT_PASSWORD="ci"
SELF_SIGN_IDENTITY="Seeker CI"

if [ "$SELF_SIGN" = "1" ]; then
    SIGN_IDENTITY="$SELF_SIGN_IDENTITY"
    DEVELOPMENT_TEAM=""
else
    SIGN_IDENTITY="Apple Development"
    # Get Development Team from environment or auto-detect from first Apple Development certificate
    if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
        # Get the first Apple Development certificate name
        CERT_NAME=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/')
        if [ -z "$CERT_NAME" ]; then
            echo "❌ Error: No Apple Development certificate found."
            echo "   Please sign into Xcode with your Apple ID first, set DEVELOPMENT_TEAM,"
            echo "   or run with SELF_SIGN=1 to use a self-signed certificate."
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
fi

echo "🔨 Building seeker ($CONFIG)..."
if [ "$SELF_SIGN" = "1" ]; then
    echo "   Signing: self-signed ($SELF_SIGN_IDENTITY, generated at build time)"
else
    echo "   Signing: Apple Development (Team ID: $DEVELOPMENT_TEAM)"
fi
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
if [ "$SELF_SIGN" = "1" ]; then
    echo "🔐 Generating self-signed code-signing certificate..."
    CERT_DIR="$BUILD_DIR/certs"
    mkdir -p "$CERT_DIR"

    # OpenSSL config for a code-signing certificate
    cat > "$CERT_DIR/cert.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = Seeker CI
O = GitHub Actions
OU = Code Signing

[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
EOF

    # Generate key + self-signed cert, then bundle into a p12
    openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
        -keyout "$CERT_DIR/signing.key" \
        -out "$CERT_DIR/signing.crt" \
        -config "$CERT_DIR/cert.conf" 2>/dev/null
    openssl pkcs12 -export \
        -inkey "$CERT_DIR/signing.key" \
        -in "$CERT_DIR/signing.crt" \
        -out "$CERT_DIR/signing.p12" \
        -passout pass:"$CERT_PASSWORD" \
        -name "$SELF_SIGN_IDENTITY"

    # Import into a temporary keychain
    echo "🔐 Importing certificate into temporary keychain..."
    security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security set-keychain-settings "$KEYCHAIN_PATH"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security import "$CERT_DIR/signing.p12" -k "$KEYCHAIN_PATH" -P "$CERT_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    # Add to search list without changing the user's default keychain
    security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | tr -d '"')

    # Cleanup keychain and generated key material on exit
    cleanup() {
        echo ""
        echo "🧹 Cleaning up temporary keychain and certificate material..."
        security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
        rm -rf "$CERT_DIR"
    }
    trap cleanup EXIT

    security find-identity -v -p codesigning "$KEYCHAIN_PATH"
else
    echo "🔐 Using local Apple Development certificate..."
    security find-identity -v -p codesigning | grep "Apple Development" | head -3
fi

# Assemble code-signing build settings
CODE_SIGN_SETTINGS=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
    CODE_SIGNING_REQUIRED=YES
    CODE_SIGNING_ALLOWED=YES
)
if [ "$SELF_SIGN" = "1" ]; then
    CODE_SIGN_SETTINGS+=(OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH")
else
    CODE_SIGN_SETTINGS+=(PROVISIONING_PROFILE_SPECIFIER="")
fi

# Archive the app
echo ""
echo "📦 Creating archive..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    "${CODE_SIGN_SETTINGS[@]}"

# Export the app (copy directly from archive, exportArchive often fails for development signing)
echo ""
echo "📤 Exporting app..."
mkdir -p "$EXPORT_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/seeker.app" "$EXPORT_PATH/"

# Re-sign with the self-signed identity to ensure the whole bundle is consistent
if [ "$SELF_SIGN" = "1" ]; then
    echo ""
    echo "🔏 Re-signing app with self-signed identity..."
    codesign --force --deep --sign "$SIGN_IDENTITY" --keychain "$KEYCHAIN_PATH" "$EXPORT_PATH/seeker.app"
fi

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
