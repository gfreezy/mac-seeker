#!/bin/bash

# Build script for Rust seeker
# This script is called by Xcode during the build process
# Usage: build-rust-seeker.sh [--version VERSION]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse command line arguments
VERSION=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --version|-v)
            VERSION="$2"
            shift 2
            ;;
        *)
            echo -e "${YELLOW}Unknown option: $1${NC}"
            shift
            ;;
    esac
done

# If version not provided via command line, check environment variable
if [ -z "$VERSION" ] && [ -n "${MARKETING_VERSION:-}" ]; then
    VERSION="${MARKETING_VERSION}"
    echo -e "${GREEN}Using version from environment: ${VERSION}${NC}"
fi

# Get the project directory
PROJECT_DIR="${SRCROOT}"

# Update MARKETING_VERSION if version is provided
if [ -n "$VERSION" ]; then
    echo -e "${GREEN}Updating MARKETING_VERSION to ${VERSION}...${NC}"
    PROJECT_FILE="${PROJECT_DIR}/seeker.xcodeproj/project.pbxproj"
    
    if [ ! -f "$PROJECT_FILE" ]; then
        echo -e "${RED}Error: Project file not found at ${PROJECT_FILE}${NC}"
        exit 1
    fi
    
    # Update MARKETING_VERSION for main app target (Debug and Release)
    # Strategy: Two-pass processing - first pass identifies config blocks with main app bundle ID,
    # second pass updates MARKETING_VERSION in those blocks
    awk -v version="$VERSION" '
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
    
    echo -e "${GREEN}✓ MARKETING_VERSION updated to ${VERSION}${NC}"
fi

echo -e "${GREEN}Building Rust seeker...${NC}"
RUST_PROJECT_DIR="${PROJECT_DIR}/rust-seeker"
BUILD_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/MacOS"

# Check if rust-seeker submodule exists
if [ ! -d "${RUST_PROJECT_DIR}" ]; then
    echo -e "${RED}Error: rust-seeker submodule not found at ${RUST_PROJECT_DIR}${NC}"
    echo -e "${YELLOW}Run: git submodule update --init --recursive${NC}"
    exit 1
fi

PATH=$PATH:~/.cargo/bin

# Check if cargo is installed
if ! command -v cargo &> /dev/null; then
    echo -e "${RED}Error: cargo not found. Please install Rust from https://rustup.rs${NC}"
    exit 1
fi

# Determine build mode based on Xcode configuration
if [ "${CONFIGURATION}" = "Release" ]; then
    CARGO_BUILD_MODE="release"
    CARGO_FLAGS="--release"
    RUST_TARGET_DIR="${RUST_PROJECT_DIR}/target/release"
else
    CARGO_BUILD_MODE="debug"
    CARGO_FLAGS=""
    RUST_TARGET_DIR="${RUST_PROJECT_DIR}/target/debug"
fi

echo -e "${GREEN}Building Rust seeker in ${CARGO_BUILD_MODE} mode...${NC}"

# Build the Rust project
cd "${RUST_PROJECT_DIR}"
cargo build ${CARGO_FLAGS}

# Check if build succeeded
if [ ! -f "${RUST_TARGET_DIR}/seeker" ]; then
    echo -e "${RED}Error: Rust build failed - seeker binary not found${NC}"
    exit 1
fi

# Create MacOS directory if it doesn't exist
mkdir -p "${BUILD_DIR}"

# Copy the binary to the app bundle with a different name to avoid conflicts
echo -e "${GREEN}Copying seeker binary to app bundle...${NC}"
cp "${RUST_TARGET_DIR}/seeker" "${BUILD_DIR}/seeker-proxy"

# Make it executable
chmod +x "${BUILD_DIR}/seeker-proxy"

echo -e "${GREEN}✓ Rust seeker build complete${NC}"
echo -e "${GREEN}Binary location: ${BUILD_DIR}/seeker-proxy${NC}"
