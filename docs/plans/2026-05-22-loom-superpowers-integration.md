# Loom-Superpowers Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the superpowers planning/execution skill chain to use loom as the durable backend; add `/epic` and `/story` entry skills; add four agent definitions and four hook scripts that bridge Claude Code's task system to loom.

**Architecture:** Plugin directory gains `agents/` and `hooks/` siblings to the existing `skills/`. Skill prose for brainstorming/writing-plans/executing-plans is fully replaced with loom-backed flows. Entry skills are thin shims invoking the rewritten chain with a pre-seeded mode. The orchestrator dispatches agents in parallel waves with per-story merge+validate.

**Tech Stack:** Markdown (skill prose, agent definitions), Bash + `jq` (hook scripts), Claude Code plugin manifest (JSON), the loom CLI added in Plan A.

**Repo:** `~/tech/superpowers`

**Working directory:** `~/tech/superpowers/`

**Dependency:** This plan REQUIRES Plan A (`2026-05-22-loom-cli-extensions.md`) to be merged and the new loom CLI commands available on `$PATH`. Verify with `loom --help | grep tree` before starting Task 1.

**Reference spec:** `~/tech/superpowers/docs/plans/2026-05-22-loom-backed-planning-design.md`

---

## Pre-flight (Task 0)

### Task 0: Baseline verification

- [ ] **Step 1: Confirm Plan A's loom CLI is installed**

Run: `loom tree --help && loom order --help && loom reopen --help && loom ready --help | head -20`
Expected: each command exits 0 and shows help. If any errors with "no such command", STOP and finish Plan A first.

- [ ] **Step 2: Confirm working tree clean**

Run: `cd /Users/danish/tech/superpowers && git status`
Expected: clean working tree on main.

- [ ] **Step 3: Skim the current skills that will be rewritten**

Run: `wc -l skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md skills/executing-plans/SKILL.md skills/subagent-driven-development/SKILL.md 2>/dev/null`
Expected: counts printed for context. Note that this plan **fully replaces** these files (and deletes the last one); the implementing agent should not try to preserve their existing structure.

---

## Phase 1: Plugin scaffolding (Tasks 1-2)

### Task 1: Update `.claude-plugin/plugin.json` to declare agents and hooks

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Read the current file**

Read `.claude-plugin/plugin.json`. Current content is a basic manifest with `name`, `description`, `author`, etc.

- [ ] **Step 2: Add hooks and agents declarations**

Replace the file contents with:

```json
{
  "name": "superpowers",
  "description": "Core skills library for Claude Code: TDD, debugging, collaboration patterns, and proven techniques",
  "author": {
    "name": "Jesse Vincent",
    "email": "jesse@fsck.com"
  },
  "homepage": "https://github.com/obra/superpowers",
  "repository": "https://github.com/obra/superpowers",
  "license": "MIT",
  "keywords": [
    "skills",
    "tdd",
    "debugging",
    "collaboration",
    "best-practices",
    "workflows"
  ],
  "hooks": {
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/loom-subagent-context-inject.sh"
          }
        ]
      }
    ],
    "TaskCreated": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/loom-task-created-guard.sh"
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/loom-task-completed-sync.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "TaskUpdate",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/loom-task-inprogress-sync.sh"
          }
        ]
      }
    ]
  }
}
```

**Verification caveat (per spec §6):** The `TaskCreated` / `TaskCompleted` events and the `${CLAUDE_PLUGIN_ROOT}` substitution in plugin-bundled hooks are described in the spec but the exact JSON schema and substitution syntax may need verification. The implementer should:

1. Search for example plugin manifests in the Claude Code docs (https://docs.claude.com/en/docs/claude-code/plugins.md or similar)
2. If `${CLAUDE_PLUGIN_ROOT}` is not the right substitution variable, replace it with whatever the docs use (commonly `$CLAUDE_PLUGIN_ROOT` or `${PLUGIN_DIR}`)
3. If `TaskCreated` / `TaskCompleted` are not valid event names, fall back to: `PreToolUse(TaskCreate)` and `PostToolUse(TaskUpdate)` with a stdin-side check that `tool_input.status == "completed"`. The hook script bodies already accept JSON on stdin so the fallback only changes registration here, not the scripts.

- [ ] **Step 3: Create the directories (empty for now; populated in later tasks)**

```bash
mkdir -p hooks agents
```

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json hooks agents
git commit -m "Declare agents/ and hooks/ in plugin manifest"
```

---

### Task 2: Create stub README pointers in `agents/` and `hooks/`

These help discoverability for humans and prevent the empty dirs from being lost in a stash.

**Files:**
- Create: `agents/README.md`
- Create: `hooks/README.md`

- [ ] **Step 1: Write agent README**

Create `agents/README.md`:

```markdown
# Superpowers agents

Agents in this directory are dispatched by skills via the `Agent` tool with
`subagent_type` matching the agent's `name:` frontmatter field. They are
loom-workflow-aware: see the spec at
`docs/plans/2026-05-22-loom-backed-planning-design.md` for how each fits into
the `/epic` and `/story` flows.

| Agent | Used by | Purpose |
|---|---|---|
| `codebase-researcher` | brainstorming skill | Enrich a rough idea with file/symbol context |
| `story-executor` | executing-plans skill (epic-wave orchestrator) | Single-threaded execution over a story's tasks |
| `story-integrator` | executing-plans skill | Per-story merge + validation |
| `epic-validator` | executing-plans skill | Final whole-epic validation via the `verify` skill |
```

- [ ] **Step 2: Write hooks README**

Create `hooks/README.md`:

```markdown
# Superpowers hooks

These hook scripts bridge Claude Code's task system to loom. Strict mode
(hard-enforced invariants for our defined agent types) activates when the
hook event body's `agent_type` matches one of: `story-executor`,
`story-integrator`, `epic-validator`, `codebase-researcher`. Otherwise
hooks operate in permissive mode (no blocks; sync only when a loom qid
prefix is already present).

See `docs/plans/2026-05-22-loom-backed-planning-design.md` §5.2 for the
full behavior matrix.

| Script | Event | Strict mode |
|---|---|---|
| `loom-subagent-context-inject.sh` | SubagentStart | Inject loom workflow context block |
| `loom-task-created-guard.sh` | TaskCreated | Require `[<qid>] ` prefix |
| `loom-task-inprogress-sync.sh` | PostToolUse(TaskUpdate, status=in_progress) | Sync `loom update <qid> status in_progress` |
| `loom-task-completed-sync.sh` | TaskCompleted | Require prefix; `loom complete <qid>` |
```

- [ ] **Step 3: Commit**

```bash
git add agents/README.md hooks/README.md
git commit -m "Add README pointers for agents/ and hooks/"
```

---

## Phase 2: Hook scripts (Tasks 3-6)

Each hook script reads JSON on stdin, inspects `agent_type` to choose strict vs permissive, calls `loom` as needed, and returns JSON or exits 0. All scripts must be `chmod +x` after creation.

### Task 3: `hooks/loom-subagent-context-inject.sh`

**Files:**
- Create: `hooks/loom-subagent-context-inject.sh`
- Create: `tests/hooks/test_subagent_context_inject.sh` (smoke test)

- [ ] **Step 1: Write the script**

Create `hooks/loom-subagent-context-inject.sh`:

```bash
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

Use \`loom show <story-qid>\` and \`loom order <story-qid>\` to learn the
story body (with \`## Validation Criteria\`) and the topological task order.
EOF
)

jq -n --arg ctx "$context" '{
  hookSpecificOutput: {
    additionalContext: $ctx
  }
}'
```

- [ ] **Step 2: Make executable**

```bash
chmod +x hooks/loom-subagent-context-inject.sh
```

- [ ] **Step 3: Create the smoke test**

Create `tests/hooks/test_subagent_context_inject.sh`:

```bash
#!/usr/bin/env bash
# Smoke-test the subagent context injection hook.

set -euo pipefail

HOOK="$(dirname "$0")/../../hooks/loom-subagent-context-inject.sh"

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
```

- [ ] **Step 4: Run the smoke test**

```bash
chmod +x tests/hooks/test_subagent_context_inject.sh
mkdir -p tests/hooks
bash tests/hooks/test_subagent_context_inject.sh
```
Expected: prints `PASS` lines and `ALL PASS`. If `jq` is not installed, install it via `brew install jq` first.

- [ ] **Step 5: Commit**

```bash
git add hooks/loom-subagent-context-inject.sh tests/hooks/test_subagent_context_inject.sh
git commit -m "hook: SubagentStart injects loom workflow context"
```

---

### Task 4: `hooks/loom-task-created-guard.sh`

**Files:**
- Create: `hooks/loom-task-created-guard.sh`
- Create: `tests/hooks/test_task_created_guard.sh`

- [ ] **Step 1: Write the script**

Create `hooks/loom-task-created-guard.sh`:

```bash
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
  status=$(echo "$info" | jq -r '.status // ""')
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
```

- [ ] **Step 2: Make executable and create smoke test**

Create `tests/hooks/test_task_created_guard.sh`:

```bash
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
```

- [ ] **Step 3: Make executable and run**

```bash
chmod +x hooks/loom-task-created-guard.sh tests/hooks/test_task_created_guard.sh
bash tests/hooks/test_task_created_guard.sh
```
Expected: 4 `PASS` lines + `ALL PASS`.

- [ ] **Step 4: Commit**

```bash
git add hooks/loom-task-created-guard.sh tests/hooks/test_task_created_guard.sh
git commit -m "hook: TaskCreated guards loom qid prefix in strict mode"
```

---

### Task 5: `hooks/loom-task-inprogress-sync.sh`

**Files:**
- Create: `hooks/loom-task-inprogress-sync.sh`
- Create: `tests/hooks/test_task_inprogress_sync.sh`

- [ ] **Step 1: Write the script**

Create `hooks/loom-task-inprogress-sync.sh`:

```bash
#!/usr/bin/env bash
# PostToolUse(TaskUpdate) hook: sync `in_progress` status to loom.
#
# Fires on every TaskUpdate. Acts only when:
#   1. The new status is "in_progress"
#   2. The task's subject carries a [<qid>] prefix that resolves
# Then runs `loom update <qid> status in_progress`.

set -euo pipefail

input=$(cat)

# Hook fires on every TaskUpdate; we only care about in_progress transitions
new_status=$(jq -r '.tool_input.status // ""' <<<"$input")
[[ "$new_status" == "in_progress" ]] || exit 0

subject=$(jq -r '.tool_input.subject // ""' <<<"$input")
# If subject isn't in tool_input, try the response (TaskUpdate may not echo subject)
if [[ -z "$subject" ]]; then
  subject=$(jq -r '.tool_response.subject // ""' <<<"$input")
fi

# Extract qid prefix
qid=""
if [[ "$subject" =~ ^\[([^]]+)\][[:space:]] ]]; then
  qid="${BASH_REMATCH[1]}"
fi
[[ -n "$qid" ]] || exit 0  # no prefix → nothing to sync

# Soft-validate: if qid doesn't resolve, exit silently (don't block).
if ! loom show "$qid" --json >/dev/null 2>&1; then
  echo "loom-task-inprogress-sync: qid '${qid}' does not resolve; skipping" >&2
  exit 0
fi

loom update "$qid" status in_progress >/dev/null || {
  echo "loom-task-inprogress-sync: failed to set status=in_progress on ${qid}" >&2
  exit 0  # never block on failure
}
```

- [ ] **Step 2: Smoke test**

Create `tests/hooks/test_task_inprogress_sync.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HOOK="$(dirname "$0")/../../hooks/loom-task-inprogress-sync.sh"

export LOOM_DIR=$(mktemp -d)
trap 'rm -rf "$LOOM_DIR"' EXIT
loom init >/dev/null
loom -y project create p --repo x >/dev/null
EPIC=$(loom -y epic create p --title E | awk '{print $NF}')
STORY=$(loom -y story create "$EPIC" --title S | awk '{print $NF}')
TASK=$(loom -y task create "$STORY" --title T | awk '{print $NF}')

# Case 1: in_progress transition with valid qid syncs to loom
echo "{\"tool_input\":{\"status\":\"in_progress\",\"subject\":\"[${TASK}] do thing\"}}" | "$HOOK"
status=$(loom show "$TASK" --json | jq -r '.status')
[[ "$status" == "in_progress" ]] && echo "PASS: synced to in_progress" || (echo "FAIL: status=${status}"; exit 1)

# Case 2: non-in_progress status is ignored
loom -y mark-ready "$TASK" >/dev/null
echo "{\"tool_input\":{\"status\":\"pending\",\"subject\":\"[${TASK}] x\"}}" | "$HOOK"
status=$(loom show "$TASK" --json | jq -r '.status')
[[ "$status" == "ready" ]] && echo "PASS: non-inprogress ignored" || (echo "FAIL: status=${status}"; exit 1)

# Case 3: subject without prefix is ignored
echo '{"tool_input":{"status":"in_progress","subject":"untagged"}}' | "$HOOK"
echo "PASS: untagged subject ignored (no error)"

echo "ALL PASS"
```

- [ ] **Step 3: chmod + run**

```bash
chmod +x hooks/loom-task-inprogress-sync.sh tests/hooks/test_task_inprogress_sync.sh
bash tests/hooks/test_task_inprogress_sync.sh
```
Expected: PASS lines + ALL PASS.

- [ ] **Step 4: Commit**

```bash
git add hooks/loom-task-inprogress-sync.sh tests/hooks/test_task_inprogress_sync.sh
git commit -m "hook: PostToolUse(TaskUpdate) syncs in_progress to loom"
```

---

### Task 6: `hooks/loom-task-completed-sync.sh`

**Files:**
- Create: `hooks/loom-task-completed-sync.sh`
- Create: `tests/hooks/test_task_completed_sync.sh`

- [ ] **Step 1: Write the script**

Create `hooks/loom-task-completed-sync.sh`:

```bash
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
  current=$(loom show "$qid" --json 2>/dev/null | jq -r '.status // ""')
  if [[ "$current" != "done" ]]; then
    echo "loom-task-completed-sync: failed to complete ${qid} (current status=${current})" >&2
  fi
fi
```

- [ ] **Step 2: Smoke test**

Create `tests/hooks/test_task_completed_sync.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HOOK="$(dirname "$0")/../../hooks/loom-task-completed-sync.sh"

export LOOM_DIR=$(mktemp -d)
trap 'rm -rf "$LOOM_DIR"' EXIT
loom init >/dev/null
loom -y project create p --repo x >/dev/null
EPIC=$(loom -y epic create p --title E | awk '{print $NF}')
STORY=$(loom -y story create "$EPIC" --title S | awk '{print $NF}')
TASK=$(loom -y task create "$STORY" --title T | awk '{print $NF}')

# Case 1: subject with valid prefix triggers loom complete
echo "{\"tool_input\":{\"subject\":\"[${TASK}] x\"}}" | "$HOOK"
status=$(loom show "$TASK" --json | jq -r '.status')
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
```

- [ ] **Step 3: chmod + run**

```bash
chmod +x hooks/loom-task-completed-sync.sh tests/hooks/test_task_completed_sync.sh
bash tests/hooks/test_task_completed_sync.sh
```
Expected: PASS lines + ALL PASS.

- [ ] **Step 4: Commit**

```bash
git add hooks/loom-task-completed-sync.sh tests/hooks/test_task_completed_sync.sh
git commit -m "hook: TaskCompleted runs loom complete on qid-prefixed subjects"
```

---

## Phase 3: Agent definitions (Tasks 7-10)

Each agent is a `.md` file with frontmatter (`name`, `description`, `tools`, optionally `model`) and a system-prompt body. The body is what the agent reads when dispatched.

### Task 7: `agents/codebase-researcher.md`

**Files:**
- Create: `agents/codebase-researcher.md`

- [ ] **Step 1: Write the agent**

Create `agents/codebase-researcher.md`:

```markdown
---
name: codebase-researcher
description: Use during the grooming phase of /epic or /story to enrich a rough idea with concrete file paths, symbol names, and architectural pointers. Returns a short report (<400 words). Does NOT propose or implement changes — read-only research.
tools: Read, Grep, Glob, Bash, WebFetch, mcp__gitnexus__context, mcp__gitnexus__query, mcp__gitnexus__impact, mcp__gitnexus__tool_map
---

# Codebase Researcher

You are dispatched during a `/epic` or `/story` grooming session. The user has
described a change at high level; the brainstorming skill needs you to ground
that description in the current codebase.

## What you receive

The dispatching prompt contains:
- A rough description of the intended change (the user's `/epic` or `/story` argument)
- The repo root
- Optionally, hints about likely subsystems

## What you produce

A report under 400 words containing:

1. **Relevant files**: specific paths (e.g., `src/foo/bar.py`) and a one-line note per file
2. **Relevant symbols**: function / class / method names with their files and line numbers
3. **Architectural pointers**: 1-2 sentences each on existing patterns the change should follow
4. **Risk surface**: any symbols whose change would impact many call sites — prefer `mcp__gitnexus__impact` for this
5. **Open questions**: things the brainstorming skill should ask the user (max 3)

## How to work

- **Use gitnexus MCP tools first** if available — `mcp__gitnexus__query` for concept search, `mcp__gitnexus__context` for a specific symbol, `mcp__gitnexus__impact` for blast radius
- **Fall back to Grep / Glob / Read** if gitnexus isn't available or the repo isn't indexed
- **Never propose or write code** — your job is to map what's there, not to design what should be
- **Cite specifics** — "this is implemented in `X.py:42` as `do_thing()`" beats "there's something somewhere about this"

## What NOT to do

- Don't analyze the user's description for "is this a good idea?" — that's brainstorming's job
- Don't enumerate every file in the repo — narrow to what's relevant
- Don't speculate about implementation — only report current state
- Don't exceed 400 words — terse beats thorough here
```

- [ ] **Step 2: Commit**

```bash
git add agents/codebase-researcher.md
git commit -m "agent: codebase-researcher for grooming-phase context"
```

---

### Task 8: `agents/story-executor.md`

**Files:**
- Create: `agents/story-executor.md`

- [ ] **Step 1: Write the agent**

Create `agents/story-executor.md`:

```markdown
---
name: story-executor
description: Single-threaded executor for a loom story's tasks. Reads the story body and its task list in topological order, implements each task with TDD discipline, commits per task. Does NOT merge or validate the story — those are the integrator's job.
tools: Read, Edit, Write, Bash, Grep, Glob, Skill, mcp__gitnexus__impact, mcp__gitnexus__context
---

# Story Executor

You are dispatched in a per-story worktree to implement one loom story. You run
single-threaded over the story's tasks in topological order.

## What you receive

The dispatching prompt contains:
- `story_qid` — the loom qid of the story you own
- `worktree` — the absolute path to your worktree
- `parent_branch` — the branch your story branch was forked from (typically the epic branch, or `main` for `/story` flow)

The SubagentStart hook has also injected your `## Loom Workflow Context` block with your `session_id`, `agent_id`, and `agent_type=story-executor`.

## First action (mandatory)

Run, immediately:

```bash
loom update <story_qid> assignee <session_id>:<agent_id>
```

Substitute the values from your injected workflow context. This records ownership in the audit trail.

## Workflow

1. `cd <worktree>`
2. `loom show <story_qid> --json | jq .body` — read the story body. Locate the `## Validation Criteria` section.
3. `loom order <story_qid> --json` — get the topologically sorted task list.
4. **For each task in that order:**
   - Use TaskCreate to add a Claude task with subject `[<task-qid>] <task title>` (the TaskCreated hook validates this against loom).
5. **Then walk your task list sequentially:**
   - Mark the task as `in_progress` in Claude's TodoList. The `loom-task-inprogress-sync` hook automatically calls `loom update <task-qid> status in_progress`.
   - **Apply TDD discipline** (invoke `superpowers:test-driven-development` skill): write failing test → run failing → minimal impl → run passing → refactor.
   - Run **verification** (invoke `superpowers:verification-before-completion` skill) before claiming the task done.
   - Commit on the story branch with a trailer: `Loom-task: <task-qid>`. Use the git-commit format from the skill prose; no special trailer formatting required beyond the literal trailer line.
   - Mark the task `completed` in Claude's TodoList. The `loom-task-completed-sync` hook automatically calls `loom complete <task-qid>`.
6. **When all tasks are done:** return a structured report to your caller (the orchestrator) with this shape:
   ```json
   {
     "story_qid": "<sqid>",
     "branch": "<your branch name>",
     "commits": ["<sha1>", "<sha2>", ...],
     "tasks_done": ["<tqid1>", "<tqid2>", ...],
     "notes": "<any concerns or surprises>"
   }
   ```

## What you must NOT do

- **Do NOT call `loom complete` on the story itself.** That is the integrator's job after a successful merge + validation.
- **Do NOT merge your branch.** The integrator (a separate agent) handles merging.
- **Do NOT skip tasks** even if you think you can fold them together. Each task is one commit, even if small.
- **Do NOT modify files outside your worktree.**
- **Do NOT call `loom update <task-qid> status <anything>` directly.** Let the hooks do it via Claude's TodoList.

## Failure modes

- If a task's TDD test reveals the task as written is wrong or infeasible, stop, report back to the orchestrator with `notes` explaining the situation. Do not improvise a different task.
- If you hit a merge conflict in your branch from upstream changes during your work, stop and report. The integrator handles re-dispatch on a fresh branch.
- If the `## Validation Criteria` section in the story body is missing or unclear, stop and report.
```

- [ ] **Step 2: Commit**

```bash
git add agents/story-executor.md
git commit -m "agent: story-executor for single-threaded task execution"
```

---

### Task 9: `agents/story-integrator.md`

**Files:**
- Create: `agents/story-integrator.md`

- [ ] **Step 1: Write the agent**

Create `agents/story-integrator.md`:

```markdown
---
name: story-integrator
description: Merges one completed story branch into its parent and validates the story's `## Validation Criteria` against the post-merge state. Tries trivial inline conflict resolution; reverts the merge on validation failure. Returns a structured result for the orchestrator.
tools: Read, Edit, Write, Bash, Grep, Glob, Skill
---

# Story Integrator

You are dispatched once per completed story to merge and validate it.

## What you receive

The dispatching prompt contains:
- `epic_qid` — the epic qid, or the literal string "none" for `/story` flow
- `story_qid` — the loom qid of the story to integrate
- `branch` — the story's branch name (e.g., `loom/<epic>/<story>` or `loom/<story>`)
- `parent_branch` — the branch to merge into (epic branch, or `main` for `/story`)
- `worktree` — the epic worktree path where you operate (cwd)

The SubagentStart hook has injected your workflow context.

## Workflow

### Step 1: Merge (skip if `/story` flow)

If `epic_qid == "none"` (i.e., `/story` flow), skip to step 2 — there is no merge needed; you validate directly on the story branch in the worktree.

Otherwise:

```bash
cd <worktree>
git checkout <parent_branch>
git merge --no-ff <branch>
```

If `git merge` reports conflicts:
- Examine the conflict surface. **Trivially resolvable** conflicts (formatting, import order, whitespace, unambiguous adjacent-line edits) you may fix inline, then `git add` the resolved files and complete the merge with `git commit --no-edit`.
- **Anything non-trivial** (semantic clash, overlapping logic edits, deleted-in-one-renamed-in-other): run `git merge --abort` and return:
  ```json
  {"result": "merge_failed", "reason": "<one-paragraph diagnostic>"}
  ```

### Step 2: Validate

Whether you just merged or are running on the story branch directly:

1. `loom show <story_qid> --json | jq -r .body` — read the story body.
2. Extract the `## Validation Criteria` checklist (lines that match `- [ ] <criterion>`).
3. For each criterion: check it against the current code state. Criteria are observable: they may name files/symbols, expected behaviors, or test outcomes. Use Read, Grep, Glob, and Bash to verify.
4. Run the project's test, lint, and format commands. Discover them from the project: typically `make test` / `pytest` / `npm test` / `cargo test`. Look for hints in `CLAUDE.md`, `Makefile`, `package.json`, `pyproject.toml`.

### Step 3: Decide

- **All criteria pass AND tests/lint/format are green:**
  ```json
  {"result": "ok", "merge_sha": "<sha or null>", "criteria": [{"text": "...", "pass": true, "evidence": "..."}, ...]}
  ```
- **Any criterion fails OR tests fail:**
  - If you just performed a merge: `git revert -m 1 HEAD --no-edit` to undo it.
  - Return:
    ```json
    {"result": "validation_failed", "failed_criteria": [{"text": "...", "evidence": "..."}, ...]}
    ```

## What you must NOT do

- **Do NOT call `loom complete` or `loom reopen`.** The orchestrator handles status transitions based on your return value.
- **Do NOT push, force-push, or create PRs.** That's `finishing-a-development-branch`'s job after the epic loop completes.
- **Do NOT modify the story's source files** to make criteria pass. If they don't pass on first observation, that's a `validation_failed`.
- **Do NOT skip the tests/lint/format runs** even if criteria all observably pass.

## Edge cases

- If the story body has no `## Validation Criteria` section, return `validation_failed` with a clear diagnostic — the planner skipped a contract.
- If tests don't exist in the project at all, run lint/format only and note "no tests defined" in the result.
```

- [ ] **Step 2: Commit**

```bash
git add agents/story-integrator.md
git commit -m "agent: story-integrator for per-story merge + validation"
```

---

### Task 10: `agents/epic-validator.md`

**Files:**
- Create: `agents/epic-validator.md`

- [ ] **Step 1: Write the agent**

Create `agents/epic-validator.md`:

```markdown
---
name: epic-validator
description: Final whole-epic validation after all stories have been merged. Runs the `verify` skill for behavioral checks (launching the app, exercising features) plus the epic's `## Validation Criteria` section. Returns pass/fail with per-criterion evidence.
tools: Read, Edit, Bash, Grep, Glob, Skill
---

# Epic Validator

You are dispatched once, at the end of the `/epic` wave loop, to validate the
fully-merged epic against its own `## Validation Criteria`.

## What you receive

The dispatching prompt contains:
- `epic_qid` — the loom qid of the epic
- `branch` — the epic branch (e.g., `loom/<epic-qid>`)
- `worktree` — the epic worktree (cwd)

## Workflow

1. `cd <worktree>` and confirm you are on `<branch>` with `git status` and `git rev-parse --abbrev-ref HEAD`.
2. `loom show <epic_qid> --json | jq -r .body` — read the epic body. Extract the `## Validation Criteria` section.
3. **Run the `verify` skill** to launch the project and exercise behavior:
   - Invoke via `Skill` tool with skill name `verify`.
   - The `verify` skill knows how to launch the project's app (CLI / server / TUI / Electron / browser) and observe behavior.
   - If `verify` reports failure or cannot launch the app, **fall back gracefully**: run the project's test suite, lint, and format. Note in your evidence that behavioral verification was unavailable.
4. **For each criterion** in the epic body's checklist: confirm against the observed state (the verify run's output, the test results, file/symbol checks).
5. **Return:**
   ```json
   {
     "result": "ok" | "failed",
     "criteria": [
       {"text": "<criterion>", "pass": true|false, "evidence": "<what you observed>"},
       ...
     ],
     "behavioral_verification": "ran|skipped|failed",
     "notes": "<optional summary>"
   }
   ```

## What you must NOT do

- **Do NOT modify the epic branch.** You are read-only verification at this stage.
- **Do NOT call `loom complete`** on the epic. The orchestrator handles that.
- **Do NOT propose fixes** if criteria fail. Just report. The orchestrator surfaces failures to the user for a manual decision (no auto-retry at epic level per spec §7).
```

- [ ] **Step 2: Commit**

```bash
git add agents/epic-validator.md
git commit -m "agent: epic-validator for final whole-epic verification"
```

---

## Phase 4: Skill rewrites (Tasks 11-14)

These are pure prose changes — no automated tests. Verification is by careful read + smoke test via `/epic` on a sandbox repo at the end of the plan (Task 17).

### Task 11: Delete `skills/subagent-driven-development/`

The role of this skill is fully absorbed by the `story-executor` agent definition.

**Files:**
- Delete: `skills/subagent-driven-development/` (entire directory)

- [ ] **Step 1: Inspect first to understand what we're losing**

```bash
ls skills/subagent-driven-development/
wc -l skills/subagent-driven-development/*.md
```

Note the file list. Confirm nothing of unique value is here — its job is now `story-executor`.

- [ ] **Step 2: Delete the directory**

```bash
git rm -r skills/subagent-driven-development/
```

- [ ] **Step 3: Commit**

```bash
git commit -m "Delete subagent-driven-development skill (replaced by story-executor agent)"
```

---

### Task 12: Rewrite `skills/brainstorming/SKILL.md`

**Files:**
- Modify (full rewrite): `skills/brainstorming/SKILL.md`

The existing supporting files in `skills/brainstorming/` (`spec-document-reviewer-prompt.md`, `visual-companion.md`, `scripts/`) are kept — they may still be useful for the loom path's research phase.

- [ ] **Step 1: Overwrite SKILL.md**

Replace the entire contents of `skills/brainstorming/SKILL.md` with:

````markdown
---
name: brainstorming
description: "You MUST use this before any creative work — creating features, building components, adding functionality, or modifying behavior. Loom-backed groom phase: research the codebase, ask clarifying questions, draft a loom epic or story with validation criteria, hand off to writing-plans."
---

# Brainstorming — loom-backed groom phase

This skill is the entry point for all planning work. It produces a **groomed draft** that the writing-plans skill materializes as loom items.

<HARD-GATE>
Do NOT invoke any implementation skill, write any code, or take any implementation action until you have presented the groomed draft and the user has approved it.
</HARD-GATE>

## Scope decision (first action)

If you were dispatched with a `mode=epic` or `mode=story` hint in your prompt (i.e., from `/epic` or `/story`), use that mode.

If no mode is pre-seeded (you were auto-triggered or invoked plain), **first decide the scope**:

| Scope | Pick when |
|---|---|
| **epic** | End-to-end feature, multi-subsystem refactor, change touches multiple modules with non-trivial dep relationships, expected to take many commits / many hours |
| **story** | Single-file or scoped change, self-contained behavior modification, bugfix, one or a few related functions |

Borderline case? Ask the user one question with the two options and let them decide.

## Mandatory checklist

You MUST create a Claude TodoList task for each of these and complete in order:

1. **Bind loom to this repo** — walk up from cwd looking for `.loom/state.json`. If absent, run `loom project create <repo-basename> -y` (loom auto-discovers the `origin` remote). Capture the project qid.
2. **Dispatch the codebase-researcher agent** with the user's description and the repo root. Wait for its report (~under 400 words).
3. **Ask clarifying questions** — one at a time. Use the research report to ground each question in concrete context (files, symbols, behaviors). Prefer multiple-choice questions when possible. Cover: purpose, constraints, success criteria, out-of-scope.
4. **Propose 2-3 approaches** with trade-offs and your recommendation. (Skip for trivial bug-fix stories.)
5. **Assemble the groomed draft** in conversation (no file written yet) — see the structure below.
6. **Present the draft** for user approval. Iterate until they approve.
7. **Hand off to writing-plans** with the approved draft + scope + project qid + session id.

## Groomed draft structure

For **epic** mode, the draft includes:

```
- title: <short epic title>
- body sections:
    - Summary: 1-paragraph what-and-why
    - Context: relevant files/symbols from research
    - Validation Criteria (checklist): observable, no implementation detail
    - Implementation Notes: approach + key decisions from this session
    - Out of Scope
- child stories: list of {title, body sections (same shape), parent epic, deps on other stories}
```

For **story** mode, the draft includes:

```
- title: <short story title>
- body sections (same as epic): Summary, Context, Validation Criteria, Implementation Notes, Out of Scope
- child tasks: list of {title, optional body, deps on other tasks}
```

**Validation criteria rules:**
- Each criterion is observable from "criteria + final code state" alone — no "uses a hashmap" type implementation detail
- May name expected behaviors, expected files/functions, expected test outcomes
- Both story and epic bodies MUST contain a `## Validation Criteria` section
- Tasks do NOT carry validation criteria (they're too granular)

## Constraints

- **No design doc file is written.** The groomed draft goes straight into loom items at the writing-plans step. The old `docs/superpowers/specs/` flow is gone.
- **Never skip the research step** even when the description seems detailed. Grounding the conversation in concrete files/symbols is what makes the criteria observable.
- **Loom is the only backend.** If the consumer repo can't be bound to a loom project (e.g., not a git repo), surface the failure and stop. There is no fallback path.

## Transition

When the user approves the groomed draft, invoke **`superpowers:writing-plans`** with the draft, scope, project qid, and `${CLAUDE_SESSION_ID}` (the writing-plans skill uses the session id to set `assignee` on the created items).

`writing-plans` is the only skill you hand off to.
````

- [ ] **Step 2: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "Rewrite brainstorming skill for loom-backed grooming"
```

---

### Task 13: Rewrite `skills/writing-plans/SKILL.md`

**Files:**
- Modify (full rewrite): `skills/writing-plans/SKILL.md`

- [ ] **Step 1: Overwrite SKILL.md**

Replace the entire contents with:

````markdown
---
name: writing-plans
description: "Use after the brainstorming skill produces an approved groomed draft. Materializes the draft as loom items via `loom epic|story|task create --body-file`, adds dependencies via `loom dep add`, sets `assignee` on epics and stories. Hands off to executing-plans."
---

# Writing Plans — loom-backed materialization

This skill takes an approved groomed draft from `brainstorming` and turns it
into a tree of loom items. It is the only writer of loom items in the
workflow.

**Announce at start:** "I'm using the writing-plans skill to materialize the plan in loom."

## What you receive

From the brainstorming skill's handoff:
- The approved groomed draft (titles, bodies, child items, deps)
- The scope: `mode=epic` or `mode=story`
- The bound loom project qid
- `${CLAUDE_SESSION_ID}` — for the `assignee` field

## Body template (enforced)

Every created epic and story body MUST contain these sections in order:

```markdown
## Summary
<one-paragraph statement of what this delivers>

## Context
<what the code looks like today; pointers to files/symbols the agent will touch>

## Validation Criteria
- [ ] <observable criterion 1>
- [ ] <observable criterion 2>
- [ ] <...>

## Implementation Notes
<for stories: any non-obvious approach decisions made during grooming>
<for epics: the story breakdown rationale, cross-story interactions>

## Out of Scope
<things explicitly NOT in this item; common source of validation disputes>
```

Tasks do NOT carry validation criteria; their bodies are short (under ~10 lines), describing what the single task does.

## Workflow

### Step 1: Compose body files

In a temp directory (`mktemp -d`), write one markdown file per loom item to be created. Name them descriptively (e.g., `epic.md`, `story-1.md`, `task-1-1.md`).

### Step 2: Create the loom items

For **epic mode**:

```bash
EPIC=$(loom epic create <project-qid> --title "<title>" --body-file <tmp>/epic.md -y)
loom update "$EPIC" assignee "${CLAUDE_SESSION_ID}"

for each story in the draft:
  STORY=$(loom story create "$EPIC" --title "<story title>" --body-file <tmp>/story-N.md -y)
  loom update "$STORY" assignee "${CLAUDE_SESSION_ID}"
  for each task in the story:
    loom task create "$STORY" --title "<task title>" --body-file <tmp>/task-N-M.md -y
```

For **story mode**:

```bash
# Story lives under <project>:backlog
STORY=$(loom story create "<project>:backlog" --title "<title>" --body-file <tmp>/story.md -y)
loom update "$STORY" assignee "${CLAUDE_SESSION_ID}"
for each task in the draft:
  loom task create "$STORY" --title "<task title>" --body-file <tmp>/task-N.md -y
```

### Step 3: Add dependencies

```bash
loom dep add <source-qid> --on <target-qid>
```

Loom rejects cycles automatically (exit code 4). If you hit a cycle, the groom phase produced a malformed plan — surface the cycle to the user and stop.

### Step 4: Self-review

```bash
loom validate
loom tree <epic-qid or story-qid>
```

Show both outputs to the user. Confirm the structure is what they approved. If they want changes:
- Status / structure: `loom update`, `loom dep add/rm`, etc.
- Bodies: `loom update <qid> body --body-file <new-file>`

### Step 5: Hand off

Once the user signs off on the materialized tree, invoke **`superpowers:executing-plans`** with:
- `epic_qid=<qid>` (epic mode) or `story_qid=<qid>` (story mode)
- The orchestrator handles worktree creation and the dispatch loop.

`executing-plans` is the only skill you hand off to.

## Constraints

- **Always use `--body-file`.** Never use `--body` with multi-paragraph strings — temp files keep the loom CLI invocation clean and atomic.
- **Always set `assignee` on epics and stories at creation.** Tasks never carry assignee.
- **Never write a markdown plan file.** Loom items replace the old `docs/superpowers/plans/` artifacts.
- **One item per create call.** Don't try to batch via shell loops without checking exit codes — capture each created qid for later reference.

## No placeholders in loom item bodies

The body template is mandatory. Don't leave "TBD" or "Add criteria later" in Validation Criteria sections — the brainstorming step produced concrete criteria. If the criteria are vague, return to brainstorming.
````

- [ ] **Step 2: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "Rewrite writing-plans skill for loom-backed materialization"
```

---

### Task 14: Rewrite `skills/executing-plans/SKILL.md`

**Files:**
- Modify (full rewrite): `skills/executing-plans/SKILL.md`

- [ ] **Step 1: Overwrite SKILL.md**

Replace the entire contents with:

````markdown
---
name: executing-plans
description: "Use after writing-plans has materialized loom items. Orchestrates execution: epic-wave loop (parallel story-executor dispatch + per-story merge & validate) for epic scope, or single-executor-then-integrator for story scope. Hands off to finishing-a-development-branch on success."
---

# Executing Plans — loom-backed orchestrator

This skill is the orchestrator. It runs in the main session (not a subagent) and dispatches the per-story / per-task work.

**Announce at start:** "I'm using the executing-plans skill to orchestrate execution."

## What you receive

From the writing-plans skill's handoff, one of:
- `epic_qid=<qid>` — runs the epic wave loop
- `story_qid=<qid>` — runs the single-story shape

Plus the bound loom project qid and `${CLAUDE_SESSION_ID}` (for orchestrator-side ownership tracking if needed).

## Orchestrator state files

Maintained under `<epic-worktree>/.loom/`:
- `retry-counters.json` — per-story retry counts across waves
- `orchestrator.log` — append-only wave-by-wave log

Both are gitignored by loom's `.loom/.gitignore`.

## Epic wave loop

### Setup (once per `/epic`)

1. Invoke `superpowers:using-git-worktrees` to create `<repo>/.worktrees/<epic-qid>/` on branch `loom/<epic-qid>` off `main`.
2. `cd <epic-worktree>`.
3. Initialize retry counters file: `echo "{}" > .loom/retry-counters.json`.

### Loop body (until no ready stories remain)

```
loop:
    ready=$(loom ready <epic-qid> --type story --json)
    if [empty]: break

    # Wave 1: dispatch story-executor subagents in PARALLEL
    for each sqid in ready:
        - Create child worktree: <repo>/.worktrees/<epic-qid>--<sqid> off loom/<epic-qid>
          on branch loom/<epic-qid>/<sqid>
        - Dispatch:
            Agent(subagent_type="story-executor",
                  prompt="story_qid=<sqid> worktree=<path> parent_branch=loom/<epic-qid>")
    wait for ALL parallel dispatches to complete

    # Wave 2: integrate each completed story sequentially
    for each sqid that the executor reported done (topo order):
        result = Agent(subagent_type="story-integrator",
                       prompt="epic_qid=<epic-qid> story_qid=<sqid> branch=loom/<epic-qid>/<sqid> parent_branch=loom/<epic-qid> worktree=<epic-worktree>")
        if result.result == "ok":
            loom complete <sqid>
        elif result.result in ("merge_failed", "validation_failed"):
            # Discard the story; it goes back to ready and gets picked up next iteration.
            rm -rf <repo>/.worktrees/<epic-qid>--<sqid>
            git branch -D loom/<epic-qid>/<sqid>
            loom reopen <sqid>
            increment retry_counter[sqid] in .loom/retry-counters.json
            if retry_counter[sqid] >= 3:
                HALT with diagnostic — surface result.reason / failed_criteria to the user
        log everything to .loom/orchestrator.log
```

To dispatch subagents in parallel, send a single message with multiple `Agent` tool calls.

### After loop exits

1. Dispatch the final validator:
   ```
   Agent(subagent_type="epic-validator",
         prompt="epic_qid=<eqid> branch=loom/<eqid> worktree=<epic-worktree>")
   ```
2. If `result.result == "ok"`:
   - `loom complete <epic-qid>`
   - Invoke `superpowers:finishing-a-development-branch` to choose merge / PR / keep.
3. Else: HALT with the validator's diagnostic. Do not auto-retry at the epic level — that's a human decision.

## Story (single-item) shape

For `story_qid=...` entry:

1. Invoke `superpowers:using-git-worktrees` to create `<repo>/.worktrees/<story-qid>/` on branch `loom/<story-qid>` off `main`.
2. Dispatch one story-executor:
   ```
   Agent(subagent_type="story-executor",
         prompt="story_qid=<sqid> worktree=<path> parent_branch=main")
   ```
3. Wait. Then dispatch a story-integrator with `epic_qid=none` (the integrator will skip the merge step and run validation directly on the story branch):
   ```
   Agent(subagent_type="story-integrator",
         prompt="epic_qid=none story_qid=<sqid> branch=loom/<sqid> parent_branch=main worktree=<story-worktree>")
   ```
4. If `result.ok`:
   - `loom complete <sqid>`
   - Invoke `superpowers:finishing-a-development-branch`.
5. If `result` is merge_failed or validation_failed:
   - `loom reopen <sqid>`, increment retry counter, redispatch up to 3 times.
   - On exhausting retries: HALT.

## Tracking work in the orchestrator's own TodoList

In your own (main session) TodoList, use subjects formatted as `[<sqid>] <story title>` while a wave is in flight. The main session is in **permissive mode** for the hooks (not a defined agent_type), so the prefix is optional but doing it lets the loom-task-completed-sync hook auto-complete the story tracking item if a wave finishes cleanly.

## Halt UX

When you halt, leave the workspace inspectable:
- Branches stay in place
- Worktrees stay in place (the failed-story worktree was deleted; others remain)
- Loom items reflect current status
- `.loom/orchestrator.log` has the full trail
- `.loom/retry-counters.json` shows what's been retried

Tell the user where things stand and suggest concrete next steps (e.g., "Run `cd <epic-worktree> && loom tree <epic-qid>` to inspect; the failing story is `<sqid>` with these unmet criteria: ...").

## Constraints

- **Never call `git push` or open PRs.** That's `finishing-a-development-branch`'s job.
- **Never call `loom complete` on a story before the integrator returns `ok`.**
- **Never auto-retry at the epic level.** Halt and surface.
- **Bounded retries**: 3 per story across waves.
````

- [ ] **Step 2: Commit**

```bash
git add skills/executing-plans/SKILL.md
git commit -m "Rewrite executing-plans skill as loom-backed epic-wave orchestrator"
```

---

## Phase 5: Entry skills (Tasks 15-16)

### Task 15: `skills/epic/SKILL.md`

**Files:**
- Create: `skills/epic/SKILL.md`

- [ ] **Step 1: Create the directory and skill**

```bash
mkdir -p skills/epic
```

Create `skills/epic/SKILL.md`:

````markdown
---
name: epic
description: "Use when the user types /epic followed by a description of a large feature, refactor, or end-to-end change. Drives the full loom-backed planning and parallel execution workflow: research → groom → plan as a loom epic with child stories and tasks → execute via parallel story-subagents with merge and validation orchestration → final epic-level verify."
---

# /epic — Large-feature workflow

The user has invoked `/epic <description>`. The description is in `$ARGUMENTS`. Session id is `${CLAUDE_SESSION_ID}`.

## Mandatory sequence

1. **Bind loom** to this repo:
   - Walk up from cwd for `.loom/state.json`. If found, note the bound project qid.
   - If not found, run `loom project create <repo-basename> -y` (loom auto-discovers the `origin` remote). Fail if cwd is not in a git repo.

2. **Hand off to `superpowers:brainstorming`** with context:
   - `mode=epic`
   - `description=$ARGUMENTS`
   - `project=<project-qid>`
   - `session_id=${CLAUDE_SESSION_ID}`

3. brainstorming returns a groomed draft (epic title, body with criteria, list of stories with their drafts, story deps).

4. **Hand off to `superpowers:writing-plans`** with the groomed draft. That skill materializes the epic, stories, tasks, and deps in loom via CLI; sets `assignee: ${CLAUDE_SESSION_ID}` on the epic and stories; writes bodies via `--body-file`.

5. **Hand off to `superpowers:executing-plans`** with `epic_qid=<qid>`. The orchestrator creates the epic worktree, runs the wave loop, and runs final epic validation.

6. On final validation pass, the orchestrator hands off to `superpowers:finishing-a-development-branch`. On failure, the orchestrator halts and surfaces the diagnostic — that ends your turn.

## Constraints

- Never skip the groom phase even if the description is detailed — the research step always adds value.
- Never execute code changes from this skill directly. All implementation happens inside story-executor subagents in story worktrees.
- If the workflow halts at any step (cycle detected during planning, validation fails after retries, merge conflict requires human input), surface the diagnostic and stop. Do not retry or work around silently.

## What you do NOT do here

- Do NOT dispatch subagents directly. Each skill in the chain knows its part.
- Do NOT write to loom directly. `writing-plans` handles all loom writes during planning; the agents/hooks handle writes during execution.
- Do NOT create worktrees or branches yourself. `using-git-worktrees` (invoked by `executing-plans`) handles them.
````

- [ ] **Step 2: Commit**

```bash
git add skills/epic/SKILL.md
git commit -m "skill: /epic entry point for large-feature workflow"
```

---

### Task 16: `skills/story/SKILL.md`

**Files:**
- Create: `skills/story/SKILL.md`

- [ ] **Step 1: Create the skill**

```bash
mkdir -p skills/story
```

Create `skills/story/SKILL.md`:

````markdown
---
name: story
description: "Use when the user types /story followed by a description of a small, scoped change — a bugfix, single-file refactor, or self-contained feature. Drives the loom-backed flow at story scale: research → groom → plan as a loom story (with tasks) under the project's backlog epic → execute via a single story-executor subagent → validate → hand off to finishing-a-development-branch."
---

# /story — Small-change workflow

The user has invoked `/story <description>`. The description is in `$ARGUMENTS`. Session id is `${CLAUDE_SESSION_ID}`.

## Mandatory sequence

1. **Bind loom** to this repo (same as `/epic`: walk up for `.loom/state.json`; `loom project create <repo-basename> -y` if absent).

2. **Identify the target epic**: the project's default `backlog` epic (qid `<project>:backlog`). Loom auto-creates the backlog epic on every project at schema_version=2 and later; if it's missing (older project), the `loom story create` command auto-creates it on first use.

3. **Hand off to `superpowers:brainstorming`** with context:
   - `mode=story`
   - `description=$ARGUMENTS`
   - `epic=<project>:backlog`
   - `session_id=${CLAUDE_SESSION_ID}`

4. brainstorming returns a groomed story draft (title, body with criteria, task list).

5. **Hand off to `superpowers:writing-plans`** with the groomed draft. That skill creates the story under backlog and its tasks; sets `assignee: ${CLAUDE_SESSION_ID}` on the story.

6. **Hand off to `superpowers:executing-plans`** with `story_qid=<qid>`. The orchestrator creates the story worktree off main, dispatches one story-executor, then one story-integrator (validation only, no merge — branch stays unmerged), then hands off to `finishing-a-development-branch`.

7. On validation pass, you're done. On validation fail after 3 retries, the orchestrator halts and surfaces the diagnostic.

## Differences from /epic

- One story, not many. No parallel fanout.
- No epic worktree. Story worktree branches directly off `main`.
- No auto-merge. The validated story branch is handed to `finishing-a-development-branch` unmerged.
- Lives under the `backlog` epic, not a freshly-created epic.

## Constraints

Same as `/epic`: never skip the groom phase, no direct code changes from this skill, halt on any failure rather than retrying silently.
````

- [ ] **Step 2: Commit**

```bash
git add skills/story/SKILL.md
git commit -m "skill: /story entry point for small-change workflow"
```

---

## Phase 6: Docs (Task 17)

### Task 17: README / AGENTS.md updates

**Files:**
- Modify: `README.md` (add a section pointing to `/epic` and `/story`)
- Modify: `AGENTS.md` (if it exists; otherwise skip)

- [ ] **Step 1: Check what exists**

Run: `ls README.md AGENTS.md 2>&1; head -50 README.md`

- [ ] **Step 2: Add a section to README.md**

Find a sensible insertion point in `README.md` (likely after the introductory section). Insert this block:

```markdown
## Loom-backed planning workflow

Two slash commands drive a project-management-aware planning loop:

- **`/epic <description>`** — large features, multi-subsystem refactors. Grooms a loom epic with child stories and tasks, dispatches parallel story-executor subagents in their own worktrees off an epic branch, runs per-story merge + validation, and final epic-level verification via the `verify` skill.
- **`/story <description>`** — small, scoped changes. Grooms a loom story under the project's `backlog` epic, runs one story-executor over its tasks, validates, hands off to `finishing-a-development-branch`.

Both commands auto-create a loom workspace (`.loom/`) in the current repo on first use. See `docs/plans/2026-05-22-loom-backed-planning-design.md` for the full design and the related agent definitions in `agents/`.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document /epic and /story workflow in README"
```

---

## Final verification (Task 18)

### Task 18: End-to-end smoke test against a sandbox repo

**Files:** none modified — pure verification.

This is the closest we have to an integration test for the skill chain. The implementing agent runs it manually with a throwaway repo.

- [ ] **Step 1: Create a sandbox repo**

```bash
SANDBOX=$(mktemp -d)
cd "$SANDBOX"
git init -q
echo "# sandbox" > README.md
git add README.md && git commit -m "init" -q
# Set up a fake origin so loom project create works
git remote add origin "git@example.com:sandbox.git"
```

- [ ] **Step 2: Verify the hooks fire when Claude Code is run in this directory**

(This step requires a live Claude Code session. The implementing agent should report back to the user with the smoke-test results rather than trying to run Claude inside Claude.)

The implementing agent should describe to the user:

> "Plan B is implemented. To smoke-test:
> 1. Open a Claude Code session in `<SANDBOX>`.
> 2. Run `/story add a hello world script`.
> 3. Confirm: `.loom/` is created; the brainstorming flow runs; the user is asked clarifying questions one at a time; a story is created in loom; tasks are created; a worktree is created at `.worktrees/<story-qid>/`; a story-executor subagent runs through the tasks; an integrator validates."

- [ ] **Step 3: If the implementing agent has access to its own Claude Code instance, run the smoke test**

If the implementing agent has the ability to spawn a sub-instance of Claude Code (unlikely), run the smoke test directly. Otherwise, report to the user and stop.

- [ ] **Step 4: Cleanup**

```bash
rm -rf "$SANDBOX"
```

---

## Self-review notes (filled in at plan-writing time)

**Spec coverage:**
- §3 architecture → Tasks 11 (delete), 12-14 (skill rewrites), 15-16 (entry skills)
- §4 loom CLI → covered in Plan A (this plan's prerequisite, gated by Task 0)
- §5.1 agents → Tasks 7-10
- §5.2 hooks → Tasks 3-6 + Task 1 plugin.json
- §5.3 skill rewrites → Tasks 12-14
- §5.4 entry skills → Tasks 15-16
- §6 hook→context mechanics → Task 3 (the subagent-start hook)
- §7 failure modes → Encoded in Task 14 (orchestrator) and Tasks 8-9 (executor + integrator)

**Placeholder scan:** No "TBD" / "implement later" patterns. The "implementer should verify the exact event names" note in Task 1 is a known caveat from the spec's §6 verification list, not a placeholder.

**Type consistency:**
- Agent name `story-executor` consistent across skill prose, hook strict-mode lists, agent file.
- Agent name `story-integrator` consistent (no leftover `merge-orchestrator` references — that name was retired during design).
- Hook script file names match their declaration in plugin.json (Task 1).
- The four strict-mode agent types appear in the same list in: Task 3 (hook), Task 4 (hook), Task 6 (hook), and the orchestrator skill (Task 14, indirectly).

**Open caveats** (acknowledged, deferred to implementation):
- Plugin.json `${CLAUDE_PLUGIN_ROOT}` substitution and `TaskCreated`/`TaskCompleted` event names need verification against the live Claude Code version (Task 1).
- The Agent tool's return value for dispatched subagents may not include the structured JSON shapes prescribed in the agent system prompts; the orchestrator may need to parse free-text returns. Flagged in Task 14.
