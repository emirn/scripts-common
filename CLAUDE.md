# shared-script

Reusable shell scripts for git workflow automation. Designed to work as a git submodule across multiple projects.

## Scripts

### push-pr.sh
Full PR workflow automation - creates branch, commits, pushes, creates PR, and auto-merges.

```bash
./push-pr.sh "Your commit message"
./push-pr.sh --dir /path/to/repo "Commit message"  # Run in different directory
./push-pr.sh --files src/app.ts src/utils.ts "Fix utils import"  # Stage specific files
```

**Requirements:**
- Must be on `main` branch
- GitHub CLI (`gh`) installed and authenticated
- Changes to commit

**What it does:**
1. Generates branch name from commit message (e.g., `2026jan28-15-09-fix-bug-auth`)
2. Creates branch and commits all changes
3. Pushes to origin
4. Creates PR via `gh pr create`
5. Enables auto-merge with squash
6. Polls for merge completion (60s timeout, 5s intervals)
7. Returns to main branch and cleans up local branch

**Failure recovery:** If any step fails after branch creation, a trap automatically returns to `main` and prints cleanup instructions.

### worktree-claude.sh
Creates a git worktree and launches Claude Code for parallel AI development.

```bash
./worktree-claude.sh "feature description"
./worktree-claude.sh --no-claude "description"                    # Don't launch Claude
./worktree-claude.sh --dir /path/to/repo "desc"                  # Run in different directory
./worktree-claude.sh --prompt "fix the login bug" "fix login"     # Unattended mode
./worktree-claude.sh --prompt "add tests" --print "add tests"     # Batch mode (stream-json)
./worktree-claude.sh --cleanup                                    # Remove stale worktrees
```

**Options:**
- `--dir <path>` — Run in specified directory
- `--no-claude` — Only create worktree, don't launch Claude
- `--prompt <text>` — Pass initial task to Claude (`-p` flag), skips confirmation prompt
- `--print` — Non-interactive batch mode (adds `--output-format stream-json`, use with `--prompt`)
- `--cleanup` — List all worktrees, show merged/unmerged status, interactively remove them

**What it does:**
1. Creates worktree at `../<repo>-wt-<short-name>` based on `origin/main`
2. Initializes submodules in the new worktree
3. Launches `claude --dangerously-skip-permissions` (unless `--no-claude`)

**Use case:** Run multiple Claude Code sessions in parallel on different features.

### _lib.sh
Shared functions sourced by other scripts. Contains `generate_branch_name` and `short_name`.

### update-submodules.sh
Updates all git submodules including nested ones.

```bash
./update-submodules.sh          # Sync submodules to recorded commits
./update-submodules.sh --pull   # Also pull latest commits for each submodule
```

## Installation as Submodule

```bash
git submodule add git@github.com:emirn/shared-script.git shared-script
git commit -m "Add shared-script submodule"
```

## Updating the Submodule

From the parent repo:
```bash
cd shared-script && git pull origin main && cd ..
git add shared-script
git commit -m "Update shared-script submodule"
```

Or use the script itself:
```bash
./shared-script/update-submodules.sh --pull
```
