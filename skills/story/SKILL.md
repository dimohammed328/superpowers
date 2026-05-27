---
name: story
description: "Use when the user types /story followed by a description of a small, scoped change — a bugfix, single-file refactor, or self-contained feature. Drives the loom-backed flow at story scale: research → groom → plan as a loom story (with tasks) under the project's backlog epic → execute via a single story-executor subagent → validate → finalize the branch (merge + push by default, or `gh pr create` when the user explicitly asked for a PR)."
---

# /story — Small-change workflow

The user has invoked `/story <description>`. The description is in `$ARGUMENTS`. Session id is `${CLAUDE_SESSION_ID}`.

## Mandatory sequence

1. **Bind loom** to this repo (same as `/epic`: walk up for `.loom/state.json`; `loom -y project create <repo-basename>` if absent).

2. **Identify the target epic**: the project's default `backlog` epic (qid `<project>:backlog`). Loom auto-creates the backlog epic on every project at schema_version=2 and later; if it's missing (older project), the `loom story create` command auto-creates it on first use.

3. **Hand off to `superpowers:brainstorming`** with context:
   - `mode=story`
   - `description=$ARGUMENTS`
   - `epic=<project>:backlog`
   - `session_id=${CLAUDE_SESSION_ID}`

4. brainstorming returns a groomed story draft (title, body with criteria, task list).

5. **Hand off to `superpowers:writing-plans`** with the groomed draft. That skill creates the story under backlog and its tasks; sets `assignee: ${CLAUDE_SESSION_ID}` on the story.

6. **Hand off to `superpowers:executing-plans`** with `story_qid=<qid>`. The orchestrator creates the story worktree off main, dispatches one story-executor, then one story-integrator (validation only, on the story branch directly). On validation success, `executing-plans` finalizes the branch in-skill — by default merging into `main` and pushing; if the original `/story` request explicitly named a PR, it pushes the branch and opens one via `gh pr create` instead.

7. On validation pass, you're done. On validation fail after 3 retries, the orchestrator halts and surfaces the diagnostic.

## Differences from /epic

- One story, not many. No parallel fanout.
- No epic worktree. Story worktree branches directly off `main`.
- Validation runs directly on the story branch (no per-story integrator merge into an epic branch). Final integration is done by the `executing-plans` Finalize step itself: merge into `main` and push by default, or `gh pr create` if the user explicitly asked for a PR.
- Lives under the `backlog` epic, not a freshly-created epic.

## Constraints

Same as `/epic`: never skip the groom phase, no direct code changes from this skill, halt on any failure rather than retrying silently.
