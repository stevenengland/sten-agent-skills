#!/usr/bin/env bash
# Structural smoke check for the interview lens pass (PRD #40, slice #41): the
# shared reference exists and holds its dispatch templates, the result and
# summary tokens the caller parses are present, plan and prd-from-grill-me are
# wired to it and no longer confirm settled decisions unconditionally,
# decision-weighting carries the business-logic question, and the files the PRD
# keeps out of scope stay off the lens pass.
#
# It deliberately does not pin instructional prose: rewording a rule must not
# fail this suite. A passing run says nothing about whether a lens judges well,
# whether fewer questions reach the user, or whether escalation behaves as
# before. Those limits are accepted in
# docs/stenswf/decisions/2026-10-16-interview-lenses.md.
#
# Run: bash plugins/stenswf/tests/interview-lenses.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
REPO=$(CDPATH= cd -- "$ROOT/../.." && pwd)
SKILLS="$ROOT/skills"
REFS="$ROOT/references"

PASS=0
FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()      { [ "$2" = "$3" ] && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
# Substring checks without a pipe: under pipefail, "printf | grep -q" can fail
# when grep exits early and printf takes SIGPIPE on a large haystack.
assert_match()   { [[ "$2" == *"$3"* ]] && ok "$1" || { fail "$1"; printf '    missing %q\n' "$3"; }; }
assert_nomatch() { [[ "$2" == *"$3"* ]] && { fail "$1"; printf '    unexpected %q\n' "$3"; } || ok "$1"; }
assert_file()    { [ -f "$2" ] && ok "$1" || { fail "$1"; printf '    missing file %s\n' "$2"; }; }
read_file()      { cat "$1" 2>/dev/null || true; }
# Lines of $2 from the first line matching the regex $1 up to (not including)
# the next line matching the regex $3. Write a literal "." "*" "[" "]" as
# "[.]" "[*]" "[[]" "[]]": awk -v rewrites backslash escapes.
between() { awk -v start="$1" -v stop="$3" '
  !on && $0 ~ start { on = 1; print; next }
  on && $0 ~ stop { exit }
  on { print }' "$2" 2>/dev/null; }
# "in order" when the regexes after $1 first match file $1 in ascending lines.
in_order() { local f=$1; shift; local IFS=$'\t'; awk -v pats="$*" '
  BEGIN { n = split(pats, p, "\t") }
  { for (i = 1; i <= n; i++) if (!(i in at) && $0 ~ p[i]) at[i] = NR }
  END { for (i = 1; i <= n; i++) if (!(i in at) || (i > 1 && at[i] <= at[i-1])) { print "out of order"; exit }
        print "in order" }' "$f" 2>/dev/null; }

LENSES="$REFS/interview-lenses.md"
PLAN="$SKILLS/plan/SKILL.md"
PRD="$SKILLS/prd-from-grill-me/SKILL.md"
WEIGHTING="$REFS/decision-weighting.md"
ADR="$REPO/docs/stenswf/decisions/2026-10-16-interview-lenses.md"
LT=$(read_file "$LENSES")
PT=$(read_file "$PLAN")

# --- 1. The shared reference and plan's hook (AC1) ---------------------------
assert_file "the lens-pass reference exists" "$LENSES"
assert_match "the reference delegates classification to decision-escalation" "$LT" "(decision-escalation.md)"
assert_match "plan links the lens-pass reference" "$PT" "(../../references/interview-lenses.md)"
assert_eq "plan runs the lens pass after orientation and before the interview" \
  "$(in_order "$PLAN" '^### Orientation$' '^### Lens pass$' '^### Interview$')" "in order"
DISPATCH=$(between '^## 2[.] Dispatch the lenses' "$LENSES" '^## ')
assert_match "the lenses are dispatched in parallel" "$DISPATCH" "in parallel"
assert_match "each lens is dispatched at most once per run" "$DISPATCH" "at most once per run"
TRD=$(read_file "$HERE/README.md")
assert_match "tests/README describes this suite" "$TRD" "[\`interview-lenses.test.sh\`](interview-lenses.test.sh)"
assert_match "tests/README runs this suite" "$TRD" "bash plugins/stenswf/tests/interview-lenses.test.sh"

# --- 2. The three dispatch templates (AC2) -----------------------------------
for lens in Design Strategy Precedent; do
  body=$(between "^### $lens lens\$" "$LENSES" '^###? ')
  assert_match "the $lens block starts a dispatch message" "$body" "SKILLS TO LOAD:"
  assert_match "the $lens block is read-only" "$body" "MUST NOT edit"
  assert_match "the $lens block names its subject slot" "$body" "<SUBJECT>"
done
DESIGN=$(between '^### Design lens$' "$LENSES" '^###? ')
STRATEGY=$(between '^### Strategy lens$' "$LENSES" '^###? ')
PRECEDENT=$(between '^### Precedent lens$' "$LENSES" '^###? ')
assert_match "Design loads codebase-design and clean-code" "$DESIGN" "SKILLS TO LOAD: codebase-design, clean-code, brevity"
assert_match "Strategy loads architecture" "$STRATEGY" "SKILLS TO LOAD: architecture, brevity"
assert_match "Strategy weighs options per decision-weighting" "$STRATEGY" "decision-weighting"
assert_match "Precedent loads only brevity" "$PRECEDENT" "SKILLS TO LOAD: brevity"
for src in "git log" "gh issue list --state all" "decisions.md" "docs/"; do
  assert_match "Precedent searches $src" "$PRECEDENT" "$src"
done
CONTEXT=$(between '^### Shared context block$' "$LENSES" '^###? ')
for slot in "<SUBJECT>" "<ORIENTATION>" "<QUESTIONS>" "<PINNED>"; do
  assert_match "the shared context block carries $slot" "$CONTEXT" "$slot"
done
DRAFT=$(between '^## 1[.] Draft the questions' "$LENSES" '^## ')
assert_match "drafting covers interface changes" "$DRAFT" "interface changes"
assert_match "drafting covers the behaviors to test" "$DRAFT" "behaviors to test"
assert_match "drafting pins only resolved decisions" "$DRAFT" "resolved"
assert_match "drafting leaves out anchored decisions" "$DRAFT" "decisions.md"
assert_match "drafting tags business questions" "$DRAFT" "[business]"

# --- 3. The result format (AC3) ----------------------------------------------
RETURN=$(between '^### Return format$' "$LENSES" '^###? ')
assert_match "a verdict names its recommended option" "$RETURN" "recommend: <letter>"
assert_match "options are lettered" "$RETURN" "A) <option>"
for field in evidence downsides contradicts also_solves tiebreaker reversible uncertain; do
  assert_match "the result format carries $field" "$RETURN" "$field:"
done
assert_match "tiebreaker uses decision-escalation's vocabulary" "$RETURN" "convention | anchor | analog | none"
assert_match "contradicts qualifies decisions by issue" "$RETURN" "#<issue>/D<n> | invariant: <source> | none"
assert_match "lenses add at most 3 questions" "$RETURN" "at most 3"
assert_match "each lens ends with one LENS_SUMMARY line" "$RETURN" \
  "LENS_SUMMARY: <lens> answered=<n> added=<n> tiebreakers=<n> contradictions=<n>"

# --- footer (append new sections above this line) --------------------------
printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
