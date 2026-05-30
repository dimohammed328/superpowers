# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Superpowers is a **multi-harness coding-agent plugin**, not an application. The "product" is the collection of skills, agents, and hooks under `skills/`, `agents/`, and `hooks/` — most of it is markdown and shell, with a small JS plugin entry for OpenCode. The same content is shipped to seven harnesses (Claude Code, Codex CLI/App, Factory Droid, Gemini CLI, OpenCode, Cursor, GitHub Copilot CLI), each with its own thin manifest in a top-level dotdir:

- `.claude-plugin/` — Claude Code plugin + dev marketplace manifests
- `.codex-plugin/`, `.cursor-plugin/` — per-harness manifests
- `.opencode/plugins/superpowers.js` — OpenCode's JS plugin entry (`package.json` `main` points here)
- `gemini-extension.json` + `GEMINI.md` — Gemini CLI extension
- `agents/openai.yaml` files inside each skill — Codex-specific per-skill metadata, preserved by the sync script

Any change you make is content for *all* of these harnesses unless it lives inside one of those dotdirs.

## Common commands

```bash
# Version bookkeeping — version is declared in many manifests
scripts/bump-version.sh --check          # detect drift across manifests
scripts/bump-version.sh --audit          # check + grep repo for stale version strings
scripts/bump-version.sh 5.2.0            # bump every declared file in .version-bump.json

# Sync the upstream plugin into the Codex plugins fork (opens a PR on prime-radiant-inc/openai-codex-plugins)
scripts/sync-to-codex-plugin.sh -n       # dry-run preview (always shown anyway)
scripts/sync-to-codex-plugin.sh          # full run: clone fork, rsync, commit, push, gh pr create

# Hook unit tests (fast, hermetic — each spins up a temp loom workspace)
tests/hooks/test_subagent_context_inject.sh

# Claude Code skill tests (slow; require `claude` CLI on PATH and dev marketplace enabled)
tests/claude-code/run-skill-tests.sh                 # fast unit tests (currently none registered)
tests/claude-code/run-skill-tests.sh --integration   # full integration runs, 10–30 min each
tests/skill-triggering/run-test.sh <skill> <prompt>  # does a naive prompt auto-trigger a skill?
tests/explicit-skill-requests/run-test.sh <skill> <prompt>

# Codex sync self-test
tests/codex-plugin-sync/test-sync-to-codex-plugin.sh
```

Integration tests must be run **from the repo root** so Claude Code resolves the local plugin, and require `"superpowers@superpowers-dev": true` in `~/.claude/settings.json` `enabledPlugins`. See `docs/testing.md` for the session-transcript verification pattern (`.jsonl` parsing, `analyze-token-usage.py`).

## Architecture

### Skills (`skills/<name>/SKILL.md`)

Each skill is a single `SKILL.md` with YAML frontmatter (`name`, `description`) plus optional supporting files in the same directory. The `description` field is what the harness uses to decide when to auto-trigger the skill — it is **behavior-shaping prose**, not documentation. Treat edits to descriptions and to in-skill content like behavior changes: pressure-test with subagents per `skills/writing-skills/SKILL.md`.

### Agents (`agents/*.md`)

Subagent definitions used by the loom-backed planning workflow: `codebase-researcher`, `story-executor`, `story-integrator`, `epic-validator`. Same frontmatter pattern; tools/model/effort are declared per agent.

### Hooks (`hooks/`)

Wired up in `.claude-plugin/plugin.json` and (for the SessionStart bootstrap) `hooks/hooks.json`. Two roles:

1. **`session-start`** — injects the full `using-superpowers` SKILL.md into every new session as `additionalContext`. The script branches on `CURSOR_PLUGIN_ROOT` / `CLAUDE_PLUGIN_ROOT` / `COPILOT_CLI` env vars because each harness expects a different JSON shape (`additional_context` vs `hookSpecificOutput.additionalContext` vs `additionalContext`). Don't emit more than one — Claude Code reads both without dedup.
2. **`loom-*.sh`** — Two remaining loom hooks: `loom-subagent-context-inject.sh` injects the workflow-context block at SubagentStart; `loom-log.sh` logs task/subagent lifecycle events. Story executors drive loom task status directly (via `loom update` / `loom complete`) — there are no hook scripts that mirror status.

### Loom-backed planning workflow

The `/epic` and `/story` slash commands drive a project-managed planning loop backed by the external `loom` CLI (workspace lives in `.loom/`, gitignored). The contract — story executors live in worktrees, drive loom task status directly, never merge their own branches — is described in `agents/story-executor.md`, `agents/story-integrator.md`, and the design doc `docs/plans/2026-05-22-loom-backed-planning-design.md`. If you change hook behavior or subagent frontmatter, re-read those before assuming the new behavior composes.

## Cross-harness invariants

- **Version is declared in six files** (see `.version-bump.json`). Never edit one by hand — use `scripts/bump-version.sh`. The `--audit` mode greps the repo for stragglers.
- **The codex-plugin sync is deterministic.** `scripts/sync-to-codex-plugin.sh` excludes top-level infra (`/.claude/`, `/scripts/`, `/tests/`, `/docs/`, `/hooks/`, `/CLAUDE.md`, `/RELEASE-NOTES.md`, etc.) — only the harness-agnostic plugin payload ships. If you add a new top-level dir that should not ship to Codex, add it to the `EXCLUDES` array.
- **Skills are loaded by all harnesses simultaneously.** Don't reference Claude Code–only tool names (`TaskCreate`, `Skill`, etc.) in skill bodies without checking how Codex/Gemini/Cursor render the same skill. The Gemini variant uses `GEMINI.md` as its context file (`gemini-extension.json` sets `contextFileName`), and OpenCode loads `using-superpowers/SKILL.md` via `@`-include in its JS plugin.
- **`.opencode/plugins/superpowers.js` is the OpenCode entry point.** `package.json` `main` and `type: "module"` exist for that single file; this is not a Node project.

## Local vs upstream

The git remote in this checkout is a personal fork. The upstream project (`obra/superpowers`) has a strict contribution model — most changes here are intended to stay local or land via the documented PR flow. Don't open PRs to upstream from automated runs without explicit user instruction.
