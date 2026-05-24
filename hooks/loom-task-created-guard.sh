#!/usr/bin/env bash
# TaskCreated hook: enforce loom qid prefix on subjects in strict-mode contexts.
#
# Strict mode (agent_type matches one of our defined types):
#   - Subject MUST start with "[<qid>] "
#   - qid MUST resolve to a loom task in `ready` status
#   - Otherwise: return a hook-blocking response with a diagnostic
#
# Permissive mode (any other agent_type, e.g. main session, Explore):
#   - If a qid prefix happens to be present, soft-validate; warn to stderr if unresolved
#   - Never block

set -euo pipefail

input=$(cat)
agent_type=$(jq -r '.agent_type // ""' <<<"$input")
subject=$(jq -r '.tool_input.subject // .subject // ""' <<<"$input")

strict=false
case "$agent_type" in
  story-executor|story-integrator|epic-validator|codebase-researcher)
    strict=true
    ;;
esac

# Extract qid prefix if present: [<qid>] followed by space
qid=""
if [[ "$subject" =~ ^\[([^]]+)\][[:space:]] ]]; then
  qid="${BASH_REMATCH[1]}"
fi

# Helper: emit a hook-blocking response (used in strict mode).
deny() {
  local msg="$1"
  jq -n --arg reason "$msg" '{
    decision: "block",
    reason: $reason
  }'
  exit 0
}

# Strict mode path
if [[ "$strict" == "true" ]]; then
  if [[ -z "$qid" ]]; then
    deny "TaskCreate subject must start with [<loom-task-qid>] in strict-mode agents (agent_type=${agent_type}). Got: ${subject}"
  fi
  # Verify the qid resolves to a loom task in ready status
  if ! info=$(loom show "$qid" --json 2>/dev/null); then
    deny "TaskCreate qid '${qid}' does not resolve in loom (loom show failed)"
  fi
  type=$(echo "$info" | jq -r '.type // ""')
  status=$(echo "$info" | jq -r '.frontmatter.status // .status // ""')
  if [[ "$type" != "task" ]]; then
    deny "TaskCreate qid '${qid}' is a ${type}, not a task"
  fi
  if [[ "$status" != "ready" ]]; then
    deny "TaskCreate qid '${qid}' has status '${status}', expected 'ready'"
  fi
  exit 0  # accept
fi

# Permissive mode: soft-warn if prefix present but unresolved
if [[ -n "$qid" ]]; then
  if ! loom show "$qid" --json >/dev/null 2>&1; then
    echo "loom-task-created-guard: warning: qid '${qid}' does not resolve in loom (permissive mode; not blocking)" >&2
  fi
fi
exit 0
