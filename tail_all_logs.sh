#!/bin/bash

echo "========================================="
echo "Tailing All Seeker Logs"
echo "========================================="
echo ""

# Define log file paths
DAEMON_OUT="/tmp/io.allsunday.seeker.launchDaemon.out.log"
DAEMON_ERR="/tmp/io.allsunday.seeker.launchDaemon.err.log"
SEEKER_LOG="/Users/feichao/Library/Application Support/seeker/seeker.log"

# Check which files exist
echo "Checking log files..."
for logfile in "$DAEMON_OUT" "$DAEMON_ERR" "$SEEKER_LOG"; do
    if [ -f "$logfile" ]; then
        echo "✓ Found: $logfile"
    else
        echo "✗ Not found: $logfile (will watch for creation)"
    fi
done
echo ""
echo "Starting tail (press Ctrl+C to stop)..."
echo "========================================="
echo ""

# Use tail with -F flag to follow files even if they don't exist yet
tail -F "$DAEMON_OUT" "$DAEMON_ERR" "$SEEKER_LOG" 2>/dev/null

