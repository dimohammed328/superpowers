---
name: executing-plans
description: "Use after writing-plans has materialized loom items. Orchestrates execution end-to-end: epic-wave loop (parallel story-executor dispatch + per-story merge & validate) for epic scope, or single-executor-then-integrator for story scope; on validation success, finalizes the branch (merge + push by default, or `gh pr create` when the user explicitly asked for a PR)."
---

# Executing Plans — loom-backed orchestrator

<SUBAGENT-STOP>
If you were dispatched as a subagent (story-executor, story-integrator,
epic-validator, codebase-researcher, or any other agent type), STOP — this
skill is not yours. It is the orchestrator's, and only the main session
runs it. Subagents that invoke this skill will create nested orchestration
loops, mis-write the parent session's worktree state, and corrupt the
epic-wave invariants. Return to your dispatched task instructions instead.
</SUBAGENT-STOP>

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

This file is gitignored by loom's `.loom/.gitignore`.

## Semantic event logging

The orchestrator emits semantic events via `hooks/lib/loom-log-event.sh` at key decision points — moments the mechanical hooks (SubagentStart, TaskUpdate, etc.) cannot observe. These are wave composition, retry rationale, validation outcome interpretation, and the finalize decision. Mechanical events (agent lifecycle, task transitions, commits) are handled automatically; do not re-emit them.

Base invocation pattern:
```bash
hooks/lib/loom-log-event.sh \
  --kind <semantic_kind> \
  --epic-qid <epic_qid> \
  --agent-id "${CLAUDE_SESSION_ID}-orchestrator" \
  --session-id "$CLAUDE_SESSION_ID" \
  --agent-type "story-executor" \
  [--story-qid <sqid>] \
  [--field key=value] ...
```

See `docs/orchestrator-log.md` for the full semantic event vocabulary and per-kind payload spec.

## Epic wave loop

### Setup (once per `/epic`)

1. Call `EnterWorktree` with `name="loom/<epic-qid-dashed>"` to enter a
   worktree for the epic. The harness creates the worktree at
   `<repo>/.claude/worktrees/<name-with-slashes-replaced>/` on a branch
   named `worktree-<name>` (the renamed-slash form), off the parent
   session's HEAD (typically `main`).
2. Confirm the working directory is the epic worktree (the harness sets
   cwd as part of `EnterWorktree`) and record:
   - `<epic_worktree>` — the absolute path printed by `pwd`.
   - `<epic_branch>` — the branch name from `git rev-parse --abbrev-ref HEAD`.

   You will pass both to story-integrator dispatches.
3. Initialize retry counters file: `mkdir -p .loom && echo "{}" > .loom/retry-counters.json`.

### How subagents create their own worktrees

Story-executor agents are declared with `isolation: worktree` in their
frontmatter. The Claude Code harness automatically creates a per-subagent
worktree on dispatch — you do NOT pass an `isolation` parameter or specify
a worktree path. The base branch is governed by the `worktree.baseRef`
setting (must be `"head"` in `~/.claude/settings.json` so subagents branch
off the orchestrator's current HEAD, i.e. the epic branch).

The harness names the auto-worktree's branch `worktree-<random>` and
places it at `<repo>/.claude/worktrees/<random>/`. The executor records
both and reports them back in its result JSON as `branch` and `worktree`.
You forward those exact values to the story-integrator — do NOT construct
branch names from the story qid.

### Loop body (until no ready stories remain)

```
loop:
    ready=$(loom ready <epic-qid> --type story --json)
    if [empty]: break

    # Wave N: dispatch story-executor subagents in PARALLEL
    # Log wave composition before dispatch — the orchestrator knows which stories
    # are in the wave; mechanical hooks only see individual subagent starts.
    hooks/lib/loom-log-event.sh \
      --kind wave_start \
      --epic-qid <epic_qid> \
      --agent-id "${CLAUDE_SESSION_ID}-orchestrator" \
      --session-id "$CLAUDE_SESSION_ID" \
      --agent-type "story-executor" \
      --field "wave_index=<N>" \
      --field "story_qids=<sqid1> <sqid2> ..."

    for each sqid in ready:
        - Dispatch:
            Agent(subagent_type="story-executor",
                  prompt="story_qid=<sqid> parent_branch=<epic_branch>")
          # The harness creates the executor's worktree automatically via
          # the agent's `isolation: worktree` frontmatter. The executor
          # records its assigned branch + worktree path and returns them
          # in its result JSON.
    wait for ALL parallel dispatches to complete

    # Extract from each executor's return value the fields you need to
    # dispatch the integrator. Each executor returns JSON of shape:
    #   {"story_qid": "...", "branch": "worktree-<random>",
    #    "worktree": "<repo>/.claude/worktrees/<random>/", "commits": [...],
    #    "tasks_done": [...], "notes": "..."}
    # Store per-sqid: executor_branch[sqid], executor_worktree[sqid].

    # Log wave completion with a brief outcome summary.
    hooks/lib/loom-log-event.sh \
      --kind wave_complete \
      --epic-qid <epic_qid> \
      --agent-id "${CLAUDE_SESSION_ID}-orchestrator" \
      --session-id "$CLAUDE_SESSION_ID" \
      --agent-type "story-executor" \
      --field "wave_index=<N>" \
      --note "<M ok, K failed>"

    # Integrate each completed story sequentially
    for each sqid that the executor reported done (topo order):
        result = Agent(subagent_type="story-integrator",
                       prompt="epic_qid=<epic-qid> story_qid=<sqid> "
                              "branch=<executor_branch[sqid]> "
                              "parent_branch=<epic_branch> "
                              "epic_worktree=<epic_worktree> "
                              "story_worktree=<executor_worktree[sqid]>")
        if result.result == "ok":
            loom complete <sqid>
        elif result.result in ("merge_failed", "validation_failed"):
            # Discard the story; it goes back to ready and gets picked up next iteration.
            git -C <epic_worktree> worktree remove --force <executor_worktree[sqid]>
            git -C <epic_worktree> branch -D <executor_branch[sqid]>
            loom reopen <sqid>
            increment retry_counter[sqid] in .loom/retry-counters.json
            if retry_counter[sqid] >= 3:
                HALT with diagnostic — surface result.reason / failed_criteria to the user
            # Log the retry decision so the audit trail captures the rationale.
            hooks/lib/loom-log-event.sh \
              --kind retry_decision \
              --epic-qid <epic_qid> \
              --agent-id "${CLAUDE_SESSION_ID}-orchestrator" \
              --session-id "$CLAUDE_SESSION_ID" \
              --agent-type "story-executor" \
              --story-qid <sqid> \
              --field "attempt=<retry_counter[sqid]>" \
              --field "reason=<result.result>: <brief description>"
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
   - Proceed to the **Finalize branch** section below to merge/push (or open a PR).
3. Else: HALT with the validator's diagnostic. Do not auto-retry at the epic level — that's a human decision.

## Story (single-item) shape

For `story_qid=...` entry:

1. Dispatch one story-executor:
   ```
   Agent(subagent_type="story-executor",
         prompt="story_qid=<sqid> parent_branch=main")
   ```
   The harness creates the executor's worktree automatically (`isolation:
   worktree` frontmatter). The executor returns `branch` and `worktree` in
   its result JSON. Capture both.
2. Wait. Then dispatch a story-integrator with `epic_qid=none` (the integrator will skip the merge step and run validation directly on the story branch):
   ```
   Agent(subagent_type="story-integrator",
         prompt="epic_qid=none story_qid=<sqid> "
                "branch=<executor_branch> "
                "parent_branch=main "
                "epic_worktree=<repo-root> "
                "story_worktree=<executor_worktree>")
   ```
3. If `result.ok`:
   - `loom complete <sqid>`
   - Proceed to the **Finalize branch** section below to merge/push (or open a PR).
4. If `result` is merge_failed or validation_failed:
   - `loom reopen <sqid>`, increment retry counter, redispatch up to 3 times.
   - On exhausting retries: HALT.

## Tracking work in the orchestrator's own TodoList

In your own (main session) TodoList, use subjects formatted as `[<sqid>] <story title>` while a wave is in flight. The main session is in **permissive mode** for the hooks (not a defined agent_type), so the prefix is optional but doing it lets the loom-task-completed-sync hook auto-complete the story tracking item if a wave finishes cleanly.

## Finalize branch

On final validation success, this skill itself terminates the flow by integrating the validated branch into its parent. There is no further handoff.

**What "the branch" means here:**
- For epic flow: the epic branch `loom/<epic-qid>` is merged into `main`.
- For story flow (`/story`): the story branch `loom/<sqid>` is merged into `main`.

**Default behavior (merge + push):**

Before merging, emit an `epic_finalize` event so the log captures the finalize decision:
```bash
hooks/lib/loom-log-event.sh \
  --kind epic_finalize \
  --epic-qid <epic_qid> \
  --agent-id "${CLAUDE_SESSION_ID}-orchestrator" \
  --session-id "$CLAUDE_SESSION_ID" \
  --agent-type "story-executor" \
  --field "merged_to=<parent>"
```

Then merge and push:
```bash
cd <repo-root>          # use the main checkout, not the worktree
git fetch origin
git checkout <parent>   # main for epics, main for /story flow
git pull --ff-only
git merge --no-ff <branch> -m "Merge <branch>: <one-line summary>"
git push origin <parent>
```

Use `--no-ff` to preserve the branch boundary in history, matching the convention the story-integrator already uses for per-story merges into the epic branch.

After a successful push, clean up the local branch and worktree:

```bash
git branch -d <branch>
git worktree remove <worktree-path>   # if a worktree existed for this branch
```

**PR mode (only when the user explicitly asked):**

If the original `/epic` or `/story` request named "PR" or "pull request" (e.g. "open a PR for X", "send a pull request that does Y"), do not merge locally. Instead, emit `epic_finalize` with a `pr_url` once the PR is created, then push the branch and open a PR:

```bash
git push -u origin <branch>
pr_url=$(gh pr create --base <parent> --head <branch> \
  --title "<epic or story title>" \
  --body "<summary derived from the loom item body>")

hooks/lib/loom-log-event.sh \
  --kind epic_finalize \
  --epic-qid <epic_qid> \
  --agent-id "${CLAUDE_SESSION_ID}-orchestrator" \
  --session-id "$CLAUDE_SESSION_ID" \
  --agent-type "story-executor" \
  --field "merged_to=<parent>" \
  --field "pr_url=${pr_url}"
```

Leave the branch and worktree in place; the user will land the PR.

**How to tell which mode applies.** Look at the original user request that triggered `/epic` or `/story`. If it contains the literal words "PR" or "pull request", use PR mode. Otherwise use the default merge + push. If genuinely ambiguous, ask once before acting.

**Validation failure path is unchanged:** if the final validator returned a failure, halt and surface the diagnostic — do not attempt to finalize.

## Halt UX

When you halt, leave the workspace inspectable:
- Branches stay in place
- Worktrees stay in place (the failed-story worktree was deleted; others remain)
- Loom items reflect current status
- The per-agent JSONL logs under `${XDG_STATE_HOME:-$HOME/.local/state}/loom/<project>/<epic_qid>/` have the full event trail; merge and sort by `ts` to reconstruct the timeline (see `docs/orchestrator-log.md`)
- `.loom/retry-counters.json` shows what's been retried

Tell the user where things stand and suggest concrete next steps (e.g., "Run `cd <epic-worktree> && loom tree <epic-qid>` to inspect; the failing story is `<sqid>` with these unmet criteria: ...").

## Constraints

- **Never call `git push` or open PRs before final validation passes.** Pushing / PR-opening happens only in the Finalize branch section, after the final validator returns `ok`.
- **Never call `loom complete` on a story before the integrator returns `ok`.**
- **Never auto-retry at the epic level.** Halt and surface.
- **Bounded retries**: 3 per story across waves.
