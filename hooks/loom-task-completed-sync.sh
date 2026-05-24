#!/usr/bin/env bash
# TaskCompleted hook: run `loom complete <qid>` when subject has qid prefix.
#
# Fires on TaskCompleted. Strict mode requires the qid prefix; permissive
# acts only if a prefix is present.

set -euo pipefail

input=$(cat)
agent_type=$(jq -r '.agent_type // ""' <<<"$input")
subject=$(jq -r '.tool_input.subject // .subject // .tool_response.subject // ""' <<<"$input")

strict=false
case "$agent_type" in
  story-executor|story-integrator|epic-validator|codebase-researcher)
    strict=true
    ;;
esac

qid=""
if [[ "$subject" =~ ^\[([^]]+)\][[:space:]] ]]; then
  qid="${BASH_REMATCH[1]}"
fi

if [[ -z "$qid" ]]; then
  if [[ "$strict" == "true" ]]; then
    jq -n --arg msg "TaskCompleted in strict mode requires [<qid>] subject prefix; got: ${subject}" '{
      decision: "block",
      reason: $msg
    }'
    exit 0
  fi
  exit 0  # permissive: no prefix → nothing to do
fi

# Sync to loom. `loom complete` should be idempotent (per spec §9 caveat —
# if not, this hook will surface the error on stderr; not fatal).
if ! loom complete "$qid" >/dev/null 2>&1; then
  # Already done? Treat as ok. Otherwise log.
  current=$(loom show "$qid" --json 2>/dev/null | jq -r '.frontmatter.status // .status // ""')
  if [[ "$current" != "done" ]]; then
    echo "loom-task-completed-sync: failed to complete ${qid} (current status=${current})" >&2
  fi
fi
