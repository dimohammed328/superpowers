#!/usr/bin/env bash
# tests/hooks/test_loom_log_semantic.sh
#
# Tests for semantic event kinds defined in docs/orchestrator-log.md.
# Invokes hooks/lib/loom-log-event.sh directly with each semantic kind under
# a temp XDG_STATE_HOME and stub .loom/state.json. Asserts each event lands
# in the expected per-agent file as well-formed JSON carrying the documented
# payload fields.

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

echo "=== test_loom_log_semantic.sh ==="
echo ""

# ---------------------------------------------------------------------------
# Test 1: wave_start — wave_index and story_qids land in JSON
# ---------------------------------------------------------------------------
echo "[1] wave_start: wave_index and story_qids payload fields"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "wave_start" \
    --epic-qid "proj:abc" \
    --agent-id "sess-1-orchestrator" \
    --session-id "sess-1" \
    --agent-type "story-executor" \
    --field "wave_index=0" \
    --field "story_qids=proj:abc:1 proj:abc:2"

  expected_file="${XDG}/loom/testproject/proj:abc/sess-1-orchestrator.jsonl"
  ok=true

  if [[ ! -f "$expected_file" ]]; then
    fail "wave_start: file not created at expected path"
    ok=false
  else
    # Verify JSON is well-formed
    if ! jq -e . "$expected_file" >/dev/null 2>&1; then
      fail "wave_start: output is not valid JSON"
      ok=false
    fi

    kind=$(jq -r '.kind' "$expected_file")
    wave_index=$(jq -r '.wave_index' "$expected_file")
    story_qids=$(jq -r '.story_qids' "$expected_file")

    [[ "$kind" != "wave_start" ]] && { fail "wave_start: kind field is '$kind', expected 'wave_start'"; ok=false; }
    [[ "$wave_index" != "0" ]] && { fail "wave_start: wave_index is '$wave_index', expected '0'"; ok=false; }
    [[ "$story_qids" != "proj:abc:1 proj:abc:2" ]] && { fail "wave_start: story_qids is '$story_qids'"; ok=false; }

    [[ "$ok" == "true" ]] && pass "wave_start: wave_index and story_qids present in JSON"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 2: wave_complete — wave_index and optional note
# ---------------------------------------------------------------------------
echo "[2] wave_complete: wave_index and note payload fields"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "wave_complete" \
    --epic-qid "proj:abc" \
    --agent-id "sess-1-orchestrator" \
    --session-id "sess-1" \
    --agent-type "story-executor" \
    --field "wave_index=0" \
    --note "2 ok, 0 failed"

  expected_file="${XDG}/loom/testproject/proj:abc/sess-1-orchestrator.jsonl"
  ok=true

  if [[ ! -f "$expected_file" ]]; then
    fail "wave_complete: file not created"
    ok=false
  else
    if ! jq -e . "$expected_file" >/dev/null 2>&1; then
      fail "wave_complete: output is not valid JSON"
      ok=false
    fi

    kind=$(jq -r '.kind' "$expected_file")
    wave_index=$(jq -r '.wave_index' "$expected_file")
    note=$(jq -r '.note' "$expected_file")

    [[ "$kind" != "wave_complete" ]] && { fail "wave_complete: kind is '$kind'"; ok=false; }
    [[ "$wave_index" != "0" ]] && { fail "wave_complete: wave_index is '$wave_index'"; ok=false; }
    [[ "$note" != "2 ok, 0 failed" ]] && { fail "wave_complete: note is '$note'"; ok=false; }

    [[ "$ok" == "true" ]] && pass "wave_complete: wave_index and note present"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 3: integration_start — story_qid required
# ---------------------------------------------------------------------------
echo "[3] integration_start: story_qid payload field"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "integration_start" \
    --epic-qid "proj:abc" \
    --agent-id "sess-1:integrator-1" \
    --session-id "sess-1" \
    --agent-type "story-integrator" \
    --story-qid "proj:abc:1"

  expected_file="${XDG}/loom/testproject/proj:abc/sess-1:integrator-1.jsonl"
  ok=true

  if [[ ! -f "$expected_file" ]]; then
    fail "integration_start: file not created"
    ok=false
  else
    if ! jq -e . "$expected_file" >/dev/null 2>&1; then
      fail "integration_start: output is not valid JSON"
      ok=false
    fi

    kind=$(jq -r '.kind' "$expected_file")
    story_qid=$(jq -r '.story_qid' "$expected_file")

    [[ "$kind" != "integration_start" ]] && { fail "integration_start: kind is '$kind'"; ok=false; }
    [[ "$story_qid" != "proj:abc:1" ]] && { fail "integration_start: story_qid is '$story_qid'"; ok=false; }

    [[ "$ok" == "true" ]] && pass "integration_start: story_qid present"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 4: integration_complete — story_qid and result fields
# ---------------------------------------------------------------------------
echo "[4] integration_complete: story_qid and result payload fields"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "integration_complete" \
    --epic-qid "proj:abc" \
    --agent-id "sess-1:integrator-1" \
    --session-id "sess-1" \
    --agent-type "story-integrator" \
    --story-qid "proj:abc:1" \
    --field "result=ok"

  expected_file="${XDG}/loom/testproject/proj:abc/sess-1:integrator-1.jsonl"
  ok=true

  if [[ ! -f "$expected_file" ]]; then
    fail "integration_complete: file not created"
    ok=false
  else
    if ! jq -e . "$expected_file" >/dev/null 2>&1; then
      fail "integration_complete: output is not valid JSON"
      ok=false
    fi

    kind=$(jq -r '.kind' "$expected_file")
    story_qid=$(jq -r '.story_qid' "$expected_file")
    result=$(jq -r '.result' "$expected_file")

    [[ "$kind" != "integration_complete" ]] && { fail "integration_complete: kind is '$kind'"; ok=false; }
    [[ "$story_qid" != "proj:abc:1" ]] && { fail "integration_complete: story_qid is '$story_qid'"; ok=false; }
    [[ "$result" != "ok" ]] && { fail "integration_complete: result is '$result', expected 'ok'"; ok=false; }

    [[ "$ok" == "true" ]] && pass "integration_complete: story_qid and result present"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 5: validation_start — emitted by epic-validator (no extra payload)
# ---------------------------------------------------------------------------
echo "[5] validation_start: well-formed JSON with base fields"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "validation_start" \
    --epic-qid "proj:abc" \
    --agent-id "sess-1:validator-1" \
    --session-id "sess-1" \
    --agent-type "epic-validator"

  expected_file="${XDG}/loom/testproject/proj:abc/sess-1:validator-1.jsonl"
  ok=true

  if [[ ! -f "$expected_file" ]]; then
    fail "validation_start: file not created"
    ok=false
  else
    if ! jq -e . "$expected_file" >/dev/null 2>&1; then
      fail "validation_start: output is not valid JSON"
      ok=false
    fi

    kind=$(jq -r '.kind' "$expected_file")
    epic_qid=$(jq -r '.epic_qid' "$expected_file")
    agent_type=$(jq -r '.agent_type' "$expected_file")

    [[ "$kind" != "validation_start" ]] && { fail "validation_start: kind is '$kind'"; ok=false; }
    [[ "$epic_qid" != "proj:abc" ]] && { fail "validation_start: epic_qid is '$epic_qid'"; ok=false; }
    [[ "$agent_type" != "epic-validator" ]] && { fail "validation_start: agent_type is '$agent_type'"; ok=false; }

    [[ "$ok" == "true" ]] && pass "validation_start: well-formed JSON with base fields"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 6: validation_result — result and optional summary
# ---------------------------------------------------------------------------
echo "[6] validation_result: result field (pass) and optional summary"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "validation_result" \
    --epic-qid "proj:abc" \
    --agent-id "sess-1:validator-1" \
    --session-id "sess-1" \
    --agent-type "epic-validator" \
    --field "result=fail" \
    --field "summary=criterion 2 unmet: rg returned matches"

  expected_file="${XDG}/loom/testproject/proj:abc/sess-1:validator-1.jsonl"
  ok=true

  if [[ ! -f "$expected_file" ]]; then
    fail "validation_result: file not created"
    ok=false
  else
    if ! jq -e . "$expected_file" >/dev/null 2>&1; then
      fail "validation_result: output is not valid JSON"
      ok=false
    fi

    kind=$(jq -r '.kind' "$expected_file")
    result=$(jq -r '.result' "$expected_file")
    summary=$(jq -r '.summary' "$expected_file")

    [[ "$kind" != "validation_result" ]] && { fail "validation_result: kind is '$kind'"; ok=false; }
    [[ "$result" != "fail" ]] && { fail "validation_result: result is '$result', expected 'fail'"; ok=false; }
    [[ "$summary" != "criterion 2 unmet: rg returned matches" ]] && { fail "validation_result: summary is '$summary'"; ok=false; }

    [[ "$ok" == "true" ]] && pass "validation_result: result and summary present"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 7: retry_decision — story_qid, attempt, reason
# ---------------------------------------------------------------------------
echo "[7] retry_decision: story_qid, attempt, and reason payload fields"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "retry_decision" \
    --epic-qid "proj:abc" \
    --agent-id "sess-1-orchestrator" \
    --session-id "sess-1" \
    --agent-type "story-executor" \
    --story-qid "proj:abc:2" \
    --field "attempt=1" \
    --field "reason=validation_failed: 2 criteria unmet"

  expected_file="${XDG}/loom/testproject/proj:abc/sess-1-orchestrator.jsonl"
  ok=true

  if [[ ! -f "$expected_file" ]]; then
    fail "retry_decision: file not created"
    ok=false
  else
    if ! jq -e . "$expected_file" >/dev/null 2>&1; then
      fail "retry_decision: output is not valid JSON"
      ok=false
    fi

    kind=$(jq -r '.kind' "$expected_file")
    story_qid=$(jq -r '.story_qid' "$expected_file")
    attempt=$(jq -r '.attempt' "$expected_file")
    reason=$(jq -r '.reason' "$expected_file")

    [[ "$kind" != "retry_decision" ]] && { fail "retry_decision: kind is '$kind'"; ok=false; }
    [[ "$story_qid" != "proj:abc:2" ]] && { fail "retry_decision: story_qid is '$story_qid'"; ok=false; }
    [[ "$attempt" != "1" ]] && { fail "retry_decision: attempt is '$attempt', expected '1'"; ok=false; }
    [[ "$reason" != "validation_failed: 2 criteria unmet" ]] && { fail "retry_decision: reason is '$reason'"; ok=false; }

    [[ "$ok" == "true" ]] && pass "retry_decision: story_qid, attempt, reason present"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 8: epic_finalize — merged_to and optional pr_url
# ---------------------------------------------------------------------------
echo "[8] epic_finalize: merged_to payload field"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "epic_finalize" \
    --epic-qid "proj:abc" \
    --agent-id "sess-1-orchestrator" \
    --session-id "sess-1" \
    --agent-type "story-executor" \
    --field "merged_to=main"

  expected_file="${XDG}/loom/testproject/proj:abc/sess-1-orchestrator.jsonl"
  ok=true

  if [[ ! -f "$expected_file" ]]; then
    fail "epic_finalize: file not created"
    ok=false
  else
    if ! jq -e . "$expected_file" >/dev/null 2>&1; then
      fail "epic_finalize: output is not valid JSON"
      ok=false
    fi

    kind=$(jq -r '.kind' "$expected_file")
    merged_to=$(jq -r '.merged_to' "$expected_file")

    [[ "$kind" != "epic_finalize" ]] && { fail "epic_finalize: kind is '$kind'"; ok=false; }
    [[ "$merged_to" != "main" ]] && { fail "epic_finalize: merged_to is '$merged_to', expected 'main'"; ok=false; }

    [[ "$ok" == "true" ]] && pass "epic_finalize: merged_to present"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 9: epic_finalize with pr_url (PR mode)
# ---------------------------------------------------------------------------
echo "[9] epic_finalize: pr_url payload field when present"
{
  XDG=$(mktemp -d)
  LOOM_DIR=$(mktemp -d)
  make_loom_workspace "$LOOM_DIR" "testproject"

  cd "$LOOM_DIR"
  XDG_STATE_HOME="$XDG" \
    "$HELPER" \
    --kind "epic_finalize" \
    --epic-qid "proj:abc" \
    --agent-id "sess-1-orchestrator" \
    --session-id "sess-1" \
    --agent-type "story-executor" \
    --field "merged_to=main" \
    --field "pr_url=https://github.com/org/repo/pull/42"

  expected_file="${XDG}/loom/testproject/proj:abc/sess-1-orchestrator.jsonl"
  ok=true

  if [[ ! -f "$expected_file" ]]; then
    fail "epic_finalize pr_url: file not created"
    ok=false
  else
    if ! jq -e . "$expected_file" >/dev/null 2>&1; then
      fail "epic_finalize pr_url: output is not valid JSON"
      ok=false
    fi

    pr_url=$(jq -r '.pr_url' "$expected_file")

    [[ "$pr_url" != "https://github.com/org/repo/pull/42" ]] && { fail "epic_finalize pr_url: pr_url is '$pr_url'"; ok=false; }

    [[ "$ok" == "true" ]] && pass "epic_finalize: pr_url present when passed"
  fi

  rm -rf "$XDG" "$LOOM_DIR"
}

# ---------------------------------------------------------------------------
# Test 10: all 8 semantic kinds produce schema_version=1
# ---------------------------------------------------------------------------
echo "[10] all semantic kinds produce schema_version=1"
{
  ok=true
  for kind_val in wave_start wave_complete integration_start integration_complete \
                  validation_start validation_result retry_decision epic_finalize; do
    XDG=$(mktemp -d)
    LOOM_DIR=$(mktemp -d)
    make_loom_workspace "$LOOM_DIR" "testproject"

    cd "$LOOM_DIR"
    XDG_STATE_HOME="$XDG" \
      "$HELPER" \
      --kind "$kind_val" \
      --epic-qid "proj:schema" \
      --agent-id "schema-check-agent" \
      --session-id "sess-schema" \
      --agent-type "story-executor" >/dev/null 2>&1

    expected_file="${XDG}/loom/testproject/proj:schema/schema-check-agent.jsonl"
    if [[ ! -f "$expected_file" ]]; then
      fail "schema_version check: $kind_val file not created"
      ok=false
    else
      sv=$(jq -r '.schema_version' "$expected_file")
      if [[ "$sv" != "1" ]]; then
        fail "schema_version check: $kind_val schema_version=$sv, expected 1"
        ok=false
      fi
    fi

    rm -rf "$XDG" "$LOOM_DIR"
  done

  [[ "$ok" == "true" ]] && pass "all 8 semantic kinds produce schema_version=1"
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
