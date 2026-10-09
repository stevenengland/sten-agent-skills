#!/usr/bin/env bash
# Behavior + wiring tests for reading issue comments (`get_comments`).
#
# Comments carry clarifications and corrections the body never gets, and the
# failure is silent: a skill that reads only the body still runs, just on a
# stale spec. Two ways that happens are tested here:
#
#   1. A filter creeps into the helper. Any comment may carry the user's design
#      marker — including a minimized one, or one that looks like stenswf
#      bookkeeping — so the helper must print every comment.
#   2. A content read loses its `get_comments` line, or one is added where the
#      body is hashed (concept.md, drift check), turning every new comment
#      into false drift.
#
# Run: bash plugins/stenswf/tests/issue-comments.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)

# shellcheck source=../scripts/extractors.sh
source "$ROOT/scripts/extractors.sh"

PASS=0
FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()    { [ "$2" = "$3" ] && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
assert_match() { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || { fail "$1"; printf '    missing %q in: %s\n' "$3" "$2"; }; }
assert_no()    { printf '%s' "$2" | grep -qF -- "$3" && { fail "$1"; printf '    unexpected %q in: %s\n' "$3" "$2"; } || ok "$1"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Fake gh: `gh issue view <n> --json comments -q <expr>` → the -q expression
# applied to $WORK/comments-<n>.json, as gh's built-in jq would.
gh() {
  [ "$1 $2 $4 $5 $6" = "issue view --json comments -q" ] || { echo "fake gh: unexpected call: $*" >&2; return 99; }
  jq -r "$7" "$WORK/comments-$3.json"
}

# ---------------------------------------------------------------------------
# 1. get_comments — every comment, compact, in order
# ---------------------------------------------------------------------------

cat > "$WORK/comments-1.json" <<'EOF'
{"comments": [
  {"author": {"login": "alice"}, "body": "Please also handle the empty case.", "isMinimized": false},
  {"author": {"login": "bob"}, "body": "Outdated idea, but keep X.", "isMinimized": true, "minimizedReason": "OUTDATED"},
  {"author": {"login": "me"}, "body": "<!-- stenswf:decisions:start -->\nD1\n<!-- stenswf:decisions:end -->", "isMinimized": false},
  {"author": {"login": "me"}, "body": "Claiming.\n\n<!-- stenswf-claim: s1 -->", "isMinimized": false},
  {"author": {"login": "me"}, "body": "Holding.\n\n<!-- stenswf-maplock: lock-s1 at 1 -->", "isMinimized": false},
  {"author": {"login": "me"}, "body": "Answer.\n\n<!-- stenswf-resolved:v1 -->", "isMinimized": false},
  {"author": null, "body": "From a deleted account.", "isMinimized": false}
]}
EOF
OUT=$(get_comments 1)

assert_eq "the header comes first" "$(printf '%s\n' "$OUT" | head -1 | cut -c1-12)" "## Comments "
assert_match "the header carries the conflict rule" "$OUT" "check the code, else escalate"
assert_match "a comment prints as @login + body" "$OUT" "$(printf '@alice:\nPlease also handle the empty case.')"
assert_match "a minimized comment is kept" "$OUT" "Outdated idea, but keep X."
assert_match "a decisions-render comment is kept" "$OUT" "<!-- stenswf:decisions:start -->"
assert_match "a claim comment is kept" "$OUT" "<!-- stenswf-claim: s1 -->"
assert_match "a map-lock comment is kept" "$OUT" "<!-- stenswf-maplock: lock-s1 at 1 -->"
assert_match "a resolution comment is kept" "$OUT" "<!-- stenswf-resolved:v1 -->"
assert_match "a deleted author prints as @ghost" "$OUT" "@ghost:"
assert_eq "every comment prints, oldest first" \
  "$(printf '%s\n' "$OUT" | grep '^@' | tr '\n' ' ')" \
  "@alice: @bob: @me: @me: @me: @me: @ghost: "
assert_no "no JSON metadata leaks into the output" "$OUT" "isMinimized"

echo '{"comments": []}' > "$WORK/comments-2.json"
assert_eq "no comments prints nothing" "$(get_comments 2)" ""

# ---------------------------------------------------------------------------
# 2. The rule the header points at exists
# ---------------------------------------------------------------------------

SECTION=$(printf '%s\n' "$OUT" | head -1 | sed -n 's/.*§ \([^)]*\)).*/\1/p')
assert_eq "the header names a section" "$SECTION" "Issue comments"
grep -qx "## $SECTION" "$ROOT/references/decision-escalation.md" \
  && ok "decision-escalation.md has the section the header names" \
  || fail "decision-escalation.md has the section the header names"

# ---------------------------------------------------------------------------
# 3. Wiring — every content read calls the helper; no hash site does
# ---------------------------------------------------------------------------

# Bash-block call sites: must call the helper and source the library.
for f in skills/plan/SKILL.md skills/plan-light/SKILL.md skills/ship-light/SKILL.md \
         references/mode-detection.md skills/review-loop/SKILL.md \
         skills/apply-loop/SKILL.md skills/prd-from-grill-me/SKILL.md \
         skills/triage-issue/SKILL.md; do
  grep -q 'get_comments' "$ROOT/$f" && ok "$f reads comments" || fail "$f reads comments"
  grep -q 'source \.\./\.\./scripts/extractors\.sh' "$ROOT/$f" \
    && ok "$f sources extractors.sh" || fail "$f sources extractors.sh"
done
assert_match "plan reads the parent PRD's comments too" \
  "$(cat "$ROOT/skills/plan/SKILL.md")" 'get_comments $PRD_REF'

# Prose call sites.
for f in skills/prd-to-issues/SKILL.md skills/wayfinder/SKILL.md; do
  grep -q 'get_comments' "$ROOT/$f" && ok "$f reads comments" || fail "$f reads comments"
done

assert_no "drift-check never mixes comments into the hashed body" \
  "$(cat "$ROOT/references/drift-check.md")" "get_comments"
assert_eq "no concept.md or drift snapshot receives comments" \
  "$(grep -rn 'get_comments' "$ROOT/skills" "$ROOT/references" | grep -E 'concept\.md|-now\.md')" ""

printf '\n1..%s\n# pass %s fail %s\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
