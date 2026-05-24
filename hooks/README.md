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
