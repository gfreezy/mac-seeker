#!/bin/bash
# generate-daemon-plist.sh
# Generates the launch daemon plist with the correct identifier based on build configuration.
# DAEMON_IDENTIFIER is defined in xcconfig and exposed by Xcode as an environment variable.

set -euo pipefail

if [ -z "${DAEMON_IDENTIFIER:-}" ]; then
    echo "error: DAEMON_IDENTIFIER not set. Check xcconfig files." >&2
    exit 1
fi

DEST_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Library/LaunchDaemons"
mkdir -p "$DEST_DIR"

# Remove any previously generated seeker daemon plists
rm -f "$DEST_DIR"/io.allsunday.seeker*.launchDaemon.plist

cat > "$DEST_DIR/${DAEMON_IDENTIFIER}.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${DAEMON_IDENTIFIER}</string>
	<key>BundleProgram</key>
	<string>Contents/MacOS/launchDaemon</string>
	<key>RunAtLoad</key>
	<true/>
	<key>MachServices</key>
	<dict>
		<key>${DAEMON_IDENTIFIER}</key>
		<true/>
	</dict>
	<key>StandardOutPath</key>
	<string>/tmp/${DAEMON_IDENTIFIER}.out.log</string>
	<key>StandardErrorPath</key>
	<string>/tmp/${DAEMON_IDENTIFIER}.err.log</string>
</dict>
</plist>
PLIST

echo "Generated daemon plist: ${DEST_DIR}/${DAEMON_IDENTIFIER}.plist"
