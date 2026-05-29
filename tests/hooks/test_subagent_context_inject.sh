#!/usr/bin/env bash
# Smoke-test the subagent context injection hook.

set -euo pipefail

HOOK="$(dirname "$0")/../../scripts/loom-subagent-context-inject.sh"

# Case 1: matching agent_type returns hookSpecificOutput.additionalContext
out=$(echo '{"agent_type": "story-executor", "session_id": "S1", "agent_id": "A1"}' | "$HOOK")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("session_id: S1")' >/dev/null
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("agent_id: A1")' >/dev/null
echo "PASS: story-executor injection works"

# Case 2: non-matching agent_type returns nothing
out=$(echo '{"agent_type": "general-purpose", "session_id": "S1", "agent_id": "A1"}' | "$HOOK")
if [[ -n "$out" ]]; then
  echo "FAIL: expected no output for general-purpose; got: $out"
  exit 1
fi
echo "PASS: general-purpose is permissive (no injection)"

# Case 3: missing fields gracefully default
out=$(echo '{"agent_type": "story-executor"}' | "$HOOK")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("session_id: unknown")' >/dev/null
echo "PASS: missing fields default to 'unknown'"

echo "ALL PASS"
