# Orchestrator Log

The orchestrator log is a per-agent, append-only JSONL file that records the lifecycle of every subagent spawned during an epic execution. It is written by `hooks/lib/loom-log-event.sh` and is designed for post-hoc reconstruction of what happened across the full orchestration run.

---

## Overview

Each subagent appends one JSONL line per significant event. Because each agent writes only its own file (single-writer invariant), no locking is needed. The full story of an epic execution is reconstructed by merging all per-agent files in the epic directory and sorting by `ts`.

---

## Path Layout

```
${XDG_STATE_HOME:-$HOME/.local/state}/loom/<project>/<epic_qid>/<agent_id>.jsonl
```

- **`<project>`** — derived from `.loom/state.json`'s `project` field, walking up from cwd.
- **`<epic_qid>`** — the loom qualified ID of the epic (e.g. `superpowers:je66zjb`).
- **`<agent_id>`** — the unique agent identifier from the loom workflow context (e.g. `sess-1:agent-3`).

**Why per-agent files?** Single-writer invariant: each agent owns its own file, so concurrent appends across agents never collide. No `flock`, no mutex.

**Why `XDG_STATE_HOME`?** Follows the XDG Base Directory Specification. State that persists across runs but is not user configuration belongs in `~/.local/state` by default.

The directory `<epic_qid>/` is created with `mkdir -p` on every call (idempotent).

---

## Schema

Every JSONL line is a JSON object. All fields are at the top level (no nesting).

### Required fields

| Field          | Type    | Description                                               |
|----------------|---------|-----------------------------------------------------------|
| `schema_version` | integer | Always `1` for this schema version.                    |
| `ts`           | string  | ISO 8601 UTC timestamp. Millisecond precision where supported (e.g. `2026-05-26T14:23:01.456Z`); second precision fallback on platforms where `date %N` is unsupported (e.g. macOS). |
| `kind`         | string  | Event kind (see catalogue below).                         |
| `epic_qid`     | string  | Loom qualified ID of the epic.                            |
| `agent_id`     | string  | Unique identifier for this agent instance.                |
| `session_id`   | string  | Claude session ID from the loom workflow context.         |
| `agent_type`   | string  | One of: `story-executor`, `story-integrator`, `epic-validator`, `codebase-researcher`. |

### Optional fields

Optional fields are **omitted entirely** when not applicable — they are never set to `null`.

| Field       | Type   | Description                                               |
|-------------|--------|-----------------------------------------------------------|
| `story_qid` | string | Loom qualified ID of the story being worked.              |
| `task_qid`  | string | Loom qualified ID of the specific task.                   |
| `note`      | string | Free-text annotation for the event.                       |

### Event-specific payload fields

The `--field key=value` flag on `loom-log-event.sh` appends arbitrary fields to the JSONL object. Each event kind defines its own payload (see the catalogue). Fields are always strings in the raw JSON; consumers may coerce types as needed.

---

## Mechanical Event-Kind Catalogue

Mechanical kinds are emitted by the dispatcher hooks (wired in Story 2). The dispatcher calls `loom-log-event.sh` at each lifecycle boundary.

| Kind               | Emitted by          | When                                             | Payload fields                   |
|--------------------|---------------------|--------------------------------------------------|----------------------------------|
| `agent_start`      | SubagentStart hook  | An agent is spawned and enters its worktree.     | —                                |
| `agent_stop`       | SubagentStop hook   | An agent's session ends (success or failure).    | `exit_code`                      |
| `task_start`       | TaskUpdate hook     | A task transitions to `in_progress`.             | `task_qid`                       |
| `task_complete`    | TaskCompleted hook  | A task is marked completed.                      | `task_qid`                       |
| `task_blocked`     | TaskCreated guard   | A TaskCreate is blocked (invalid qid/status).    | `task_qid`, `reason`             |
| `story_commit`     | PostToolUse(Bash)   | A commit is made on the story branch.            | `sha`, `branch`                  |
| `story_merge`      | story-integrator    | A story branch is merged into the epic branch.   | `story_qid`, `sha`, `branch`     |
| `story_conflict`   | story-integrator    | A merge attempt encounters a conflict.           | `story_qid`, `branch`            |
| `validation_start` | epic-validator      | Epic-level validation begins.                    | —                                |
| `validation_result`| epic-validator      | Epic-level validation completes.                 | `result` (`pass` or `fail`), `note` |

### Semantic event kinds

Semantic kinds are emitted from skill prose (e.g. `superpowers:brainstorming`, `superpowers:test-driven-development`) to record AI-level decision points. These are defined and enumerated in Story 3. See Story 3 implementation for the full catalogue.

---

## Reconstruction Pattern

To view the complete history of an epic execution, merge all per-agent files in the epic directory and sort by `ts`:

```bash
epic_qid="superpowers:je66zjb"
project="superpowers"
log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/loom/${project}/${epic_qid}"

# Merge and sort all agent logs by timestamp
cat "${log_dir}"/*.jsonl | jq -s 'sort_by(.ts)[]' -c
```

Because timestamps are ISO 8601 UTC, lexicographic sort (`sort_by(.ts)`) is equivalent to chronological sort. Sub-millisecond ordering within a single agent is guaranteed by file ordering (append-only). Ordering across agents with the same second (or millisecond on platforms without `%N`) is not strictly guaranteed, but in practice agents emit events at different times.

### Sample lines

```jsonl
{"schema_version":1,"ts":"2026-05-26T14:23:01Z","kind":"agent_start","epic_qid":"superpowers:je66zjb","agent_id":"sess-1:agent-3","session_id":"sess-1","agent_type":"story-executor","story_qid":"superpowers:je66zjb:1"}
{"schema_version":1,"ts":"2026-05-26T14:25:44Z","kind":"task_start","epic_qid":"superpowers:je66zjb","agent_id":"sess-1:agent-3","session_id":"sess-1","agent_type":"story-executor","story_qid":"superpowers:je66zjb:1","task_qid":"superpowers:je66zjb:1:1"}
{"schema_version":1,"ts":"2026-05-26T14:31:02Z","kind":"story_commit","epic_qid":"superpowers:je66zjb","agent_id":"sess-1:agent-3","session_id":"sess-1","agent_type":"story-executor","story_qid":"superpowers:je66zjb:1","sha":"deadbeef","branch":"loom/superpowers-je66zjb-1"}
```
