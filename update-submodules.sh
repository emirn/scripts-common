#!/bin/bash
# Update all git submodules including nested ones
# Usage: ./scripts-common/update-submodules.sh [--pull]
#   --pull: Also pull latest commits for each submodule (default: just sync to recorded commits)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

echo "=== Updating Git Submodules ==="
echo "Repository: $REPO_ROOT"
echo ""

# Initialize and update all submodules recursively
echo "Initializing and syncing submodules..."
git submodule update --init --recursive

if [ "$1" == "--pull" ]; then
    echo ""
    echo "Pulling latest for each submodule..."
    git submodule foreach --recursive 'git checkout main 2>/dev/null || git checkout master 2>/dev/null || true; git pull || true'
fi

echo ""
echo "=== Submodule Status ==="
git submodule status --recursive

echo ""
echo "Done!"
