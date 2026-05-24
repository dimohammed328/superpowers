#!/usr/bin/env bash
# Smoke-test the TaskCreated guard. Requires loom to be installed and a
# temporary LOOM_DIR populated with a known task.

set -euo pipefail

HOOK="$(dirname "$0")/../../hooks/loom-task-created-guard.sh"

# Prepare a temp LOOM_DIR with a ready task
export LOOM_DIR=$(mktemp -d)
trap 'rm -rf "$LOOM_DIR"' EXIT
loom init >/dev/null
loom -y project create p --repo "x" >/dev/null
EPIC=$(loom -y epic create p --title "E" | awk '{print $NF}')
STORY=$(loom -y story create "$EPIC" --title "S" | awk '{print $NF}')
TASK=$(loom -y task create "$STORY" --title "T" | awk '{print $NF}')

# Case 1: permissive mode (no agent_type) accepts anything
out=$(echo '{"tool_input": {"subject": "some random task"}}' | "$HOOK")
[[ -z "$out" ]] && echo "PASS: permissive accepts no-prefix" || (echo "FAIL: $out"; exit 1)

# Case 2: strict mode rejects missing prefix
out=$(echo '{"agent_type": "story-executor", "tool_input": {"subject": "raw task title"}}' | "$HOOK")
echo "$out" | jq -e '.decision == "block"' >/dev/null && echo "PASS: strict blocks missing prefix" || (echo "FAIL: $out"; exit 1)

# Case 3: strict mode rejects bad qid
out=$(echo "{\"agent_type\":\"story-executor\",\"tool_input\":{\"subject\":\"[bogus:qid] x\"}}" | "$HOOK")
echo "$out" | jq -e '.decision == "block"' >/dev/null && echo "PASS: strict blocks unresolved qid" || (echo "FAIL: $out"; exit 1)

# Case 4: strict mode accepts a real ready task
out=$(echo "{\"agent_type\":\"story-executor\",\"tool_input\":{\"subject\":\"[${TASK}] implement T\"}}" | "$HOOK")
[[ -z "$out" ]] && echo "PASS: strict accepts valid ready task" || (echo "FAIL: $out"; exit 1)

echo "ALL PASS"
