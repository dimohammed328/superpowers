#!/usr/bin/env bash
# Test: no template text in injected context output.
#
# Verifies that:
# 1. The injected additionalContext contains a pre-substituted loom update command
#    with real session_id:agent_id values (not literal shell variable or angle-bracket templates).
# 2. The injected block clearly marks the assignee command as "ready to run verbatim"
#    so agents don't attempt to substitute placeholder variables.

set -euo pipefail

HOOK="$(dirname "$0")/../../scripts/loom-subagent-context-inject.sh"

payload='{"agent_type": "story-executor", "session_id": "sess-real-123", "agent_id": "agent-real-456"}'
out=$(echo "$payload" | "$HOOK")
ctx=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext')

# Case 1: no literal ${session_id} or ${agent_id} shell variable syntax in output
if echo "$ctx" | grep -qE '\$\{session_id\}|\$\{agent_id\}'; then
  echo "FAIL: literal shell variable text \${session_id} or \${agent_id} found in injected output"
  echo "Context: $ctx"
  exit 1
fi
echo "PASS: no literal shell variable syntax in output"

# Case 2: no <session_id> or <agent_id> angle-bracket template in output
if echo "$ctx" | grep -qE '<session_id>|<agent_id>|<session_id_from_context>|<agent_id_from_context>'; then
  echo "FAIL: angle-bracket template text found in injected output"
  echo "Context: $ctx"
  exit 1
fi
echo "PASS: no angle-bracket template text in output"

# Case 3: the loom update command contains the pre-substituted real values
if ! echo "$ctx" | grep -qE "loom update.*assignee sess-real-123:agent-real-456"; then
  echo "FAIL: loom update command does not contain pre-substituted session:agent values"
  echo "Context lines with 'loom': $(echo "$ctx" | grep 'loom update' || echo '(none)')"
  exit 1
fi
echo "PASS: loom update command contains pre-substituted values"

# Case 4: the injected block instructs the agent to use the command verbatim
# (must contain language like "verbatim" or "Copy it verbatim" or "exactly as shown")
if ! echo "$ctx" | grep -qiE "verbatim|copy.*command|exactly as shown|as shown below"; then
  echo "FAIL: injected context does not instruct agent to use command verbatim"
  echo "Context: $ctx"
  exit 1
fi
echo "PASS: injected context instructs agent to use command verbatim"

echo "ALL PASS"
