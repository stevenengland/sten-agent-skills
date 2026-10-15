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

# --- 3. Deepening review subagent ------------------------------------------
DS="$REFS/deepening-subagent.md"
DST=$(read_file "$DS")
assert_file "references/deepening-subagent.md exists" "$DS"
# Dispatch contract and output format
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
# Severity, confidence and diff attribution
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
# Decision context
assert_match "every active decision entry, any category" "$DST" "every active entry in <N>'s anchor, of any category"
assert_match "inherited entries resolve through Source" "$DST" "Source #<P>/D<n> means entry D<n> in <P>'s anchor"
assert_match "an anchor is live or the newest dated archive" "$DST" "else the newest .stenswf/.archive/<I>-*/decisions.md (shipping archives it dated)"
assert_match "slice decisions in PRD mode use the same lookup" "$DST" "in prd mode, each slice's anchor"
assert_nomatch "no undated archive path" "$DST" ".stenswf/.archive/<slice>/decisions.md"
assert_match "ADR locations" "$DST" "ADRs in docs/adr/ or any docs/**/decisions/ directory"
assert_match "glossary files" "$DST" "GLOSSARY.md, CONTEXT.md or UBIQUITOUS_LANGUAGE.md"
# Caller-side merge rules
assert_match "callers dedup across Architect, thermo and deepening" "$DST" "**Dedup across Architect, thermo and deepening.**"
assert_match "follow-up lines stay outside the counts" "$DST" "**Follow-up lines are not findings.**"

# --- 4. Review wiring: slice and PRD modes ---------------------------------
SL="$SKILLS/review/slice.md"
PR="$SKILLS/review/prd.md"
SLT=$(read_file "$SL")
PRT=$(read_file "$PR")
DEEP=$(section '### Deepening subagent pass (codebase-design lens)' "$SL" '^### ')
THS=$(section '### Thermo subagent pass (aggressive maintainability)' "$SL" '^### ')
assert_match "slice review has a deepening pass" "$DEEP" "### Deepening subagent pass (codebase-design lens)"
assert_match "the slice pass runs on DEEPEN_HIT" "$DEEP" "*Only if \`DEEPEN_HIT\` is set.*"
assert_match "the slice pass dispatches the shared contract" "$DEEP" "[../../references/deepening-subagent.md](../../references/deepening-subagent.md)"
assert_match "the slice pass passes the staged diff" "$DEEP" "\`DIFF_PATH=/tmp/review-\$ARGUMENTS-staged.patch\`"
assert_match "the slice pass runs in slice mode" "$DEEP" "\`<MODE>=slice\`"
assert_match "the slice deepening pass runs once" "$DEEP" "Dispatch it at most once per review."
assert_match "the slice thermo pass runs once" "$THS" "Dispatch it at most once per review."
assert_match "the slice pass dedups across all three sources" "$DEEP" "dedup across Architect, thermo and deepening findings (higher severity wins)"
assert_match "the slice pass folds survivors into the Summary counts" "$DEEP" "fold them into the \`Summary:\` counts"
assert_match "the slice pass writes the verbatim skip line" "$DEEP" "\`Deepening: skipped (no production code in diff).\`"
assert_match "the slice pass routes follow-ups outside the counts" "$DEEP" "\`## Follow-ups (not counted)\`"
assert_match "the slice output has the follow-ups section" "$SLT" "## Follow-ups (not counted)"
line_in() { grep -nF -- "$2" "$1" | head -1 | cut -d: -f1; }
TH=$(line_in "$SL" "### Thermo subagent pass"); DP4=$(line_in "$SL" "### Deepening subagent pass (codebase-design lens)")
assert_eq "the deepening pass follows the thermo pass" "$([ -n "$TH" ] && [ -n "$DP4" ] && [ "$TH" -lt "$DP4" ] && echo yes || echo no)" "yes"
assert_match "Perspective 4 leaves depth to the subagent" "$SLT" "come from the deepening subagent pass below."
assert_match "deepening findings are never Critical" "$SLT" "Thermo and deepening findings are maintainability only (no Critical)"
assert_match "the Summary schema is unchanged" "$SLT" "Close with: \`Summary: N high | M medium | K low\`."
assert_match "the Priority schema is unchanged" "$SLT" "\`**Priority:** <level>\` (schema check below depends on this)."
AX3=$(section '### Axis 3 — Architectural coherence' "$PR" '^### ')
assert_match "PRD Axis 3 has a deepening pass" "$AX3" "**Deepening subagent pass.**"
assert_match "PRD Axis 3 runs it on every review" "$AX3" "On every PRD review (no gate)"
assert_match "PRD Axis 3 dispatches the shared contract" "$AX3" "[../../references/deepening-subagent.md](../../references/deepening-subagent.md)"
assert_match "PRD Axis 3 passes the PRD diff in prd mode" "$AX3" "(the delta patch on idempotent re-review), \`<N>=\$ARGUMENTS\` and \`<MODE>=prd\`"
assert_match "PRD Axis 3 deepening and thermo run once" "$AX3" "Dispatch each pass at most once per review."
assert_match "PRD Axis 3 never emits critical" "$AX3" "Deepening contributes no \`critical\`."
assert_match "PRD Step 5 emits deepening survivors as findings" "$PRT" "Deduped thermo and deepening survivors (from the Axis-3 passes)"
assert_match "PRD Step 5 emits follow-ups as uncounted elements" "$PRT" "<follow-up module=\"<module>\">"
assert_match "the PRD finding schema is unchanged" "$PRT" "<finding id=\"F<n>\" severity=\"high|medium|low\">"

# --- 5. review-loop runs thermo and deepening once -------------------------
RL="$SKILLS/review-loop/SKILL.md"
RLT=$(read_file "$RL")
P1=$(section '## Phase 1 — Open deliberations first, then the delta pass' "$RL" '^## ')
assert_match "review-loop: thermo and deepening run on the first pass only" "$P1" "**Thermo and deepening run on the first pass only.**"
assert_match "review-loop: the first pass is the one starting at the PR base" "$P1" "the one whose delta starts at the PR base"
assert_match "review-loop: later passes write the verbatim skip line" "$P1" "\`Thermo and deepening: skipped (run on the first pass only).\`"
assert_match "review-loop still scopes passes to the delta" "$RLT" "Then review only \`<last-reviewed-sha>..\$HEAD_SHA\` (delta scope; the first"

# --- 6. Thermo hands module structure to deepening -------------------------
TS="$SKILLS/thermo-nuclear-code-quality-review/SKILL.md"
TST=$(read_file "$TS")
TC="$REFS/thermo-subagent.md"
TCT=$(read_file "$TC")
assert_match "thermo: module structure is out of scope" "$TST" "**Module structure is out of scope.**"
assert_match "thermo: points module structure at codebase-design" "$TST" "belong to the \`codebase-design\` skill"
assert_match "thermo: points standalone users at the architecture skill" "$TST" "\`/stenswf:improve-codebase-architecture\` on its own"
ABQ="abstraction"" quality"
assert_nomatch "thermo: the description no longer claims abstraction quality" "$(frontmatter "$TS")" "$ABQ"
assert_nomatch "thermo: no pass-through-helper rule" "$TST" "identity wrappers, or pass-through helpers"
assert_nomatch "thermo: no canonical-layer rule" "$TST" "Keep logic in the canonical layer"
assert_nomatch "thermo: no earning-its-keep question" "$TST" "Is this abstraction actually earning its keep"
assert_nomatch "thermo: no API-leak rule" "$TST" "implementation details leaking through APIs"
assert_nomatch "thermo: no thin-wrapper flag" "$TST" "Thin wrappers or identity abstractions"
assert_nomatch "thermo: no wrong-layer flag" "$TST" "Logic added in the wrong layer"
assert_nomatch "thermo: no ownership-boundary remedy" "$TST" "Change the ownership boundary"
assert_match "thermo keeps its code-level rules" "$TST" "**Do not allow random spaghetti growth in existing code.**"
assert_eq "thermo's description passes the one-sentence lint" "$(lint_ok plugins/stenswf/skills/thermo-nuclear-code-quality-review/SKILL.md)" "pass"
assert_match "thermo contract: module structure belongs to deepening" "$TCT" "belongs to the deepening subagent ([deepening-subagent.md](deepening-subagent.md)), never to thermo."
assert_match "thermo contract: the dispatch leaves module structure alone" "$TCT" "to the deepening pass; do not flag it."
assert_match "thermo contract: dispatched at most once" "$TCT" "Each review dispatches it at most once"
assert_nomatch "thermo contract: no boundary-leak blocker" "$TCT" "boundary / canonical-layer leak"
assert_nomatch "thermo contract: no wrong-layer blocker" "$TCT" "wrong-layer or duplicate-helper logic"

# --- 7. improve-codebase-architecture workflow skill -----------------------
IC="$SKILLS/improve-codebase-architecture/SKILL.md"
ICT=$(read_file "$IC")
ICFM=$(frontmatter "$IC")
assert_file "improve-codebase-architecture/SKILL.md exists" "$IC"
assert_match "it names itself" "$ICFM" "name: improve-codebase-architecture"
assert_match "it is user-invoked only" "$ICFM" "disable-model-invocation: true"
assert_eq "its description passes the one-sentence lint" "$(lint_ok plugins/stenswf/skills/improve-codebase-architecture/SKILL.md)" "pass"
assert_match "it opens with the brevity header" "$ICT" "**Load and apply \`brevity\` now.** See [../../references/brevity-load.md](../../references/brevity-load.md)."
assert_match "it logs feedback under its own name" "$ICT" "with \`STENSWF_SKILL=improve-codebase-architecture\`."
assert_match "it has a Feedback section" "$ICT" "## Feedback"
assert_match "it loads codebase-design" "$ICT" "Load \`codebase-design\` ([../codebase-design/SKILL.md](../codebase-design/SKILL.md))"
assert_match "scope: a named direction wins" "$ICT" "If the user named a direction"
assert_match "scope: otherwise git-log hot spots" "$ICT" "(\`git log --oneline\`) to find the codebase's hot spots"
assert_match "scope: widen when scattered" "$ICT" "widen the net."
assert_match "it reads an existing glossary" "$ICT" "When the repo has a domain glossary (GLOSSARY.md, CONTEXT.md or UBIQUITOUS_LANGUAGE.md)"
assert_match "it reads existing ADRs in either location" "$ICT" "ADRs (in \`docs/adr/\` or a \`docs/**/decisions/\` directory), when present"
assert_match "an Explore subagent walks the scope" "$ICT" "dispatch an \`Explore\` subagent to walk the codebase, with \`codebase-design\` in its SKILLS TO LOAD."
assert_match "principles are questions, not verdicts" "$ICT" "as questions, not verdicts"
assert_match "a solution names the invariants it keeps" "$ICT" "naming the invariants it must keep"
assert_match "it applies the deletion test" "$ICT" "Apply the **deletion test**"
assert_match "report: show-me's state directory" "$ICT" "DIR=\$(bash ../../scripts/ensure-stenswf-dir.sh .show-me)"
assert_match "report: UTC timestamp" "$ICT" "TS=\$(date -u +%Y%m%dT%H%M%SZ)"
assert_match "report: file name" "$ICT" "REPORT=\"\$DIR/architecture-review-\$TS.html\""
assert_match "report: opened with open-html.sh" "$ICT" "bash ../../scripts/open-html.sh \"\$REPORT\""
assert_match "report: the path reaches the user" "$ICT" "pass that path on to the user"
assert_match "report: links its design guide" "$ICT" "[html-report.md](html-report.md)"
assert_match "no interfaces before the pick" "$ICT" "Do NOT propose interfaces yet."
assert_match "it asks which candidate to explore" "$ICT" "\"Which of these would you like to explore?\""
assert_match "a pick loads grill-me" "$ICT" "load \`grill-me\`"
assert_match "design-it-twice on request" "$ICT" "[../codebase-design/design-it-twice.md](../codebase-design/design-it-twice.md)"
assert_match "glossary: update only an existing one" "$ICT" "only when the repo already has one"
assert_match "ADR: existing location, else offer docs/adr/" "$ICT" "offer to create \`docs/adr/\` using the ADR fields from the \`architecture\` skill"
assert_match "ADR: never created unasked" "$ICT" "Never create either unasked."
assert_match "ADR conflicts are surfaced only when warranted" "$ICT" "**ADR conflicts**"
assert_match "ADR conflicts are marked on the card" "$ICT" "Mark it clearly in the card"
assert_match "handoff section" "$ICT" "### 4. Hand off to a PRD"
assert_match "handoff to prd-from-grill-me as class: refactor" "$ICT" "argument text that starts with \`class: refactor\`"
assert_nomatch "no platform-specific Skill-tool phrasing" "$ICT" "the Skill tool"
assert_nomatch "no domain-modeling dependency" "$ICT" "domain-modeling"
assert_nomatch "no OS temp dir" "$ICT" "TMPDIR"
assert_nomatch "no hand-rolled opener" "$ICT" "xdg-open"

# --- 8. HTML report design guide -------------------------------------------
HR="$SKILLS/improve-codebase-architecture/html-report.md"
HRT=$(read_file "$HR")
assert_file "html-report.md exists" "$HR"
assert_match "the report lives in the local state directory" "$HRT" "in the local state directory (\`.stenswf/.show-me/\`, see step 2 of [SKILL.md](SKILL.md))"
assert_match "card: files" "$HRT" "- **Files**: monospaced list"
assert_match "card: problem" "$HRT" "- **Problem**: one sentence. What hurts."
assert_match "card: solution" "$HRT" "- **Solution**: one sentence. What changes."
assert_match "card: wins" "$HRT" "- **Wins**: bullets"
assert_match "card: before/after diagram" "$HRT" "- **Before / After diagram**: the centrepiece."
assert_match "card: strength badge" "$HRT" "- **Badge row**: recommendation strength (\`Strong\` = emerald, \`Worth exploring\` = amber, \`Speculative\` = slate)"
assert_match "card: ADR callout" "$HRT" "- **ADR callout** (if applicable)"
assert_match "diagram patterns" "$HRT" "## Diagram patterns"
assert_match "top-recommendation section" "$HRT" "## Top recommendation section"
assert_match "tone: mandatory vocabulary" "$HRT" "**Use exactly:** module, interface, implementation, depth, deep, shallow, seam, adapter, leverage, locality."
assert_match "tone: forbidden substitutes" "$HRT" "**Never substitute:**"
assert_nomatch "no OS temp directory" "$HRT" "OS temp directory"
CDN=$(printf '%s\n' "$HRT" | grep -oE 'https://cdn[^"]+' || true)
assert_eq "the report loads exactly two CDN scripts" "$(printf '%s\n' "$CDN" | grep -c .)" "2"
UNPINNED=$(printf '%s\n' "$CDN" | grep -vE '[@/][0-9]+\.[0-9]+\.[0-9]+(/|$)' || true)
assert_eq "every CDN script URL pins an exact version" "$UNPINNED" ""

# --- 9. prd-from-grill-me intake and Step 4, architecture ------------------
PGT=$(read_file "$SKILLS/prd-from-grill-me/SKILL.md")
ART=$(read_file "$SKILLS/architecture/SKILL.md")
assert_match "inline brief: the rule exists" "$PGT" "**Inline brief.**"
assert_match "inline brief: it is the Step-1 description" "$PGT" "that text is the Step-1 description: skip Step 1's question."
assert_match "inline brief: a class line is proposed and confirmed" "$PGT" "A leading \`class: <value>\` line proposes the PRD class"
assert_match "inline brief: the interview asks only what is open" "$PGT" "Step 3 asks only what it leaves open"
assert_match "inline brief: Step 1 is skipped" "$PGT" "or an inline brief was given.**"
assert_match "inline brief: Step 3 covers only the gaps" "$PGT" "With an inline brief, cover only what it leaves open."
assert_match "issue-number intake is unchanged" "$PGT" "If \`\$ARGUMENTS\` is a GitHub issue number"
assert_match "prd-from-grill-me Step 4 consults codebase-design alongside architecture" "$PGT" "Consult the \`codebase-design\` skill (deletion test, seam and adapter rules) alongside the \`architecture\` skill."
assert_match "prd-from-grill-me Step 4 still sketches with views" "$PGT" "Sketch modules to build/modify — with \`show-me\` views where they clarify"
assert_match "architecture keeps the Module Deepening pattern" "$ART" "**Module Deepening (Pocock Approach):**"
assert_match "architecture keeps the pattern in its table" "$ART" "| Good core logic, poor structure | Module Deepening (Pocock approach) |"
assert_match "architecture links codebase-design for the theory" "$ART" "live in [\`codebase-design\`](../codebase-design/SKILL.md)"
assert_match "architecture points interface design at design-it-twice" "$ART" "[design-it-twice](../codebase-design/design-it-twice.md)"
assert_match "architecture points scans at the workflow skill" "$ART" "run \`/stenswf:improve-codebase-architecture\`."
assert_nomatch "architecture no longer restates the deepening process" "$ART" "Module deepening process:"
DAI="design-an""-interface"   # split so this file never names the dropped skill
assert_nomatch "architecture no longer links a skill stenswf does not ship" "$ART" "$DAI"

# --- 10. Design-time pointers: tdd, plan, plan-light -----------------------
PLT=$(read_file "$SKILLS/plan/SKILL.md")
PLLT=$(read_file "$SKILLS/plan-light/SKILL.md")
TDT=$(read_file "$SKILLS/tdd/SKILL.md")
assert_match "plan links codebase-design for deep modules" "$PLT" "[deep modules](../codebase-design/SKILL.md)"
assert_match "plan applies the deletion test and the adapter-count question" "$PLT" "Apply the deletion test and the adapter-count question from \`codebase-design\`"
assert_match "plan-light links codebase-design and applies its questions" "$PLLT" "[../codebase-design/SKILL.md](../codebase-design/SKILL.md) and apply its deletion test and adapter-count question"
assert_match "tdd links codebase-design" "$TDT" "[codebase-design](../codebase-design/SKILL.md):"
assert_match "tdd still applies interface-design" "$TDT" "Apply [interface-design.md](interface-design.md) and"
assert_match "tdd stays in the plan dispatch prefix" "$(read_file "$REFS/plan-artifact-schemas.md")" "SKILLS TO LOAD: tdd, clean-code, lint-escape"
assert_match "tdd stays in the ship-light dispatch" "$(read_file "$SKILLS/slice-e2e/SKILL.md")" "SKILLS TO LOAD: ship-light, visual-pr, tdd, clean-code, lint-escape, brevity"
OLD_PAGE="$SKILLS/tdd/deep-modules"
assert_absent "the old tdd deep-modules page is gone" "$OLD_PAGE.md"
DM_PAT='deep-modules[.]md'
assert_eq "nothing in stenswf links the old tdd deep-modules page" "$(grep -rlE "$DM_PAT" "$ROOT" --include='*.md' --include='*.sh' || true)" ""

# --- 11. One improve-codebase-architecture ---------------------------------
ICA='improve-codebase-architecture'
assert_absent "the stenswr port is gone" "$REPO/plugins/stenswr/skills/$ICA"
assert_file "the stenswf skill remains" "$SKILLS/$ICA/SKILL.md"
LEFT=$(cd "$REPO" && git grep -n "$ICA" -- ':!plugins/stenswf' ':!docs/stenswf' ':!sources.yaml' | grep -v "/stenswf:$ICA" || true)
assert_eq "outside stenswf, only /stenswf: pointers name the skill" "$LEFT" ""
assert_match "functional-bug-hunting pairs with the stenswf skill" "$(read_file "$REPO/plugins/stenswr/skills/functional-bug-hunting/SKILL.md")" "Pairs with \`/stenswf:$ICA\`"
assert_match "security-bug-hunting pairs with the stenswf skill" "$(read_file "$REPO/plugins/stenswr/skills/security-bug-hunting/SKILL.md")" "Pairs with \`/stenswf:$ICA\`"
for f in plugins/stenswr/plugin.json plugins/stenswr/.claude-plugin/plugin.json .claude-plugin/marketplace.json .github/plugin/marketplace.json; do
  assert_match "$f lists the remaining discover skills" "$(read_file "$REPO/$f")" "discover (functional-bug-hunting, security-bug-hunting)"
done

# --- 12. Upstream tracking in sources.yaml ---------------------------------
SRC="$REPO/sources.yaml"
# The sources.yaml entry whose first line is "- skill: $1".
entry() { awk -v k="- skill: $1" '
  $0 == k { on = 1; print; next }
  on && /^- skill: / { exit }
  on { print }' "$SRC" 2>/dev/null; }
for s in codebase-design improve-codebase-architecture; do
  E=$(entry "plugins/stenswf/skills/$s")
  assert_match "sources.yaml tracks $s" "$E" "- skill: plugins/stenswf/skills/$s"
  assert_match "$s is tracked against mattpocock/skills" "$E" "upstream: https://github.com/mattpocock/skills/tree/main/skills/engineering/$s"
  assert_match "$s is pinned to the reviewed upstream ref" "$E" 'ref: "d80fa0f4ebe0c5714af0adf8670336065233ecc6"'
  assert_eq "$s records when it was reviewed" "$(printf '%s\n' "$E" | grep -cE '^  last_reviewed: "[0-9]{4}-[0-9]{2}-[0-9]{2}"$')" "1"
  assert_match "$s lists its adaptations" "$E" "Adaptations:"
done
assert_match "codebase-design maps upstream file names" "$(entry plugins/stenswf/skills/codebase-design)" "DEEPENING.md -> deepening.md, DESIGN-IT-TWICE.md -> design-it-twice.md"
assert_match "improve-codebase-architecture maps upstream file names" "$(entry plugins/stenswf/skills/improve-codebase-architecture)" "HTML-REPORT.md -> html-report.md"
assert_match "codebase-design lists its rule adaptations" "$(entry plugins/stenswf/skills/codebase-design)" "Rule adaptations:"
assert_match "improve-codebase-architecture lists the questions-not-verdicts adaptation" "$(entry plugins/stenswf/skills/improve-codebase-architecture)" "principles applied as questions, not verdicts"
assert_nomatch "sources.yaml no longer tracks the stenswr port" "$(read_file "$SRC")" "skill: plugins/stenswr/skills/improve-codebase-architecture"

# --- 13. Review scenarios --------------------------------------------------
RS="$HERE/review-scenarios"
RST=$(read_file "$RS/README.md")
assert_file "review scenarios have a README" "$RS/README.md"
assert_match "the README says when to run them" "$RST" "## When to run"
assert_match "the README says how to run them" "$RST" "## How to run"
assert_match "the README keeps expected verdicts from the reviewer" "$RST" "Never show \`expected.md\` to the reviewer"
assert_match "the README says where results go" "$RST" "under \`## Review scenarios\`"
# yes when the scenario's diff.patch applies cleanly to its before/ tree.
scenario_applies() {
  local w; w=$(mktemp -d)
  cp -R "$1/before/." "$w/" 2>/dev/null
  (cd "$w" && git init -q && git apply --check "$1/diff.patch" 2>/dev/null) && echo yes || echo no
  rm -rf "$w"
}
for s in redundant-pass-through single-implementation-domain-port coupling-behind-unchanged-interface \
         pre-existing-shallow-module decision-settled-abstraction; do
  assert_file "$s has expected verdicts" "$RS/$s/expected.md"
  assert_file "$s has a diff" "$RS/$s/diff.patch"
  assert_eq "$s's diff applies to its before tree" "$(scenario_applies "$RS/$s")" "yes"
done
assert_file "decision-settled-abstraction's parent anchor is archived, dated" \
  "$RS/decision-settled-abstraction/before/dot-stenswf/.archive/890-2026-09-30/decisions.md"
assert_file "discovery-to-prd-handoff has a brief" "$RS/discovery-to-prd-handoff/brief.md"
assert_file "discovery-to-prd-handoff has expected verdicts" "$RS/discovery-to-prd-handoff/expected.md"
assert_match "the handoff brief starts with its class line" "$(head -1 "$RS/discovery-to-prd-handoff/brief.md" 2>/dev/null)" "class: refactor"

# --- 14. Registration and rationale ----------------------------------------
RD="$ROOT/README.md"
RDT=$(read_file "$RD")
assert_match "the routing table lists the workflow skill" "$RDT" "| \`/stenswf:improve-codebase-architecture\` | Opus |"
assert_match "the craft table lists codebase-design" "$RDT" "| \`/stenswf:codebase-design\` |"
assert_match "the repository tree lists codebase-design" "$RDT" "│       │   ├── codebase-design/"
assert_match "the repository tree lists improve-codebase-architecture" "$RDT" "│       │   ├── improve-codebase-architecture/"
LENS=$(section '## Deepening lens' "$RD" '^## ')
assert_match "the README has a Deepening lens section" "$LENS" "## Deepening lens"
assert_match "the lens section explains the trigger" "$LENS" "- **Trigger.**"
assert_match "the lens section explains the thermo split" "$LENS" "- **Ownership.**"
assert_match "the lens section links the scenarios" "$LENS" "[tests/review-scenarios/](tests/review-scenarios/README.md)"
assert_match "the lens section links the contract" "$LENS" "Contract: [references/deepening-subagent.md](references/deepening-subagent.md)."
assert_match "the lens section links the rationale" "$LENS" "[docs/stenswf/decisions/2026-10-14-deepening-lens.md](../../docs/stenswf/decisions/2026-10-14-deepening-lens.md)"
L_TDD=$(grep -n '^## TDD-as-lens$' "$RD" | cut -d: -f1)
L_DEEP=$(grep -n '^## Deepening lens$' "$RD" | cut -d: -f1)
L_PONY=$(grep -n '^## Subtractive pass (ponytail-lens)$' "$RD" | cut -d: -f1)
assert_eq "the Deepening lens sits between TDD-as-lens and the ponytail lens" \
  "$([ -n "$L_TDD" ] && [ -n "$L_DEEP" ] && [ -n "$L_PONY" ] && [ "$L_TDD" -lt "$L_DEEP" ] && [ "$L_DEEP" -lt "$L_PONY" ] && echo yes || echo no)" "yes"
DR="$REPO/docs/stenswf/decisions/2026-10-14-deepening-lens.md"
DRT=$(read_file "$DR")
assert_file "the decision record exists" "$DR"
assert_match "the record names the decision" "$DRT" "# Decision: Deepening lens (2026-10-14)"
assert_match "the record explains the trigger" "$DRT" "- **Trigger.**"
assert_match "the record explains the lens" "$DRT" "- **Lens.**"
assert_match "the record explains consequence-based findings" "$DRT" "- **Finding.**"
assert_match "the record explains the thermo split" "$DRT" "- **Ownership.**"
assert_match "the record says why the lens is not part of thermo" "$DRT" "- **Fold the deepening pass into the thermo subagent.**"
assert_match "the record keeps the convergence invariant" "$DRT" "\`review-loop\` never converges while a deliberation is open."

# --- 15. Every test is registered ------------------------------------------
TRD=$(read_file "$HERE/README.md")
for t in "$HERE"/*.test.sh; do
  n=$(basename "$t")
  assert_match "tests/README describes $n" "$TRD" "[\`$n\`]($n)"
  assert_match "tests/README runs $n" "$TRD" "bash plugins/stenswf/tests/$n"
done
assert_match "tests/README points at the review scenarios" "$TRD" "[\`review-scenarios/\`](review-scenarios/README.md)"

# --- footer (append new sections above this line) --------------------------
printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
