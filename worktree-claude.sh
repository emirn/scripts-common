#!/bin/bash
# worktree-claude.sh - Create git worktree and launch Claude Code
# Usage: ./worktree-claude.sh [options] "branch description"
#
# Creates a git worktree based on main/master branch with an auto-generated branch name,
# then launches Claude Code in that worktree for parallel AI development.
# Works from any branch - always bases the new worktree on main or master.
#
# Options:
#   --dir <path>       Run in specified directory instead of current directory
#   --no-claude        Only create worktree, don't launch Claude Code
#   --prompt <text>    Pass initial task to Claude (unattended, skips confirmation)
#   --print            Non-interactive batch mode (use with --prompt, adds stream-json output)
#   --cleanup          List and remove stale worktrees, then exit
#
# Examples:
#   worktree-claude.sh "fix auth bug"
#   worktree-claude.sh --dir /path/to/repo "add new feature"
#   worktree-claude.sh --no-claude "refactor database"
#   worktree-claude.sh --prompt "fix the login validation bug" "fix login"
#   worktree-claude.sh --cleanup

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Cleanup command ---
do_cleanup() {
    # Must be in a git repo
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo -e "${RED}Error: Not in a git repository${NC}"
        exit 1
    fi

    local repo_root
    repo_root=$(git rev-parse --show-toplevel)

    echo -e "${BLUE}Worktrees for $(basename "$repo_root"):${NC}"
    echo ""
    git worktree list
    echo ""

    # Get list of worktrees (excluding the main one)
    local worktrees=()
    local branches=()
    local statuses=()

    while IFS= read -r line; do
        local wt_path wt_branch
        wt_path=$(echo "$line" | awk '{print $1}')
        wt_branch=$(echo "$line" | sed -n 's/.*\[\(.*\)\].*/\1/p')

        # Skip the main worktree
        [ "$wt_path" = "$repo_root" ] && continue
        [ -z "$wt_branch" ] && continue

        worktrees+=("$wt_path")
        branches+=("$wt_branch")

        # Check if branch is merged into main
        if git branch --merged main 2>/dev/null | grep -q "^\s*${wt_branch}$"; then
            statuses+=("merged")
        else
            statuses+=("unmerged")
        fi
    done < <(git worktree list)

    if [ ${#worktrees[@]} -eq 0 ]; then
        echo -e "${GREEN}No extra worktrees found.${NC}"
        return
    fi

    echo -e "${BLUE}Extra worktrees:${NC}"
    for i in "${!worktrees[@]}"; do
        local status_color="$RED"
        [ "${statuses[$i]}" = "merged" ] && status_color="$GREEN"
        echo -e "  [$i] ${branches[$i]} (${status_color}${statuses[$i]}${NC}) — ${worktrees[$i]}"
    done
    echo ""

    echo -e "Options:"
    echo -e "  ${GREEN}[m]${NC} Remove all merged worktrees"
    echo -e "  ${YELLOW}[0-9]${NC} Remove specific worktree by number"
    echo -e "  ${RED}[q]${NC} Quit"
    echo ""
    echo -n "Choice: "
    read -r choice

    case "$choice" in
        m)
            local removed=0
            for i in "${!worktrees[@]}"; do
                if [ "${statuses[$i]}" = "merged" ]; then
                    echo -e "${GREEN}Removing: ${branches[$i]} (${worktrees[$i]})${NC}"
                    git worktree remove "${worktrees[$i]}" 2>/dev/null || \
                        git worktree remove --force "${worktrees[$i]}" 2>/dev/null || \
                        echo -e "${RED}  Failed to remove ${worktrees[$i]}${NC}"
                    git branch -d "${branches[$i]}" 2>/dev/null || true
                    removed=$((removed + 1))
                fi
            done
            if [ $removed -eq 0 ]; then
                echo -e "${YELLOW}No merged worktrees to remove.${NC}"
            else
                echo -e "${GREEN}Removed $removed merged worktree(s).${NC}"
            fi
            ;;
        [0-9]*)
            if [ "$choice" -lt "${#worktrees[@]}" ] 2>/dev/null; then
                local wt="${worktrees[$choice]}"
                local br="${branches[$choice]}"

                # Confirm before removing unmerged worktrees
                if [ "${statuses[$choice]}" = "unmerged" ]; then
                    echo -e "${RED}Warning: Branch '$br' has unmerged changes.${NC}"
                    echo -n "Remove anyway? [y/N] "
                    read -r confirm
                    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                        echo -e "${YELLOW}Skipped.${NC}"
                        return
                    fi
                fi

                echo -e "${YELLOW}Removing: $br ($wt)${NC}"
                if ! git worktree remove "$wt" 2>/dev/null; then
                    echo -e "${YELLOW}Normal remove failed (worktree may have uncommitted changes).${NC}"
                    echo -n "Force remove? [y/N] "
                    read -r force_confirm
                    if [[ "$force_confirm" =~ ^[Yy]$ ]]; then
                        git worktree remove --force "$wt" 2>/dev/null || \
                            { echo -e "${RED}Failed to remove $wt${NC}"; return; }
                    else
                        echo -e "${YELLOW}Skipped. Clean up manually: git worktree remove --force $wt${NC}"
                        return
                    fi
                fi
                git branch -d "$br" 2>/dev/null || \
                    echo -e "${YELLOW}Branch '$br' not deleted (may be unmerged). Use 'git branch -D $br' to force.${NC}"
                echo -e "${GREEN}Done.${NC}"
            else
                echo -e "${RED}Invalid selection.${NC}"
            fi
            ;;
        q|"")
            echo -e "${YELLOW}Cancelled.${NC}"
            ;;
        *)
            echo -e "${RED}Invalid selection.${NC}"
            ;;
    esac

    git worktree prune 2>/dev/null || true
}

# Parse arguments
TARGET_DIR="."
NO_CLAUDE=false
PROMPT_TEXT=""
PRINT_MODE=false
DO_CLEANUP=false
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
        --prompt)
            PROMPT_TEXT="$2"
            shift 2
            ;;
        --print)
            PRINT_MODE=true
            shift
            ;;
        --cleanup)
            DO_CLEANUP=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options] \"branch description\""
            echo ""
            echo "Creates a git worktree based on main/master and launches Claude Code."
            echo ""
            echo "Options:"
            echo "  --dir <path>       Run in specified directory"
            echo "  --no-claude        Only create worktree, don't launch Claude"
            echo "  --prompt <text>    Pass initial task to Claude (skips confirmation)"
            echo "  --print            Non-interactive batch mode (use with --prompt)"
            echo "  --cleanup          List and remove stale worktrees"
            echo "  -h, --help         Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 \"fix auth bug\""
            echo "  $0 --dir /path/to/repo \"add new feature\""
            echo "  $0 --no-claude \"refactor database\""
            echo "  $0 --prompt \"fix the login validation bug\" \"fix login\""
            echo "  $0 --cleanup"
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

# Handle --cleanup early
if [ "$DO_CLEANUP" = true ]; then
    do_cleanup
    exit 0
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

# Build START_CMD array dynamically
START_CMD=(claude --dangerously-skip-permissions)

if [ -n "$PROMPT_TEXT" ]; then
    START_CMD+=(-p "$PROMPT_TEXT")
fi

if [ "$PRINT_MODE" = true ] && [ -n "$PROMPT_TEXT" ]; then
    START_CMD+=(--output-format stream-json)
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
    read -r DESCRIPTION
    if [ -z "$DESCRIPTION" ]; then
        echo -e "${RED}Error: Branch description is required.${NC}"
        exit 1
    fi
fi

# Generate branch name from description
BRANCH=$(generate_branch_name "$DESCRIPTION")

# Calculate worktree path: ../<repo>-wt-<short-name>
SHORT=$(short_name "$DESCRIPTION" 3)
[ -z "$SHORT" ] && SHORT="worktree"
WORKTREE_PATH="$(dirname "$REPO_ROOT")/${REPO_NAME}-wt-${SHORT}"

# If that path exists, fall back to full branch name
if [ -e "$WORKTREE_PATH" ]; then
    WORKTREE_PATH="$(dirname "$REPO_ROOT")/${REPO_NAME}-${BRANCH}"
fi

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

    # If --prompt was given, launch immediately (no confirmation)
    if [ -n "$PROMPT_TEXT" ]; then
        echo -e "${GREEN}Launching Claude Code with prompt...${NC}"
        echo -e "  Working directory: ${BLUE}$(pwd)${NC}"
        echo -e "  Command: ${YELLOW}${START_CMD[*]}${NC}"
        exec "${START_CMD[@]}"
    fi

    # Interactive confirmation
    echo -e "${GREEN}Ready to launch Claude Code${NC}"
    echo -e "  Working directory: ${BLUE}$(pwd)${NC}"
    echo -e "  Command: ${YELLOW}${START_CMD[*]}${NC}"
    echo ""
    echo -e "Tip: Run ${YELLOW}/init${NC} inside Claude to set up project context."
    echo ""
    echo -e "  ${GREEN}[Enter]${NC} Launch Claude    ${YELLOW}[s]${NC} Open shell only    ${RED}[q]${NC} Quit"
    echo -n "> "
    read -r -n1 response
    echo "" # newline after single keypress

    case "$response" in
        "") # Enter key
            exec "${START_CMD[@]}"
            ;;
        s|S)
            echo -e "${GREEN}Opening shell in worktree...${NC}"
            exec "$SHELL"
            ;;
        *)
            echo -e "${YELLOW}Exiting without running Claude.${NC}"
            echo -e "To enter the worktree manually: cd $WORKTREE_PATH"
            exit 0
            ;;
    esac
fi
