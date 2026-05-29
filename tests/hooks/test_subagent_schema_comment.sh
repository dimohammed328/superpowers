#!/usr/bin/env bash
# Test: scripts/loom-subagent-context-inject.sh has schema comment, no debug logging block.
#
# Verifies that after diagnosis is complete:
# 1. The debug logging block (LOOM_SUBAGENT_DEBUG_LOG) is removed from the hook.
# 2. A comment documenting the observed SubagentStart payload field names is present.

set -euo pipefail

HOOK="$(dirname "$0")/../../scripts/loom-subagent-context-inject.sh"

if [[ ! -f "$HOOK" ]]; then
  echo "FAIL: hook not found at $HOOK"
  exit 1
fi

# Case 1: the debug logging block is removed (LOOM_SUBAGENT_DEBUG_LOG must not appear)
if grep -q 'LOOM_SUBAGENT_DEBUG_LOG' "$HOOK"; then
  echo "FAIL: hook still contains LOOM_SUBAGENT_DEBUG_LOG debug logging block"
  grep -n 'LOOM_SUBAGENT_DEBUG_LOG' "$HOOK"
  exit 1
fi
echo "PASS: debug logging block removed from hook"

# Case 2: the hook contains a comment documenting the SubagentStart payload schema
# It must mention session_id and agent_id as confirmed field names
if ! grep -q 'session_id' "$HOOK" | head -5; then
  # Use grep -c to check
  :
fi
schema_comment_count=$(grep -c 'SubagentStart.*payload\|payload.*SubagentStart\|Observed.*field\|field.*observed\|Confirmed.*field\|schema.*SubagentStart\|SubagentStart.*schema' "$HOOK" 2>/dev/null || echo 0)
if [[ "$schema_comment_count" -eq 0 ]]; then
  echo "FAIL: hook does not contain a comment documenting the SubagentStart payload schema"
  exit 1
fi
echo "PASS: hook contains SubagentStart payload schema documentation comment"

# Case 3: the hook still correctly reads session_id and agent_id fields
if ! grep -q "jq.*session_id" "$HOOK"; then
  echo "FAIL: hook no longer reads session_id from payload"
  exit 1
fi
if ! grep -q "jq.*agent_id" "$HOOK"; then
  echo "FAIL: hook no longer reads agent_id from payload"
  exit 1
fi
echo "PASS: hook still reads session_id and agent_id from payload"

# Case 4: hook still works correctly end-to-end after the change
out=$(echo '{"agent_type": "story-executor", "session_id": "S1", "agent_id": "A1"}' | "$HOOK")
if ! echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("S1:A1")' >/dev/null 2>&1; then
  echo "FAIL: hook end-to-end output is broken after change"
  echo "Output: $out"
  exit 1
fi
echo "PASS: hook end-to-end works correctly"

echo "ALL PASS"
