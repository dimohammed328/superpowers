#!/usr/bin/env bash
set -euo pipefail
HOOK="$(cd "$(dirname "$0")/../../hooks" && pwd)/loom-task-inprogress-sync.sh"

export LOOM_DIR=$(mktemp -d)
trap 'rm -rf "$LOOM_DIR"' EXIT
cd "$LOOM_DIR"  # avoid creating .loom/ workspace in parent repo
loom init >/dev/null
loom -y project create p --repo x >/dev/null
EPIC=$(loom -y epic create p --title E | awk '{print $NF}')
STORY=$(loom -y story create "$EPIC" --title S | awk '{print $NF}')
TASK=$(loom -y task create "$STORY" --title T | awk '{print $NF}')

# Case 1: in_progress transition with valid qid syncs to loom
echo "{\"tool_input\":{\"status\":\"in_progress\",\"subject\":\"[${TASK}] do thing\"}}" | "$HOOK"
status=$(loom show "$TASK" --json | jq -r '.frontmatter.status // .status')
[[ "$status" == "in_progress" ]] && echo "PASS: synced to in_progress" || (echo "FAIL: status=${status}"; exit 1)

# Case 2: non-in_progress status is ignored
loom -y mark-ready "$TASK" >/dev/null
echo "{\"tool_input\":{\"status\":\"pending\",\"subject\":\"[${TASK}] x\"}}" | "$HOOK"
status=$(loom show "$TASK" --json | jq -r '.frontmatter.status // .status')
[[ "$status" == "ready" ]] && echo "PASS: non-inprogress ignored" || (echo "FAIL: status=${status}"; exit 1)

# Case 3: subject without prefix is ignored
echo '{"tool_input":{"status":"in_progress","subject":"untagged"}}' | "$HOOK"
echo "PASS: untagged subject ignored (no error)"

echo "ALL PASS"
