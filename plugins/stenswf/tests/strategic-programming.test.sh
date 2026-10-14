#!/usr/bin/env bash
# Presence tests for the strategic-over-tactical rule and the justification
# clause it asks planning artifacts to carry.
#
# The rule is prose, so nothing breaks loudly when an edit drops it: a lost
# question, a skill name slipping into the wrong scope, or the subsection
# bloating past its line budget all read fine to a reviewer skimming a diff.
# Every pinned string sits on one source line (never wrapped), so a fixed-
# string grep is enough to catch each of those.
#
# Run: bash plugins/stenswf/tests/strategic-programming.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
WEIGHTING="$ROOT/references/decision-weighting.md"

PASS=0
FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()      { [ "$2" = "$3" ] && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
assert_match()   { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || { fail "$1"; printf '    missing %q\n' "$3"; }; }
assert_nomatch() { printf '%s' "$2" | grep -qF -- "$3" && { fail "$1"; printf '    unexpected %q\n' "$3"; } || ok "$1"; }

# Lines of $2 from the first line equal to $1 up to (not including) the first
# line after it that matches the regex $3.
section() { awk -v start="$1" -v stop="$3" '
  $0 == start { on = 1; print; next }
  on && $0 ~ stop { exit }
  on { print }' "$2"; }

CLAUSE='why this is the best solution for the underlying problem, the architecture and the business rules, and its trade-off against the strongest plausible alternative'

# --- 1. The strategic-over-tactical subsection ------------------------------
HEADING='### Strategic over tactical'
RULE=$(section '## The rule' "$WEIGHTING" '^---$')
SUB=$(section "$HEADING" "$WEIGHTING" '^---$')

assert_match "the subsection sits inside ## The rule, before its closing ---" "$RULE" "$HEADING"
line_of() { printf '%s\n' "$1" | grep -nF -- "$2" | cut -d: -f1 | head -1; }
GOLD=$(line_of "$RULE" 'Do not gold-plate'); HEAD=$(line_of "$RULE" "$HEADING")
assert_eq "the existing rule text precedes the subsection" \
  "$([ -n "$HEAD" ] && [ "${GOLD:-0}" -lt "$HEAD" ] && echo yes || echo no)" "yes"
assert_eq "the question sits verbatim on one source line" \
  "$(printf '%s\n' "$SUB" | grep -cxF '**Is this the best solution to the problem from an architectural and business-logic point of view?**')" "1"
# Prose may rewrap, so phrases are matched on the subsection joined into one line.
JOINED=$(printf '%s\n' "$SUB" | tr '\n' ' ')
assert_match "the rejection phrase is present" "$JOINED" '"No, but quicker" rejects the option.'
assert_match "the reversibility proviso is present" "$JOINED" "one-way vs. two-way doors"
assert_match "the tactical exception is for business urgency" "$JOINED" "business urgency"
assert_match "the tactical exception never serves developer convenience" "$JOINED" "never developer convenience"
assert_match "the compromise and its reason are named" "$JOINED" "name it and its reason"
assert_match "the user accepts it via decision-escalation" "$JOINED" "(decision-escalation.md)"
assert_match "acceptance ASKs when available" "$JOINED" "ASK"
assert_match "acceptance PARKs when unattended" "$JOINED" "PARK when unattended"
assert_match "a follow-up issue, new or existing, is linked" "$JOINED" "follow-up issue, new or existing"

# Order check: each name must occur after the previous one.
ORDER=$(awk -v s="$JOINED" 'BEGIN {
  n = split("architecture grill-me prd-from-grill-me prd-to-issues plan plan-light triage-issue deliberate deliberate-peer", k, " ")
  pos = 0
  for (i = 1; i <= n; i++) {
    rest = substr(s, pos + 1); j = index(rest, "`" k[i] "`")
    if (j == 0) { print "missing " k[i]; exit }
    pos += j
  }
  print "in order" }')
assert_eq "the nine planning skills appear in Conventions order" "$ORDER" "in order"
for name in tdd apply clean-code slice-e2e; do
  assert_nomatch "the subsection does not name \`$name\`" "$SUB" "\`$name\`"
done
SPAN=$(printf '%s\n' "$SUB" | awk 'NF { last = NR } END { print last + 0 }')
assert_eq "the subsection spans at most 16 lines" "$([ "$SPAN" -ge 1 ] && [ "$SPAN" -le 16 ] && echo yes || echo "no ($SPAN)")" "yes"

LOADERS=$(awk '/^---$/ { exit } { print }' "$WEIGHTING" | tr '\n' ' ')
assert_match "the loader list names deliberate and deliberate-peer after triage-issue" \
  "$LOADERS" '`triage-issue`, `deliberate`, `deliberate-peer`,'

printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
