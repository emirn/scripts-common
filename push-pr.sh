#!/bin/bash
# push-pr.sh - Full PR workflow automation
# Usage: ./push-pr.sh [--dir <path>] "branch-name" "commit message"
#
# Creates a branch, commits all changes, pushes, creates PR, and auto-merges.
# Works from any git repo (main repo or submodule).
#
# Options:
#   --dir <path>  Run in specified directory (e.g., a submodule)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Handle --dir option
TARGET_DIR="."
if [ "$1" = "--dir" ]; then
    TARGET_DIR="$2"
    shift 2
fi

# Change to target directory
if [ "$TARGET_DIR" != "." ]; then
    echo -e "${YELLOW}Changing to directory: $TARGET_DIR${NC}"
    cd "$TARGET_DIR" || { echo -e "${RED}Error: Cannot cd to $TARGET_DIR${NC}"; exit 1; }
fi

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

# Get the repo root and name
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")

echo -e "${YELLOW}Working in: ${REPO_NAME}${NC}"

# Check if we're on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo -e "${RED}Error: Must be on 'main' branch. Currently on '$CURRENT_BRANCH'.${NC}"
    exit 1
fi

# Check if there are any changes to commit
if git diff --quiet && git diff --cached --quiet; then
    echo -e "${YELLOW}No changes to commit. Exiting.${NC}"
    exit 0
fi

# Set branch name and commit message
BRANCH="${1:-$(date +%Yjan%d)-update}"
MSG="${2:-Quick update}"

echo -e "${GREEN}Creating branch: $BRANCH${NC}"
git checkout -b "$BRANCH"

echo -e "${GREEN}Staging all changes and committing...${NC}"
git add .
git commit -m "$MSG"

echo -e "${GREEN}Pushing to origin...${NC}"
git push --set-upstream origin "$BRANCH"

echo -e "${GREEN}Creating PR...${NC}"
gh pr create --title "$MSG" --body "Automated PR via push-pr script" --base main

echo -e "${GREEN}Enabling auto-merge...${NC}"
gh pr merge --auto --squash --delete-branch

echo -e "${GREEN}Returning to main...${NC}"
git checkout main
git pull

echo -e "${GREEN}Done! Changes merged to main.${NC}"
