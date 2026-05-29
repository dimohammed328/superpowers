#!/usr/bin/env bash
# PostToolUse(TaskUpdate) hook: sync `in_progress` status to loom.
#
# Fires on every TaskUpdate. Acts only when:
#   1. The new status is "in_progress"
#   2. The task's subject carries a [<qid>] prefix that resolves
# Then runs `loom update <qid> status in_progress`.

set -euo pipefail

input=$(cat)

# Hook fires on every TaskUpdate; we only care about in_progress transitions
new_status=$(jq -r '.tool_input.status // ""' <<<"$input")
[[ "$new_status" == "in_progress" ]] || exit 0

subject=$(jq -r '.tool_input.subject // ""' <<<"$input")
# If subject isn't in tool_input, try the response (TaskUpdate may not echo subject)
if [[ -z "$subject" ]]; then
  subject=$(jq -r '.tool_response.subject // ""' <<<"$input")
fi

# Extract qid prefix
qid=""
if [[ "$subject" =~ ^\[([^]]+)\][[:space:]] ]]; then
  qid="${BASH_REMATCH[1]}"
fi
[[ -n "$qid" ]] || exit 0  # no prefix → nothing to sync

# Soft-validate: if qid doesn't resolve, exit silently (don't block).
if ! loom show "$qid" --json >/dev/null 2>&1; then
  echo "loom-task-inprogress-sync: qid '${qid}' does not resolve; skipping" >&2
  exit 0
fi

loom update "$qid" status in_progress >/dev/null || {
  echo "loom-task-inprogress-sync: failed to set status=in_progress on ${qid}" >&2
  exit 0  # never block on failure
}
