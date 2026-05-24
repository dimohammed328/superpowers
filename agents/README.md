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
