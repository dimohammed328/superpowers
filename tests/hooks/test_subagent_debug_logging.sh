#!/usr/bin/env bash
# Test: debug logging in loom-subagent-context-inject.sh.
#
# Verifies that when LOOM_SUBAGENT_DEBUG_LOG is set, the hook appends the
# raw SubagentStart JSON payload to the specified file, enabling field-name
# verification of live Claude Code invocations.

set -euo pipefail

HOOK="$(dirname "$0")/../../hooks/loom-subagent-context-inject.sh"

# --- Test setup ---
TMPDIR_TEST=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

payload='{"agent_type": "story-executor", "session_id": "sess-abc", "agent_id": "agent-xyz"}'

# Case 1: when LOOM_SUBAGENT_DEBUG_LOG is set, hook writes raw payload to that file
DEBUG_LOG="${TMPDIR_TEST}/subagent-debug.jsonl"
export LOOM_SUBAGENT_DEBUG_LOG="$DEBUG_LOG"
echo "$payload" | "$HOOK" >/dev/null
unset LOOM_SUBAGENT_DEBUG_LOG
if [[ ! -f "$DEBUG_LOG" ]]; then
  echo "FAIL: debug log file was not created at $DEBUG_LOG"
  exit 1
fi
logged=$(cat "$DEBUG_LOG")
if ! echo "$logged" | jq -e '.session_id == "sess-abc"' >/dev/null 2>&1; then
  echo "FAIL: debug log does not contain expected session_id; got: $logged"
  exit 1
fi
if ! echo "$logged" | jq -e '.agent_id == "agent-xyz"' >/dev/null 2>&1; then
  echo "FAIL: debug log does not contain expected agent_id; got: $logged"
  exit 1
fi
echo "PASS: debug log written when LOOM_SUBAGENT_DEBUG_LOG is set"

# Case 2: when LOOM_SUBAGENT_DEBUG_LOG is not set, hook does NOT create any debug file
MARKER_FILE="${TMPDIR_TEST}/case2-marker"
# Ensure no stray debug env var leaks in
unset LOOM_SUBAGENT_DEBUG_LOG 2>/dev/null || true
echo "$payload" | "$HOOK" >/dev/null
# There should be only the file from Case 1 in TMPDIR_TEST
file_count=$(ls "$TMPDIR_TEST" | wc -l | tr -d ' ')
if [[ "$file_count" -ne 1 ]]; then
  echo "FAIL: unexpected files in TMPDIR_TEST after unset run: $(ls "$TMPDIR_TEST")"
  exit 1
fi
echo "PASS: no debug log created when LOOM_SUBAGENT_DEBUG_LOG is unset"

# Case 3: LOOM_SUBAGENT_DEBUG_LOG works with non-matching agent_type too (permissive for diagnosis)
OTHER_LOG="${TMPDIR_TEST}/other-debug.jsonl"
non_matching='{"agent_type": "general-purpose", "session_id": "s2", "agent_id": "a2"}'
export LOOM_SUBAGENT_DEBUG_LOG="$OTHER_LOG"
echo "$non_matching" | "$HOOK" >/dev/null || true
unset LOOM_SUBAGENT_DEBUG_LOG
if [[ ! -f "$OTHER_LOG" ]]; then
  echo "FAIL: debug log file was not created for non-matching agent type"
  exit 1
fi
if ! cat "$OTHER_LOG" | jq -e '.agent_type == "general-purpose"' >/dev/null 2>&1; then
  echo "FAIL: debug log for non-matching type doesn't contain expected agent_type"
  exit 1
fi
echo "PASS: debug log written even for non-matching agent_type"

echo "ALL PASS"
