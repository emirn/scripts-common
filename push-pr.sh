#!/bin/bash
# push-pr.sh - Full PR workflow automation
# Usage: ./push-pr.sh [--dir <path>] "commit message"
#
# Creates a branch, commits all changes, pushes, creates PR, and auto-merges.
# Branch name is auto-generated from commit message: 2026jan12-16-43-first-four-words
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

# Generate branch name from commit message
# Format: 2026jan12-16-43-fix-bug-in-auth
generate_branch_name() {
    local msg="$1"

    # Date: 2026jan12-16-43
    local datestamp=$(date +%Y)$(date +%b | tr '[:upper:]' '[:lower:]')$(date +%d-%H-%M)

    # Clean message: keep only alphanumeric and spaces
    local clean_msg=$(echo "$msg" | tr -cd 'a-zA-Z0-9 ')

    # Get first 4 words, convert to lowercase, join with hyphens
    local words=$(echo "$clean_msg" | tr '[:upper:]' '[:lower:]' | awk '{for(i=1;i<=4&&i<=NF;i++) printf "%s%s", (i>1?"-":""), $i}')

    # Fallback if empty
    [ -z "$words" ] && words="update"

    echo "${datestamp}-${words}"
}

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

# Set commit message and generate branch name
MSG="${1:-Quick update}"
BRANCH=$(generate_branch_name "$MSG")

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
