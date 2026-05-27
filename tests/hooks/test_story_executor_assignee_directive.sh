#!/usr/bin/env bash
# Test: agents/story-executor.md does not contain <session_id>/<agent_id> templates.
#
# Verifies that story-executor.md Step 2 no longer shows a template command
# with placeholder values that agents might attempt to fill in themselves.
# Instead it should reference the injected context block and say "copy verbatim".

set -euo pipefail

AGENT_FILE="$(dirname "$0")/../../agents/story-executor.md"

if [[ ! -f "$AGENT_FILE" ]]; then
  echo "FAIL: agents/story-executor.md not found at $AGENT_FILE"
  exit 1
fi

# Case 1: no <session_id_from_context> template placeholder in file
if grep -q '<session_id_from_context>' "$AGENT_FILE"; then
  echo "FAIL: agents/story-executor.md still contains <session_id_from_context> placeholder"
  grep -n '<session_id_from_context>' "$AGENT_FILE"
  exit 1
fi
echo "PASS: no <session_id_from_context> placeholder in story-executor.md"

# Case 2: no <agent_id_from_context> template placeholder in file
if grep -q '<agent_id_from_context>' "$AGENT_FILE"; then
  echo "FAIL: agents/story-executor.md still contains <agent_id_from_context> placeholder"
  grep -n '<agent_id_from_context>' "$AGENT_FILE"
  exit 1
fi
echo "PASS: no <agent_id_from_context> placeholder in story-executor.md"

# Case 3: Step 2 instructs the agent to copy the command verbatim from the injected context
step2_section=$(awk '/### Step 2/,/### Step 3/' "$AGENT_FILE")
if ! echo "$step2_section" | grep -qiE "verbatim|injected.*context|Loom Workflow Context"; then
  echo "FAIL: Step 2 in story-executor.md does not reference the injected context block"
  echo "Step 2 content:"
  echo "$step2_section"
  exit 1
fi
echo "PASS: Step 2 references the injected context block"

echo "ALL PASS"
