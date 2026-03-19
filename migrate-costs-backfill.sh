#!/usr/bin/env bash
# Backfill costs[] for all articles and pages.
#
# Ensures every index.json has a complete costs[] audit trail:
#   1. Ensure costs[] array exists
#   2. Ensure "create" entry at position 0 with actual word count
#   3. Backfill applied_actions into costs (count-based dedup)
#   4. Normalize incomplete cost entries (missing fields)
#   5. Re-derive authors[] from costs
#
# Usage:
#   ./scripts-common/migrate-costs-backfill.sh                          # dry-run all projects
#   ./scripts-common/migrate-costs-backfill.sh --apply                   # write all
#   ./scripts-common/migrate-costs-backfill.sh --project aicw.io         # single project dry-run
#   ./scripts-common/migrate-costs-backfill.sh --project aicw.io --apply

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$REPO_DIR/blogpostgen-data/data/projects"

APPLY=false
PROJECT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=true; shift ;;
    --project) PROJECT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "$PROJECT" ]]; then
  PROJECT_DIRS=("$DATA_DIR/$PROJECT")
  if [[ ! -d "${PROJECT_DIRS[0]}" ]]; then
    echo "Project directory not found: ${PROJECT_DIRS[0]}" >&2
    exit 1
  fi
else
  PROJECT_DIRS=()
  for d in "$DATA_DIR"/*/; do
    PROJECT_DIRS+=("${d%/}")
  done
fi

TOTAL_SCANNED=0
TOTAL_MODIFIED=0

for PROJECT_DIR in "${PROJECT_DIRS[@]}"; do
  PROJECT_NAME=$(basename "$PROJECT_DIR")

  # Collect all index.json files from drafts/ and pages/
  FILES=()
  for subdir in drafts pages; do
    if [[ -d "$PROJECT_DIR/$subdir" ]]; then
      while IFS= read -r f; do
        FILES+=("$f")
      done < <(find "$PROJECT_DIR/$subdir" -name "index.json" -not -path "*/_history/*" -type f)
    fi
  done

  if [[ ${#FILES[@]} -eq 0 ]]; then
    continue
  fi

  COUNT=0
  MODIFIED=0

  for INDEX_FILE in "${FILES[@]}"; do
    COUNT=$((COUNT + 1))

    RESULT=$(node -e "
      const fs = require('fs');
      const raw = fs.readFileSync(process.argv[1], 'utf-8');
      const data = JSON.parse(raw);
      let changed = false;

      function countWords(text) {
        if (!text) return 0;
        return text.split(/\s+/).filter(Boolean).length;
      }

      // Step 1: Ensure costs[] exists
      if (!Array.isArray(data.costs)) {
        data.costs = [];
        changed = true;
      }

      // Step 2: Ensure 'create' entry at position 0
      const wordCount = countWords(data.content);
      if (data.costs.length === 0 || data.costs[0].action !== 'create') {
        const createEntry = {
          created_at: data.created_at || new Date().toISOString(),
          action: 'create',
          cost: 0,
          words_before: 0,
          words_after: wordCount,
          words_delta: wordCount,
          words_delta_pct: 0,
          changes: 0,
          changed_by: 'system',
        };
        data.costs.unshift(createEntry);
        changed = true;
      } else if (data.costs[0].action === 'create' && data.costs[0].words_after === 0 && wordCount > 0) {
        // Fix existing create entry with words_after=0
        data.costs[0].words_after = wordCount;
        data.costs[0].words_delta = wordCount;
        changed = true;
      }

      // Step 3: Backfill applied_actions into costs
      if (Array.isArray(data.applied_actions) && data.applied_actions.length > 0) {
        // Count occurrences in applied_actions
        const actionCounts = {};
        for (const a of data.applied_actions) {
          actionCounts[a] = (actionCounts[a] || 0) + 1;
        }
        // Count occurrences already in costs (skip 'create')
        const costCounts = {};
        for (const c of data.costs) {
          if (c.action === 'create') continue;
          costCounts[c.action] = (costCounts[c.action] || 0) + 1;
        }
        // Build list of actions to insert
        const toInsert = [];
        for (const [action, count] of Object.entries(actionCounts)) {
          const existing = costCounts[action] || 0;
          for (let i = 0; i < count - existing; i++) {
            toInsert.push(action);
          }
        }

        if (toInsert.length > 0) {
          const createdAt = new Date(data.created_at || data.costs[0].created_at).getTime();
          const updatedAt = new Date(data.updated_at || data.created_at || data.costs[0].created_at).getTime();
          const step = toInsert.length > 1 ? (updatedAt - createdAt) / (toInsert.length + 1) : 0;

          // Find insert position: after 'create' but before any human-authored costs
          let insertPos = 1; // after create
          const newEntries = toInsert.map((action, i) => ({
            created_at: new Date(createdAt + step * (i + 1)).toISOString(),
            action,
            cost: 0,
            words_before: 0,
            words_after: 0,
            words_delta: 0,
            words_delta_pct: 0,
            changes: 0,
            changed_by: 'ai',
          }));

          data.costs.splice(insertPos, 0, ...newEntries);
          changed = true;
        }
      }

      // Step 4: Normalize incomplete existing cost entries
      for (const c of data.costs) {
        if (!c.changed_by) {
          c.changed_by = 'ai';
          changed = true;
        }
        for (const field of ['cost', 'words_before', 'words_after', 'words_delta', 'words_delta_pct', 'changes']) {
          if (c[field] === undefined || c[field] === null) {
            c[field] = 0;
            changed = true;
          }
        }
      }

      // Step 5: Re-derive authors[]
      const map = new Map();
      for (const cost of data.costs) {
        if (!cost.changed_by || cost.changed_by === 'ai' || cost.changed_by === 'system') continue;
        const role = cost.action === 'review' ? 'reviewer' : 'author';
        const existing = map.get(cost.changed_by);
        if (!existing || cost.created_at > existing.updated_at) {
          map.set(cost.changed_by, { id: cost.changed_by, role, updated_at: cost.created_at });
        }
      }
      const derived = Array.from(map.values()).sort((a, b) => b.updated_at.localeCompare(a.updated_at));
      const prevAuthors = JSON.stringify(data.authors || []);
      if (JSON.stringify(derived) !== prevAuthors) {
        data.authors = derived;
        changed = true;
      }

      console.log(JSON.stringify({ changed, data }));
    " "$INDEX_FILE")

    CHANGED=$(echo "$RESULT" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).changed.toString())")

    if [[ "$CHANGED" == "true" ]]; then
      MODIFIED=$((MODIFIED + 1))
      # Get a readable slug from the path
      REL_PATH="${INDEX_FILE#$PROJECT_DIR/}"
      SLUG=$(dirname "$REL_PATH")
      if $APPLY; then
        echo "$RESULT" | node -e "
          const fs = require('fs');
          const input = JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8'));
          fs.writeFileSync(process.argv[1], JSON.stringify(input.data, null, 2) + '\n');
        " "$INDEX_FILE"
        echo "  UPDATED: $SLUG"
      else
        echo "  WOULD UPDATE: $SLUG"
      fi
    fi
  done

  TOTAL_SCANNED=$((TOTAL_SCANNED + COUNT))
  TOTAL_MODIFIED=$((TOTAL_MODIFIED + MODIFIED))
  echo "$PROJECT_NAME: scanned $COUNT, $MODIFIED need updates."
done

echo ""
echo "Total: scanned $TOTAL_SCANNED, $TOTAL_MODIFIED need updates."
if ! $APPLY && [[ $TOTAL_MODIFIED -gt 0 ]]; then
  echo "Run with --apply to write changes."
fi
