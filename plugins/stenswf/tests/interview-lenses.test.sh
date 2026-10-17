#!/usr/bin/env bash
# Structural smoke check for the interview lens pass (PRD #40, slice #41): the
# shared reference exists and holds its dispatch templates, the result and
# summary tokens the caller parses are present, plan and prd-from-grill-me are
# wired to it and no longer confirm settled decisions unconditionally,
# decision-weighting carries the business-logic question, and the files the PRD
# keeps out of scope stay off the lens pass.
#
# It anchors on structural tokens — headings, slots, field names, table rows,
# link targets, ordering — plus a few load-bearing phrases taken from the
# acceptance criteria (for example "rejected without asking"); rewording one of
# those fails the suite on purpose. Negative checks guard against removed or
# unwanted text coming back. A passing run says nothing about whether a lens
# judges well, whether fewer questions reach the user, or whether escalation
# behaves as before. Those limits are accepted in
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

# --- 4. Verification (AC4) ---------------------------------------------------
VERIFY=$(between '^## 3[.] Verify the verdicts' "$LENSES" '^## ')
for outcome in confirmed rejected inconclusive; do
  assert_match "verification can mark a verdict $outcome" "$VERIFY" "\`$outcome\`"
done
assert_match "verification follows review-finding validation" "$VERIFY" "(review-finding-validation.md)"
assert_match "verification checks against requirements, not only citations" "$VERIFY" "requirements"
assert_match "verification looks for counterevidence" "$VERIFY" "counterevidence"
assert_nomatch "verification is not limited to the cited evidence" "$VERIFY" "only the cited"
assert_match "existing behavior never settles a business question" "$VERIFY" "[business]"
assert_match "a question with no surviving verdict is researched narrowly, not dropped" "$VERIFY" "§6"
assert_match "surviving recommendations get a pre-mortem" "$VERIFY" "pre-mortem"
assert_match "a replaced recommendation is re-verified" "$VERIFY" "re-verify"
assert_match "the pre-mortem applies decision-weighting's business-logic question" "$VERIFY" "(decision-weighting.md)"

# --- 5. Classification, asks and the digest (AC5) ----------------------------
CLASSIFY=$(between '^## 4[.] Classify and ask' "$LENSES" '^## ')
assert_match "classification is handed to decision-escalation" "$CLASSIFY" "(decision-escalation.md)"
assert_match "lens consensus is never a tiebreaker" "$CLASSIFY" "never a tiebreaker"
assert_match "heavy questions go through AskUserQuestion" "$CLASSIFY" "AskUserQuestion"
for opt in Keep "Exempt this work" Supersede; do
  assert_match "a needed exception offers $opt" "$CLASSIFY" "\`$opt\`"
done
assert_match "Supersede uses the existing anchor field" "$CLASSIFY" "\`Supersedes:\`"
assert_match "an unchosen conflicting alternative is rejected without asking" "$CLASSIFY" "rejected without asking"
DIGEST=$(between '^## 5[.] Decided without asking' "$LENSES" '^## ')
assert_match "the digest is headed Decided without asking" "$DIGEST" "\`Decided without asking\`"
assert_match "a vetoed digest line becomes an ask" "$DIGEST" "vetoed"
CHANGED=$(between '^## 6[.] Changed premises' "$LENSES" '^## ')
assert_match "a changed premise reopens the affected conclusions" "$CHANGED" "reopen"
assert_match "reopened questions do not spend a second lens dispatch" "$CHANGED" "second lens dispatch"

# --- 6. plan's interface checklist (AC13) ------------------------------------
CHECKLIST=$(between '^### Interface and behavior interview$' "$PLAN" '^### ')
assert_match "the checklist routes its items through the lens pass" "$CHECKLIST" "lens pass"
assert_nomatch "the checklist no longer confirms interfaces and tests unconditionally" "$CHECKLIST" "Confirm with user"
assert_nomatch "the checklist no longer asks the interface question unconditionally" "$CHECKLIST" "What should the public interface look like?"
assert_eq "plan shows the digest before its approval checkpoint" \
  "$(in_order "$PLAN" '^- [[] []] .*Decided without asking' '^- [[] []] Get user approval on the plan')" "in order"

# --- 7. prd-from-grill-me (AC8, AC9) -----------------------------------------
RT=$(read_file "$PRD")
assert_match "prd-from-grill-me links the lens-pass reference" "$RT" "(../../references/interview-lenses.md)"
assert_eq "prd-from-grill-me runs the lens pass between Step 2 and Step 3" \
  "$(in_order "$PRD" '^2[.] Explore the repo' '^2a[.] [*][*]Lens pass' '^3[.] Interview')" "in order"
assert_match "prd-from-grill-me passes full depth" "$(between '^2a[.] ' "$PRD" '^3[.] Interview')" "\`full\` depth"
assert_nomatch "prd-from-grill-me leaves lens names to the reference" "$(between '^2a[.] ' "$PRD" '^3[.] Interview')" "three lenses"
assert_match "an inline brief's decisions are pinned" "$(between '^2a[.] ' "$PRD" '^3[.] Interview')" "inline brief"
assert_match "Step 4b routes late decisions through the changed-premises rule" \
  "$(between '^4b[.] ' "$PRD" '^5[.] Write the PRD')" "changed-premises"
STEP4=$(between '^4[.] Sketch' "$PRD" '^4a[.] ')
assert_match "Step 4 routes module and test choices through the lens pass" "$STEP4" "lens-pass questions"
assert_nomatch "Step 4 no longer confirms modules unconditionally" "$STEP4" "Check with the user that modules match"
STEP4A=$(between '^4a[.] ' "$PRD" '^4b[.] ')
assert_nomatch "Step 4a no longer asks every bikeshed" "$STEP4A" "For each, ask the user their preference"
assert_match "Step 4a lists classifier-settled bikesheds in the digest" "$STEP4A" "Decided without asking"
assert_match "Step 4a turns a vetoed line into an ask" "$STEP4A" "vetoed"

# --- 8. Depth and resume (AC6) -----------------------------------------------
WHEN=$(between '^## When to run' "$LENSES" '^## ')
assert_match "no open question means no dispatch" "$WHEN" "no dispatch"
assert_match "abbreviated depth dispatches Precedent only" "$WHEN" "| \`abbreviated\` | Precedent only |"
assert_match "full depth dispatches all three lenses" "$WHEN" "| \`full\` | Design, Strategy, Precedent |"
assert_match "plan --resume is covered" "$WHEN" "plan --resume"
assert_match "parked anchors are not pinned" "$WHEN" "Status: parked"
DEPTH=$(between '^- [[] []] [*][*]Interview depth' "$PLAN" '^---$')
assert_match "plan's depth list passes abbreviated depth" "$DEPTH" "\`abbreviated\`"
assert_match "plan's depth list passes full depth" "$DEPTH" "\`full\`"
assert_nomatch "plan's depth list leaves lens names to the reference" "$DEPTH" "Precedent"

# --- 9. Unattended runs (AC7) ------------------------------------------------
UNATTENDED=$(between '^## Unattended runs' "$LENSES" '^## ')
assert_match "unattended detection uses STENSWF_UNATTENDED" "$UNATTENDED" "STENSWF_UNATTENDED"
assert_match "the PARK carries the research in the DECISION_NEEDED envelope" "$UNATTENDED" "DECISION_NEEDED"
PARKED=$(between '^### The parked block' "$LENSES" '^###? ')
for field in Decision Reversible Alternatives Recommendation; do
  assert_match "the parked block maps a verdict onto the envelope's $field" "$PARKED" "\`$field\`"
done
assert_match "the parked block keeps the verdicts as research" "$PARKED" "\`Research\`"
assert_nomatch "the reference leaves park targets to the callers" "$UNATTENDED" "prd-from-grill-me"
assert_nomatch "the reference has no unreachable blank-page park" "$UNATTENDED" "blank-page"
STEP2A=$(between '^2a[.] ' "$PRD" '^3[.] Interview')
assert_match "a PRD session parks on an intake issue" "$STEP2A" "Intake: <topic>"
assert_match "an inline brief survives the intake issue" "$STEP2A" "Inline brief:"
assert_match "a parked PRD session resumes from its intake issue" "$STEP2A" "/stenswf:prd-from-grill-me <intake>"
UL='interview-lenses.md#unattended-runs'
assert_match "prd Phase 0's classification confirmation has an unattended outcome" \
  "$(between '^2[.] Print a 5-line summary' "$PRD" '^3[.] Use ')" "$UL"
P0STEP2=$(between '^2[.] Print a 5-line summary' "$PRD" '^3[.] Use ')
assert_match "an unconfirmed class parks no later than the end of Step 2a" "$P0STEP2" "end of Step 2a"
assert_nomatch "an unconfirmed class is not carried to Step 4a" "$P0STEP2" "Step 4a"
assert_match "prd Step 4a's approval has an unattended outcome" "$(between '^4a[.] ' "$PRD" '^4b[.] ')" "$UL"
assert_match "an unattended blank-page PRD run stops before research" \
  "$(between '^1[.] Ask the user' "$PRD" '^2[.] Explore')" "BLOCKED:"
assert_match "plan's approval has an unattended outcome" \
  "$(between '^- [[] []] Get user approval on the plan' "$PLAN" '^[*][*]You')" "$UL"
assert_match "plan's decisions note covers the approval" "$(between '^[*][*]Decisions[.][*][*]' "$PLAN" '^## ')" "$UL"
assert_match "prd-from-grill-me stops at a parked question instead of reaching Step 5" \
  "$(between '^2a[.] ' "$PRD" '^3[.] Interview')" "never reaches Step 5"
assert_match "Phase 0 resumes an Inline brief: intake issue as a brief" \
  "$(between '^[*][*]Inline brief[.][*][*]' "$PRD" '^## ')" "Inline brief:"
assert_nomatch "Step 5 does not write parked questions after publishing" \
  "$(between '^5[.] Write the PRD' "$PRD" '^## ')" "Write parked questions"

# --- 10. The business-logic question (AC10) ----------------------------------
Q='Which option is cleanest from a business-logic point of view?'
RULE_HEAD=$(between '^## The rule' "$WEIGHTING" '^### Strategic over tactical')
SUB=$(between '^### Strategic over tactical' "$WEIGHTING" '^---')
assert_match "## The rule asks the business-logic question before the subsection" "$RULE_HEAD" "$Q"
assert_nomatch "the question stays outside the strategic subsection" "$SUB" "$Q"
assert_eq "the question appears once, on one line" "$(grep -cF -- "$Q" "$WEIGHTING")" "1"

# --- 11. Registration, decision record and links (AC11) ----------------------
RDT=$(read_file "$ROOT/README.md")
assert_match "README links the lens-pass contract" "$RDT" "(references/interview-lenses.md)"
assert_match "README links the decision record" "$RDT" "(../../docs/stenswf/decisions/2026-10-16-interview-lenses.md)"
assert_file "the decision record exists" "$ADR"
ADRT=$(read_file "$ADR")
for h in "## Decision" "## Consequences" "## Rejected alternatives" "## Carved invariants"; do
  assert_match "the decision record has $h" "$ADRT" "$h"
done
assert_match "the record names the topology hypothesis" "$ADRT" "hypothesis"
for f in "$LENSES" "$PLAN" "$PRD" "$WEIGHTING" "$ROOT/README.md" "$ADR"; do
  d=$(dirname "$f"); bad=""
  while IFS= read -r link; do
    [ -e "$d/$link" ] || bad="$bad $link"
  done < <(grep -oE '\]\([^)#:]+\)' "$f" 2>/dev/null | sed 's/^](//; s/)$//' | sort -u)
  assert_eq "links resolve: ${f#"$REPO"/}" "$bad" ""
done

# --- 12. Out of scope stays out (AC12) ---------------------------------------
for f in "$SKILLS/plan-light/SKILL.md" "$REFS/decision-escalation.md"; do
  assert_nomatch "${f#"$ROOT"/} stays off the lens pass" "$(read_file "$f")" "interview-lenses"
done
assert_match "prd Step 3 keeps its practice-citation rule" \
  "$(between '^3[.] Interview' "$PRD" '^4[.] Sketch')" "Cite winning practices"

# --- footer (append new sections above this line) --------------------------
printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
