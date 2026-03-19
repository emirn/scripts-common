#!/usr/bin/env bash
# Migrate article costs: rename actions and ensure "create" entry exists.
#
# Usage:
#   ./scripts-common/migrate-costs.sh <project-dir>          # dry-run (default)
#   ./scripts-common/migrate-costs.sh <project-dir> --apply   # write changes
#
# Changes per article index.json:
#   1. Rename cost actions: edit_by_user → edit, review_by_user → review
#   2. Rename applied_actions entries similarly
#   3. Prepend a "create" cost entry if the first entry isn't one
#   4. Re-derive authors from updated costs

set -euo pipefail

PROJECT_DIR="${1:?Usage: $0 <project-dir> [--apply]}"
APPLY=false
[[ "${2:-}" == "--apply" ]] && APPLY=true

DRAFTS_DIR="$PROJECT_DIR/drafts"
if [[ ! -d "$DRAFTS_DIR" ]]; then
  echo "No drafts/ directory found in $PROJECT_DIR" >&2
  exit 1
fi

COUNT=0
MODIFIED=0

while IFS= read -r INDEX_FILE; do
  COUNT=$((COUNT + 1))

  UPDATED=$(node -e "
    const fs = require('fs');
    const raw = fs.readFileSync('$INDEX_FILE', 'utf-8');
    const data = JSON.parse(raw);
    let changed = false;

    // 1. Rename cost actions
    if (Array.isArray(data.costs)) {
      for (const c of data.costs) {
        if (c.action === 'edit_by_user') { c.action = 'edit'; changed = true; }
        if (c.action === 'review_by_user') { c.action = 'review'; changed = true; }
      }
    }

    // 2. Rename applied_actions
    if (Array.isArray(data.applied_actions)) {
      data.applied_actions = data.applied_actions.map(a => {
        if (a === 'edit_by_user') { changed = true; return 'edit'; }
        if (a === 'review_by_user') { changed = true; return 'review'; }
        return a;
      });
    }

    // 3. Prepend create entry if missing
    if (Array.isArray(data.costs) && data.costs.length > 0 && data.costs[0].action !== 'create') {
      const createEntry = {
        created_at: data.created_at || new Date().toISOString(),
        action: 'create',
        cost: 0,
        words_before: 0,
        words_after: 0,
        words_delta: 0,
        words_delta_pct: 0,
        changes: 0,
        changed_by: 'system',
      };
      data.costs.unshift(createEntry);
      changed = true;
    }

    // 4. Re-derive authors from costs
    if (Array.isArray(data.costs)) {
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
    }

    console.log(JSON.stringify({ changed, data }));
  ")

  CHANGED=$(echo "$UPDATED" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).changed.toString())")

  if [[ "$CHANGED" == "true" ]]; then
    MODIFIED=$((MODIFIED + 1))
    SLUG=$(basename "$(dirname "$INDEX_FILE")")
    if $APPLY; then
      echo "$UPDATED" | node -e "
        const fs = require('fs');
        const input = JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8'));
        fs.writeFileSync('$INDEX_FILE', JSON.stringify(input.data, null, 2) + '\n');
      "
      echo "  UPDATED: $SLUG"
    else
      echo "  WOULD UPDATE: $SLUG"
    fi
  fi
done < <(find "$DRAFTS_DIR" -name "index.json" -not -path "*/_history/*" -type f)

echo ""
echo "Scanned $COUNT articles, $MODIFIED need updates."
if ! $APPLY && [[ $MODIFIED -gt 0 ]]; then
  echo "Run with --apply to write changes."
fi
