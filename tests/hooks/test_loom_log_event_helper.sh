#!/usr/bin/env bash
# Unit tests for hooks/lib/loom-log-event.sh
#
# Each test case uses a temp XDG_STATE_HOME and a temp .loom/state.json
# to control `project` derivation. Tests verify:
#   1. Happy path: single well-formed JSONL line at expected path
#   2. Missing required field exits non-zero
#   3. Optional fields omitted (not nulled) when not passed
#   4. Two concurrent invocations to different agent_id files both succeed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SCRIPT_DIR}/../../hooks/lib/loom-log-event.sh"

PASS=0
FAIL=0
ERRORS=()

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# Create a temp loom workspace with a given project name
# Usage: make_loom_workspace <dir> <project>
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

echo "=== test_loom_log_event_helper.sh ==="
echo ""

# ---------------------------------------------------------------------------
# Test 1: Happy path — single well-formed JSONL line at expected path
# ---------------------------------------------------------------------------
echo "[1] Happy path: writes one JSONL line to expected path"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  output=$(
    cd "$LOOM_DIR" && \
    XDG_STATE_HOME="$XDG" \
      "$HELPER" \
      --kind "agent_start" \
      --epic-qid "proj:abc123" \
      --agent-id "agent-42" \
      --session-id "sess-99" \
      --agent-type "story-executor" 2>&1
  )
  exit_code=$?

  expected_file="${XDG}/loom/testproject/proj:abc123/agent-42.jsonl"

  if [[ $exit_code -ne 0 ]]; then
    fail "helper exited $exit_code; output: $output"
  elif [[ ! -f "$expected_file" ]]; then
    fail "expected file not found: $expected_file"
  else
    line_count=$(wc -l < "$expected_file" | tr -d ' ')
    if [[ "$line_count" -ne 1 ]]; then
      fail "expected 1 line, got $line_count"
    else
      pass "file created with 1 line"
    fi
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 2: Required fields present in JSONL output
# ---------------------------------------------------------------------------
echo "[2] Required fields present: schema_version, ts, kind, epic_qid, agent_id, session_id, agent_type"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "task_complete" \
    --epic-qid "proj:abc123" \
    --agent-id "agent-1" \
    --session-id "sess-1" \
    --agent-type "story-executor" >/dev/null 2>&1

  expected_file="${XDG}/loom/testproject/proj:abc123/agent-1.jsonl"
  record=$(cat "$expected_file")

  ok=true
  for field in schema_version ts kind epic_qid agent_id session_id agent_type; do
    val=$(echo "$record" | jq -r ".${field} // \"__MISSING__\"")
    if [[ "$val" == "__MISSING__" ]] || [[ "$val" == "null" ]]; then
      fail "required field '$field' missing or null in JSONL"
      ok=false
    fi
  done
  [[ "$ok" == "true" ]] && pass "all required fields present"

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 3: Optional fields omitted (not nulled) when not passed
# ---------------------------------------------------------------------------
echo "[3] Optional fields omitted when not passed (no story_qid, task_qid, note)"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "agent_start" \
    --epic-qid "proj:abc123" \
    --agent-id "agent-2" \
    --session-id "sess-2" \
    --agent-type "story-executor" >/dev/null 2>&1

  expected_file="${XDG}/loom/testproject/proj:abc123/agent-2.jsonl"
  record=$(cat "$expected_file")

  ok=true
  for field in story_qid task_qid note; do
    # jq returns "null" string if key is present with null, or fails if absent
    present=$(echo "$record" | jq "has(\"${field}\")")
    if [[ "$present" == "true" ]]; then
      fail "optional field '$field' should be absent but is present in JSONL"
      ok=false
    fi
  done
  [[ "$ok" == "true" ]] && pass "optional fields omitted when not passed"

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 4: Optional fields included when passed
# ---------------------------------------------------------------------------
echo "[4] Optional fields included when passed"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "task_start" \
    --epic-qid "proj:abc123" \
    --agent-id "agent-3" \
    --session-id "sess-3" \
    --agent-type "story-executor" \
    --story-qid "proj:abc123:1" \
    --task-qid "proj:abc123:1:1" \
    --note "beginning task" >/dev/null 2>&1

  expected_file="${XDG}/loom/testproject/proj:abc123/agent-3.jsonl"
  record=$(cat "$expected_file")

  ok=true
  for field in story_qid task_qid note; do
    present=$(echo "$record" | jq "has(\"${field}\")")
    if [[ "$present" != "true" ]]; then
      fail "optional field '$field' should be present but is absent"
      ok=false
    fi
  done
  [[ "$ok" == "true" ]] && pass "optional fields present when passed"

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 5: Missing required field exits non-zero
# ---------------------------------------------------------------------------
echo "[5] Missing required field --kind exits non-zero"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  exit_code=0
  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --epic-qid "proj:abc123" \
    --agent-id "agent-4" \
    --session-id "sess-4" \
    --agent-type "story-executor" >/dev/null 2>&1 \
  || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    pass "exits non-zero when --kind is missing"
  else
    fail "expected non-zero exit when --kind is missing, got 0"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 6: Missing required field --epic-qid exits non-zero
# ---------------------------------------------------------------------------
echo "[6] Missing required field --epic-qid exits non-zero"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  exit_code=0
  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "agent_start" \
    --agent-id "agent-5" \
    --session-id "sess-5" \
    --agent-type "story-executor" >/dev/null 2>&1 \
  || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    pass "exits non-zero when --epic-qid is missing"
  else
    fail "expected non-zero exit when --epic-qid is missing, got 0"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 7: --field key=value adds extra payload fields
# ---------------------------------------------------------------------------
echo "[7] --field key=value adds extra payload fields"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "story_commit" \
    --epic-qid "proj:abc123" \
    --agent-id "agent-6" \
    --session-id "sess-6" \
    --agent-type "story-executor" \
    --field "branch=loom/abc123-1" \
    --field "sha=deadbeef" >/dev/null 2>&1

  expected_file="${XDG}/loom/testproject/proj:abc123/agent-6.jsonl"
  record=$(cat "$expected_file")

  branch_val=$(echo "$record" | jq -r '.branch // "__MISSING__"')
  sha_val=$(echo "$record" | jq -r '.sha // "__MISSING__"')

  if [[ "$branch_val" == "loom/abc123-1" ]] && [[ "$sha_val" == "deadbeef" ]]; then
    pass "--field key=value payload fields present"
  else
    fail "--field fields missing or wrong: branch=$branch_val sha=$sha_val"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 8: Concurrent invocations to different agent_id files both succeed
# ---------------------------------------------------------------------------
echo "[8] Concurrent invocations to different agent_id files both succeed"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"

  (
    XDG_STATE_HOME="$XDG" \
      "$HELPER" \
      --kind "agent_start" \
      --epic-qid "proj:abc123" \
      --agent-id "agent-concurrent-A" \
      --session-id "sess-A" \
      --agent-type "story-executor" >/dev/null 2>&1
  ) &
  pid1=$!

  (
    XDG_STATE_HOME="$XDG" \
      "$HELPER" \
      --kind "agent_start" \
      --epic-qid "proj:abc123" \
      --agent-id "agent-concurrent-B" \
      --session-id "sess-B" \
      --agent-type "story-executor" >/dev/null 2>&1
  ) &
  pid2=$!

  wait $pid1
  rc1=$?
  wait $pid2
  rc2=$?

  file_a="${XDG}/loom/testproject/proj:abc123/agent-concurrent-A.jsonl"
  file_b="${XDG}/loom/testproject/proj:abc123/agent-concurrent-B.jsonl"

  ok=true
  [[ $rc1 -ne 0 ]] && { fail "concurrent invocation A exited $rc1"; ok=false; }
  [[ $rc2 -ne 0 ]] && { fail "concurrent invocation B exited $rc2"; ok=false; }
  [[ ! -f "$file_a" ]] && { fail "file A not created"; ok=false; }
  [[ ! -f "$file_b" ]] && { fail "file B not created"; ok=false; }

  if [[ "$ok" == "true" ]]; then
    lines_a=$(wc -l < "$file_a" | tr -d ' ')
    lines_b=$(wc -l < "$file_b" | tr -d ' ')
    if [[ "$lines_a" -eq 1 ]] && [[ "$lines_b" -eq 1 ]]; then
      pass "both concurrent invocations produced exactly 1 line each"
    else
      fail "expected 1 line each, got A=$lines_a B=$lines_b"
    fi
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 9: No loom workspace found — exits non-zero with diagnostic
# ---------------------------------------------------------------------------
echo "[9] No .loom workspace found — exits non-zero"
{
  XDG=$(mktemp -d)
  NO_LOOM_DIR=$(mktemp -d)

  exit_code=0
  cd "$NO_LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "agent_start" \
    --epic-qid "proj:abc123" \
    --agent-id "agent-7" \
    --session-id "sess-7" \
    --agent-type "story-executor" >/dev/null 2>&1 \
  || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    pass "exits non-zero when no .loom workspace found"
  else
    fail "expected non-zero exit when no .loom workspace, got 0"
  fi

  rm -rf "$XDG" "$NO_LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 10: schema_version is 1
# ---------------------------------------------------------------------------
echo "[10] schema_version is 1"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "agent_start" \
    --epic-qid "proj:abc123" \
    --agent-id "agent-8" \
    --session-id "sess-8" \
    --agent-type "story-executor" >/dev/null 2>&1

  expected_file="${XDG}/loom/testproject/proj:abc123/agent-8.jsonl"
  sv=$(cat "$expected_file" | jq -r '.schema_version')
  if [[ "$sv" == "1" ]]; then
    pass "schema_version is 1"
  else
    fail "schema_version expected 1, got $sv"
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
