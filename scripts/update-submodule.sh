#!/bin/bash

# Update rust-seeker submodule and commit the change
# Usage: ./scripts/update-submodule.sh [commit-message]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "📦 Updating rust-seeker submodule..."

# Fetch latest changes in submodule
cd rust-seeker
git fetch origin
OLD_COMMIT=$(git rev-parse HEAD)
git checkout master
git pull origin master
NEW_COMMIT=$(git rev-parse HEAD)
cd ..

# Check if there are changes
if [ "$OLD_COMMIT" = "$NEW_COMMIT" ]; then
    echo "✅ Submodule already up to date at $NEW_COMMIT"
    exit 0
fi

echo "📝 Submodule updated: $OLD_COMMIT -> $NEW_COMMIT"

# Get short commit info for commit message
SHORT_OLD=$(echo "$OLD_COMMIT" | cut -c1-7)
SHORT_NEW=$(echo "$NEW_COMMIT" | cut -c1-7)
COMMIT_MSG="${1:-Update rust-seeker submodule ($SHORT_OLD -> $SHORT_NEW)}"

# Stage and commit
git add rust-seeker
git commit -m "$COMMIT_MSG"

echo "✅ Committed: $COMMIT_MSG"
echo ""
echo "Run 'git push' to push the changes to remote."
