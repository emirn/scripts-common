# shared-script

Reusable shell scripts for git workflow automation. Designed to work as a git submodule across multiple projects.

## Scripts

### push-pr.sh
Full PR workflow automation - creates branch, commits, pushes, creates PR, and merges.

```bash
./push-pr.sh --all "Your commit message"                         # Stage everything (explicit)
./push-pr.sh -a "Your commit message"                            # Shorthand for --all
./push-pr.sh --files src/app.ts src/utils.ts "Fix utils import"  # Stage specific files
./push-pr.sh --files "src/app.ts,src/utils.ts" "Fix imports"     # Comma-separated paths
./push-pr.sh --dir /path/to/repo -a "Commit message"             # Run in different directory
./push-pr.sh "Some message"                                      # No flag = shows status + usage hint
```

**Options:**
- `--all`, `-a` — Stage all changes (must be explicit, no longer the default)
- `--files <paths>...` — Stage only these files/dirs. Supports space-separated, comma-separated, or mixed
- `--dir <path>` — Run in specified directory (e.g., a submodule)
- `--no-wait` — Skip polling for merge completion (recommended for automation/Claude usage)

**Requirements:**
- Must be on `main` branch
- GitHub CLI (`gh`) installed and authenticated
- Changes to commit

**What it does:**
1. Generates branch name from commit message (e.g., `2026-jan-28-150912-fix-bug-auth`)
2. Creates branch and commits all changes
3. Pushes to origin
4. Creates PR via `gh pr create`
5. Returns to `main` immediately (before merge attempt)
6. Tries direct squash merge first (instant for repos without branch protection)
7. Falls back to auto-merge if direct merge unavailable
8. Optionally polls for merge completion (skipped with `--no-wait`)

**Key design:** The script checks out `main` right after creating the PR, before attempting any merge. This ensures the repo is always on `main` even if the script is interrupted or times out.

**Failure recovery:** Traps EXIT, INT, and TERM signals. If interrupted while on the feature branch, automatically returns to `main` and prints cleanup instructions.

### worktree.sh
Creates a git worktree and launches Claude Code for parallel AI development.

Claude always runs **interactively** (no `-p` flag). The `--prompt` and `--plan` flags control what gets auto-typed into the session after Claude starts.

```bash
./worktree.sh "feature description"
./worktree.sh --no-claude "description"                    # Don't launch Claude
./worktree.sh --dir /path/to/repo "desc"                  # Run in different directory
./worktree.sh --prompt "fix the login bug" "fix login"     # Auto-type prompt after start
./worktree.sh --plan ~/.claude/plans/my-plan.md "desc"     # Copy plan + auto-type instruction
./worktree.sh --plan ~/.claude/plans/my-plan.md --tab "d"  # Plan in new iTerm2 tab
./worktree.sh --cleanup                                    # Remove stale worktrees
```

**Options:**
- `--dir <path>` — Run in specified directory
- `--no-claude` — Only create worktree, don't launch Claude
- `--prompt <text>` — Auto-type this text into Claude after it starts (in `--tab` mode; printed for copy-paste otherwise)
- `--plan <path>` — Copy plan file into worktree as `.temp-plan.md` (gitignored), auto-type instruction to implement it
- `--tab` — Open a new iTerm2 tab (named `reponame: description`), cd into worktree, launch Claude
- `--print` — Add `--output-format stream-json` to Claude command
- `--cleanup` — List all worktrees, show merged/unmerged status, interactively remove them

**What it does:**
1. Creates worktree at `../<repo>-<branch>` based on `origin/main`
2. Initializes submodules in the new worktree
3. If `--plan`: copies plan as `.temp-plan.md` and adds it to `.gitignore`
4. Launches `claude --dangerously-skip-permissions` interactively (unless `--no-claude`)
5. In `--tab` mode: sets iTerm2 tab name, cd's into worktree, auto-types prompt after 3s delay

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
./scripts-common/update-submodules.sh --pull
```
