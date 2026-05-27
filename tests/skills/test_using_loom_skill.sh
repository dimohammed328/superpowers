#!/usr/bin/env bash
# Test: skills/using-loom/SKILL.md validation criteria
# Verifies the skill file exists, has correct frontmatter, documents
# all required subcommands, and includes the -y global option callout.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_FILE="$REPO_ROOT/skills/using-loom/SKILL.md"

PASS=0
FAIL=0

check() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "ok" ]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# 1. File exists
if [ -f "$SKILL_FILE" ]; then
  check "SKILL.md exists" ok
else
  check "SKILL.md exists" fail
  echo "FATAL: $SKILL_FILE not found — cannot run remaining tests."
  exit 1
fi

# 2. Frontmatter: name: using-loom
if grep -q '^name: using-loom' "$SKILL_FILE"; then
  check "frontmatter has 'name: using-loom'" ok
else
  check "frontmatter has 'name: using-loom'" fail
fi

# 3. Frontmatter: description field present
if grep -q '^description:' "$SKILL_FILE"; then
  check "frontmatter has 'description:' field" ok
else
  check "frontmatter has 'description:' field" fail
fi

# 4-15. Each required subcommand is documented
SUBCOMMANDS=(
  "project create"
  "epic create"
  "story create"
  "task create"
  "dep add"
  "order"
  "ready"
  "show"
  "update"
  "complete"
  "validate"
  "tree"
)

for subcmd in "${SUBCOMMANDS[@]}"; do
  if grep -q "$subcmd" "$SKILL_FILE"; then
    check "documents '$subcmd' subcommand" ok
  else
    check "documents '$subcmd' subcommand" fail
  fi
done

# 16. -y / --non-interactive callout present
if grep -q '\-y' "$SKILL_FILE" && grep -qiE 'global' "$SKILL_FILE"; then
  check "'-y is a global option' callout present" ok
else
  check "'-y is a global option' callout present" fail
fi

# 18. -y callout appears before subcommand docs (prominent = early in file)
# The callout section must appear before line 50 (within the first third)
callout_line=$(grep -n 'GLOBAL' "$SKILL_FILE" | head -1 | cut -d: -f1)
first_subcmd_line=$(grep -n '### `project create`' "$SKILL_FILE" | head -1 | cut -d: -f1)
if [ -n "$callout_line" ] && [ -n "$first_subcmd_line" ] && [ "$callout_line" -lt "$first_subcmd_line" ]; then
  check "'-y global' callout appears before subcommand docs (prominent position)" ok
else
  check "'-y global' callout appears before subcommand docs (prominent position)" fail
fi

# 19. Callout uses a section heading (## level)
if grep -q '^## .*GLOBAL\|^## CRITICAL' "$SKILL_FILE"; then
  check "'-y global' callout uses a dedicated section heading (##)" ok
else
  check "'-y global' callout uses a dedicated section heading (##)" fail
fi

# 17. At least one example per subcommand (check for 'loom ' command examples)
example_count=$(grep -c '^loom ' "$SKILL_FILE" 2>/dev/null || true)
if [ "$example_count" -ge 12 ]; then
  check "at least 12 canonical examples (one per subcommand)" ok
else
  check "at least 12 canonical examples (one per subcommand) [found: $example_count]" fail
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
