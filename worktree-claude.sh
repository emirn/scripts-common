#!/bin/bash
# worktree-claude.sh - Create git worktree and launch Claude Code
# Usage: ./worktree-claude.sh [--dir <path>] [--no-claude] "branch description"
#
# Creates a git worktree based on main/master branch with an auto-generated branch name,
# then launches Claude Code in that worktree for parallel AI development.
# Works from any branch - always bases the new worktree on main or master.
#
# Options:
#   --dir <path>    Run in specified directory instead of current directory
#   --no-claude     Only create worktree, don't launch Claude Code
#
# Examples:
#   worktree-claude.sh "fix auth bug"
#   worktree-claude.sh --dir /path/to/repo "add new feature"
#   worktree-claude.sh --no-claude "refactor database"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Command to run in the worktree (customize as needed)
# Using array syntax for proper argument handling
START_CMD=(claude --dangerously-skip-permissions)

# Generate branch name from description
# Format: 2026jan26-14-30-fix-auth-bug (stopwords filtered, up to 6 words)
generate_branch_name() {
    local msg="$1"

    # Stopwords to filter out (common filler words)
    local stopwords="for with to in on at as is the a an and or but"

    # Date: 2026jan26-14-30
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
    [ -z "$words" ] && words="worktree"

    echo "${datestamp}-${words}"
}

# Parse arguments
TARGET_DIR="."
NO_CLAUDE=false
DESCRIPTION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        --no-claude)
            NO_CLAUDE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dir <path>] [--no-claude] \"branch description\""
            echo ""
            echo "Creates a git worktree based on main/master and launches Claude Code."
            echo ""
            echo "Options:"
            echo "  --dir <path>    Run in specified directory"
            echo "  --no-claude     Only create worktree, don't launch Claude"
            echo "  -h, --help      Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 \"fix auth bug\""
            echo "  $0 --dir /path/to/repo \"add new feature\""
            echo "  $0 --no-claude \"refactor database\""
            exit 0
            ;;
        *)
            if [ -z "$DESCRIPTION" ]; then
                DESCRIPTION="$1"
            fi
            shift
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

echo -e "${BLUE}Repository: ${REPO_NAME}${NC}"

# Detect the main branch, preferring an up-to-date remote version
BASE_BRANCH=""
if git remote | grep -q '^origin$'; then
    echo -e "${BLUE}Fetching from 'origin' remote to find an up-to-date base branch...${NC}"
    git fetch origin --prune
    if git show-ref --verify --quiet "refs/remotes/origin/main"; then
        BASE_BRANCH="origin/main"
    elif git show-ref --verify --quiet "refs/remotes/origin/master"; then
        BASE_BRANCH="origin/master"
    fi
fi

# If no remote branch found, fallback to local main/master
if [ -z "$BASE_BRANCH" ]; then
    if git show-ref --verify --quiet "refs/heads/main"; then
        BASE_BRANCH="main"
    elif git show-ref --verify --quiet "refs/heads/master"; then
        BASE_BRANCH="master"
    else
        echo -e "${RED}Error: Neither 'main' nor 'master' branch found.${NC}"
        echo -e "${YELLOW}Looked for 'main'/'master' on 'origin' remote and locally.${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}Base branch: ${BASE_BRANCH}${NC}"

# Check for uncommitted changes (warn but proceed)
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}Warning: Working tree has uncommitted changes.${NC}"
    echo -e "${YELLOW}These won't affect the new worktree, but you may want to commit or stash them.${NC}"
fi

# Check if start command exists (unless --no-claude)
if [ "$NO_CLAUDE" = false ]; then
    if ! command -v "${START_CMD[0]}" &> /dev/null; then
        echo -e "${RED}Error: '${START_CMD[0]}' command not found.${NC}"
        echo -e "${YELLOW}Install Claude Code: npm install -g @anthropic-ai/claude-code${NC}"
        exit 1
    fi
fi

# Prompt for description if not provided
if [ -z "$DESCRIPTION" ]; then
    echo -n "Enter branch description: "
    read DESCRIPTION
    if [ -z "$DESCRIPTION" ]; then
        echo -e "${RED}Error: Branch description is required.${NC}"
        exit 1
    fi
fi

# Generate branch name from description
BRANCH=$(generate_branch_name "$DESCRIPTION")

# Calculate worktree path: ../<folder>-<branch>
WORKTREE_PATH="$(dirname "$REPO_ROOT")/${REPO_NAME}-${BRANCH}"

# Check if worktree path already exists
if [ -e "$WORKTREE_PATH" ]; then
    echo -e "${RED}Error: Worktree path already exists: $WORKTREE_PATH${NC}"
    echo -e "${YELLOW}Remove it or choose a different description.${NC}"
    exit 1
fi

# Create the worktree
echo -e "${GREEN}Creating worktree...${NC}"
echo -e "  Branch: ${BLUE}$BRANCH${NC}"
echo -e "  Path:   ${BLUE}$WORKTREE_PATH${NC}"

# Check if branch already exists
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo -e "${YELLOW}Branch '$BRANCH' already exists, using it...${NC}"
    git worktree add "$WORKTREE_PATH" "$BRANCH"
else
    # Create new branch with worktree from the base branch
    git worktree add -b "$BRANCH" "$WORKTREE_PATH" "$BASE_BRANCH"
fi

echo -e "${GREEN}Worktree created successfully!${NC}"
echo -e "  Path: ${BLUE}$WORKTREE_PATH${NC}"

# Initialize submodules in the new worktree
if [ -f "$WORKTREE_PATH/.gitmodules" ]; then
    echo -e "${GREEN}Initializing submodules...${NC}"
    (cd "$WORKTREE_PATH" && git submodule update --init --recursive)
fi

# Launch claude or just report success
if [ "$NO_CLAUDE" = true ]; then
    echo -e "${GREEN}Done. To enter the worktree:${NC}"
    echo -e "  cd $WORKTREE_PATH"
else
    cd "$WORKTREE_PATH" || { echo -e "${RED}Error: Cannot cd to worktree path: $WORKTREE_PATH${NC}"; exit 1; }
    echo -e "${GREEN}Ready to launch Claude Code${NC}"
    echo -e "  Working directory: ${BLUE}$(pwd)${NC}"
    echo -e "  Command: ${YELLOW}${START_CMD[*]}${NC}"
    echo ""
    echo -n "Press Enter to run, or any other key to exit: "
    read -r response
    if [ -z "$response" ]; then
        exec "${START_CMD[@]}"
    else
        echo -e "${YELLOW}Exiting without running Claude.${NC}"
        echo -e "To enter the worktree manually: cd $WORKTREE_PATH"
        exit 0
    fi
fi
