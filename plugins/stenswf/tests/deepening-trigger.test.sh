#!/usr/bin/env bash
# Behavior tests for the deepening trigger in skills/review/slice.md.
#
# The trigger is a bash block inside the skill, so this test extracts the
# block and executes it against fixture changes in throwaway repos — staged,
# or committed and named by DIFF_RANGE as review-loop does — instead of
# restating the predicate (see tests/README.md). DEEPEN_HIT is on
# when any changed file lies outside documentation and data files (*.md,
# *.markdown, *.json, *.yaml, *.yml, *.toml, *.lock, *.txt) and test paths.
# It deliberately does not look for declarations: uncertainty means the
# subagent inspects, and the subagent decides what is a finding.
#
# Run: bash plugins/stenswf/tests/deepening-trigger.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
SLICE="$ROOT/skills/review/slice.md"

PASS=0
FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq() { [ "$2" = "$3" ] && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }

# The fenced bash block under "### Deepening trigger (rule-based)".
TRIGGER=$(awk '
  $0 == "### Deepening trigger (rule-based)" { s = 1; next }
  s && $0 == "```bash" { on = 1; next }
  on && $0 == "```" { exit }
  on { print }' "$SLICE")
assert_eq "the trigger block is extractable" "$([ -n "$TRIGGER" ] && echo yes || echo no)" "yes"
assert_eq "the trigger block computes DEEPEN_HIT" \
  "$(printf '%s\n' "$TRIGGER" | grep -c '^DEEPEN_HIT=')" "1"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A fresh repo with one committed baseline; the caller then edits and stages.
new_repo() {
  R="$WORK/$1"
  mkdir -p "$R/src" "$R/lib" "$R/scripts" "$R/docs" "$R/tests"
  git -C "$R" init -q
  git -C "$R" config user.email t@t
  git -C "$R" config user.name t
  printf 'export function existing() {\n  return 1\n}\n\nexport function helper() {\n  return 2\n}\n' > "$R/src/core.ts"
  printf 'class Model:\n    def run(self):\n        return 1\n' > "$R/lib/model.py"
  printf '# Guide\n' > "$R/docs/guide.md"
  printf 'def test_existing():\n    assert True\n' > "$R/tests/test_core.py"
  printf '{}\n' > "$R/package.json"
  printf '# lock\n' > "$R/yarn.lock"
  git -C "$R" add -A
  git -C "$R" commit -qm base
}

# Run the extracted trigger in $R and print on|off.
trigger() { (cd "$R" && bash -c "$TRIGGER") 2>/dev/null | sed -n 's/^Deepening trigger: //p'; }
stage() { git -C "$R" add -A; }
# review-loop reads fetched commits, never the index: commit, then run the
# trigger on that commit range with an empty index.
trigger_range() { git -C "$R" add -A; git -C "$R" commit -qm change
  (cd "$R" && DIFF_RANGE=HEAD~1..HEAD bash -c "$TRIGGER") 2>/dev/null | sed -n 's/^Deepening trigger: //p'; }

# --- 1. Production code turns the trigger on --------------------------------
new_repo indented-method
printf 'class Model:\n    def run(self, scale):\n        return scale\n' > "$R/lib/model.py"; stage
assert_eq "a change inside an indented method turns the trigger on" "$(trigger)" "on"

new_repo removed-function
printf 'export function existing() {\n  return 1\n}\n' > "$R/src/core.ts"; stage
assert_eq "a removed function turns the trigger on" "$(trigger)" "on"

new_repo new-script
printf '#!/usr/bin/env bash\necho hi\n' > "$R/scripts/run.sh"; stage
assert_eq "a new shell script turns the trigger on" "$(trigger)" "on"

# --- 2. Docs, data and tests keep it off -----------------------------------
new_repo markdown-only
printf '## Usage\nexport function inDocs() {}\n' >> "$R/docs/guide.md"; stage
assert_eq "a markdown-only change keeps the trigger off" "$(trigger)" "off"

new_repo tests-only
printf 'def test_more():\n    assert True\n' >> "$R/tests/test_core.py"
printf 'test("x", () => {})\n' > "$R/src/core.test.ts"; stage
assert_eq "changes only under test paths keep the trigger off" "$(trigger)" "off"

new_repo data-only
printf '{"name": "x"}\n' > "$R/package.json"
printf '# lock 2\n' > "$R/yarn.lock"; stage
assert_eq "a lockfile and JSON-only change keeps the trigger off" "$(trigger)" "off"

# --- 3. review-loop: a committed range with an empty index -----------------
new_repo committed-source
printf 'export function existing() {\n  return 3\n}\n' > "$R/src/core.ts"
assert_eq "a committed source change in DIFF_RANGE turns the trigger on" "$(trigger_range)" "on"

new_repo committed-docs
printf '## More\n' >> "$R/docs/guide.md"
assert_eq "a committed docs-only change in DIFF_RANGE keeps the trigger off" "$(trigger_range)" "off"

printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
