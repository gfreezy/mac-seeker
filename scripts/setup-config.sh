#!/bin/bash

# Setup script to create default config for seeker
# This should be run by the user after installing the app

set -e

# Use system Application Support directory for config
CONFIG_DIR="/Library/Application Support/seeker"
CONFIG_FILE="$CONFIG_DIR/config.yml"

echo "Setting up seeker configuration..."

# Create config directory if it doesn't exist (requires sudo)
if [ ! -d "$CONFIG_DIR" ]; then
    echo "Creating config directory at $CONFIG_DIR (requires sudo)"
    sudo mkdir -p "$CONFIG_DIR"
    sudo chmod 755 "$CONFIG_DIR"
fi

# Check if config already exists
if [ -f "$CONFIG_FILE" ]; then
    echo "Config file already exists at $CONFIG_FILE"
    read -p "Do you want to overwrite it? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing config file"
        exit 0
    fi
fi

# Get the sample config from the rust-seeker submodule
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SAMPLE_CONFIG="$PROJECT_DIR/rust-seeker/sample_config.yml"

if [ -f "$SAMPLE_CONFIG" ]; then
    echo "Copying sample config to $CONFIG_FILE (requires sudo)"
    sudo cp "$SAMPLE_CONFIG" "$CONFIG_FILE"
    sudo chmod 644 "$CONFIG_FILE"
    echo "✓ Config file created successfully"
    echo ""
    echo "Please edit $CONFIG_FILE to configure your proxy settings"
else
    echo "Warning: Sample config not found at $SAMPLE_CONFIG"
    echo "Creating minimal config (requires sudo)..."

    sudo tee "$CONFIG_FILE" > /dev/null << 'EOF'
verbose: false
dns_timeout: 1s
dns_servers:
  - 114.114.114.114:53
  - 8.8.8.8:53
tun_name: utun10
tun_ip: 198.18.0.1
tun_cidr: 198.18.0.0/15
dns_start_ip: 198.18.0.10
dns_listen: 0.0.0.0:53
ping_timeout: 15s
db_path: seeker.sqlite
gateway_mode: true
probe_timeout: 1000ms
connect_timeout: 4s
read_timeout: 300s
write_timeout: 3s
max_connect_errors: 3

rules:
  - "GEOIP,CN,DIRECT"
  - "MATCH,PROXY"

servers: []
EOF

    sudo chmod 644 "$CONFIG_FILE"
    echo "✓ Minimal config file created"
    echo ""
    echo "Please edit $CONFIG_FILE to add your proxy servers (requires sudo)"
fi

echo ""
echo "Config setup complete!"
echo "Location: $CONFIG_FILE"
