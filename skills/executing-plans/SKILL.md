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

1. Call `EnterWorktree` to enter a worktree on branch `loom/<epic-qid>` off `main`. The harness creates the worktree (typically at `<repo>/.worktrees/<epic-qid>/`) and switches the session into it.
2. Confirm the working directory is the epic worktree (the harness sets cwd as part of `EnterWorktree`).
3. Initialize retry counters file: `echo "{}" > .loom/retry-counters.json`.

### Loop body (until no ready stories remain)

```
loop:
    ready=$(loom ready <epic-qid> --type story --json)
    if [empty]: break

    # Wave 1: dispatch story-executor subagents in PARALLEL
    for each sqid in ready:
        - Dispatch:
            Agent(subagent_type="story-executor",
                  prompt="story_qid=<sqid> parent_branch=loom/<epic-qid>")
          # The story-executor calls EnterWorktree on startup to create
          # its own worktree on branch loom/<epic-qid>/<sqid> off loom/<epic-qid>.
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

1. Dispatch one story-executor:
   ```
   Agent(subagent_type="story-executor",
         prompt="story_qid=<sqid> parent_branch=main")
   ```
   The story-executor calls `EnterWorktree` on startup to create its own worktree on branch `loom/<sqid>` off `main`.
2. Wait. Then dispatch a story-integrator with `epic_qid=none` (the integrator will skip the merge step and run validation directly on the story branch):
   ```
   Agent(subagent_type="story-integrator",
         prompt="epic_qid=none story_qid=<sqid> branch=loom/<sqid> parent_branch=main")
   ```
3. If `result.ok`:
   - `loom complete <sqid>`
   - Invoke `superpowers:finishing-a-development-branch`.
4. If `result` is merge_failed or validation_failed:
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
