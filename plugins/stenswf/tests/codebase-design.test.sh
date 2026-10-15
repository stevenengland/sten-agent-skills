#!/usr/bin/env bash
# Presence, wiring and legacy-gone tests for the deepening lens (PRD #37):
# the codebase-design craft skill, the deepening review subagent, the thermo
# hand-off, the improve-codebase-architecture workflow skill, and the pointers
# that make codebase-design the single home of deep-module theory in stenswf.
#
# Skill text is prose, so nothing breaks loudly when an edit drops a rule.
# The tests pin contract tokens — headings, bold lead-ins, links, front-matter,
# output and skip lines, script paths — not whole instructional sentences.
# Each pinned token sits on one source line, so a substring match is enough.
# Absence checks build their pattern so the literal never appears in this file.
# Whether the reviewers judge well is checked by tests/review-scenarios/,
# not here.
#
# Run: bash plugins/stenswf/tests/codebase-design.test.sh
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
assert_absent()  { [ ! -e "$2" ] && ok "$1" || { fail "$1"; printf '    unexpected path %s\n' "$2"; }; }
read_file()      { cat "$1" 2>/dev/null || true; }
# YAML frontmatter of $1 (between the first two --- lines).
frontmatter()    { awk '/^---[[:space:]]*$/ { n++; next } n == 1 { print } n >= 2 { exit }' "$1" 2>/dev/null; }
# Lines of $2 from the first line equal to $1 up to (not including) the
# first later line matching the regex $3.
section() { awk -v start="$1" -v stop="$3" '
  $0 == start { on = 1; print; next }
  on && $0 ~ stop { exit }
  on { print }' "$2" 2>/dev/null; }
lint_ok() { (cd "$REPO" && bash scripts/check-skill-descriptions.sh "$1" >/dev/null 2>&1) && echo pass || echo fail; }

# --- 1. codebase-design craft skill ----------------------------------------
CD="$SKILLS/codebase-design/SKILL.md"
CDT=$(read_file "$CD")
CDFM=$(frontmatter "$CD")
assert_file "codebase-design/SKILL.md exists" "$CD"
assert_match "codebase-design names itself" "$CDFM" "name: codebase-design"
assert_nomatch "codebase-design is model-invocable" "$CDFM" "disable-model-invocation"
assert_eq "codebase-design's description passes the one-sentence lint" "$(lint_ok plugins/stenswf/skills/codebase-design/SKILL.md)" "pass"
for entry in '**Module**:' '**Interface**:' '**Implementation**:' '**Depth**:' \
             '**Seam** _(Michael Feathers)_:' '**Adapter**:' '**Leverage**:' '**Locality**:'; do
  assert_match "the glossary defines $entry" "$CDT" "$entry"
done
assert_match "glossary terms carry avoid-lists" "$CDT" "_Avoid_:"
assert_match "deep vs shallow" "$CDT" "## Deep vs shallow"
assert_match "principle: the deletion test" "$CDT" "**The deletion test.**"
assert_match "principle: the interface is the test surface" "$CDT" "**The interface is the test surface.**"
assert_match "principle: one adapter vs two" "$CDT" "**One adapter means a hypothetical seam. Two adapters means a real one.**"
assert_match "adaptation: the rules are questions, not verdicts" "$CDT" "**These are questions, not verdicts.**"
assert_match "adaptation: the single-adapter exceptions are named" "$CDT" "keeps vendor types out of domain code, centralizes an invariant, or isolates volatile infrastructure"
assert_match "adaptation: recommendations name the invariants to keep" "$CDT" "**Name the invariants that must survive.**"
assert_match "adaptation: the four invariants" "$CDT" "transaction boundaries, error behaviour, authorization, ordering"
assert_match "designing for testability" "$CDT" "## Designing for testability"
assert_match "relationships" "$CDT" "## Relationships"
assert_match "rejected framings" "$CDT" "## Rejected framings"
assert_match "links the deepening page" "$CDT" "(deepening.md)"
assert_match "links the design-it-twice page" "$CDT" "(design-it-twice.md)"

# --- 2. codebase-design sub-pages ------------------------------------------
DP="$SKILLS/codebase-design/deepening.md"
DT="$SKILLS/codebase-design/design-it-twice.md"
DPT=$(read_file "$DP")
DTT=$(read_file "$DT")
assert_file "deepening.md exists" "$DP"
assert_file "design-it-twice.md exists" "$DT"
assert_match "deepening: in-process" "$DPT" "### 1. In-process"
assert_match "deepening: local-substitutable" "$DPT" "### 2. Local-substitutable"
assert_match "deepening: ports & adapters" "$DPT" "### 3. Remote but owned (Ports & Adapters)"
assert_match "deepening: mock" "$DPT" "### 4. True external (Mock)"
assert_match "deepening: seam discipline" "$DPT" "## Seam discipline"
assert_match "deepening: replace, don't layer" "$DPT" "## Testing strategy: replace, don't layer"
assert_match "adaptation: seam discipline names the single-adapter exceptions" "$DPT" "or a single adapter keeps vendor types out of domain code"
assert_match "adaptation: old tests go only once the new ones cover them" "$DPT" "cover the behaviours they checked; delete them only then."
assert_nomatch "adaptation: no unconditional test deletion" "$DPT" "interface exist; delete them."
assert_match "design-it-twice: frame the problem space" "$DTT" "### 1. Frame the problem space"
assert_match "design-it-twice: 3+ parallel sub-agents" "$DTT" "Spawn 3+ sub-agents in parallel."
assert_match "design-it-twice: compare on seam placement" "$DTT" "**seam placement**"
assert_match "design-it-twice: opinionated recommendation" "$DTT" "Be opinionated"
assert_match "design-it-twice honors an existing domain glossary" "$DTT" "(GLOSSARY.md, CONTEXT.md or UBIQUITOUS_LANGUAGE.md) when one exists"
assert_nomatch "sub-pages link lowercase file names" "$DPT$DTT$CDT" "DEEPENING.md"
assert_nomatch "sub-pages link lowercase file names (design-it-twice)" "$DPT$DTT$CDT" "DESIGN-IT-TWICE.md"

# --- 3. Deepening review subagent (AC4, AC5, AC6) --------------------------
DS="$REFS/deepening-subagent.md"
DST=$(read_file "$DS")
assert_file "references/deepening-subagent.md exists" "$DS"
# AC4: dispatch contract and output format
assert_match "it loads codebase-design" "$DST" "SKILLS TO LOAD: codebase-design, brevity"
assert_match "it takes the issue number and mode" "$DST" "Read-only deepening review for issue #<N> (<MODE> mode)."
assert_match "it is read-only" "$DST" "You MUST NOT edit any"
assert_match "it takes the diff path" "$DST" "Review the diff at <DIFF_PATH>"
assert_match "it reads touched modules and their callers" "$DST" "read the module and its callers"
assert_match "it inspects even when no interface changed" "$DST" "whether or not its interface changed"
assert_match "it honors ponytail markers" "$DST" "Do NOT flag a \`// ponytail:\`-marked simplification"
assert_match "it returns four-line blocks" "$DST" "  severity: high | medium | low"
assert_match "it never emits critical" "$DST" "There is NO critical severity."
assert_match "it ends with the summary line" "$DST" "DEEPENING_SUMMARY: <H> high | <M> medium | <L> low"
assert_match "follow-up lines are capped at three" "$DST" "Then at most three follow-up lines"
assert_match "follow-up line format" "$DST" "follow-up: <module> — <friction> — /stenswf:improve-codebase-architecture <module>"
assert_match "it never grills" "$DST" "grilling a candidate belongs to \`/stenswf:improve-codebase-architecture\`"
assert_match "it owns module structure" "$DST" "The lens owns **module structure**"
assert_match "each review dispatches it at most once" "$DST" "Each review dispatches it at most once"
# AC5: severity, confidence and diff attribution
assert_match "diff attribution: introduced or worsened only" "$DST" "Diff attribution: raise a finding only for a problem the diff introduced or materially worsened."
assert_match "older friction is never a finding" "$DST" "is never a finding; list it as a follow-up line instead."
assert_match "severity follows consequence" "$DST" "Severity follows demonstrated consequence"
assert_match "high: duplicated business rule" "$DST" "duplicated business rule"
assert_match "high: invariant leaking across an interface" "$DST" "an invariant leaking across an interface"
assert_match "high: change propagating through callers" "$DST" "a change that must propagate through callers"
assert_match "high: materially obscured contract" "$DST" "a materially obscured contract"
assert_match "medium: contained cost" "$DST" "- medium — a real but contained cost"
assert_match "low: minor cost" "$DST" "- low    — a minor cost."
assert_match "confidence only gates publishing" "$DST" "Confidence decides only whether to publish"
assert_match "findings need file:line evidence" "$DST" "every finding needs file:line evidence"
assert_match "no speculative redesigns" "$DST" "Never emit a speculative redesign"
assert_match "recommendations name invariants" "$DST" "names the invariants it must keep"
assert_nomatch "upstream strength is not mapped to severity" "$DST" "Worth exploring ->"
# AC6: decision context
assert_match "every active decision entry, any category" "$DST" "every active entry in .stenswf/<N>/decisions.md, of any category"
assert_match "inherited entries resolve through Source" "$DST" "Source #<P>/D<n> means entry D<n> in .stenswf/<P>/decisions.md"
assert_match "archived slice decisions in PRD mode" "$DST" "in prd mode, archived slice decisions in .stenswf/.archive/<slice>/decisions.md"
assert_match "ADR locations" "$DST" "ADRs in docs/adr/ or any docs/**/decisions/ directory"
assert_match "glossary files" "$DST" "GLOSSARY.md, CONTEXT.md or UBIQUITOUS_LANGUAGE.md"
# Caller-side merge rules
assert_match "callers dedup across Architect, thermo and deepening" "$DST" "**Dedup across Architect, thermo and deepening.**"
assert_match "follow-up lines stay outside the counts" "$DST" "**Follow-up lines are not findings.**"

# --- footer (append new sections above this line) --------------------------
printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
