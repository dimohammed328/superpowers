#!/usr/bin/env bash
# Unit tests for hooks/loom-log.sh (dispatcher hook)
#
# Validates:
#   1. Directory creation at XDG_STATE_HOME/loom/<project>/<epic_qid>/
#   2. Per-agent file partition: one <agent_id>.jsonl per distinct agent_id
#   3. Every line parses as JSON with required fields
#   4. All ten mechanical event kinds appear at least once
#   5. Non-matching Bash invocations (ls, npm test) produce zero events
#   6. Malformed stdin exits 0 with diagnostic on stderr

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCHER="${SCRIPT_DIR}/../../hooks/loom-log.sh"

PASS=0
FAIL=0
ERRORS=()

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# Create a temp loom workspace with a given project name
make_loom_workspace() {
  local dir="$1"
  local project="$2"
  mkdir -p "${dir}/.loom"
  cat > "${dir}/.loom/state.json" <<EOF
{
  "project": "${project}",
  "schema_version": 1,
  "last": { "epic": null, "story": null, "task": null }
}
EOF
}

# Run dispatcher with given event kind and JSON body, from a loom workspace
# Usage: run_dispatcher <loom_dir> <xdg_dir> <event_kind> <json_body>
run_dispatcher() {
  local loom_dir="$1"
  local xdg_dir="$2"
  local event_kind="$3"
  local json_body="$4"
  (
    cd "$loom_dir"
    CLAUDE_HOOK_EVENT="$event_kind" XDG_STATE_HOME="$xdg_dir" \
      "$DISPATCHER" <<<"$json_body" 2>/dev/null
  )
}

# Run dispatcher capturing stderr too
run_dispatcher_with_stderr() {
  local loom_dir="$1"
  local xdg_dir="$2"
  local event_kind="$3"
  local json_body="$4"
  (
    cd "$loom_dir"
    CLAUDE_HOOK_EVENT="$event_kind" XDG_STATE_HOME="$xdg_dir" \
      "$DISPATCHER" <<<"$json_body" 2>&1
  )
}

echo "=== test_loom_log_dispatch.sh ==="
echo ""

# ---------------------------------------------------------------------------
# Setup: shared workspace and XDG dir for multi-event tests
# ---------------------------------------------------------------------------
SHARED_XDG=$(mktemp -d)
SHARED_LOOM_DIR=$(mktemp -d)
make_loom_workspace "$SHARED_LOOM_DIR" "testproj"

# Common agent identifiers for a shared epic
EPIC_QID="testproj:abc123"
SESSION_ID="sess-test"
AGENT_ID_A="agent-executor"
AGENT_ID_B="agent-integrator"

# ---------------------------------------------------------------------------
# Test 1: TaskCreated → task_created kind
# ---------------------------------------------------------------------------
echo "[1] TaskCreated event → task_created kind logged"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  payload=$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "$AGENT_ID_A" \
    --arg epic_qid "$EPIC_QID" \
    '{
      session_id: $session_id,
      agent_id: $agent_id,
      agent_type: "story-executor",
      epic_qid: $epic_qid,
      tool_name: "TaskCreate",
      tool_input: {
        subject: "[testproj:abc123:1:1] Implement feature X"
      }
    }')

  run_dispatcher "$LOOM_DIR" "$XDG" "TaskCreated" "$payload"

  log_dir="${XDG}/loom/testproj/${EPIC_QID}"
  log_file="${log_dir}/${AGENT_ID_A}.jsonl"

  if [[ -f "$log_file" ]]; then
    kind=$(jq -r '.kind' "$log_file" 2>/dev/null)
    if [[ "$kind" == "task_created" ]]; then
      pass "TaskCreated → task_created in log"
    else
      fail "TaskCreated → expected kind=task_created, got $kind"
    fi
  else
    fail "TaskCreated: log file not created at $log_file"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 2: PostToolUse(TaskUpdate) → task_updated kind
# ---------------------------------------------------------------------------
echo "[2] PostToolUse(TaskUpdate) event → task_updated kind logged"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  payload=$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "$AGENT_ID_A" \
    --arg epic_qid "$EPIC_QID" \
    '{
      session_id: $session_id,
      agent_id: $agent_id,
      agent_type: "story-executor",
      epic_qid: $epic_qid,
      tool_name: "TaskUpdate",
      tool_input: {
        subject: "[testproj:abc123:1:1] Implement feature X",
        status: "in_progress"
      }
    }')

  run_dispatcher "$LOOM_DIR" "$XDG" "PostToolUse" "$payload"

  log_file="${XDG}/loom/testproj/${EPIC_QID}/${AGENT_ID_A}.jsonl"
  if [[ -f "$log_file" ]]; then
    kind=$(jq -r '.kind' "$log_file" 2>/dev/null)
    if [[ "$kind" == "task_updated" ]]; then
      pass "PostToolUse(TaskUpdate) → task_updated in log"
    else
      fail "PostToolUse(TaskUpdate) → expected task_updated, got $kind"
    fi
  else
    fail "PostToolUse(TaskUpdate): log file not created"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 3: TaskCompleted → task_completed kind
# ---------------------------------------------------------------------------
echo "[3] TaskCompleted event → task_completed kind logged"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  payload=$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "$AGENT_ID_A" \
    --arg epic_qid "$EPIC_QID" \
    '{
      session_id: $session_id,
      agent_id: $agent_id,
      agent_type: "story-executor",
      epic_qid: $epic_qid,
      tool_name: "TaskComplete",
      tool_input: {
        subject: "[testproj:abc123:1:1] Implement feature X"
      }
    }')

  run_dispatcher "$LOOM_DIR" "$XDG" "TaskCompleted" "$payload"

  log_file="${XDG}/loom/testproj/${EPIC_QID}/${AGENT_ID_A}.jsonl"
  if [[ -f "$log_file" ]]; then
    kind=$(jq -r '.kind' "$log_file" 2>/dev/null)
    if [[ "$kind" == "task_completed" ]]; then
      pass "TaskCompleted → task_completed in log"
    else
      fail "TaskCompleted → expected task_completed, got $kind"
    fi
  else
    fail "TaskCompleted: log file not created"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 4: SubagentStart → subagent_start kind
# ---------------------------------------------------------------------------
echo "[4] SubagentStart event → subagent_start kind logged"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  payload=$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "$AGENT_ID_A" \
    --arg epic_qid "$EPIC_QID" \
    '{
      session_id: $session_id,
      agent_id: $agent_id,
      agent_type: "story-executor",
      epic_qid: $epic_qid
    }')

  run_dispatcher "$LOOM_DIR" "$XDG" "SubagentStart" "$payload"

  log_file="${XDG}/loom/testproj/${EPIC_QID}/${AGENT_ID_A}.jsonl"
  if [[ -f "$log_file" ]]; then
    kind=$(jq -r '.kind' "$log_file" 2>/dev/null)
    if [[ "$kind" == "subagent_start" ]]; then
      pass "SubagentStart → subagent_start in log"
    else
      fail "SubagentStart → expected subagent_start, got $kind"
    fi
  else
    fail "SubagentStart: log file not created"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 5: SubagentStop → subagent_stop kind
# ---------------------------------------------------------------------------
echo "[5] SubagentStop event → subagent_stop kind logged"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  payload=$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "$AGENT_ID_A" \
    --arg epic_qid "$EPIC_QID" \
    '{
      session_id: $session_id,
      agent_id: $agent_id,
      agent_type: "story-executor",
      epic_qid: $epic_qid,
      exit_code: 0
    }')

  run_dispatcher "$LOOM_DIR" "$XDG" "SubagentStop" "$payload"

  log_file="${XDG}/loom/testproj/${EPIC_QID}/${AGENT_ID_A}.jsonl"
  if [[ -f "$log_file" ]]; then
    kind=$(jq -r '.kind' "$log_file" 2>/dev/null)
    if [[ "$kind" == "subagent_stop" ]]; then
      pass "SubagentStop → subagent_stop in log"
    else
      fail "SubagentStop → expected subagent_stop, got $kind"
    fi
  else
    fail "SubagentStop: log file not created"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 6: EnterWorktree → worktree_create kind
# ---------------------------------------------------------------------------
echo "[6] EnterWorktree event → worktree_create kind logged"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  payload=$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "$AGENT_ID_A" \
    --arg epic_qid "$EPIC_QID" \
    '{
      session_id: $session_id,
      agent_id: $agent_id,
      agent_type: "story-executor",
      epic_qid: $epic_qid,
      worktree_path: "/repo/.worktrees/abc123",
      branch: "loom/testproj-abc123"
    }')

  run_dispatcher "$LOOM_DIR" "$XDG" "EnterWorktree" "$payload"

  log_file="${XDG}/loom/testproj/${EPIC_QID}/${AGENT_ID_A}.jsonl"
  if [[ -f "$log_file" ]]; then
    kind=$(jq -r '.kind' "$log_file" 2>/dev/null)
    if [[ "$kind" == "worktree_create" ]]; then
      pass "EnterWorktree → worktree_create in log"
    else
      fail "EnterWorktree → expected worktree_create, got $kind"
    fi
  else
    fail "EnterWorktree: log file not created"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 7: ExitWorktree → worktree_delete kind
# ---------------------------------------------------------------------------
echo "[7] ExitWorktree event → worktree_delete kind logged"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  payload=$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "$AGENT_ID_A" \
    --arg epic_qid "$EPIC_QID" \
    '{
      session_id: $session_id,
      agent_id: $agent_id,
      agent_type: "story-executor",
      epic_qid: $epic_qid,
      worktree_path: "/repo/.worktrees/abc123",
      branch: "loom/testproj-abc123"
    }')

  run_dispatcher "$LOOM_DIR" "$XDG" "ExitWorktree" "$payload"

  log_file="${XDG}/loom/testproj/${EPIC_QID}/${AGENT_ID_A}.jsonl"
  if [[ -f "$log_file" ]]; then
    kind=$(jq -r '.kind' "$log_file" 2>/dev/null)
    if [[ "$kind" == "worktree_delete" ]]; then
      pass "ExitWorktree → worktree_delete in log"
    else
      fail "ExitWorktree → expected worktree_delete, got $kind"
    fi
  else
    fail "ExitWorktree: log file not created"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 8: PostToolUse(Bash) git commit → git_commit kind
# ---------------------------------------------------------------------------
echo "[8] PostToolUse(Bash) git commit → git_commit kind logged"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  payload=$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "$AGENT_ID_A" \
    --arg epic_qid "$EPIC_QID" \
    '{
      session_id: $session_id,
      agent_id: $agent_id,
      agent_type: "story-executor",
      epic_qid: $epic_qid,
      tool_name: "Bash",
      tool_input: {
        command: "git commit -m \"feat: implement thing\""
      },
      tool_response: {
        stdout: "[main abc1234] feat: implement thing\n 1 file changed",
        stderr: "",
        exit_code: 0
      }
    }')

  run_dispatcher "$LOOM_DIR" "$XDG" "PostToolUse" "$payload"

  log_file="${XDG}/loom/testproj/${EPIC_QID}/${AGENT_ID_A}.jsonl"
  if [[ -f "$log_file" ]]; then
    kind=$(jq -r '.kind' "$log_file" 2>/dev/null)
    if [[ "$kind" == "git_commit" ]]; then
      pass "PostToolUse(Bash/git commit) → git_commit in log"
    else
      fail "PostToolUse(Bash/git commit) → expected git_commit, got $kind"
    fi
  else
    fail "PostToolUse(Bash/git commit): log file not created"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 9: PostToolUse(Bash) git merge → git_merge kind
# ---------------------------------------------------------------------------
echo "[9] PostToolUse(Bash) git merge → git_merge kind logged"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  payload=$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "$AGENT_ID_A" \
    --arg epic_qid "$EPIC_QID" \
    '{
      session_id: $session_id,
      agent_id: $agent_id,
      agent_type: "story-executor",
      epic_qid: $epic_qid,
      tool_name: "Bash",
      tool_input: {
        command: "git merge --no-ff loom/abc123-1 -m \"Merge story branch\""
      },
      tool_response: {
        stdout: "Merge made by the \"recursive\" strategy.",
        stderr: "",
        exit_code: 0
      }
    }')

  run_dispatcher "$LOOM_DIR" "$XDG" "PostToolUse" "$payload"

  log_file="${XDG}/loom/testproj/${EPIC_QID}/${AGENT_ID_A}.jsonl"
  if [[ -f "$log_file" ]]; then
    kind=$(jq -r '.kind' "$log_file" 2>/dev/null)
    if [[ "$kind" == "git_merge" ]]; then
      pass "PostToolUse(Bash/git merge) → git_merge in log"
    else
      fail "PostToolUse(Bash/git merge) → expected git_merge, got $kind"
    fi
  else
    fail "PostToolUse(Bash/git merge): log file not created"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 10: PostToolUse(Bash) git branch -D → git_branch_delete kind
# ---------------------------------------------------------------------------
echo "[10] PostToolUse(Bash) git branch -D → git_branch_delete kind logged"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  payload=$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "$AGENT_ID_A" \
    --arg epic_qid "$EPIC_QID" \
    '{
      session_id: $session_id,
      agent_id: $agent_id,
      agent_type: "story-executor",
      epic_qid: $epic_qid,
      tool_name: "Bash",
      tool_input: {
        command: "git branch -D loom/abc123-1"
      }
    }')

  run_dispatcher "$LOOM_DIR" "$XDG" "PostToolUse" "$payload"

  log_file="${XDG}/loom/testproj/${EPIC_QID}/${AGENT_ID_A}.jsonl"
  if [[ -f "$log_file" ]]; then
    kind=$(jq -r '.kind' "$log_file" 2>/dev/null)
    if [[ "$kind" == "git_branch_delete" ]]; then
      pass "PostToolUse(Bash/git branch -D) → git_branch_delete in log"
    else
      fail "PostToolUse(Bash/git branch -D) → expected git_branch_delete, got $kind"
    fi
  else
    fail "PostToolUse(Bash/git branch -D): log file not created"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 11: Directory creation and agent-id file partition
# ---------------------------------------------------------------------------
echo "[11] Directory created; per-agent-id file partition"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  # Fire two events with different agent IDs
  for agent_id in "executor-agent" "integrator-agent"; do
    payload=$(jq -n \
      --arg session_id "$SESSION_ID" \
      --arg agent_id "$agent_id" \
      --arg epic_qid "$EPIC_QID" \
      '{
        session_id: $session_id,
        agent_id: $agent_id,
        agent_type: "story-executor",
        epic_qid: $epic_qid
      }')
    run_dispatcher "$LOOM_DIR" "$XDG" "SubagentStart" "$payload"
  done

  expected_dir="${XDG}/loom/testproj/${EPIC_QID}"
  ok=true

  if [[ ! -d "$expected_dir" ]]; then
    fail "log directory not created: $expected_dir"
    ok=false
  else
    pass "log directory created: $expected_dir"
  fi

  for agent_id in "executor-agent" "integrator-agent"; do
    f="${expected_dir}/${agent_id}.jsonl"
    if [[ -f "$f" ]]; then
      pass "per-agent file created: ${agent_id}.jsonl"
    else
      fail "per-agent file missing: ${agent_id}.jsonl"
      ok=false
    fi
  done

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 12: Every line parses as JSON with required fields
# ---------------------------------------------------------------------------
echo "[12] Every logged line parses as JSON with required fields"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  # Fire several events
  events=(
    "TaskCreated:{\"session_id\":\"s1\",\"agent_id\":\"ag1\",\"agent_type\":\"story-executor\",\"epic_qid\":\"${EPIC_QID}\",\"tool_name\":\"TaskCreate\",\"tool_input\":{\"subject\":\"[testproj:abc123:1:1] test\"}}"
    "TaskCompleted:{\"session_id\":\"s1\",\"agent_id\":\"ag1\",\"agent_type\":\"story-executor\",\"epic_qid\":\"${EPIC_QID}\",\"tool_input\":{\"subject\":\"[testproj:abc123:1:1] test\"}}"
    "SubagentStart:{\"session_id\":\"s1\",\"agent_id\":\"ag1\",\"agent_type\":\"story-executor\",\"epic_qid\":\"${EPIC_QID}\"}"
  )

  for event_payload in "${events[@]}"; do
    event_kind="${event_payload%%:*}"
    json_body="${event_payload#*:}"
    run_dispatcher "$LOOM_DIR" "$XDG" "$event_kind" "$json_body"
  done

  log_file="${XDG}/loom/testproj/${EPIC_QID}/ag1.jsonl"
  if [[ ! -f "$log_file" ]]; then
    fail "log file not created"
  else
    ok=true
    while IFS= read -r line; do
      for field in schema_version ts kind epic_qid agent_id session_id agent_type; do
        val=$(echo "$line" | jq -r ".${field} // \"__MISSING__\"" 2>/dev/null)
        if [[ "$val" == "__MISSING__" ]] || [[ "$val" == "null" ]] || [[ -z "$val" ]]; then
          fail "required field '$field' missing in line: $line"
          ok=false
        fi
      done
    done < "$log_file"
    [[ "$ok" == "true" ]] && pass "all log lines have required fields"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 13: Non-matching Bash invocations produce zero events
# ---------------------------------------------------------------------------
echo "[13] Non-matching Bash (ls, npm test) produces zero events"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  for cmd in "ls -la" "npm test" "echo hello" "cat /etc/hosts"; do
    payload=$(jq -n \
      --arg session_id "$SESSION_ID" \
      --arg agent_id "$AGENT_ID_A" \
      --arg epic_qid "$EPIC_QID" \
      --arg command "$cmd" \
      '{
        session_id: $session_id,
        agent_id: $agent_id,
        agent_type: "story-executor",
        epic_qid: $epic_qid,
        tool_name: "Bash",
        tool_input: { command: $command }
      }')
    run_dispatcher "$LOOM_DIR" "$XDG" "PostToolUse" "$payload"
  done

  log_file="${XDG}/loom/testproj/${EPIC_QID}/${AGENT_ID_A}.jsonl"
  if [[ -f "$log_file" ]]; then
    line_count=$(wc -l < "$log_file" | tr -d ' ')
    fail "non-matching Bash: expected 0 events, got $line_count (file exists)"
  else
    pass "non-matching Bash: no events logged (file absent)"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 14: Malformed stdin → exit 0 with diagnostic on stderr
# ---------------------------------------------------------------------------
echo "[14] Malformed stdin → exit 0 with diagnostic on stderr"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  exit_code=0
  stderr_output=""
  stderr_output=$(
    cd "$LOOM_DIR"
    CLAUDE_HOOK_EVENT="TaskCreated" XDG_STATE_HOME="$XDG" \
      "$DISPATCHER" <<<"this is not json" 2>&1
  ) || exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    if [[ -n "$stderr_output" ]]; then
      pass "malformed stdin → exit 0 with diagnostic on stderr"
    else
      fail "malformed stdin → exit 0 but no diagnostic on stderr"
    fi
  else
    fail "malformed stdin → expected exit 0 (fail-open), got exit $exit_code"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 15: All ten mechanical event kinds present across combined run
# ---------------------------------------------------------------------------
echo "[15] All ten mechanical kinds produced"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproj"

  base_fields="\"session_id\":\"s1\",\"agent_id\":\"ag1\",\"agent_type\":\"story-executor\",\"epic_qid\":\"${EPIC_QID}\""

  # TaskCreated → task_created
  run_dispatcher "$LOOM_DIR" "$XDG" "TaskCreated" \
    "{${base_fields},\"tool_name\":\"TaskCreate\",\"tool_input\":{\"subject\":\"[testproj:abc123:1:1] test\"}}"

  # PostToolUse(TaskUpdate) → task_updated
  run_dispatcher "$LOOM_DIR" "$XDG" "PostToolUse" \
    "{${base_fields},\"tool_name\":\"TaskUpdate\",\"tool_input\":{\"subject\":\"[testproj:abc123:1:1] test\",\"status\":\"in_progress\"}}"

  # TaskCompleted → task_completed
  run_dispatcher "$LOOM_DIR" "$XDG" "TaskCompleted" \
    "{${base_fields},\"tool_input\":{\"subject\":\"[testproj:abc123:1:1] test\"}}"

  # SubagentStart → subagent_start
  run_dispatcher "$LOOM_DIR" "$XDG" "SubagentStart" \
    "{${base_fields}}"

  # SubagentStop → subagent_stop
  run_dispatcher "$LOOM_DIR" "$XDG" "SubagentStop" \
    "{${base_fields},\"exit_code\":0}"

  # EnterWorktree → worktree_create
  run_dispatcher "$LOOM_DIR" "$XDG" "EnterWorktree" \
    "{${base_fields},\"worktree_path\":\"/repo/.worktrees/abc123\",\"branch\":\"loom/testproj-abc123\"}"

  # ExitWorktree → worktree_delete
  run_dispatcher "$LOOM_DIR" "$XDG" "ExitWorktree" \
    "{${base_fields},\"worktree_path\":\"/repo/.worktrees/abc123\",\"branch\":\"loom/testproj-abc123\"}"

  # PostToolUse(Bash) git commit → git_commit
  run_dispatcher "$LOOM_DIR" "$XDG" "PostToolUse" \
    "{${base_fields},\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m 'feat: x'\"},\"tool_response\":{\"stdout\":\"[main abc1234] feat: x\",\"exit_code\":0}}"

  # PostToolUse(Bash) git merge → git_merge
  run_dispatcher "$LOOM_DIR" "$XDG" "PostToolUse" \
    "{${base_fields},\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git merge --no-ff loom/abc123-1\"}}"

  # PostToolUse(Bash) git branch -D → git_branch_delete
  run_dispatcher "$LOOM_DIR" "$XDG" "PostToolUse" \
    "{${base_fields},\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git branch -D loom/abc123-1\"}}"

  log_file="${XDG}/loom/testproj/${EPIC_QID}/ag1.jsonl"
  if [[ ! -f "$log_file" ]]; then
    fail "log file not created for all-kinds test"
  else
    required_kinds=(
      task_created
      task_updated
      task_completed
      subagent_start
      subagent_stop
      worktree_create
      worktree_delete
      git_commit
      git_merge
      git_branch_delete
    )
    ok=true
    for kind in "${required_kinds[@]}"; do
      if grep -q "\"kind\":\"${kind}\"" "$log_file" 2>/dev/null; then
        pass "kind '$kind' present"
      else
        fail "kind '$kind' MISSING from log"
        ok=false
      fi
    done
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
  exit 1
fi
exit 0
