#!/bin/bash

# Build and export seeker app
# Usage: ./scripts/build-and-export.sh [release|debug]
#
# Signing modes:
#   - Default: sign with a local "Apple Development" certificate from the
#     login keychain (for local builds where you're signed into Xcode).
#   - SELF_SIGN=1: import a self-signed PKCS#12 certificate supplied through
#     SIGNING_P12_BASE64 and SIGNING_P12_PASSWORD. CI requires this fixed
#     identity. Local builds may omit it to generate a throwaway certificate.

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

# Signing mode: SELF_SIGN=1 uses a fixed or runtime-generated self-signed certificate.
SELF_SIGN="${SELF_SIGN:-0}"
SIGNING_P12_BASE64="${SIGNING_P12_BASE64:-}"
SIGNING_P12_PASSWORD="${SIGNING_P12_PASSWORD:-}"
REQUIRE_FIXED_SIGNING_CERTIFICATE="${REQUIRE_FIXED_SIGNING_CERTIFICATE:-0}"
FIXED_SIGNING_CERTIFICATE_SHA256="EE46A339367F47327F8CBFD43B7FD88AA8DDFDACE7B8F278D25D435FF9E54C10"
USING_FIXED_SIGNING_CERTIFICATE=0

# Self-sign settings (only used when SELF_SIGN=1)
KEYCHAIN_PATH="$BUILD_DIR/seeker-ci.keychain-db"
KEYCHAIN_PASSWORD="ci"
CERT_PASSWORD=""
SELF_SIGN_IDENTITY="Seeker Release"

if [ "$SELF_SIGN" = "1" ]; then
    SIGN_IDENTITY="$SELF_SIGN_IDENTITY"
    DEVELOPMENT_TEAM=""
    if { [ -n "$SIGNING_P12_BASE64" ] && [ -z "$SIGNING_P12_PASSWORD" ]; } \
        || { [ -z "$SIGNING_P12_BASE64" ] && [ -n "$SIGNING_P12_PASSWORD" ]; }; then
        echo "❌ Error: SIGNING_P12_BASE64 and SIGNING_P12_PASSWORD must be provided together."
        exit 1
    fi
    if [ -n "$SIGNING_P12_BASE64" ]; then
        USING_FIXED_SIGNING_CERTIFICATE=1
    elif [ "$REQUIRE_FIXED_SIGNING_CERTIFICATE" = "1" ]; then
        echo "❌ Error: A fixed signing certificate is required for this build."
        exit 1
    fi
else
    # Resolve the certificate to its SHA-1 identity so later codesign calls are
    # deterministic even when the keychain contains duplicate display names.
    IDENTITY_QUERY="${SIGN_IDENTITY:-Apple Development}"
    CERT_LINE=$(security find-identity -v -p codesigning | grep "$IDENTITY_QUERY" | head -1)
    if [ -z "$CERT_LINE" ]; then
        echo "❌ Error: No Apple Development certificate found."
        echo "   Please sign into Xcode with your Apple ID first, set DEVELOPMENT_TEAM,"
        echo "   or run with SELF_SIGN=1 to use a self-signed certificate."
        exit 1
    fi
    SIGN_IDENTITY=$(echo "$CERT_LINE" | awk '{print $2}')
    CERT_NAME=$(echo "$CERT_LINE" | sed 's/.*"\(.*\)".*/\1/')

    # Get Development Team from environment or auto-detect from the selected certificate.
    if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
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
    if [ "$USING_FIXED_SIGNING_CERTIFICATE" = "1" ]; then
        echo "   Signing: fixed self-signed identity ($SELF_SIGN_IDENTITY)"
    else
        echo "   Signing: throwaway self-signed identity ($SELF_SIGN_IDENTITY)"
    fi
else
    echo "   Signing: Apple Development (Team ID: $DEVELOPMENT_TEAM)"
fi
echo "   Project: $PROJECT"
echo "   Scheme: $SCHEME"
if [ -n "${MARKETING_VERSION:-}" ]; then
    echo "   Version: $MARKETING_VERSION"
fi
echo ""

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Setup code signing
if [ "$SELF_SIGN" = "1" ]; then
    CERT_DIR="$BUILD_DIR/certs"
    mkdir -p "$CERT_DIR"

    if [ "$USING_FIXED_SIGNING_CERTIFICATE" = "1" ]; then
        echo "🔐 Loading fixed self-signed code-signing certificate..."
        printf '%s' "$SIGNING_P12_BASE64" | /usr/bin/base64 -D > "$CERT_DIR/signing.p12"
        CERT_PASSWORD="$SIGNING_P12_PASSWORD"
    else
        echo "🔐 Generating throwaway self-signed code-signing certificate..."
        CERT_PASSWORD="ci"

        # OpenSSL config for a code-signing certificate
        cat > "$CERT_DIR/cert.conf" << 'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = Seeker Release
O = Seeker
OU = Code Signing

[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
EOF

        # Generate key + self-signed cert, then bundle into a p12.
        openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
            -keyout "$CERT_DIR/signing.key" \
            -out "$CERT_DIR/signing.crt" \
            -config "$CERT_DIR/cert.conf" 2>/dev/null
        # OpenSSL 3.x exports PKCS12 with modern algorithms (AES-256 / SHA-256 MAC)
        # that macOS `security import` cannot read. Use -legacy when available.
        PKCS12_LEGACY=""
        if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
            PKCS12_LEGACY="-legacy"
        fi
        openssl pkcs12 -export $PKCS12_LEGACY \
            -inkey "$CERT_DIR/signing.key" \
            -in "$CERT_DIR/signing.crt" \
            -out "$CERT_DIR/signing.p12" \
            -passout pass:"$CERT_PASSWORD" \
            -name "$SELF_SIGN_IDENTITY"
    fi

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

    if [ "$USING_FIXED_SIGNING_CERTIFICATE" = "1" ]; then
        ACTUAL_SIGNING_CERTIFICATE_SHA256=$(security find-certificate \
            -c "$SELF_SIGN_IDENTITY" -p "$KEYCHAIN_PATH" \
            | openssl x509 -noout -fingerprint -sha256 \
            | cut -d= -f2 | tr -d ':')
        if [ "$ACTUAL_SIGNING_CERTIFICATE_SHA256" != "$FIXED_SIGNING_CERTIFICATE_SHA256" ]; then
            echo "❌ Error: The imported signing certificate does not match the pinned identity."
            exit 1
        fi
        echo "   Certificate SHA-256: $ACTUAL_SIGNING_CERTIFICATE_SHA256"
    fi

    # Cleanup keychain and generated key material on exit
    cleanup() {
        echo ""
        echo "🧹 Cleaning up temporary keychain and certificate material..."
        security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
        rm -rf "$CERT_DIR"
    }
    trap cleanup EXIT

    security find-certificate -c "$SELF_SIGN_IDENTITY" -p "$KEYCHAIN_PATH" \
        | openssl x509 -noout -subject
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

# Version overrides are passed directly to Xcode. The project file remains
# untouched, so tag builds cannot accidentally commit generated version edits.
VERSION_BUILD_SETTINGS=()
if [ -n "${MARKETING_VERSION:-}" ]; then
    VERSION_BUILD_SETTINGS+=(MARKETING_VERSION="$MARKETING_VERSION")
fi
if [ -n "${CURRENT_PROJECT_VERSION:-}" ]; then
    VERSION_BUILD_SETTINGS+=(CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION")
fi

# Archive the app
echo ""
echo "📦 Creating archive..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -destination "generic/platform=macOS" \
    "${CODE_SIGN_SETTINGS[@]}" \
    "${VERSION_BUILD_SETTINGS[@]}"

# Export the app (copy directly from archive, exportArchive often fails for development signing)
echo ""
echo "📤 Exporting app..."
mkdir -p "$EXPORT_PATH"
ditto "$ARCHIVE_PATH/Products/Applications/seeker.app" "$EXPORT_PATH/seeker.app"

# Xcode's Archive action re-signs Sparkle.framework but leaves Sparkle's nested
# helpers ad-hoc signed. With Hardened Runtime enabled, that prevents a
# certificate-signed host app from loading Sparkle. Sign the helpers explicitly
# from the inside out as recommended by Sparkle, then refresh only the enclosing
# framework and app signatures. Do not use --deep because the helpers have
# distinct signing requirements.
SPARKLE_FRAMEWORK="$EXPORT_PATH/seeker.app/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    echo ""
    echo "🔏 Signing Sparkle helpers..."
    CODESIGN_KEYCHAIN_ARGS=()
    if [ "$SELF_SIGN" = "1" ]; then
        CODESIGN_KEYCHAIN_ARGS+=(--keychain "$KEYCHAIN_PATH")
    fi
    SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/B"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none \
        "${CODESIGN_KEYCHAIN_ARGS[@]}" \
        "$SPARKLE_VERSION/XPCServices/Installer.xpc"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none \
        --preserve-metadata=entitlements \
        "${CODESIGN_KEYCHAIN_ARGS[@]}" \
        "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none \
        "${CODESIGN_KEYCHAIN_ARGS[@]}" \
        "$SPARKLE_VERSION/Autoupdate"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none \
        "${CODESIGN_KEYCHAIN_ARGS[@]}" \
        "$SPARKLE_VERSION/Updater.app"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none \
        "${CODESIGN_KEYCHAIN_ARGS[@]}" \
        "$SPARKLE_FRAMEWORK"
    if [ "$SELF_SIGN" = "1" ]; then
        # A non-Apple self-signed certificate has no Team ID, so Hardened
        # Runtime library validation cannot establish that Sparkle belongs to
        # the same team even when both signatures use the same certificate.
        # Keep this exception scoped to self-signed release artifacts.
        SELF_SIGN_ENTITLEMENTS="$BUILD_DIR/self-sign.entitlements"
        codesign -d --entitlements :- "$EXPORT_PATH/seeker.app" \
            > "$SELF_SIGN_ENTITLEMENTS" 2>/dev/null
        /usr/libexec/PlistBuddy \
            -c "Add :com.apple.security.cs.disable-library-validation bool true" \
            "$SELF_SIGN_ENTITLEMENTS"
        codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none \
            --entitlements "$SELF_SIGN_ENTITLEMENTS" \
            "${CODESIGN_KEYCHAIN_ARGS[@]}" \
            "$EXPORT_PATH/seeker.app"
    else
        codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none \
            --preserve-metadata=entitlements \
            "$EXPORT_PATH/seeker.app"
    fi
fi

# Fail the release before packaging when the archive version and tag disagree.
APP_INFO_PLIST="$EXPORT_PATH/seeker.app/Contents/Info.plist"
APP_MARKETING_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_INFO_PLIST")
APP_BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_INFO_PLIST")
if [ -n "${MARKETING_VERSION:-}" ] && [ "$APP_MARKETING_VERSION" != "$MARKETING_VERSION" ]; then
    echo "❌ Error: CFBundleShortVersionString is $APP_MARKETING_VERSION; expected $MARKETING_VERSION."
    exit 1
fi
if [ -n "${CURRENT_PROJECT_VERSION:-}" ] && [ "$APP_BUILD_VERSION" != "$CURRENT_PROJECT_VERSION" ]; then
    echo "❌ Error: CFBundleVersion is $APP_BUILD_VERSION; expected $CURRENT_PROJECT_VERSION."
    exit 1
fi
echo "   App version: $APP_MARKETING_VERSION ($APP_BUILD_VERSION)"

# Verify signing
echo ""
echo "🔏 Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$EXPORT_PATH/seeker.app"

# Create DMG with Applications shortcut
echo ""
echo "💿 Creating DMG..."
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
ditto "$EXPORT_PATH/seeker.app" "$DMG_STAGING/seeker.app"
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
