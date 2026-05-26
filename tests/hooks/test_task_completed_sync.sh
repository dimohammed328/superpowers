#!/usr/bin/env bash
set -euo pipefail
HOOK="$(cd "$(dirname "$0")/../../hooks" && pwd)/loom-task-completed-sync.sh"

export LOOM_DIR=$(mktemp -d)
trap 'rm -rf "$LOOM_DIR"' EXIT
cd "$LOOM_DIR"  # avoid creating .loom/ workspace in parent repo
loom init >/dev/null
loom -y project create p --repo x >/dev/null
EPIC=$(loom -y epic create p --title E | awk '{print $NF}')
STORY=$(loom -y story create "$EPIC" --title S | awk '{print $NF}')
TASK=$(loom -y task create "$STORY" --title T | awk '{print $NF}')

# Case 1: subject with valid prefix triggers loom complete
echo "{\"tool_input\":{\"subject\":\"[${TASK}] x\"}}" | "$HOOK"
status=$(loom show "$TASK" --json | jq -r '.frontmatter.status // .status')
[[ "$status" == "done" ]] && echo "PASS: completed via hook" || (echo "FAIL: status=${status}"; exit 1)

# Case 2: idempotent on already-done
echo "{\"tool_input\":{\"subject\":\"[${TASK}] x\"}}" | "$HOOK"  # should not error
echo "PASS: idempotent on already-done"

# Case 3: permissive without prefix is silent
echo '{"tool_input":{"subject":"no prefix"}}' | "$HOOK"
echo "PASS: permissive silent on no prefix"

# Case 4: strict without prefix blocks
out=$(echo '{"agent_type":"story-executor","tool_input":{"subject":"no prefix"}}' | "$HOOK")
echo "$out" | jq -e '.decision == "block"' >/dev/null && echo "PASS: strict blocks missing prefix" || (echo "FAIL: $out"; exit 1)

echo "ALL PASS"
