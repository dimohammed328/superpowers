#!/usr/bin/env bash
# SubagentStart hook: inject loom workflow context for our defined agent types.
#
# Reads JSON on stdin with fields { session_id, agent_id, agent_type, ... }.
# Returns JSON with hookSpecificOutput.additionalContext for matching types.
# Returns nothing (silent exit 0) for non-matching types.
#
# See docs/plans/2026-05-22-loom-backed-planning-design.md §5.2 + §6.

set -euo pipefail

input=$(cat)
agent_type=$(jq -r '.agent_type // ""' <<<"$input")

case "$agent_type" in
  story-executor|story-integrator|epic-validator|codebase-researcher)
    : # fall through to inject context
    ;;
  *)
    exit 0  # permissive — no injection for other agents
    ;;
esac

session_id=$(jq -r '.session_id // "unknown"' <<<"$input")
agent_id=$(jq -r '.agent_id // "unknown"' <<<"$input")

# The injected block tells the subagent who it is and what loom expects
# of it. Story-executor agents must self-attribute via `loom update`.
context=$(cat <<EOF
## Loom Workflow Context

- session_id: ${session_id}
- agent_id: ${agent_id}
- agent_type: ${agent_type}

If you are a **story-executor**: as your FIRST action, run
\`loom update <story-qid> assignee ${session_id}:${agent_id}\` for the
story qid passed in your prompt. This claims ownership for the audit trail.

The TaskCreated / TaskCompleted hooks are enforcing **strict mode** for
your agent_type:
- Every TaskCreate subject MUST start with \`[<loom-task-qid>] \` where the
  qid resolves to an existing ready task. Malformed task creations will
  be blocked with a diagnostic.
- TaskCompleted will automatically run \`loom complete <qid>\` for tasks
  whose subjects carry the qid prefix.

Read the story body (with \`## Validation Criteria\`) via
\`loom show <story-qid>\` and get the topological task list via
\`loom order <story-qid>\`.

If you are a **story-executor**: emit exactly one \`TaskCreate\` per task
returned by \`loom order\` — your TodoList must have one entry per child
task, never a single entry for the story qid itself. With N tasks
returned, expect N TaskCreate calls before any task work begins.
EOF
)

jq -n --arg ctx "$context" '{
  hookSpecificOutput: {
    additionalContext: $ctx
  }
}'
