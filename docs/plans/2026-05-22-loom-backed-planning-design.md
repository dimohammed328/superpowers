# Loom-Backed Planning & Execution — Design

> **Superseded (2026-05-29):** The loom task guard and status-sync hooks described in this document (`loom-task-created-guard.sh`, `loom-task-inprogress-sync.sh`, `loom-task-completed-sync.sh`) have been removed. The story-executor now calls `loom update <task-qid> status in_progress` and `loom complete <task-qid>` directly, without relying on harness hooks to mirror status.

**Status:** approved spec, pending implementation plan
**Date:** 2026-05-22
**Scope:** rewrite the superpowers planning / execution skill chain to use the [`loom`](https://github.com/danishflorist/loom) project-management CLI as the durable backend; add `/epic` and `/story` slash-command entry skills; add 5 small CLI features to loom.

---

## 1. Motivation

Today's superpowers chain (`brainstorming` → `writing-plans` → `executing-plans` / `subagent-driven-development` → `finishing-a-development-branch`) persists work in markdown files under `docs/superpowers/specs/` and `docs/superpowers/plans/`. Those files are read-once artifacts; they don't model dependencies, status, or hierarchy.

`loom` already models exactly this domain: markdown-first projects / epics / stories / tasks with cross-cutting dependencies, a derived SQLite index, a stable CLI, and a defined markdown schema. Replacing the per-skill markdown files with loom items gives us:

- **Durable, queryable state**: `loom ready`, `loom tree`, `loom order` for the orchestrator
- **Hierarchy + deps as first-class**: stories under epics, tasks under stories, deps anywhere
- **Status tracking**: ready / in-progress / done observable in real time
- **Audit trail**: `assignee` records which session / subagent did what

The workflow this design enables: `/epic <description>` grooms a large change into an epic with child stories and tasks, dispatches parallel story-subagents in their own worktrees off the epic branch, runs a per-story merge-and-validate integrator, retries discarded stories on the next wave, and runs a final epic-level behavioral validation before handing off to merge / PR. `/story <description>` is the same chain compressed to a single story under the project's `backlog` epic.

---

## 2. Non-goals

- **Epic resume across sessions**: the `assignee` field is designed to enable this (orphan detection on /epic re-entry), but the orchestrator path for resume is deferred.
- **Generalizing dependency satisfaction**: only `done` satisfies a dep — loom's existing invariant is preserved.
- **Auto-push or auto-PR**: branch / PR finalization stays in `finishing-a-development-branch`.
- **Per-task validation criteria**: only stories and epics carry the `## Validation Criteria` section. Tasks are too granular.
- **Backwards-compat with the old skill chain**: this is a hard replace. No general-spec fallback path. Old `docs/superpowers/specs/` and `docs/superpowers/plans/` artifacts are not produced by the rewritten skills.

---

## 3. Architecture

### 3.1 Skill graph

```
NEW entry skills (= slash commands):
  skills/epic/                       → /epic <description>
  skills/story/                      → /story <description>

REWRITTEN skills (loom is the backend):
  skills/brainstorming/              → groom phase: research + clarify + draft loom items
  skills/writing-plans/              → planning phase: emit loom items via CLI, write bodies+criteria+deps
  skills/executing-plans/            → epic-wave orchestrator (parallel stories, per-story integrator)

DELETED:
  skills/subagent-driven-development/  (role absorbed by the `story-executor` agent definition)

REUSED AS-IS (composed in, no edits):
  using-git-worktrees
  verification-before-completion
  test-driven-development
  dispatching-parallel-agents
  finishing-a-development-branch
  verify
```

### 3.2 Two flows, same backend

- `/epic`: full chain — groom → plan → epic-wave orchestrator → final epic validation → finish.
- `/story`: compressed chain — groom → plan → single executor → single integrator → finish. Story lives under the project's `backlog` epic.

Auto-triggered brainstorming (no slash command) assesses scope itself and picks the right mode. Borderline cases prompt the user.

### 3.3 Data flow

Persistent state lives in three places:

1. **Loom items** (markdown files under `$LOOM_DIR/projects/...`): the canonical record of scope, validation criteria, deps, status, assignee, branch, pr_url.
2. **Git branches and worktrees** (under `<repo>/.worktrees/`): the code being produced.
3. **Per-run ephemeral state** (`<epic-worktree>/.loom/`): retry counters, orchestrator logs. Gitignored. Not in loom.

No markdown spec files. No plan markdown files. The skill chain treats loom items as the single source of truth for plan-shaped data.

### 3.4 Worktrees and branches

| Flow | Worktree path | Branch |
|---|---|---|
| `/epic` epic root | `<repo>/.worktrees/<epic-qid>/` | `loom/<epic-qid>` off `main` |
| `/epic` per-story | `<repo>/.worktrees/<epic-qid>--<story-qid>/` | `loom/<epic-qid>/<story-qid>` off `loom/<epic-qid>` |
| `/story` | `<repo>/.worktrees/<story-qid>/` | `loom/<story-qid>` off `main` |

`<repo>/.worktrees/` is gitignored if it isn't already; the using-git-worktrees skill handles this.

### 3.5 Loom binding

If the consumer repo has no `.loom/state.json` (walked up from cwd), `/epic`, `/story`, and auto-triggered brainstorming all call `loom project create <repo-basename> -y` first. Loom auto-discovers the `origin` remote. Fails if cwd is not in a git repo.

---

## 4. Loom CLI changes

All loom changes are additive and non-breaking. Schema bump is for the new `assignee` field convention; no existing field semantics change.

### 4.1 `--body-file <path>` flag

Added to `project create`, `epic create`, `story create`, `task create`, and `loom update`. Reads the file's contents as the markdown body. Mutually exclusive with `--body`.

**Why:** the planning skill composes long structured bodies (Summary + Context + Validation Criteria + Implementation Notes + Out of Scope) in a temp file and passes the path. Removes the brittle two-step "create then write to canonical path" workaround.

### 4.2 `loom ready [<qid>] [--recursive] [--json]`

Extended. When no qid is passed, returns global ready items (current behavior). When a qid is passed, returns ready items at the **next level down** under that qid (epic → ready stories, story → ready tasks, project → ready epics). With `--recursive`, returns all ready descendants at any depth.

**Why:** the orchestrator wave loop calls `loom ready <epic-qid> --json` each iteration to find dispatchable stories.

### 4.3 `loom tree <qid> [--depth N] [--status STR] [--json]`

New read-only command.

- **Text default**: indented unicode tree:
  ```
  myproj:apt2467  [ready]  epic  branch=loom/myproj:apt2467
  ├─ myproj:apt2467:1  [done]   story  branch=loom/myproj:apt2467/1
  │  ├─ myproj:apt2467:1:1  [done]  task
  │  └─ myproj:apt2467:1:2  [done]  task
  └─ myproj:apt2467:2  [ready]  story
  ```
- **`--json`**: flat array, children-as-qid-refs:
  ```json
  {
    "root": "myproj:apt2467",
    "items": [
      {"qid": "myproj:apt2467", "type": "epic", "status": "ready",
       "branch": "loom/myproj:apt2467", "pr_url": null, "assignee": "<sid>",
       "deps": [], "children": ["myproj:apt2467:1", "myproj:apt2467:2"]},
      ...
    ]
  }
  ```

`--depth N` limits to N levels under the qid (1 = direct children only). `--status STR` filters items to a single status.

**Why:** the orchestrator's status display, the validator, and the merge-and-validate agent all need a hierarchical view. Flat-array JSON is friendlier for agents than nested objects (uniform item shape, easy to filter / build a dict from).

### 4.4 `loom order <qid> [--recursive] [--include-done] [--json]`

New read-only command. Returns the children of `<qid>` (or descendants with `--recursive`) in **topological order respecting deps**. Same-rank items ordered by qid. By default, done items are skipped; `--include-done` to include them.

**Why:** the story-executor reads `loom order <story-qid>` once upfront and walks the result deterministically, creating Claude TodoList items in that exact order.

### 4.5 `loom reopen <qid>`

New command. Sets `<qid>` and all descendants to `status=ready`, clears their `assignee`. Used when a story is discarded after a failed merge or failed validation: the story-integrator's caller runs `loom reopen <sqid>` to reset state cleanly so the story reappears in the next `loom ready` query.

### 4.6 `assignee` field convention

`docs/MARKDOWN_SPEC.md` documents an optional `assignee: <string>` frontmatter field. Loom doesn't enforce a format; the loom/superpowers workflow uses four states:

| State | Value | Meaning |
|---|---|---|
| Unassigned | empty / field absent | Never started, or just discarded by `loom reopen` |
| Scheduled | `<session_id>` | Created by a session's planning step; no worker dispatched yet |
| Active | `<session_id>:<agent_id>` | A specific subagent currently owns the item |
| Completed | `<session_id>:<agent_id>` + `status=done` | Audit record of who completed it |

For epics, the Active and Completed states use just `<session_id>` (no `agent_id` — the main session owns the epic directly, not a subagent). For stories, all four states are reachable.

`schema_version` bumps to **3** as part of this documentation change. No format change beyond the new optional field.

### 4.7 `## Validation Criteria` body section

Pure convention; loom doesn't parse it. The writing-plans skill enforces that every story and epic body contains a `## Validation Criteria` heading followed by a markdown checklist. The story-integrator and epic-validator agents extract the section by heading.

---

## 5. Superpowers plugin changes

### 5.1 Agent definitions (`agents/`)

New `agents/` directory at the plugin root, with one definition per agent role:

| File | Role | Tools | Notes |
|---|---|---|---|
| `agents/story-executor.md` | Single-threaded over a story's tasks; TDD per task; commits to story branch; returns structured report. Does NOT merge. | Read, Edit, Write, Bash, Grep, Glob, Skill (TDD + verification), gitnexus MCP | Runs in a per-story worktree |
| `agents/story-integrator.md` | Per-story merge + validate. Attempts merge into parent branch; trivial inline conflict resolution; runs Validation Criteria + tests + lint + format; reverts on validation failure. | Bash, Read, Edit, Grep, Glob, Skill | Runs in the epic worktree |
| `agents/epic-validator.md` | Final whole-epic validation using `verify` skill (tests + app behavior). | Bash, Read, Grep, Glob, Skill (verify) | Runs in the epic worktree |
| `agents/codebase-researcher.md` | Used during grooming for context enrichment. Short-report contract. | Read, Grep, Glob, gitnexus MCP, WebFetch | Runs in cwd |

Each agent definition is `.md` with frontmatter (`name`, `description`, `tools`, optionally `model`) and a system prompt body. Skills dispatch them by name via the `Agent` tool.

### 5.2 Hooks (`hooks/`)

New `hooks/` directory at the plugin root. Four hook scripts, registered in `.claude-plugin/plugin.json`.

All hooks parse stdin JSON via `jq` and inspect `agent_type` to decide **strict** vs **permissive** mode:

- **Strict mode** activates when `agent_type` matches one of: `story-executor`, `story-integrator`, `epic-validator`, `codebase-researcher`.
- **Permissive mode** is the default (main session, Explore, general-purpose, etc.) — hooks act only when a qid prefix is already present, never block.

| Script | Event | Strict-mode behavior | Permissive-mode behavior |
|---|---|---|---|
| `hooks/loom-subagent-context-inject.sh` | `SubagentStart` | Injects `## Loom Workflow Context` block via `hookSpecificOutput.additionalContext` with `session_id`, `agent_id`, `agent_type`, and a directive: "as your first action, run `loom update <story-qid> assignee <sid>:<aid>`". | No-op |
| `hooks/loom-task-created-guard.sh` | `TaskCreated` | Subject MUST start with `[<qid>] `; qid MUST resolve to an existing loom task in `ready` status. Otherwise: block + emit precise error (malformed / not found / wrong type / wrong status). | If a qid prefix happens to be present, soft-validate; warn to stderr if unresolved; never block. |
| `hooks/loom-task-inprogress-sync.sh` | `PostToolUse(TaskUpdate)` filtered on `tool_input.status == "in_progress"` | If subject has `[<qid>] ` prefix, run `loom update <qid> status in_progress`. | Same. (Permissive mode never has strict requirements on the prefix.) |
| `hooks/loom-task-completed-sync.sh` | `TaskCompleted` | Subject MUST have `[<qid>] ` prefix; run `loom complete <qid>`. | If a qid prefix is present, run `loom complete <qid>`; never block. |

If `TaskCreated` / `TaskCompleted` events turn out to be unavailable in the deployed Claude Code version, fall back to `PreToolUse(TaskCreate)` / `PostToolUse(TaskUpdate)` with a `status == "completed"` filter respectively. Behavior is identical.

### 5.3 Skill rewrites

#### `skills/brainstorming/SKILL.md` (rewritten)

- If invoked via `/epic` or `/story`, receives `mode` and proceeds with that scope.
- If invoked any other way, **first decides scope** itself: end-to-end feature / multi-subsystem refactor → epic; single-file or scoped change → story; borderline → ask the user.
- Always loom-backed. No spec doc is ever written.
- Sequence: auto-bind loom → dispatch `codebase-researcher` agent for context → ask clarifying questions one at a time (existing discipline preserved) → assemble an in-conversation draft (title, body with `## Validation Criteria`, draft child items for epics, draft tasks for stories, deps) → get user approval → hand off to `writing-plans` with the draft and `session_id`.

#### `skills/writing-plans/SKILL.md` (rewritten)

- Always loom-backed. No plan markdown file is ever written.
- Body template enforced for every story and epic:
  ```markdown
  ## Summary
  <one-paragraph statement of what this delivers>

  ## Context
  <what the code looks like today; pointers to files/symbols the agent will touch>

  ## Validation Criteria
  - [ ] <observable criterion 1>
  - [ ] <observable criterion 2>

  ## Implementation Notes
  <approach decisions made during grooming>

  ## Out of Scope
  <things explicitly NOT in this item>
  ```
- Criteria rules: each is observable from "criteria + final code state" alone (no implementation-detail criteria). May name expected behaviors, expected files/functions, expected test results.
- CLI usage pattern:
  ```sh
  EPIC=$(loom epic create <project> --title "..." --body-file /tmp/.../epic.md -y)
  loom update $EPIC assignee ${CLAUDE_SESSION_ID}
  STORY=$(loom story create $EPIC --title "..." --body-file /tmp/.../story-N.md -y)
  loom update $STORY assignee ${CLAUDE_SESSION_ID}    # Scheduled state
  loom task create $STORY --title "..." --body-file /tmp/.../task-N-M.md -y
  loom dep add <source-qid> --on <target-qid>
  ```
  Every created epic and story receives `assignee: <session_id>` at plan time (Scheduled state). The story-executor later overwrites stories to `<session_id>:<agent_id>` (Active state) via the SubagentStart-injected directive. Tasks do not receive assignee.
- Self-review: run `loom validate` (existing) + `loom tree <epic-qid>` and show structure to user for sign-off. On approval, hand off to `executing-plans`.

#### `skills/executing-plans/SKILL.md` (rewritten — the orchestrator)

Two shapes based on the item type at entry.

**Epic wave loop:**

```
loop:
  ready = loom ready <epic-qid> --json --type story
  if empty: break

  # Wave dispatch
  for sqid in ready:
    create child worktree: <repo>/.worktrees/<epic-qid>--<sqid> off loom/<epic-qid>
    branch loom/<epic-qid>/<sqid>
    Agent(subagent_type=story-executor, prompt="story_qid=<sqid> worktree=<path> parent_branch=loom/<epic-qid>")
  wait_for_all_subagents()

  # Per-story integrate (merge + validate)
  for sqid in topo_sorted(stories_just_completed_in_this_wave):
    result = Agent(subagent_type=story-integrator,
                   prompt="epic=<eqid> story=<sqid> branch=loom/<eqid>/<sqid>")
    if result.ok:
      loom complete <sqid>
    else:  # merge_failed or validation_failed
      delete worktree <repo>/.worktrees/<eqid>--<sqid>
      git branch -D loom/<eqid>/<sqid>
      loom reopen <sqid>
      retry_counter[sqid] += 1
      if retry_counter[sqid] >= 3:
        HALT with diagnostic

# Final epic validation
result = Agent(subagent_type=epic-validator, prompt="epic=<eqid> branch=loom/<eqid>")
if result.ok:
  hand off to finishing-a-development-branch
else:
  HALT
```

`story-integrator` behavior (defined once in the agent prompt, called per story):

```
git checkout loom/<eqid>
git merge --no-ff loom/<eqid>/<sqid>
if conflicts:
  attempt trivial inline resolution (formatting, import order, whitespace)
  if still conflicted:
    git merge --abort
    return {result: "merge_failed", reason: "..."}
# merge succeeded
load story body via `loom show <sqid> --json`
extract `## Validation Criteria` checklist
run project tests + lint + format
check each criterion against post-merge state
if all pass:
  return {result: "ok", merge_sha: <sha>, criteria: [...]}
else:
  git revert -m 1 HEAD --no-edit
  return {result: "validation_failed", failed_criteria: [...]}
```

**Story (single-item) shape:**

```
create worktree: <repo>/.worktrees/<sqid> off main, branch loom/<sqid>
Agent(subagent_type=story-executor, prompt="story_qid=<sqid> worktree=<path> parent_branch=main")
result = Agent(subagent_type=story-integrator,
               prompt="epic=<none> story=<sqid> branch=loom/<sqid> parent_branch=main")
  # integrator skips the merge step for /story; only runs validation on the story branch
if result.ok:
  hand off to finishing-a-development-branch
else:
  loom reopen <sqid>, retry_counter++, redispatch up to 3 times, then HALT
```

**Orchestrator-owned state:**

- `<epic-worktree>/.loom/retry-counters.json` — per-story retry counts, ephemeral
- Per-agent JSONL logs under `${XDG_STATE_HOME:-$HOME/.local/state}/loom/<project>/<epic_qid>/` — event trail written by `hooks/lib/loom-log-event.sh`
- TodoList items in the orchestrator's own session use `[<story-qid>] <title>` subjects (permissive mode, since main session is not a defined agent_type)

**Halt UX:** halts leave workspace inspectable — branches in place, worktrees in place, loom items reflect current status. User can `cd <epic-worktree>` and run `loom tree <epic-qid>` to assess.

#### `skills/subagent-driven-development/` (deleted)

The directory and its `SKILL.md` are removed. Its role — single-threaded sequential task execution by a subagent — is fully captured by the `story-executor` agent definition.

### 5.4 Entry skills

#### `skills/epic/SKILL.md`

```markdown
---
name: epic
description: Use when the user types /epic followed by a description of a large
  feature, refactor, or end-to-end change. Drives the full loom-backed planning
  and parallel execution workflow.
---

# /epic — Large-feature workflow

The user has invoked `/epic <description>`. Description in $ARGUMENTS. Session
id is ${CLAUDE_SESSION_ID}.

## Mandatory sequence

1. Bind loom to this repo (walk up for `.loom/state.json`; `loom project create
   <repo-basename> -y` if absent).
2. Hand off to the brainstorming skill with `mode=epic`, `description=$ARGUMENTS`,
   `project=<project-qid>`, `session_id=${CLAUDE_SESSION_ID}`.
3. brainstorming returns a groomed draft; hand off to writing-plans with the
   draft. writing-plans materializes epic + stories + tasks + deps and sets
   `assignee: ${CLAUDE_SESSION_ID}` on the epic and on every story (Scheduled
   state per §4.6).
4. Invoke using-git-worktrees to create `<repo>/.worktrees/<epic-qid>/` on
   branch `loom/<epic-qid>` off main.
5. Hand off to executing-plans with `epic_qid=<qid>`, `worktree=<path>`. It
   runs the wave loop and final epic validation.
6. On validation pass, hand off to finishing-a-development-branch.

## Constraints

- Never skip the groom phase. Research always adds value.
- No implementation code is written from this skill. All implementation is
  inside story-executor subagents in story worktrees.
- On halt at any step (cycle, validation, merge), surface the diagnostic and
  stop. No silent retries beyond the orchestrator's bounded counters.
```

#### `skills/story/SKILL.md`

```markdown
---
name: story
description: Use when the user types /story followed by a description of a
  small, scoped change — a bugfix, single-file refactor, or self-contained
  feature. Drives the loom-backed flow at story scale.
---

# /story — Small-change workflow

The user has invoked `/story <description>`. Description in $ARGUMENTS. Session
id is ${CLAUDE_SESSION_ID}.

## Mandatory sequence

1. Bind loom to this repo.
2. Target epic = `<project>:backlog` (auto-created on every project at loom
   schema_version=2; create explicitly if absent for older projects).
3. Hand off to brainstorming with `mode=story`, `description=$ARGUMENTS`,
   `epic=<project>:backlog`, `session_id=${CLAUDE_SESSION_ID}`.
4. brainstorming returns a groomed story draft (title, body with criteria, task
   list). Hand off to writing-plans, which creates the story under backlog and
   its tasks; sets `assignee: ${CLAUDE_SESSION_ID}` on the story.
5. Invoke using-git-worktrees to create `<repo>/.worktrees/<story-qid>/` on
   branch `loom/<story-qid>` off main.
6. Hand off to executing-plans with `story_qid=<qid>`, `worktree=<path>`. It
   dispatches one story-executor, then one story-integrator (validation only,
   no merge), then hands off to finishing-a-development-branch.

## Constraints

Same as /epic: no skipped groom phase, no direct code changes from this skill.
```

---

## 6. Hook → context injection mechanics

`SubagentStart` is the canonical mechanism. Documented behavior per Claude Code hooks reference: the hook receives `session_id`, `agent_id`, `agent_type`, `transcript_path` on stdin (subagent-context fields). The script returns:

```json
{
  "hookSpecificOutput": {
    "additionalContext": "## Loom Workflow Context\n- session_id: <sid>\n- agent_id: <aid>\n- agent_type: <atype>\n\nIf you are a story-executor: as your first action, run `loom update <story-qid> assignee <sid>:<aid>` for the story qid passed in your prompt.\n\nThe TaskCreated/TaskCompleted hooks are enforcing strict mode for your agent_type — every TaskCreate must have a `[<task-qid>] ` prefix matching an existing ready task under your story."
  }
}
```

`additionalContext` is rendered as a system reminder visible to the subagent before its first turn. The subagent self-attributes on first action; `loom show <story-qid>` then reflects ownership in real time, no polling.

For the main `/epic` session, `${CLAUDE_SESSION_ID}` substitution in SKILL.md handles the equivalent — the value is rendered into the prose at skill-load time and passed to `loom update <epic-qid> assignee <sid>`.

**Field-name caveat (implementation-time verification):** the `SubagentStart` event body's exact schema is mentioned but not fully spelled out in the docs research pass. If `agent_id` turns out to be absent in actual events, fallback is parsing the most-recent transcript JSONL filename under the transcripts dir. The design is not sensitive to which mechanism wins.

---

## 7. Failure modes and recovery

| Failure | Detection | Recovery | Halt threshold |
|---|---|---|---|
| Story-executor returns without all tasks done | Executor reports incomplete tasks | Story stays in-progress; orchestrator notes and treats as discard | 1 — no retry on incomplete-executor |
| Story merge has non-trivial conflicts | story-integrator returns `merge_failed` | `loom reopen <sqid>`, delete branch + worktree; reappears in next `loom ready` | 3 retries across waves, then halt |
| Story validation criteria fail post-merge | story-integrator returns `validation_failed`; reverts the merge | `loom reopen <sqid>`, delete branch + worktree | 3 retries across waves, then halt |
| Cycle detected during planning | `loom dep add` rejects | writing-plans surfaces the cycle to user | 0 retries |
| Epic validation fails at end | epic-validator returns failure | Halt; user inspects, decides | 0 retries (human-only decision) |
| Hook strict-mode rejection on TaskCreate | TaskCreated hook blocks | Agent receives the error in its context, self-corrects | N/A — agent-level loop |

Halt UX: workspace inspectable; `loom tree <epic-qid>` shows current state; per-agent JSONL logs under `${XDG_STATE_HOME:-$HOME/.local/state}/loom/<project>/<epic_qid>/` have the full event trail (see `docs/orchestrator-log.md`); retry counters preserved in case the user wants to manually reset.

---

## 8. File-by-file change list

### `~/tech/loom`

| # | File | Change |
|---|---|---|
| L1 | `src/loom/cli.py` | Add `--body-file` to project/epic/story/task create + update; extend `loom ready` to take optional qid + `--recursive`; add `loom tree`, `loom order`, `loom reopen` commands. |
| L2 | `src/loom/api.py` | Add `order()`, `tree()`, `reopen()` facade methods. Extend `ready()` signature. |
| L3 | `src/loom/items.py` | Implement `reopen()` mutator; `set_body_from_file()` helper. |
| L4 | `src/loom/deps.py` | Add topological sort utility (reuse existing graph machinery). |
| L5 | `docs/MARKDOWN_SPEC.md` | Document optional `assignee` field; bump `schema_version` to 3. |
| L6 | `docs/WORKFLOW.md` (new) | Public document describing the loom-as-backend-for-Claude-Code workflow. |
| L7-12 | `tests/test_body_file.py`, `test_ready_scoped.py`, `test_tree.py`, `test_order.py`, `test_reopen.py`, `tests/test_e2e.py` | Unit + e2e coverage for each new feature. |

### `~/tech/superpowers`

| # | File | Change |
|---|---|---|
| S1 | `agents/story-executor.md` | New agent definition. |
| S2 | `agents/story-integrator.md` | New agent definition (combines merge + per-story validation). |
| S3 | `agents/epic-validator.md` | New agent definition (uses `verify` skill). |
| S4 | `agents/codebase-researcher.md` | New agent definition (research during grooming). |
| S5 | `hooks/loom-subagent-context-inject.sh` | New `SubagentStart` hook. |
| S6 | `hooks/loom-task-created-guard.sh` | New `TaskCreated` hook (with PreToolUse(TaskCreate) fallback). |
| S7 | `hooks/loom-task-inprogress-sync.sh` | New `PostToolUse(TaskUpdate)` hook filtered on `status=in_progress`. |
| S8 | `hooks/loom-task-completed-sync.sh` | New `TaskCompleted` hook (with PostToolUse(TaskUpdate) status=completed fallback). |
| S9 | `.claude-plugin/plugin.json` | Register hooks; declare `agents/` and `hooks/` directories. |
| S10 | `skills/brainstorming/SKILL.md` | Rewrite (loom-only; auto-scope decision when mode not pre-seeded). |
| S11 | `skills/writing-plans/SKILL.md` | Rewrite (loom-only; emit items via CLI; enforce body template). |
| S12 | `skills/executing-plans/SKILL.md` | Rewrite (epic-wave orchestrator + story-flow variant). |
| S13 | `skills/subagent-driven-development/` | **Delete** the directory. |
| S14 | `skills/epic/SKILL.md` | New entry skill. |
| S15 | `skills/story/SKILL.md` | New entry skill. |
| S16 | `README.md` and/or `AGENTS.md` | Document the new `/epic` / `/story` commands and the loom-backed chain. |

---

## 9. Open implementation-time questions

These are intentionally deferred to the writing-plans phase because they require verification against the live Claude Code / loom code, not design decisions:

1. **Exact `SubagentStart` event body field names** (`agent_id` vs `subagent_id` vs other) — verify when implementing the hook script.
2. **Availability of `TaskCreated` / `TaskCompleted` events** — if absent, use the PreToolUse/PostToolUse fallback described above.
3. **`loom complete` idempotency** — verify that running it on an already-done item is a no-op or harmless. If it errors, the completion hook adds a status-check before calling.
4. **`loom project create` re-bind behavior** — re-running in an already-bound workspace already emits a warning per the current CLI; verify this is non-destructive enough for the auto-bind path on every `/epic` invocation.

---

**Approval:** this spec is approved as of 2026-05-22. Implementation plan to be drafted via the writing-plans skill in a follow-up session.
