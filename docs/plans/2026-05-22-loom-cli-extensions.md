# Loom CLI Extensions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five CLI features to loom (`--body-file`, qid-scoped `loom ready`, `loom tree`, `loom order`, `loom reopen`) and document the `assignee` field convention, to support the loom-backed planning workflow in superpowers (Plan B).

**Architecture:** Thin CLI wrappers over library methods (per `cli.py` doctrine: "The CLI is a thin shell over the library. Anything non-trivial belongs in `loom.api` or `loom.items`."). New methods on `Loom` facade; topological sort utility in `deps.py`; recursive mutator in `items.py`. Schema bump to 3 covers the new `assignee` field documentation (the field itself is already supported as generic frontmatter — already in `Item.assignee` property at `items.py:229`).

**Tech Stack:** Python 3.11, uv, typer, pytest, ruff. Existing loom conventions.

**Repo:** `~/tech/loom`

**Working directory:** All paths in this plan are relative to `~/tech/loom/`. The implementing agent should `cd` there before starting.

**Reference spec:** `~/tech/superpowers/docs/plans/2026-05-22-loom-backed-planning-design.md` §4.

---

## Pre-flight (Task 0)

### Task 0: Baseline verification

**Files:** none modified

- [ ] **Step 1: Confirm working tree clean**

Run: `git status`
Expected: `nothing to commit, working tree clean` on branch `main`.

- [ ] **Step 2: Confirm tests pass on main**

Run: `uv run pytest -q`
Expected: all tests pass, no failures.

- [ ] **Step 3: Confirm lint is clean**

Run: `uv run ruff check src tests && uv run ruff format --check src tests`
Expected: no errors.

If any step fails, STOP and surface to the user. Do not start the plan on a broken baseline.

---

## Task 1: Document the `assignee` field and bump `schema_version` to 3

**Files:**
- Modify: `docs/MARKDOWN_SPEC.md` (frontmatter table + example; add Assignment & ownership section)
- Modify: `src/loom/items.py:117` (the `_build_frontmatter` schema_version default — search for `schema_version` literal)

Note: `Item.assignee` property already exists at `items.py:229`, and `set_assignee` at `items.py:442`. The field is already plumbed through; this task is documentation + version bump only.

- [ ] **Step 1: Update the `schema_version` literal in code**

Locate `schema_version` in `src/loom/items.py` (it appears in `_build_frontmatter`). Change `2` to `3`. Also update the example in `docs/MARKDOWN_SPEC.md` (line 14: `schema_version: 2` → `schema_version: 3`).

- [ ] **Step 2: Add `assignee` documentation to MARKDOWN_SPEC.md**

After the "Identifier rules" section (find the section that documents `branch` and `pr_url` — if not present, add after the frontmatter table at the top). Insert this new section:

```markdown
## Assignment and ownership

Every non-project item may carry an optional `assignee` frontmatter field
recording who currently owns the item. Loom does not enforce a format;
external workflows define the convention.

The loom-backed Claude Code workflow (see `docs/WORKFLOW.md`) uses four
states for this field on stories and epics:

| State      | Value                          | Meaning                                              |
|------------|--------------------------------|------------------------------------------------------|
| Unassigned | empty / field absent           | Never started, or just discarded                     |
| Scheduled  | `<session_id>`                 | Created by a session; no worker dispatched yet       |
| Active     | `<session_id>:<agent_id>`      | A specific subagent currently owns the item          |
| Completed  | `<session_id>:<agent_id>` + `status=done` | Audit record of who completed it          |

For epics, only the bare `<session_id>` form is used (the main session
owns epics directly; no subagent). For stories, all four states are
reachable. Tasks do not carry `assignee`.

The field is settable via `loom update <qid> assignee <value>`.
```

- [ ] **Step 3: Add `## Validation Criteria` convention note**

In the same file, after the Assignment section, add:

```markdown
## Validation criteria convention

Story and epic bodies in the loom-backed Claude Code workflow contain a
`## Validation Criteria` markdown section with a checklist. Loom itself
does not parse or enforce this; the convention lets external validators
(see `docs/WORKFLOW.md`) check completion deterministically. Example:

    ## Validation Criteria
    - [ ] CLI `loom tree <qid>` returns a unicode-indented hierarchy
    - [ ] `loom tree --json` returns a flat array with children-as-qid-refs
    - [ ] Existing `loom show` is unaffected

Criteria should be observable from "criteria + final code state" alone.
```

- [ ] **Step 4: Bump the test fixture's `schema_version` expectation**

Run: `grep -rn "schema_version" tests/ src/loom/`
Expected output: lists every occurrence. For each occurrence in `tests/` that asserts the value is `2`, change to `3`. For each occurrence in `src/loom/` that defaults to `2`, change to `3`. Use Edit, not sed.

- [ ] **Step 5: Run all tests, expect pass**

Run: `uv run pytest -q`
Expected: PASS. (If a test explicitly checks for `schema_version: 2` and we missed it, fix and re-run.)

- [ ] **Step 6: Lint and format**

Run: `uv run ruff check --fix src tests && uv run ruff format src tests`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add docs/MARKDOWN_SPEC.md src/loom/items.py tests/
git commit -m "Document assignee + validation criteria; bump schema_version to 3"
```

---

## Task 2: Library helper — `Item.set_body_from_file()`

**Files:**
- Modify: `src/loom/items.py` (after `set_body`, around line 326)
- Create: `tests/test_body_file.py`

- [ ] **Step 1: Write the failing test**

Create `tests/test_body_file.py`:

```python
"""Tests for --body-file flag and Item.set_body_from_file helper."""

from __future__ import annotations

from pathlib import Path

import pytest

from loom.api import Loom


def test_set_body_from_file_reads_file(loom_dir: Path, tmp_path: Path) -> None:
    body_path = tmp_path / "body.md"
    body_path.write_text("# Heading\n\nbody text.\n", encoding="utf-8")
    loom = Loom(root=loom_dir)
    project = loom.create_project(name="p")
    epic = project.create_epic(title="e")
    epic.set_body_from_file(body_path)
    assert epic.refresh().body.strip().startswith("# Heading")


def test_set_body_from_file_missing_raises(loom_dir: Path, tmp_path: Path) -> None:
    loom = Loom(root=loom_dir)
    project = loom.create_project(name="p")
    epic = project.create_epic(title="e")
    with pytest.raises(FileNotFoundError):
        epic.set_body_from_file(tmp_path / "does-not-exist.md")
```

- [ ] **Step 2: Run the test, expect failure**

Run: `uv run pytest tests/test_body_file.py -v`
Expected: FAIL with `AttributeError: 'Epic' object has no attribute 'set_body_from_file'`.

- [ ] **Step 3: Implement the helper**

In `src/loom/items.py`, after the existing `set_body` method (around line 326), add:

```python
    def set_body_from_file(self, path: Path) -> Item:
        """Read *path* as utf-8 and use its contents as this item's body.

        Raises ``FileNotFoundError`` if *path* doesn't exist. Otherwise
        delegates to :meth:`set_body`.
        """
        body = Path(path).read_text(encoding="utf-8")
        return self.set_body(body)
```

- [ ] **Step 4: Run the test, expect pass**

Run: `uv run pytest tests/test_body_file.py -v`
Expected: PASS, 2/2.

- [ ] **Step 5: Lint, format, commit**

```bash
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/items.py tests/test_body_file.py
git commit -m "Item.set_body_from_file: read body from a file path"
```

---

## Task 3: CLI — `--body-file` on `loom epic create`

**Files:**
- Modify: `src/loom/cli.py:514` (the `epic_create` command)
- Modify: `tests/test_body_file.py` (add CLI test)

- [ ] **Step 1: Write the failing test**

Append to `tests/test_body_file.py`:

```python
from typer.testing import CliRunner

from loom.cli import app


def test_epic_create_body_file(loom_dir: Path, tmp_path: Path) -> None:
    body_path = tmp_path / "epic-body.md"
    body_path.write_text("## Summary\nthe epic.\n", encoding="utf-8")
    runner = CliRunner()
    # Create the project first
    result = runner.invoke(app, ["-y", "--root", str(loom_dir),
                                  "project", "create", "p", "--repo", "x"])
    assert result.exit_code == 0, result.output
    # Now create the epic with --body-file
    result = runner.invoke(app, ["-y", "--root", str(loom_dir),
                                  "epic", "create", "p",
                                  "--title", "Big work",
                                  "--body-file", str(body_path)])
    assert result.exit_code == 0, result.output
    qid = result.output.strip().split()[-1]
    # The body should be the file's contents
    loom = Loom(root=loom_dir)
    assert loom.get(qid).body.strip().startswith("## Summary")


def test_epic_create_body_and_body_file_mutually_exclusive(
    loom_dir: Path, tmp_path: Path
) -> None:
    body_path = tmp_path / "epic-body.md"
    body_path.write_text("from file\n", encoding="utf-8")
    runner = CliRunner()
    runner.invoke(app, ["-y", "--root", str(loom_dir),
                        "project", "create", "p", "--repo", "x"])
    result = runner.invoke(app, ["-y", "--root", str(loom_dir),
                                  "epic", "create", "p",
                                  "--title", "Big",
                                  "--body", "inline",
                                  "--body-file", str(body_path)])
    assert result.exit_code != 0
    assert "mutually exclusive" in result.output.lower() or \
           "cannot use both" in result.output.lower()
```

- [ ] **Step 2: Run the test, expect failure**

Run: `uv run pytest tests/test_body_file.py -v`
Expected: 2 tests pass (from Task 2), 2 new tests fail with "unexpected argument --body-file".

- [ ] **Step 3: Add a helper for the mutex + body-file resolution**

In `src/loom/cli.py`, just before the section defining `project_create` (around line 440), add:

```python
def _resolve_body_with_file(
    body: str,
    body_file: Path | None,
) -> str:
    """Return the body string, given the inline ``body`` and the ``--body-file`` value.

    Exactly one of (body, body_file) may be non-empty. If body_file is set,
    its contents are read as utf-8. If both are set, exit with EXIT_GENERIC.
    """
    if body and body_file is not None:
        _die("--body and --body-file are mutually exclusive")
    if body_file is not None:
        try:
            return body_file.read_text(encoding="utf-8")
        except FileNotFoundError:
            _die(f"--body-file: {body_file} does not exist", code=EXIT_NOT_FOUND)
    return body
```

- [ ] **Step 4: Add the `--body-file` option to `epic_create`**

In `src/loom/cli.py`, modify `epic_create` (around line 514). After the `body` parameter, add a new one:

```python
    body_file: Annotated[
        Path | None,
        typer.Option(
            "--body-file",
            help="Path to a markdown file used as the body. Mutually exclusive with --body.",
        ),
    ] = None,
```

Then, after the line that calls `_resolve_title_body(...)`, add:

```python
    body = _resolve_body_with_file(body, body_file)
```

Make sure `_resolve_title_body` is called BEFORE `_resolve_body_with_file` so the editor flow still works for the interactive case (body_file is only set non-interactively).

- [ ] **Step 5: Run all body-file tests, expect pass**

Run: `uv run pytest tests/test_body_file.py -v`
Expected: 4/4 pass.

- [ ] **Step 6: Run the whole suite, expect no regressions**

Run: `uv run pytest -q`
Expected: all pass.

- [ ] **Step 7: Lint, format, commit**

```bash
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/cli.py tests/test_body_file.py
git commit -m "loom epic create: add --body-file flag"
```

---

## Task 4: CLI — `--body-file` on `loom story create`

**Files:**
- Modify: `src/loom/cli.py:561` (the `story_create` command)
- Modify: `tests/test_body_file.py`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_body_file.py`:

```python
def test_story_create_body_file(loom_dir: Path, tmp_path: Path) -> None:
    body_path = tmp_path / "story-body.md"
    body_path.write_text("## Summary\nthe story.\n", encoding="utf-8")
    runner = CliRunner()
    runner.invoke(app, ["-y", "--root", str(loom_dir),
                        "project", "create", "p", "--repo", "x"])
    epic_result = runner.invoke(app, ["-y", "--root", str(loom_dir),
                                       "epic", "create", "p", "--title", "e"])
    epic_qid = epic_result.output.strip().split()[-1]
    result = runner.invoke(app, ["-y", "--root", str(loom_dir),
                                  "story", "create", epic_qid,
                                  "--title", "s",
                                  "--body-file", str(body_path)])
    assert result.exit_code == 0, result.output
    sqid = result.output.strip().split()[-1]
    loom = Loom(root=loom_dir)
    assert loom.get(sqid).body.strip().startswith("## Summary")
```

- [ ] **Step 2: Run the test, expect failure**

Run: `uv run pytest tests/test_body_file.py::test_story_create_body_file -v`
Expected: FAIL with "unexpected argument --body-file".

- [ ] **Step 3: Apply the same pattern as Task 3 to `story_create`**

Same diff shape as Task 3 step 4:
- Add `body_file: Annotated[Path | None, typer.Option("--body-file", ...)] = None` after `body`.
- Add `body = _resolve_body_with_file(body, body_file)` immediately after `_resolve_title_body(...)` call.

- [ ] **Step 4: Run, expect pass**

Run: `uv run pytest tests/test_body_file.py -v`
Expected: 5/5 pass.

- [ ] **Step 5: Lint, format, commit**

```bash
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/cli.py tests/test_body_file.py
git commit -m "loom story create: add --body-file flag"
```

---

## Task 5: CLI — `--body-file` on `loom task create`

**Files:**
- Modify: `src/loom/cli.py:628`
- Modify: `tests/test_body_file.py`

- [ ] **Step 1: Write failing test**

Append to `tests/test_body_file.py`:

```python
def test_task_create_body_file(loom_dir: Path, tmp_path: Path) -> None:
    body_path = tmp_path / "task-body.md"
    body_path.write_text("the task.\n", encoding="utf-8")
    runner = CliRunner()
    runner.invoke(app, ["-y", "--root", str(loom_dir),
                        "project", "create", "p", "--repo", "x"])
    epic_result = runner.invoke(app, ["-y", "--root", str(loom_dir),
                                       "epic", "create", "p", "--title", "e"])
    epic_qid = epic_result.output.strip().split()[-1]
    story_result = runner.invoke(app, ["-y", "--root", str(loom_dir),
                                        "story", "create", epic_qid,
                                        "--title", "s"])
    story_qid = story_result.output.strip().split()[-1]
    result = runner.invoke(app, ["-y", "--root", str(loom_dir),
                                  "task", "create", story_qid,
                                  "--title", "t",
                                  "--body-file", str(body_path)])
    assert result.exit_code == 0, result.output
    tqid = result.output.strip().split()[-1]
    loom = Loom(root=loom_dir)
    assert loom.get(tqid).body.strip() == "the task."
```

- [ ] **Step 2: Run, expect failure**

Run: `uv run pytest tests/test_body_file.py::test_task_create_body_file -v`
Expected: FAIL.

- [ ] **Step 3: Apply Task 3 pattern to `task_create`** (same diff shape).

- [ ] **Step 4: Run, expect pass**

Run: `uv run pytest tests/test_body_file.py -v`
Expected: 6/6 pass.

- [ ] **Step 5: Commit**

```bash
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/cli.py tests/test_body_file.py
git commit -m "loom task create: add --body-file flag"
```

---

## Task 6: CLI — `--body-file` on `loom project create` and `loom update`

**Files:**
- Modify: `src/loom/cli.py:441` (`project_create`)
- Modify: `src/loom/cli.py:786` (`update_cmd`)
- Modify: `tests/test_body_file.py`

- [ ] **Step 1: Write failing tests**

Append to `tests/test_body_file.py`:

```python
def test_project_create_body_file(loom_dir: Path, tmp_path: Path) -> None:
    body_path = tmp_path / "p.md"
    body_path.write_text("## Goals\nbig project.\n", encoding="utf-8")
    runner = CliRunner()
    result = runner.invoke(app, ["-y", "--root", str(loom_dir),
                                  "project", "create", "myproj",
                                  "--repo", "x",
                                  "--body-file", str(body_path)])
    assert result.exit_code == 0, result.output
    loom = Loom(root=loom_dir)
    assert loom.get("myproj").body.strip().startswith("## Goals")


def test_update_body_file(loom_dir: Path, tmp_path: Path) -> None:
    runner = CliRunner()
    runner.invoke(app, ["-y", "--root", str(loom_dir),
                        "project", "create", "p", "--repo", "x"])
    epic_result = runner.invoke(app, ["-y", "--root", str(loom_dir),
                                       "epic", "create", "p", "--title", "e"])
    qid = epic_result.output.strip().split()[-1]
    new_body = tmp_path / "new.md"
    new_body.write_text("## Updated\nnew text.\n", encoding="utf-8")
    result = runner.invoke(app, ["-y", "--root", str(loom_dir),
                                  "update", qid, "body",
                                  "--body-file", str(new_body)])
    assert result.exit_code == 0, result.output
    loom = Loom(root=loom_dir)
    assert loom.get(qid).body.strip().startswith("## Updated")
```

- [ ] **Step 2: Run, expect failure**

Run: `uv run pytest tests/test_body_file.py -v`
Expected: both new tests FAIL.

- [ ] **Step 3: Add `--body-file` to `project_create`**

Apply Task 3 pattern: add the option, call `_resolve_body_with_file` immediately after `_resolve_title_body`.

- [ ] **Step 4: Add `--body-file` to `update_cmd`**

Read `src/loom/cli.py:786` first to understand the existing `update` shape (it dispatches on a field name argument). For the `body` field, accept either a positional value OR `--body-file`. Implementation sketch:

```python
# Inside update_cmd, when field == "body":
if field == "body":
    if body_file is not None:
        if value:
            _die("--body-file and positional value are mutually exclusive")
        try:
            value = body_file.read_text(encoding="utf-8")
        except FileNotFoundError:
            _die(f"--body-file: {body_file} does not exist", code=EXIT_NOT_FOUND)
    item.set_body(value)
    ...
```

Add the parameter to `update_cmd`:

```python
    body_file: Annotated[
        Path | None,
        typer.Option(
            "--body-file",
            help="When field=body, read the new body from this file.",
        ),
    ] = None,
```

- [ ] **Step 5: Run, expect pass**

Run: `uv run pytest tests/test_body_file.py -v`
Expected: 8/8 pass.

- [ ] **Step 6: Lint, format, commit**

```bash
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/cli.py tests/test_body_file.py
git commit -m "loom project create + loom update: add --body-file flag"
```

---

## Task 7: Library — extend `Loom.ready()` to accept a parent qid + recursive

**Files:**
- Modify: `src/loom/api.py:169`
- Create: `tests/test_ready_scoped.py`

- [ ] **Step 1: Write failing test**

Create `tests/test_ready_scoped.py`:

```python
"""Tests for qid-scoped, level-aware loom ready."""

from __future__ import annotations

from pathlib import Path

from loom.api import Loom


def _setup(root: Path) -> Loom:
    """Build a fixture tree:
        myproj
        └── epic E
            ├── story 1 (ready)
            │   ├── task 1 (ready)
            │   └── task 2 (depends on task 1)
            └── story 2 (ready, depends on story 1)
    """
    loom = Loom(root=root)
    p = loom.create_project(name="myproj")
    e = p.create_epic(title="E")
    s1 = e.create_story(title="s1")
    t1 = s1.create_task(title="t1")
    t2 = s1.create_task(title="t2")
    t2.depends_on(t1.qualified_id)
    s2 = e.create_story(title="s2")
    s2.depends_on(s1.qualified_id)
    return loom


def test_ready_scoped_to_epic_returns_only_first_level_stories(
    loom_dir: Path,
) -> None:
    loom = _setup(loom_dir)
    items = loom.ready(parent="myproj:E", type="story")  # 'E' placeholder; real id below
    # We don't know the random epic id; query by listing
    epic = loom.find(type="epic")[0]
    items = loom.ready(parent=epic.qualified_id, type="story")
    qids = {i.qualified_id for i in items}
    # Only s1 is ready; s2 is blocked by s1.
    assert any(q.endswith(":1") for q in qids)
    assert not any(q.endswith(":2") for q in qids)


def test_ready_recursive_returns_all_ready_descendants(loom_dir: Path) -> None:
    loom = _setup(loom_dir)
    epic = loom.find(type="epic")[0]
    items = loom.ready(parent=epic.qualified_id, recursive=True)
    # Should include story 1 AND task 1 (both ready, no blockers under epic).
    # Task 2 is blocked by task 1, story 2 is blocked by story 1.
    qids = {i.qualified_id for i in items}
    # Exactly two: the story and the unblocked task.
    assert len(qids) == 2


def test_ready_no_parent_returns_global(loom_dir: Path) -> None:
    """Existing behavior preserved when parent is omitted."""
    loom = _setup(loom_dir)
    items = loom.ready()
    # At least one ready item across the whole tree.
    assert items
```

- [ ] **Step 2: Run, expect failure**

Run: `uv run pytest tests/test_ready_scoped.py -v`
Expected: FAIL with "unexpected keyword argument 'parent'".

- [ ] **Step 3: Modify `Loom.ready()` to accept `parent` and `recursive`**

In `src/loom/api.py:169`, change the signature to:

```python
    def ready(
        self,
        *,
        type: str | None = None,
        tag: str | None = None,
        limit: int | None = None,
        parent: str | None = None,
        recursive: bool = False,
    ) -> list[Item]:
        """Return pickable items: status='ready', not archived, all deps done.

        If ``parent`` is provided, scope to items directly under that qid
        (or, with ``recursive=True``, all descendants at any depth). With
        ``parent=None`` (default), returns global ready items (existing
        behavior).
        """
        from .items import _Statused

        candidates = self._index.find_pickable(type=type, tag=tag, limit=None)
        out: list[Item] = []
        for record in candidates:
            if parent is not None:
                if recursive:
                    # All descendants at any depth.
                    if not record.qualified_id.startswith(parent + ":"):
                        continue
                else:
                    # Direct children only: qid must be parent + ":" + exactly one segment.
                    rest = record.qualified_id.removeprefix(parent + ":")
                    if rest == record.qualified_id or ":" in rest:
                        continue
            item = item_from_record(self._root, record)
            if isinstance(item, _Statused) and item.is_pickable():
                out.append(item)
                if limit is not None and len(out) >= limit:
                    break
        return out
```

- [ ] **Step 4: Run, expect pass**

Run: `uv run pytest tests/test_ready_scoped.py -v`
Expected: 3/3 pass.

- [ ] **Step 5: Run full suite to ensure no regression**

Run: `uv run pytest -q`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/api.py tests/test_ready_scoped.py
git commit -m "Loom.ready: accept parent qid + recursive flag"
```

---

## Task 8: CLI — `loom ready <qid>` (positional + `--recursive`)

**Files:**
- Modify: `src/loom/cli.py` (the `ready_cmd` definition — search for `@app.command("ready")`)
- Modify: `tests/test_ready_scoped.py`

- [ ] **Step 1: Locate the existing `ready_cmd`**

Run: `grep -n "@app.command(\"ready\")" src/loom/cli.py`
Note the line. Read 30 lines from there to see its current signature.

- [ ] **Step 2: Write CLI test**

Append to `tests/test_ready_scoped.py`:

```python
from typer.testing import CliRunner
import json
from loom.cli import app


def test_cli_ready_scoped_by_qid(loom_dir: Path) -> None:
    loom = _setup(loom_dir)
    epic = loom.find(type="epic")[0]
    runner = CliRunner()
    result = runner.invoke(app, ["--root", str(loom_dir),
                                  "ready", epic.qualified_id,
                                  "--json", "--type", "story"])
    assert result.exit_code == 0, result.output
    data = json.loads(result.output)
    qids = {item["qualified_id"] for item in data}
    assert any(q.endswith(":1") for q in qids)


def test_cli_ready_recursive(loom_dir: Path) -> None:
    loom = _setup(loom_dir)
    epic = loom.find(type="epic")[0]
    runner = CliRunner()
    result = runner.invoke(app, ["--root", str(loom_dir),
                                  "ready", epic.qualified_id,
                                  "--recursive", "--json"])
    assert result.exit_code == 0, result.output
    data = json.loads(result.output)
    # Story s1 + task 1 (both ready under the epic).
    assert len(data) == 2
```

- [ ] **Step 3: Run, expect failure**

Run: `uv run pytest tests/test_ready_scoped.py -v`
Expected: 2 new CLI tests FAIL (positional arg not accepted, --recursive unknown).

- [ ] **Step 4: Modify `ready_cmd` signature**

Add a positional `qid` argument and a `--recursive` flag. Sketch (adapt to existing arg names):

```python
@app.command("ready")
def ready_cmd(
    ctx: typer.Context,
    qid: Annotated[
        str | None,
        typer.Argument(help="Optional parent qid; scope to items under it."),
    ] = None,
    recursive: Annotated[
        bool,
        typer.Option("--recursive", help="Include all descendants, not just direct children."),
    ] = False,
    # ... existing options (type, tag, limit, json, root) ...
) -> None:
    loom = _loom(root)
    items = loom.ready(type=type, tag=tag, limit=limit, parent=qid, recursive=recursive)
    # ... existing output formatting (JSON / text) ...
```

If `qid` is provided, validate it exists with `_get_or_die(loom, qid)` before calling ready.

- [ ] **Step 5: Run, expect pass**

Run: `uv run pytest tests/test_ready_scoped.py -v`
Expected: 5/5 pass.

- [ ] **Step 6: Run full suite, lint, commit**

```bash
uv run pytest -q
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/cli.py tests/test_ready_scoped.py
git commit -m "loom ready: accept positional qid + --recursive flag"
```

---

## Task 9: Library — `Loom.tree()` method

**Files:**
- Modify: `src/loom/api.py` (after `find`, around line 160)
- Create: `tests/test_tree.py`

- [ ] **Step 1: Write failing tests**

Create `tests/test_tree.py`:

```python
"""Tests for Loom.tree() and loom tree CLI."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from typer.testing import CliRunner

from loom.api import Loom
from loom.cli import app


def _build_tree(root: Path) -> Loom:
    loom = Loom(root=root)
    p = loom.create_project(name="myproj")
    e = p.create_epic(title="E")
    s1 = e.create_story(title="s1")
    s1.create_task(title="t1")
    s1.create_task(title="t2")
    e.create_story(title="s2")
    return loom


def test_tree_flat_array_includes_all_descendants(loom_dir: Path) -> None:
    loom = _build_tree(loom_dir)
    epic = loom.find(type="epic")[0]
    result = loom.tree(epic.qualified_id)
    qids = {entry["qid"] for entry in result["items"]}
    assert result["root"] == epic.qualified_id
    # epic, 2 stories, 2 tasks = 5 items
    assert len(result["items"]) == 5
    assert epic.qualified_id in qids


def test_tree_children_are_qid_refs(loom_dir: Path) -> None:
    loom = _build_tree(loom_dir)
    epic = loom.find(type="epic")[0]
    result = loom.tree(epic.qualified_id)
    by_qid = {entry["qid"]: entry for entry in result["items"]}
    epic_entry = by_qid[epic.qualified_id]
    # children is a list of qid strings, NOT nested objects
    assert isinstance(epic_entry["children"], list)
    assert all(isinstance(c, str) for c in epic_entry["children"])
    assert len(epic_entry["children"]) == 2  # two stories


def test_tree_depth_limits_descent(loom_dir: Path) -> None:
    loom = _build_tree(loom_dir)
    epic = loom.find(type="epic")[0]
    result = loom.tree(epic.qualified_id, depth=1)
    # Only epic + direct children (2 stories), tasks excluded.
    assert len(result["items"]) == 3


def test_tree_status_filter(loom_dir: Path) -> None:
    loom = _build_tree(loom_dir)
    epic = loom.find(type="epic")[0]
    # Complete one task
    tasks = loom.find(type="task")
    tasks[0].complete()
    result = loom.tree(epic.qualified_id, status="done")
    assert all(entry["status"] == "done" for entry in result["items"])
    assert len(result["items"]) == 1
```

- [ ] **Step 2: Run, expect failure**

Run: `uv run pytest tests/test_tree.py -v`
Expected: FAIL with "AttributeError: 'Loom' object has no attribute 'tree'".

- [ ] **Step 3: Implement `Loom.tree`**

In `src/loom/api.py`, add (after `find`, around line 160):

```python
    def tree(
        self,
        qualified_id: str,
        *,
        depth: int | None = None,
        status: str | None = None,
    ) -> dict:
        """Return a flat-array tree rooted at *qualified_id*.

        The shape is::

            {
              "root": "<qid>",
              "items": [
                {"qid": "...", "type": "...", "status": "...",
                 "branch": "...", "pr_url": "...", "assignee": "...",
                 "deps": ["..."], "children": ["<qid>", ...]},
                ...
              ]
            }

        ``depth`` limits descent (``depth=1`` → root + direct children).
        ``status`` filters items to a single status string.
        """
        from .deps import compute_dependencies, descendants

        root_record = self._index.get(qualified_id)
        if root_record is None:
            raise NotFound(qualified_id)

        # Collect all descendant records; filter by depth if requested.
        all_records = [root_record, *descendants(self._index, qualified_id)]

        def _depth_below_root(qid: str) -> int:
            return qid.count(":") - qualified_id.count(":")

        if depth is not None:
            all_records = [r for r in all_records if _depth_below_root(r.qualified_id) <= depth]

        if status is not None:
            all_records = [r for r in all_records if r.status == status]

        # Build children index: for each record, list direct-child qids
        # within our (possibly depth-trimmed) record set.
        present_qids = {r.qualified_id for r in all_records}
        items_out = []
        for record in sorted(all_records, key=lambda r: r.qualified_id):
            # Direct children = qids in present_qids that are this qid + ":<one-segment>"
            prefix = record.qualified_id + ":"
            children = sorted(
                q for q in present_qids
                if q.startswith(prefix) and ":" not in q[len(prefix):]
            )
            deps = [ref.qualified_id for ref in compute_dependencies(self._index, record.qualified_id)]
            items_out.append({
                "qid": record.qualified_id,
                "type": record.type,
                "status": record.status,
                "branch": record.branch,
                "pr_url": record.pr_url,
                "assignee": record.assignee,
                "deps": deps,
                "children": children,
            })
        return {"root": qualified_id, "items": items_out}
```

If `record.assignee` or `record.branch` / `record.pr_url` are not fields on `IndexRecord`, check `src/loom/index.py` for the actual field names and adjust.

- [ ] **Step 4: Run, expect pass**

Run: `uv run pytest tests/test_tree.py -v`
Expected: 4/4 pass.

- [ ] **Step 5: Commit**

```bash
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/api.py tests/test_tree.py
git commit -m "Loom.tree: flat-array subtree with depth + status filters"
```

---

## Task 10: CLI — `loom tree <qid>` (text default)

**Files:**
- Modify: `src/loom/cli.py` (new `@app.command("tree")`)
- Modify: `tests/test_tree.py`

- [ ] **Step 1: Write failing test**

Append to `tests/test_tree.py`:

```python
def test_cli_tree_text_output(loom_dir: Path) -> None:
    loom = _build_tree(loom_dir)
    epic = loom.find(type="epic")[0]
    runner = CliRunner()
    result = runner.invoke(app, ["--root", str(loom_dir), "tree", epic.qualified_id])
    assert result.exit_code == 0, result.output
    # Unicode box characters for the tree
    assert "├─" in result.output or "└─" in result.output
    # Root qid appears at top
    assert epic.qualified_id in result.output
    # Status is shown
    assert "ready" in result.output
```

- [ ] **Step 2: Run, expect failure**

Run: `uv run pytest tests/test_tree.py::test_cli_tree_text_output -v`
Expected: FAIL with "no such command 'tree'".

- [ ] **Step 3: Implement the `tree` command**

Add to `src/loom/cli.py` (top-level command, e.g. after `show_cmd`):

```python
@app.command("tree")
def tree_cmd(
    qid: Annotated[str, typer.Argument(help="Qualified id to render as a tree.")],
    depth: Annotated[
        int | None,
        typer.Option("--depth", help="Limit descent: 1 = direct children only."),
    ] = None,
    status: Annotated[
        str | None,
        typer.Option("--status", help="Filter items to this status."),
    ] = None,
    json_out: Annotated[
        bool,
        typer.Option("--json", help="Emit the flat-array JSON shape."),
    ] = False,
    root: RootOption = None,
) -> None:
    """Render the subtree rooted at <qid>."""
    loom = _loom(root)
    try:
        result = loom.tree(qid, depth=depth, status=status)
    except LoomError as e:
        _die_from(e)
        return
    if json_out:
        typer.echo(json.dumps(result, indent=2))
        return
    # Text output: indented unicode tree
    by_qid = {item["qid"]: item for item in result["items"]}
    root_qid = result["root"]

    def _render(qid: str, prefix: str = "", is_last: bool = True) -> None:
        item = by_qid[qid]
        if qid == root_qid:
            connector = ""
            next_prefix = ""
        else:
            connector = "└─ " if is_last else "├─ "
            next_prefix = prefix + ("   " if is_last else "│  ")
        line = f"{prefix}{connector}{qid}  [{item['status']}]  {item['type']}"
        if item.get("branch"):
            line += f"  branch={item['branch']}"
        typer.echo(line)
        children = item["children"]
        for i, child in enumerate(children):
            _render(child, next_prefix, i == len(children) - 1)

    _render(root_qid)
```

- [ ] **Step 4: Run, expect pass**

Run: `uv run pytest tests/test_tree.py::test_cli_tree_text_output -v`
Expected: PASS.

- [ ] **Step 5: Add a JSON CLI test**

Append:

```python
def test_cli_tree_json_output(loom_dir: Path) -> None:
    loom = _build_tree(loom_dir)
    epic = loom.find(type="epic")[0]
    runner = CliRunner()
    result = runner.invoke(app, ["--root", str(loom_dir),
                                  "tree", epic.qualified_id, "--json"])
    assert result.exit_code == 0, result.output
    data = json.loads(result.output)
    assert data["root"] == epic.qualified_id
    assert isinstance(data["items"], list)
```

- [ ] **Step 6: Run, expect pass**

Run: `uv run pytest tests/test_tree.py -v`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/cli.py tests/test_tree.py
git commit -m "loom tree: text + JSON subtree view"
```

---

## Task 11: Library — topological sort utility in `deps.py`

**Files:**
- Modify: `src/loom/deps.py`
- Create: `tests/test_order.py`

- [ ] **Step 1: Write failing test**

Create `tests/test_order.py`:

```python
"""Tests for topological order utility and Loom.order()."""

from __future__ import annotations

from pathlib import Path

from loom.api import Loom


def test_topo_sort_respects_deps(loom_dir: Path) -> None:
    loom = Loom(root=loom_dir)
    p = loom.create_project(name="p")
    e = p.create_epic(title="E")
    s = e.create_story(title="s")
    t1 = s.create_task(title="t1")
    t2 = s.create_task(title="t2")
    t3 = s.create_task(title="t3")
    # t3 depends on t2, t2 depends on t1
    t2.depends_on(t1.qualified_id)
    t3.depends_on(t2.qualified_id)
    ordered = loom.order(s.qualified_id)
    qids = [item.qualified_id for item in ordered]
    # t1 must precede t2 must precede t3
    assert qids.index(t1.qualified_id) < qids.index(t2.qualified_id)
    assert qids.index(t2.qualified_id) < qids.index(t3.qualified_id)


def test_topo_sort_same_rank_orders_by_qid(loom_dir: Path) -> None:
    loom = Loom(root=loom_dir)
    p = loom.create_project(name="p")
    e = p.create_epic(title="E")
    s = e.create_story(title="s")
    # All three independent
    s.create_task(title="t1")
    s.create_task(title="t2")
    s.create_task(title="t3")
    ordered = loom.order(s.qualified_id)
    qids = [item.qualified_id for item in ordered]
    assert qids == sorted(qids)


def test_order_excludes_done_by_default(loom_dir: Path) -> None:
    loom = Loom(root=loom_dir)
    p = loom.create_project(name="p")
    e = p.create_epic(title="E")
    s = e.create_story(title="s")
    t1 = s.create_task(title="t1")
    s.create_task(title="t2")
    t1.complete()
    ordered = loom.order(s.qualified_id)
    assert all(item.qualified_id != t1.qualified_id for item in ordered)


def test_order_include_done(loom_dir: Path) -> None:
    loom = Loom(root=loom_dir)
    p = loom.create_project(name="p")
    e = p.create_epic(title="E")
    s = e.create_story(title="s")
    t1 = s.create_task(title="t1")
    s.create_task(title="t2")
    t1.complete()
    ordered = loom.order(s.qualified_id, include_done=True)
    assert len(ordered) == 2
```

- [ ] **Step 2: Run, expect failure**

Run: `uv run pytest tests/test_order.py -v`
Expected: FAIL with "no attribute 'order'".

- [ ] **Step 3: Add topo sort helper to `deps.py`**

At the end of `src/loom/deps.py`, add:

```python
def topological_sort(
    records: Sequence[IndexRecord],
    idx: Index,
) -> list[IndexRecord]:
    """Return *records* in topological order.

    Two records X and Y where X depends on Y: Y precedes X. Records at the
    same dep-rank are sorted by qualified_id (stable, deterministic).

    Records not present in the input set are ignored as deps (a record may
    have dependencies on items outside the input slice).
    """
    qid_set = {r.qualified_id for r in records}
    by_qid = {r.qualified_id: r for r in records}

    # Build in-degree (incoming-edge count for each record), restricted
    # to deps within the input slice.
    in_degree: dict[str, int] = {qid: 0 for qid in qid_set}
    deps_map: dict[str, list[str]] = {qid: [] for qid in qid_set}
    for qid in qid_set:
        for ref in compute_dependencies(idx, qid):
            if ref.qualified_id in qid_set:
                in_degree[qid] += 1
                deps_map[ref.qualified_id].append(qid)

    # Kahn's algorithm with deterministic ordering at each rank.
    ready = sorted(qid for qid, deg in in_degree.items() if deg == 0)
    out: list[IndexRecord] = []
    while ready:
        next_ready: list[str] = []
        for qid in ready:
            out.append(by_qid[qid])
            for dependent in deps_map[qid]:
                in_degree[dependent] -= 1
                if in_degree[dependent] == 0:
                    next_ready.append(dependent)
        ready = sorted(next_ready)
    # Any remaining items had a cycle; deterministic fallback by qid.
    if len(out) != len(records):
        out.extend(sorted(
            (r for r in records if r.qualified_id not in {o.qualified_id for o in out}),
            key=lambda r: r.qualified_id,
        ))
    return out
```

Import `Sequence` from `typing` if not already imported.

- [ ] **Step 4: Add `Loom.order()` method**

In `src/loom/api.py`, after `tree`:

```python
    def order(
        self,
        qualified_id: str,
        *,
        recursive: bool = False,
        include_done: bool = False,
    ) -> list[Item]:
        """Return descendants of *qualified_id* in topological dep-order.

        Default scope is direct children (e.g. tasks for a story, stories
        for an epic). With ``recursive=True``, all descendants at any depth.
        Done items are excluded by default; pass ``include_done=True`` to
        include them.
        """
        from .deps import descendants, topological_sort

        root_record = self._index.get(qualified_id)
        if root_record is None:
            raise NotFound(qualified_id)
        all_records = descendants(self._index, qualified_id)

        # Filter by depth scope
        if not recursive:
            prefix = qualified_id + ":"
            def _is_direct_child(qid: str) -> bool:
                rest = qid.removeprefix(prefix)
                return rest != qid and ":" not in rest
            all_records = [r for r in all_records if _is_direct_child(r.qualified_id)]

        if not include_done:
            all_records = [r for r in all_records if r.status != "done"]

        ordered = topological_sort(all_records, self._index)
        return [item_from_record(self._root, r) for r in ordered]
```

- [ ] **Step 5: Run, expect pass**

Run: `uv run pytest tests/test_order.py -v`
Expected: 4/4 pass.

- [ ] **Step 6: Commit**

```bash
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/api.py src/loom/deps.py tests/test_order.py
git commit -m "Loom.order: topological dep-order of children"
```

---

## Task 12: CLI — `loom order <qid>`

**Files:**
- Modify: `src/loom/cli.py`
- Modify: `tests/test_order.py`

- [ ] **Step 1: Write failing test**

Append to `tests/test_order.py`:

```python
import json
from typer.testing import CliRunner
from loom.cli import app


def test_cli_order_json(loom_dir: Path) -> None:
    loom = Loom(root=loom_dir)
    p = loom.create_project(name="p")
    e = p.create_epic(title="E")
    s = e.create_story(title="s")
    t1 = s.create_task(title="t1")
    t2 = s.create_task(title="t2")
    t2.depends_on(t1.qualified_id)
    runner = CliRunner()
    result = runner.invoke(app, ["--root", str(loom_dir),
                                  "order", s.qualified_id, "--json"])
    assert result.exit_code == 0, result.output
    data = json.loads(result.output)
    qids = [entry["qualified_id"] for entry in data]
    assert qids.index(t1.qualified_id) < qids.index(t2.qualified_id)
```

- [ ] **Step 2: Run, expect failure**

Run: `uv run pytest tests/test_order.py::test_cli_order_json -v`
Expected: FAIL with "no such command 'order'".

- [ ] **Step 3: Implement the `order` command**

Add to `src/loom/cli.py`:

```python
@app.command("order")
def order_cmd(
    qid: Annotated[str, typer.Argument(help="Qualified id to enumerate descendants of.")],
    recursive: Annotated[
        bool,
        typer.Option("--recursive", help="Include all descendants, not just direct children."),
    ] = False,
    include_done: Annotated[
        bool,
        typer.Option("--include-done", help="Include done items in the result."),
    ] = False,
    json_out: Annotated[
        bool,
        typer.Option("--json", help="Emit JSON array."),
    ] = False,
    root: RootOption = None,
) -> None:
    """Return descendants of <qid> in topological dep-order."""
    loom = _loom(root)
    try:
        items = loom.order(qid, recursive=recursive, include_done=include_done)
    except LoomError as e:
        _die_from(e)
        return
    if json_out:
        typer.echo(json.dumps([_item_to_dict(i) for i in items], indent=2))
        return
    for item in items:
        typer.echo(f"{item.qualified_id}  [{item._record.status}]  {item.type}  {item.title}")
```

- [ ] **Step 4: Run, expect pass**

Run: `uv run pytest tests/test_order.py -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/cli.py tests/test_order.py
git commit -m "loom order: topological dep-order CLI command"
```

---

## Task 13: Library — `Loom.reopen()` recursive status reset

**Files:**
- Modify: `src/loom/api.py`
- Modify: `src/loom/items.py` (add `reopen` mutator on `_Statused` items)
- Create: `tests/test_reopen.py`

- [ ] **Step 1: Write failing test**

Create `tests/test_reopen.py`:

```python
"""Tests for Loom.reopen() — recursive status reset + assignee clear."""

from __future__ import annotations

from pathlib import Path

from loom.api import Loom


def test_reopen_resets_self_and_descendants(loom_dir: Path) -> None:
    loom = Loom(root=loom_dir)
    p = loom.create_project(name="p")
    e = p.create_epic(title="E")
    s = e.create_story(title="s")
    t1 = s.create_task(title="t1")
    t2 = s.create_task(title="t2")
    t1.complete()
    t2.complete()
    # Mark the story done too (close_if_children_done)
    s.complete()
    assert s.refresh().status == "done"
    assert t1.refresh().status == "done"

    loom.reopen(s.qualified_id)

    assert loom.get(s.qualified_id).status == "ready"
    assert loom.get(t1.qualified_id).status == "ready"
    assert loom.get(t2.qualified_id).status == "ready"


def test_reopen_clears_assignee(loom_dir: Path) -> None:
    loom = Loom(root=loom_dir)
    p = loom.create_project(name="p")
    e = p.create_epic(title="E")
    s = e.create_story(title="s")
    s.set_assignee("session_abc:agent_xyz")
    assert s.refresh().assignee == "session_abc:agent_xyz"
    loom.reopen(s.qualified_id)
    assert loom.get(s.qualified_id).assignee is None


def test_reopen_skips_archived(loom_dir: Path) -> None:
    """Archived descendants live under _archive/; reopen should not touch them."""
    loom = Loom(root=loom_dir)
    p = loom.create_project(name="p")
    e = p.create_epic(title="E")
    s = e.create_story(title="s")
    t1 = s.create_task(title="t1")
    t1.archive()
    s.complete()
    loom.reopen(s.qualified_id)
    # Archived t1 should still be archived; reopen only touches live tree.
    archived = loom.find(type="task", archived=True)
    assert any(item.qualified_id == t1.qualified_id for item in archived)
```

- [ ] **Step 2: Run, expect failure**

Run: `uv run pytest tests/test_reopen.py -v`
Expected: FAIL with "no attribute 'reopen'".

- [ ] **Step 3: Implement `Loom.reopen`**

In `src/loom/api.py`:

```python
    def reopen(self, qualified_id: str) -> None:
        """Reset *qualified_id* and all live descendants to status=ready.

        Also clears the ``assignee`` field on each. Archived items are
        untouched (they live under ``_archive/`` and are out of the live
        tree). Tasks (which lack ``set_assignee``) get status reset but
        their assignee handling is moot (tasks never carry assignee in
        the workflow convention; if one does, it's cleared anyway).
        """
        from .deps import descendants
        from .items import _Statused

        root_record = self._index.get(qualified_id)
        if root_record is None:
            raise NotFound(qualified_id)

        all_records = [root_record, *descendants(self._index, qualified_id)]
        # Filter out archived (descendants only includes live items, but be defensive).
        all_records = [r for r in all_records if not r.archived]

        for record in all_records:
            item = item_from_record(self._root, record)
            if isinstance(item, _Statused):
                # Reset status then clear assignee. Use refresh between to avoid
                # stale-record writes.
                item.set_status("ready")
                item.refresh().set_assignee(None)
```

- [ ] **Step 4: Run, expect pass**

Run: `uv run pytest tests/test_reopen.py -v`
Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/api.py tests/test_reopen.py
git commit -m "Loom.reopen: recursive status reset + assignee clear"
```

---

## Task 14: CLI — `loom reopen <qid>`

**Files:**
- Modify: `src/loom/cli.py`
- Modify: `tests/test_reopen.py`

- [ ] **Step 1: Write failing test**

Append to `tests/test_reopen.py`:

```python
from typer.testing import CliRunner
from loom.cli import app


def test_cli_reopen(loom_dir: Path) -> None:
    loom = Loom(root=loom_dir)
    p = loom.create_project(name="p")
    e = p.create_epic(title="E")
    s = e.create_story(title="s")
    t = s.create_task(title="t")
    t.complete()
    s.complete()
    runner = CliRunner()
    result = runner.invoke(app, ["--root", str(loom_dir), "reopen", s.qualified_id])
    assert result.exit_code == 0, result.output
    assert loom.get(s.qualified_id).status == "ready"
    assert loom.get(t.qualified_id).status == "ready"
```

- [ ] **Step 2: Run, expect failure**

Run: `uv run pytest tests/test_reopen.py::test_cli_reopen -v`
Expected: FAIL with "no such command 'reopen'".

- [ ] **Step 3: Implement the `reopen` command**

Add to `src/loom/cli.py`:

```python
@app.command("reopen")
def reopen_cmd(
    qid: Annotated[str, typer.Argument(help="Qualified id to reset (with descendants).")],
    root: RootOption = None,
) -> None:
    """Reset <qid> and all live descendants to status=ready; clear assignee."""
    loom = _loom(root)
    try:
        loom.reopen(qid)
    except LoomError as e:
        _die_from(e)
        return
    _record_touch(qid)
    typer.echo(f"reopened {qid}")
```

- [ ] **Step 4: Run, expect pass**

Run: `uv run pytest tests/test_reopen.py -v`
Expected: 4/4 pass.

- [ ] **Step 5: Commit**

```bash
uv run ruff check --fix src tests && uv run ruff format src tests
git add src/loom/cli.py tests/test_reopen.py
git commit -m "loom reopen: CLI command for status reset"
```

---

## Task 15: End-to-end integration test

**Files:**
- Modify: `tests/test_e2e.py`

- [ ] **Step 1: Append a workflow-shaped e2e test**

Open `tests/test_e2e.py`. Append:

```python
def test_loom_workflow_chain_via_cli(loom_dir: Path, tmp_path: Path) -> None:
    """Drive a /epic-shaped flow end-to-end through the CLI:

    1. Create project, epic with --body-file
    2. Create two stories with --body-file
    3. Create tasks on story 1, deps between them
    4. Verify loom tree, loom order, loom ready
    5. Complete tasks, mark story done, run loom reopen
    6. Verify reopen reset state correctly
    """
    from typer.testing import CliRunner
    import json
    from loom.cli import app
    from loom.api import Loom

    body_path = tmp_path / "body.md"
    body_path.write_text("## Validation Criteria\n- [ ] criterion\n", encoding="utf-8")
    runner = CliRunner()

    # 1. project + epic
    r = runner.invoke(app, ["-y", "--root", str(loom_dir),
                             "project", "create", "myproj", "--repo", "x"])
    assert r.exit_code == 0, r.output
    r = runner.invoke(app, ["-y", "--root", str(loom_dir),
                             "epic", "create", "myproj",
                             "--title", "Big",
                             "--body-file", str(body_path)])
    assert r.exit_code == 0
    epic_qid = r.output.strip().split()[-1]

    # 2. two stories
    r = runner.invoke(app, ["-y", "--root", str(loom_dir),
                             "story", "create", epic_qid,
                             "--title", "s1",
                             "--body-file", str(body_path)])
    s1_qid = r.output.strip().split()[-1]
    r = runner.invoke(app, ["-y", "--root", str(loom_dir),
                             "story", "create", epic_qid,
                             "--title", "s2",
                             "--body-file", str(body_path)])
    s2_qid = r.output.strip().split()[-1]
    # s2 depends on s1
    r = runner.invoke(app, ["-y", "--root", str(loom_dir),
                             "dep", "add", s2_qid, "--on", s1_qid])
    assert r.exit_code == 0, r.output

    # 3. two tasks on s1
    r = runner.invoke(app, ["-y", "--root", str(loom_dir),
                             "task", "create", s1_qid, "--title", "t1"])
    t1_qid = r.output.strip().split()[-1]
    r = runner.invoke(app, ["-y", "--root", str(loom_dir),
                             "task", "create", s1_qid, "--title", "t2"])
    t2_qid = r.output.strip().split()[-1]
    r = runner.invoke(app, ["-y", "--root", str(loom_dir),
                             "dep", "add", t2_qid, "--on", t1_qid])
    assert r.exit_code == 0

    # 4. tree, order, ready
    r = runner.invoke(app, ["--root", str(loom_dir),
                             "tree", epic_qid, "--json"])
    data = json.loads(r.output)
    assert len(data["items"]) == 5  # epic + 2 stories + 2 tasks

    r = runner.invoke(app, ["--root", str(loom_dir),
                             "order", s1_qid, "--json"])
    data = json.loads(r.output)
    qids = [e["qualified_id"] for e in data]
    assert qids == [t1_qid, t2_qid]  # topo order

    r = runner.invoke(app, ["--root", str(loom_dir),
                             "ready", epic_qid, "--type", "story", "--json"])
    data = json.loads(r.output)
    assert {e["qualified_id"] for e in data} == {s1_qid}  # s2 blocked

    # 5. complete tasks + story, reopen
    runner.invoke(app, ["-y", "--root", str(loom_dir), "complete", t1_qid])
    runner.invoke(app, ["-y", "--root", str(loom_dir), "complete", t2_qid])
    runner.invoke(app, ["-y", "--root", str(loom_dir), "complete", s1_qid])
    r = runner.invoke(app, ["--root", str(loom_dir), "reopen", s1_qid])
    assert r.exit_code == 0, r.output

    # 6. verify reset
    loom = Loom(root=loom_dir)
    assert loom.get(s1_qid).status == "ready"
    assert loom.get(t1_qid).status == "ready"
    assert loom.get(t2_qid).status == "ready"
```

- [ ] **Step 2: Run the e2e test**

Run: `uv run pytest tests/test_e2e.py::test_loom_workflow_chain_via_cli -v`
Expected: PASS.

- [ ] **Step 3: Run full suite**

Run: `uv run pytest -q`
Expected: ALL tests pass.

- [ ] **Step 4: Lint and format**

Run: `uv run ruff check --fix src tests && uv run ruff format src tests`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add tests/test_e2e.py
git commit -m "e2e test: full /epic-shaped loom workflow chain"
```

---

## Task 16: WORKFLOW.md — public document

**Files:**
- Create: `docs/WORKFLOW.md`

- [ ] **Step 1: Write the document**

Create `docs/WORKFLOW.md`:

```markdown
# Loom as a project-management backend for AI coding agents

This document describes a workflow pattern: using loom items as the durable
state for an agent-driven planning + execution loop. The pattern is independent
of any specific agent toolkit, though the reference implementation is in
the [superpowers](https://github.com/obra/superpowers) plugin for Claude Code.

## The pattern

1. **Groom**: a "rough idea" is researched and turned into a structured
   loom epic (large-scale) or story (small-scale) with:
   - A `## Validation Criteria` section in the body (observable checklist)
   - Child stories (for epics) or child tasks (for stories)
   - Dependencies via `loom dep add`
2. **Plan**: items are materialized via `loom epic create`, `loom story create`,
   `loom task create` (with `--body-file` for structured bodies). The
   `assignee` field is set on epics and stories to record ownership.
3. **Execute**: agents pick up ready work via `loom ready <parent-qid>` and
   walk dep-order via `loom order <qid>`. As tasks complete, they call
   `loom complete <qid>`. Status flows from `ready` → `in_progress` → `done`.
4. **Integrate**: completed work is merged into a parent branch. The
   `## Validation Criteria` section is checked against the merged state.
5. **Discard and retry**: failed merges or failed validation use
   `loom reopen <qid>` to reset the item back to ready for the next pass.

## Roles

| Concept | Loom primitive |
|---|---|
| Large feature, multi-subsystem change | Epic |
| Self-contained scoped change | Story under an epic (often the `backlog` epic) |
| Atomic implementation step | Task under a story |
| Dependency between work items | `loom dep add` |
| "What can start right now?" | `loom ready [<qid>]` |
| "Walk this work in dep-order" | `loom order <qid>` |
| "Reset this work for retry" | `loom reopen <qid>` |
| Ownership marker | `assignee` field (see MARKDOWN_SPEC.md §Assignment) |

## Validation criteria

A `## Validation Criteria` markdown section in the body of every story and
epic provides an observable definition of done. Loom does not parse this
section; it's a convention that external validators check. Criteria should
be observable from "criteria + final code state" alone, without
implementation context.

## See also

- `docs/MARKDOWN_SPEC.md` — file format and field conventions
- The [superpowers loom integration spec](https://github.com/obra/superpowers/blob/main/docs/plans/2026-05-22-loom-backed-planning-design.md)
  for the reference implementation
```

- [ ] **Step 2: Commit**

```bash
git add docs/WORKFLOW.md
git commit -m "docs: WORKFLOW.md describing loom as an AI-agent backend"
```

---

## Final verification

- [ ] **Step 1: Full test suite**

Run: `uv run pytest -v`
Expected: ALL tests pass. Note the count.

- [ ] **Step 2: Lint and format clean**

Run: `uv run ruff check src tests && uv run ruff format --check src tests`
Expected: no errors.

- [ ] **Step 3: Smoke the new CLI commands**

Outside the test harness, run each new command against a temporary LOOM_DIR:

```bash
export LOOM_DIR=/tmp/loom-smoke-$$
uv run loom init
uv run loom -y project create demo --repo "https://example.com/x.git"
uv run loom -y epic create demo --title "Demo Epic" --body-file /dev/null
EPIC=$(uv run loom -y epic create demo --title "Another" --body-file /dev/null | awk '{print $NF}')
uv run loom -y story create $EPIC --title "S"
uv run loom tree $EPIC
uv run loom tree $EPIC --json
uv run loom order $EPIC
uv run loom ready $EPIC --json
uv run loom reopen $EPIC
rm -rf $LOOM_DIR
```
Expected: every command exits 0; outputs match the documented shapes.

- [ ] **Step 4: Tag**

```bash
git log --oneline | head -20  # review the work
# Optional: tag a milestone if your repo uses tags
```

---

## Self-review notes (filled in at plan-writing time)

**Spec coverage**: All 5 CLI features from §4 (`--body-file`, scoped `loom ready`, `loom tree`, `loom order`, `loom reopen`) have tasks. §4.6 `assignee` documentation is Task 1. §4.7 validation criteria convention is Task 1. WORKFLOW.md is Task 16.

**Placeholder scan**: No TBDs or "implement appropriately" — every step has code or exact commands.

**Type consistency**: `Loom.ready(parent=..., recursive=...)`, `Loom.tree(qid, depth=, status=)`, `Loom.order(qid, recursive=, include_done=)`, `Loom.reopen(qid)` — signatures consistent between library and CLI tasks.

**Open caveat**: Task 9 step 3 references `record.assignee`, `record.branch`, `record.pr_url` on `IndexRecord`. If those aren't fields on the dataclass, the implementer must check `src/loom/index.py` and either add them or fetch via the file's frontmatter. This was flagged inline.
