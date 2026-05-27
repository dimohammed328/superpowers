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

Mechanical kinds are emitted by `hooks/loom-log.sh` (the dispatcher wired in Story 2). The dispatcher branches by hook event type and calls `loom-log-event.sh` at each lifecycle boundary.

| Kind                | Emitted by                            | When                                                      | Payload fields                       |
|---------------------|---------------------------------------|-----------------------------------------------------------|--------------------------------------|
| `task_created`      | `TaskCreated` hook                    | A TaskCreate tool call is observed.                       | `task_qid`, `subject`                |
| `task_updated`      | `PostToolUse(TaskUpdate)` hook        | A TaskUpdate tool call is observed.                       | `task_qid`, `status`                 |
| `task_completed`    | `TaskCompleted` hook                  | A task transitions to completed.                          | `task_qid`                           |
| `subagent_start`    | `SubagentStart` hook                  | A subagent is spawned.                                    | —                                    |
| `subagent_stop`     | `SubagentStop` hook                   | A subagent's session ends (success or failure).           | `exit_code` (when available)         |
| `worktree_create`   | `EnterWorktree` hook or `PostToolUse(Bash)` matching `git worktree add` | A worktree is created.                                    | `path`, `branch`                     |
| `worktree_delete`   | `ExitWorktree` hook or `PostToolUse(Bash)` matching `git worktree remove` | A worktree is removed.                                    | `path`, `branch`                     |
| `git_commit`        | `PostToolUse(Bash)` matching `git commit` | A commit is made.                                         | `sha` (when parseable), `command`    |
| `git_merge`         | `PostToolUse(Bash)` matching `git merge` | A merge is performed.                                     | `source_branch`, `target_branch`     |
| `git_branch_delete` | `PostToolUse(Bash)` matching `git branch -D` | A branch is force-deleted.                                | `branch`                             |
| `git_push`          | `PostToolUse(Bash)` matching `git push` | A push is performed.                                      | `remote`, `branch`                   |

### Semantic event kinds

Semantic kinds are emitted from orchestrator and agent skill prose to record AI-level decision points that mechanical hooks cannot observe — wave composition, retry rationale, validation outcome interpretation, and the finalize decision. The orchestrator's `agent_id` for semantic-event logging defaults to `${CLAUDE_SESSION_ID}-orchestrator`.

| Kind                   | Emitted by             | When                                                        | Required payload fields                  | Optional payload fields        |
|------------------------|------------------------|-------------------------------------------------------------|------------------------------------------|-------------------------------|
| `wave_start`           | executing-plans        | A new wave of story-executor subagents is about to be dispatched. | `wave_index` (int), `story_qids` (space-separated list) | —                             |
| `wave_complete`        | executing-plans        | All story-executor subagents in a wave have returned.       | `wave_index` (int)                       | per-story result summary as `note` |
| `integration_start`    | story-integrator       | The merge-and-validate sequence begins for a story.         | `story_qid`                              | —                             |
| `integration_complete` | story-integrator       | The merge-and-validate sequence finishes for a story.       | `story_qid`, `result` (`ok`, `merge_failed`, or `validation_failed`) | —                             |
| `validation_start`     | epic-validator         | Epic-level validation begins.                               | —                                        | `epic_qid` (via base field)   |
| `validation_result`    | epic-validator         | Epic-level validation completes.                            | `result` (`pass` or `fail`)              | `summary` (short human-readable description on fail) |
| `retry_decision`       | executing-plans        | The orchestrator decides to retry a failed story.           | `story_qid`, `attempt` (int), `reason`   | —                             |
| `epic_finalize`        | executing-plans        | The finalize-branch step begins (merge-to-main or PR creation). | `epic_qid` (via base field)          | `merged_to`, `pr_url`         |

#### Payload detail

- **`wave_start`** — `wave_index` counts from 0. `story_qids` is a space-separated string of loom qualified IDs (e.g. `"superpowers:je66zjb:1 superpowers:je66zjb:2"`).
- **`wave_complete`** — `wave_index` matches the corresponding `wave_start`. A brief `note` may summarise per-story outcomes (e.g. `"3 ok, 1 validation_failed"`).
- **`integration_start` / `integration_complete`** — `story_qid` is the loom qualified ID of the story being integrated. `result` on `integration_complete` is one of: `ok`, `merge_failed`, `validation_failed`.
- **`validation_start`** — the epic_qid is carried by the base field already; no extra payload needed.
- **`validation_result`** — `result` is `pass` or `fail`. On fail, `summary` provides a short human-readable description of which criteria failed.
- **`retry_decision`** — `attempt` is the 1-based retry number (first retry = `1`). `reason` is a one-line description of why the story failed (e.g. `"validation_failed: 2 criteria unmet"`).
- **`epic_finalize`** — `merged_to` is the target branch (e.g. `main`). `pr_url` is included only when PR mode was used instead of merge+push.

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
{"schema_version":1,"ts":"2026-05-26T14:23:01Z","kind":"subagent_start","epic_qid":"superpowers:je66zjb","agent_id":"sess-1:agent-3","session_id":"sess-1","agent_type":"story-executor","story_qid":"superpowers:je66zjb:1"}
{"schema_version":1,"ts":"2026-05-26T14:25:44Z","kind":"task_updated","epic_qid":"superpowers:je66zjb","agent_id":"sess-1:agent-3","session_id":"sess-1","agent_type":"story-executor","story_qid":"superpowers:je66zjb:1","task_qid":"superpowers:je66zjb:1:1","status":"in_progress"}
{"schema_version":1,"ts":"2026-05-26T14:31:02Z","kind":"git_commit","epic_qid":"superpowers:je66zjb","agent_id":"sess-1:agent-3","session_id":"sess-1","agent_type":"story-executor","story_qid":"superpowers:je66zjb:1","sha":"deadbeef","command":"git commit -m \"feat: foundation\""}
```
