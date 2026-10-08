#!/usr/bin/env bash
# Behavior tests for the peer deliberation protocol (scripts/deliberation.sh).
#
# Deliberately small. The value of a deliberation is the quality of the
# research and the argument, and no shell assertion reaches that — it is
# forward-tested by running real agents. What IS worth pinning here is the
# handful of mechanics whose failure is silent:
#
#   1. turns cannot be overwritten          (a rewritable transcript proves nothing)
#   2. A hands B an exact path              (discovery is what picks the wrong one)
#   3. a modified proposal invalidates acceptance
#   4. a rejected proposal can be revised and retried
#
# Plus the state-machine transitions those rest on, and one regression
# guard for a bug that shipped in review: derived paths computed inside a
# single `local` expanded empty, so `delib_accept` reported a missing
# proposal that was sitting right there.
#
# Run:  bash plugins/stenswf/tests/deliberation.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPTS="$HERE/../scripts"
SKILLS="$HERE/../skills"
REFS="$HERE/../references"

# shellcheck source=../scripts/deliberation.sh
source "$SCRIPTS/deliberation.sh"

PASS=0; FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()      { [ "$2" = "$3" ] && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
assert_match()   { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || { fail "$1"; printf '    missing %q in: %s\n' "$3" "$2"; }; }
assert_nomatch() { printf '%s' "$2" | grep -qF -- "$3" && { fail "$1"; printf '    unexpected %q\n' "$3"; } || ok "$1"; }

WORK=$(mktemp -d); ORIG=$PWD
trap 'cd "$ORIG"; rm -rf "$WORK"' EXIT
cd "$WORK" && git init -q . && git config user.email t@t && git config user.name t

turn() { printf '# Turn %s — %s\n\n## Read\nsrc/x.ts\n\n## Open\n%s\n' "$1" "$2" "${3:-(none)}" > "$WORK/t.md"; }
prop() { printf '# Proposal\n\n## Solution\n%s\n\n## Refs\nsrc/adapter.ts\n\n## Scope impact\nnone\n' "$1" > "$WORK/p.md"; }

# --- 1. Turns are immutable ----------------------------------------------
D=$(delib_new 42)
assert_match "a deliberation gets its own id'd directory" "$D" ".stenswf/42/deliberations/"
D2=$(delib_new 42)
[ "$D" != "$D2" ] && ok "a second wall on one issue does not collide with the first" \
                  || fail "a second wall on one issue does not collide with the first"

turn 0 A; delib_turn_write "$D" 0 A "$WORK/t.md"
turn 1 B; delib_turn_write "$D" 1 B "$WORK/t.md"
assert_eq "turns are numbered from the tension" "$(delib_turn "$D")" "1"

printf 'REWRITTEN\n' > "$WORK/bad.md"
delib_turn_write "$D" 1 B "$WORK/bad.md" 2>/dev/null \
  && fail "overwriting a turn is refused" || ok "overwriting a turn is refused"
assert_nomatch "the original turn survives the attempt" "$(cat "$D/01-B.md")" "REWRITTEN"
assert_nomatch "no .tmp residue is left behind" "$(ls "$D")" ".tmp"

# --- 2. The exact path is handed over, not discovered ---------------------
assert_match "A's bootstrap hands B the directory" \
  "$(cat "$SKILLS/deliberate/SKILL.md")" 'Deliberation: $DIR'
assert_match "the peer takes the path as its argument" \
  "$(cat "$SKILLS/deliberate-peer/SKILL.md")" 'DIR="$ARGUMENTS"'
# No global scan, no env override: both were how a peer picked up the
# wrong deliberation, and how a signed-but-unaccepted proposal vanished.
assert_nomatch "no discovery function survives" "$(cat "$SCRIPTS/deliberation.sh")" "delib_find()"
assert_nomatch "no directory env override survives" "$(cat "$SCRIPTS/deliberation.sh")" "STENSWF_DELIB_DIR"

# --- 3. A modified proposal invalidates acceptance ------------------------
prop "Retry at the adapter."
N=$(delib_propose "$D" "$WORK/p.md")
assert_eq "the first proposal is version 1" "$N" "1"
# The regression guard: this reported "no proposal-1.md" for a file that
# existed, because $dir and $n expanded empty inside a single `local`.
delib_accept "$D" "$N" 2>/dev/null && ok "B can accept the proposal that exists" \
                                   || fail "B can accept the proposal that exists"
assert_eq "acceptance verifies" "$(proposal_verify "$D" "$N")" "accepted"

sed -i 's/Retry at the adapter\./Retry at the caller./' "$D/proposal-1.md"
assert_eq "editing an accepted proposal makes it stale" "$(proposal_verify "$D" "$N")" "stale"
proposal_verify "$D" "$N" >/dev/null 2>&1 && fail "stale returns non-zero" || ok "stale returns non-zero"
# Whitespace is an editor, not a rewording.
sed -i 's/Retry at the caller\./Retry at the adapter.  /' "$D/proposal-1.md"
assert_eq "trailing whitespace does not invalidate acceptance" "$(proposal_verify "$D" "$N")" "accepted"

# --- 4. Rejection, revision, retry ---------------------------------------
R=$(delib_new 43)
turn 0 A; delib_turn_write "$R" 0 A "$WORK/t.md"
prop "Use A."; P1=$(delib_propose "$R" "$WORK/p.md")
assert_eq "an unjudged proposal is owed a verdict by B" "$(delib_next_role "$R")" "B"
# A rejection needs an ARTIFACT. Written only as a turn it is invisible to
# the protocol, the proposal stays unjudged, and control never returns to A.
turn 1 B "clause 2"; delib_turn_write "$R" 1 B "$WORK/t.md"
assert_eq "a prose-only rejection does NOT hand control back" "$(delib_next_role "$R")" "B"
printf 'clause 2 double-counts the backoff\n' > "$WORK/rej.md"
delib_reject "$R" "$P1" "$WORK/rej.md"
assert_eq "a recorded rejection hands control to A" "$(delib_next_role "$R")" "A"
delib_accept "$R" "$P1" 2>/dev/null && fail "a rejected proposal cannot then be accepted" \
                                    || ok "a rejected proposal cannot then be accepted"
prop "Use C."; P2=$(delib_propose "$R" "$WORK/p.md")
assert_eq "the revision is a new version" "$P2" "2"
assert_match "the rejected version stays readable" "$(cat "$R/proposal-1.md")" "Use A."
delib_accept "$R" "$P2"
assert_eq "the revision can be accepted" "$(proposal_verify "$R" "$P2")" "accepted"
assert_eq "v1 stays unaccepted" "$(proposal_verify "$R" "$P1")" "pending"
assert_eq "after acceptance A writes the result" "$(delib_next_role "$R")" "A"

# --- 5. Closing is a guarded transition, not a file write -----------------
assert_eq "an accepted proposal does not close it" "$(delib_open_for_issue 43)" "$R"
printf '# Result\n' > "$WORK/res.md"
delib_finish "$R" "$P1" "$WORK/res.md" 2>/dev/null \
  && fail "finishing a superseded proposal is refused" \
  || ok "finishing a superseded proposal is refused"
delib_finish "$R" "$P2" "$WORK/res.md" 2>/dev/null \
  && ok "finishing the accepted latest proposal closes it" \
  || fail "finishing the accepted latest proposal closes it"
assert_eq "the deliberation is closed" "$(delib_open_for_issue 43)" ""
assert_eq "a closed deliberation has no next role" "$(delib_next_role "$R")" ""
delib_finish "$R" "$P2" "$WORK/res.md" 2>/dev/null \
  && fail "a second finish is refused" || ok "a second finish is refused"

# An unaccepted proposal must not be finishable at all.
U=$(delib_new 45); turn 0 A; delib_turn_write "$U" 0 A "$WORK/t.md"
prop "Unjudged."; PU=$(delib_propose "$U" "$WORK/p.md")
delib_finish "$U" "$PU" "$WORK/res.md" 2>/dev/null \
  && fail "finishing an unaccepted proposal is refused" \
  || ok "finishing an unaccepted proposal is refused"

# --- 6. Bounds are enforced, not merely documented ------------------------
W=$(delib_new 44); turn 0 A; delib_turn_write "$W" 0 A "$WORK/t.md"
assert_eq "wait returns at once when the peer moved" \
  "$(turn 1 B; delib_turn_write "$W" 1 B "$WORK/t.md"; delib_wait "$W" 0 0 5 1)" "turn 1"
assert_eq "an absent peer times out rather than hanging" "$(delib_wait "$W" 1 0 1 1)" "timeout"
DELIB_MAX_ROUNDS=6 delib_round_guard "$W" >/dev/null && ok "under the cap the guard passes" \
                                                     || fail "under the cap the guard passes"
DELIB_MAX_ROUNDS=0 delib_round_guard "$W" >/dev/null && fail "past the cap the guard fails" \
                                                     || ok "past the cap the guard fails"

# --- 7. Contradictions name the entry, not the file -----------------------
C=$(delib_new 80); mkdir -p .stenswf/80 docs/stenswf/decisions
cat > .stenswf/80/decisions.md <<'EOF'
# Decisions — #80

### D1 — Unrelated call

- **Category:** decision
- **Refs:** src/other.ts

---

### D2 — Retry at the caller

- **Category:** arch
- **Refs:** src/adapter.ts

---

### ~~D3~~ — Retired call

- **Category:** arch
- **Refs:** src/adapter.ts
EOF
prop "Retry at the adapter."; cp "$WORK/p.md" "$C/proposal-1.md"
CAND=$(delib_contradictions 80 "$C/proposal-1.md")
assert_match "the entry citing the path is named"     "$CAND" "D2"
assert_nomatch "entries citing other paths are not"   "$CAND" "D1"
assert_nomatch "superseded entries are not offered"   "$CAND" "D3"
assert_nomatch "the delib token is not treated as a path" "$CAND" "delib#"

# Paths are literal strings, not patterns. Matching them as regexes lost
# every real path containing a metacharacter — Next.js `app/[id]/`,
# route groups `(group)`, `a+b.ts` — and a miss here walks a real
# contradiction straight past a MANDATORY human sign-off. A false
# negative in this gate is the worst failure the feature has.
mkdir -p docs/stenswf/decisions
cat >> .stenswf/80/decisions.md <<'EOF'

---

### D4 — Render the id route on the server

- **Category:** arch
- **Refs:** app/[id]/page.tsx
EOF
printf '# Curated

Refs: app/[id]/page.tsx
' > docs/stenswf/decisions/prd-9.md
printf 'x
' > meta.txt && git add -A >/dev/null 2>&1
git commit -q -m "feat: id route

Refs: #80
Touches: app/[id]/page.tsx" >/dev/null 2>&1
printf '# Proposal

## Solution
Client render.

## Refs
app/[id]/page.tsx
' > "$C/proposal-2.md"
META=$(delib_contradictions 80 "$C/proposal-2.md")
assert_match "a bracketed path is found in the anchor tier"    "$META" "D4"
assert_match "a bracketed path is found in the committed tier" "$META" "prd-9.md"
assert_match "a bracketed path is found in the git tier"       "$META" "git"
# Literal, not merely permissive: a regex that WOULD match must not.
printf '# Proposal

## Refs
app/.id./page.tsx
' > "$C/proposal-3.md"
assert_nomatch "a regex lookalike does not match a literal path" \
  "$(delib_contradictions 80 "$C/proposal-3.md")" "D4"

# --- 8. Wiring ------------------------------------------------------------
for f in "$SKILLS/deliberate/SKILL.md" "$SKILLS/deliberate-peer/SKILL.md"; do
  n=$(basename "$(dirname "$f")")
  assert_match "$n loads the contract"    "$(cat "$f")" "deliberation-loop.md"
  assert_match "$n sources the plumbing"  "$(cat "$f")" "scripts/deliberation.sh"
done
assert_match "A always records an anchor" "$(cat "$SKILLS/deliberate/SKILL.md")" "**always**"
assert_match "issue-rework skips the human gate" \
  "$(cat "$SKILLS/deliberate/SKILL.md")" "does not pass through this gate"
assert_match "the peer is read-only"      "$(cat "$SKILLS/deliberate-peer/SKILL.md")" "read-only"
assert_match "apply-loop knows how to enter" "$(cat "$SKILLS/apply-loop/SKILL.md")" "list_reraised"
assert_match "review-loop will not converge mid-deliberation" \
  "$(cat "$SKILLS/review-loop/SKILL.md")" "Never converge or exit while a deliberation is open"
assert_match "escalation forbids unilateral, not autonomous, decisions" \
  "$(cat "$REFS/decision-escalation.md")" "No *unilateral* heavy decisions"
assert_nomatch "the old absolutist wording is gone" \
  "$(cat "$REFS/decision-escalation.md")" "Zero autonomous heavy decisions"

for f in "$REFS/deliberation-loop.md" "$SKILLS/deliberate/SKILL.md" "$SKILLS/deliberate-peer/SKILL.md"; do
  d=$(dirname "$f")
  while IFS= read -r link; do
    [ -e "$d/$link" ] && ok "link resolves: $(basename "$(dirname "$f")")/$(basename "$f") → $link" \
                      || fail "dangling link in $f: $link"
  done < <(grep -oE '\]\(([^)#]+\.(md|sh))' "$f" | sed 's/^](//' | sort -u)
done

# --- 9. The canonical run, in the skills' own command order ---------------
# One scenario over the exact calls the two SKILL.md files document. Each
# unit above pins a transition in isolation; this pins that they compose,
# which is where all three of the shipped transition bugs actually lived —
# every one of them passed its neighbours' tests.
E=$(delib_new 46)
turn 0 A;            delib_turn_write "$E" 0 A "$WORK/t.md"
assert_eq "e2e: tension opens, B answers first" "$(delib_next_role "$E")" "B"
turn 1 B "Q1";       delib_turn_write "$E" 1 B "$WORK/t.md"
turn 2 A;            delib_turn_write "$E" 2 A "$WORK/t.md"
prop "Use A.";       EP1=$(delib_propose "$E" "$WORK/p.md")
# A waits with its OWN version, per the skill. `$((N-1))` here returned
# A's own proposal instantly and A answered itself while B waited.
assert_eq "e2e: A's wait does not return A's own proposal" \
  "$(delib_wait "$E" 2 "$EP1" 1 1)" "timeout"
printf 'clause 2 fails\n' > "$WORK/rej.md"; delib_reject "$E" "$EP1" "$WORK/rej.md"
assert_eq "e2e: rejection returns control to A" "$(delib_next_role "$E")" "A"
assert_eq "e2e: A's wait reports the rejection" "$(delib_wait "$E" 2 "$EP1" 1 1)" "rejected 1"
prop "Use C.";       EP2=$(delib_propose "$E" "$WORK/p.md")
delib_accept "$E" "$EP2"
# Turn 2 is even. Under turn parity this said B, so A never ran the gate.
assert_eq "e2e: acceptance returns control to A regardless of turn parity" \
  "$(delib_next_role "$E")" "A"
assert_eq "e2e: the latest turn is even, the parity that used to fail" "$(delib_turn "$E")" "2"
delib_finish "$E" "$EP2" "$WORK/res.md"
assert_eq "e2e: the deliberation closes" "$(delib_open_for_issue 46)" ""

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
