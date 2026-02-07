#!/bin/bash
# push-pr.sh - Full PR workflow automation
# Usage: ./push-pr.sh [--dir <path>] [--files <path>...] "commit message"
#
# Creates a branch, commits all changes, pushes, creates PR, and auto-merges.
# Branch name is auto-generated from commit message: 2026jan12-16-43-first-four-words
# Works from any git repo (main repo or submodule).
#
# Options:
#   --dir <path>        Run in specified directory (e.g., a submodule)
#   --files <paths>...  Only stage these files/folders (everything after --files until the last arg)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Generate branch name from commit message
# Format: 2026jan12-16-43-fix-bug-auth (stopwords filtered, up to 6 words)
generate_branch_name() {
    local msg="$1"

    # Stopwords to filter out (common filler words)
    local stopwords="for with to in on at as is the a an and or but"

    # Date: 2026jan12-16-43
    local datestamp=$(date +%Y)$(date +%b | tr '[:upper:]' '[:lower:]')$(date +%d-%H-%M)

    # Clean message: keep only alphanumeric and spaces, convert to lowercase
    local clean_msg=$(echo "$msg" | tr -cd 'a-zA-Z0-9 ' | tr '[:upper:]' '[:lower:]')

    # Filter out stopwords and get first 6 meaningful words
    local words=$(echo "$clean_msg" | awk -v stops="$stopwords" '
        BEGIN {
            n = split(stops, arr)
            for (i = 1; i <= n; i++) stopword[arr[i]] = 1
        }
        {
            count = 0
            result = ""
            for (i = 1; i <= NF && count < 6; i++) {
                if (!($i in stopword)) {
                    result = (result == "" ? $i : result "-" $i)
                    count++
                }
            }
            print result
        }
    ')

    # Fallback if empty
    [ -z "$words" ] && words="update"

    echo "${datestamp}-${words}"
}

# Handle options
TARGET_DIR="."
STAGE_FILES=()

while [ $# -gt 1 ]; do
    case "$1" in
        --dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        --files)
            shift
            # Collect all args until the last one (which is the commit message)
            while [ $# -gt 1 ]; do
                STAGE_FILES+=("$1")
                shift
            done
            ;;
        *)
            break
            ;;
    esac
done

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

# Extract repository in OWNER/REPO format from git remote URL
REMOTE_URL=$(git config --get remote.origin.url)
REPO_FULL=$(echo "$REMOTE_URL" | sed 's|.*[:/]\([^/]*\)/\([^/]*\)\.git$|\1/\2|; s|.*[:/]\([^/]*\)/\([^/]*\)$|\1/\2|')

if [ -z "$REPO_FULL" ]; then
    echo -e "${RED}Error: Could not determine repository from remote URL${NC}"
    exit 1
fi

echo -e "${YELLOW}Repository: ${REPO_FULL}${NC}"

# Check if we're on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo -e "${RED}Error: Must be on 'main' branch. Currently on '$CURRENT_BRANCH'.${NC}"
    exit 1
fi

# Check if there are any changes to commit
if [ -z "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}No changes to commit. Exiting.${NC}"
    exit 0
fi

# Set commit message and generate branch name
MSG="${1:-Quick update}"
BRANCH=$(generate_branch_name "$MSG")

echo -e "${GREEN}Creating branch: $BRANCH${NC}"
git checkout -b "$BRANCH"

if [ ${#STAGE_FILES[@]} -gt 0 ]; then
    echo -e "${GREEN}Staging specified files: ${STAGE_FILES[*]}${NC}"
    git add "${STAGE_FILES[@]}"
else
    echo -e "${GREEN}Staging all changes...${NC}"
    git add .
fi
echo -e "${GREEN}Committing...${NC}"
git commit -m "$MSG"

echo -e "${GREEN}Pushing to origin...${NC}"
git push --set-upstream origin "$BRANCH"

echo -e "${GREEN}Creating PR...${NC}"
PR_URL=$(gh pr create --repo "$REPO_FULL" --title "$MSG" --body "Automated PR via push-pr script" --base main)
echo "$PR_URL"

echo -e "${GREEN}Enabling auto-merge...${NC}"
gh pr merge "$PR_URL" --auto --squash --delete-branch

echo -e "${GREEN}Returning to main...${NC}"
git checkout main
git pull

echo -e "${GREEN}Done! Changes merged to main.${NC}"
