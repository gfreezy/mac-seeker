#!/bin/bash

# Build script for Rust seeker
# This script is called by Xcode during the build process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building Rust seeker...${NC}"

# Get the project directory
PROJECT_DIR="${SRCROOT}"
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
