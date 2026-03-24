#!/bin/bash
# push-pr.sh - Full PR workflow automation
#
# Creates a branch, commits changes, pushes, creates PR, and merges.
# Branch name is auto-generated from commit message.
# Works from any git repo (main repo or submodule).
#
# USAGE:
#   ./push-pr.sh --all "commit message"                  # stage everything
#   ./push-pr.sh -a "commit message"                     # shorthand for --all
#   ./push-pr.sh --files path1 path2 "commit message"    # stage specific files (space-separated)
#   ./push-pr.sh --files "path1,path2" "commit message"  # stage specific files (comma-separated)
#   ./push-pr.sh "commit message"                        # shows status + usage hint, then exits
#
# OPTIONS:
#   --all, -a           Stage all changes (explicit opt-in)
#   --files <paths>...  Stage only these files/dirs. Supports:
#                          Space-separated: --files src/a.ts src/b.ts "msg"
#                          Comma-separated: --files "src/a.ts,src/b.ts" "msg"
#                          Mixed: --files "src/a.ts,src/b.ts" src/c.ts "msg"
#   --dir <path>        Run in specified directory (e.g., a submodule)
#   --no-wait           Skip polling for merge completion

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

show_usage() {
    echo -e "${BOLD}Usage:${NC}"
    echo "  ./push-pr.sh --all \"commit message\"                  # stage everything"
    echo "  ./push-pr.sh -a \"commit message\"                     # shorthand"
    echo "  ./push-pr.sh --files path1 path2 \"commit message\"    # specific files"
    echo "  ./push-pr.sh --files \"path1,path2\" \"commit message\"  # comma-separated"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --all, -a           Stage all changes"
    echo "  --files <paths>...  Stage only specified files/dirs"
    echo "  --dir <path>        Run in a different directory"
    echo "  --no-wait           Skip merge polling"
}

notify_merge_failure() {
    local pr_url="$1"
    local repo="$2"
    echo ""
    echo -e "${RED}${BOLD}====================================================${NC}"
    echo -e "${RED}${BOLD}  MERGE FAILED - NEEDS MANUAL INTERVENTION${NC}"
    echo -e "${RED}${BOLD}  Repo: ${repo}${NC}"
    echo -e "${RED}${BOLD}  PR:   ${pr_url}${NC}"
    echo -e "${RED}${BOLD}====================================================${NC}"
    echo ""
    echo "NEEDS_MANUAL_MERGE: ${pr_url}"
    # Terminal bell
    printf '\a'
    # macOS notification
    if command -v osascript &>/dev/null; then
        osascript -e "display notification \"PR needs manual merge in ${repo}\" with title \"Merge Failed\" sound name \"Basso\"" 2>/dev/null || true
    fi
}

# Track state for cleanup
ON_FEATURE_BRANCH=false
BRANCH=""
ORIGINAL_BRANCH=""

cleanup() {
    local exit_code=$?
    if [ "$ON_FEATURE_BRANCH" = true ] && [ -n "$BRANCH" ]; then
        echo ""
        echo -e "${RED}Script interrupted/failed while on branch '$BRANCH'.${NC}"
        echo -e "${YELLOW}Returning to ${ORIGINAL_BRANCH:-main}...${NC}"
        git checkout "${ORIGINAL_BRANCH:-main}" 2>/dev/null || true
        ON_FEATURE_BRANCH=false
        echo -e "${YELLOW}Local branch '$BRANCH' kept for inspection.${NC}"
        echo -e "${YELLOW}  git branch -D $BRANCH    # force delete${NC}"
    fi
    echo -e "Branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"
}
trap cleanup EXIT INT TERM

# Handle options
TARGET_DIR="."
STAGE_FILES=()
STAGE_ALL=false
NO_WAIT=false

while [ $# -gt 1 ]; do
    case "$1" in
        --dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        --no-wait)
            NO_WAIT=true
            shift
            ;;
        --all|-a)
            STAGE_ALL=true
            shift
            ;;
        --files)
            shift
            # Collect all args until the last one (which is the commit message)
            while [ $# -gt 1 ]; do
                # Split comma-separated values
                IFS=',' read -ra PARTS <<< "$1"
                for part in "${PARTS[@]}"; do
                    # Trim whitespace
                    part="$(echo -e "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                    [ -n "$part" ] && STAGE_FILES+=("$part")
                done
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
ORIGINAL_BRANCH="$CURRENT_BRANCH"
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo -e "${RED}Error: Must be on 'main' branch. Currently on '$CURRENT_BRANCH'.${NC}"
    exit 1
fi

# Pull latest (picks up version-bump commits from CI)
echo -e "${GREEN}Pulling latest...${NC}"
git pull

# Check if there are any changes to commit
if [ -z "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}No changes to commit. Exiting.${NC}"
    exit 0
fi

# If neither --all nor --files specified, show status and exit with usage hint
if [ "$STAGE_ALL" = false ] && [ ${#STAGE_FILES[@]} -eq 0 ]; then
    echo ""
    echo -e "${BOLD}Changed files:${NC}"
    git status --short
    echo ""
    MSG="${1:-commit message}"
    echo -e "${YELLOW}Specify which files to include:${NC}"
    echo -e "  ./push-pr.sh ${GREEN}--all${NC} \"$MSG\"                           # stage everything"
    # Show first changed file as example
    FIRST_FILE=$(git status --porcelain | head -1 | sed 's/^...//')
    echo -e "  ./push-pr.sh ${GREEN}--files${NC} $FIRST_FILE \"$MSG\"  # specific files"
    echo ""
    show_usage
    exit 1
fi

# Set commit message and generate branch name
MSG="${1:-Quick update}"
BRANCH=$(generate_branch_name "$MSG")

echo -e "${GREEN}Creating branch: $BRANCH${NC}"
git checkout -b "$BRANCH"
ON_FEATURE_BRANCH=true

if [ ${#STAGE_FILES[@]} -gt 0 ]; then
    echo -e "${GREEN}Staging specified files:${NC}"
    for f in "${STAGE_FILES[@]}"; do
        echo -e "  ${f}"
    done
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

# KEY: Checkout main immediately after PR creation, before any merge attempt.
# gh pr merge operates on the remote PR - it doesn't require being on the feature branch.
# This ensures we're on main even if the script is killed during merge/polling.
echo -e "${GREEN}Returning to main before merge...${NC}"
git checkout main
ON_FEATURE_BRANCH=false

# Try direct merge first (works for repos without branch protection)
# Use explicit if/else instead of set -e to handle expected merge failures gracefully
echo -e "${GREEN}Attempting direct merge...${NC}"
if gh pr merge "$PR_URL" --squash --delete-branch 2>/dev/null; then
    echo -e "${GREEN}PR merged successfully!${NC}"
    git pull
    git branch -d "$BRANCH" 2>/dev/null || true
    echo -e "${GREEN}Done! Changes merged to main.${NC}"
else
    # Direct merge failed — try auto-merge (for repos with branch protection / required checks)
    echo -e "${YELLOW}Direct merge not available, trying auto-merge...${NC}"
    if gh pr merge "$PR_URL" --auto --squash --delete-branch 2>/dev/null; then
        echo -e "${GREEN}Auto-merge enabled on PR.${NC}"

        if [ "$NO_WAIT" = true ]; then
            echo -e "${YELLOW}--no-wait: skipping merge polling. Track progress: $PR_URL${NC}"
        else
            # Poll for merge completion (60s timeout, 5s intervals)
            echo -e "${GREEN}Waiting for merge...${NC}"
            TIMEOUT=60
            INTERVAL=5
            ELAPSED=0
            MERGED=false

            while [ $ELAPSED -lt $TIMEOUT ]; do
                sleep "$INTERVAL"
                ELAPSED=$((ELAPSED + INTERVAL))
                STATE=$(gh pr view "$PR_URL" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")

                if [ "$STATE" = "MERGED" ]; then
                    MERGED=true
                    break
                elif [ "$STATE" = "CLOSED" ]; then
                    echo -e "${RED}PR was closed without merging.${NC}"
                    echo -e "${YELLOW}Local branch '$BRANCH' kept for inspection.${NC}"
                    exit 1
                fi

                echo -e "  ${YELLOW}Still waiting... (${ELAPSED}s/${TIMEOUT}s, state: $STATE)${NC}"
            done

            if [ "$MERGED" = true ]; then
                echo -e "${GREEN}PR merged successfully!${NC}"
                git pull
                git branch -d "$BRANCH" 2>/dev/null || true
                echo -e "${GREEN}Done! Changes merged to main.${NC}"
            else
                echo -e "${YELLOW}---${NC}"
                echo -e "${YELLOW}${BOLD}PR hasn't merged yet after ${TIMEOUT}s (auto-merge is enabled).${NC}"
                echo -e "${YELLOW}Track progress: $PR_URL${NC}"
                echo "AUTO_MERGE_PENDING: ${PR_URL}"
            fi
        fi
    else
        notify_merge_failure "$PR_URL" "$REPO_NAME"
        exit 1
    fi
fi
