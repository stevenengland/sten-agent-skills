#!/usr/bin/env bash
# Structural smoke check for the deepening lens (PRD #37): the files exist,
# their front-matter and links are valid, the review callers are wired to the
# shared contracts, the output tokens other code parses are present, and the
# replaced artifacts are gone.
#
# It deliberately does not pin instructional prose: rewording a rule must not
# fail this suite, and a passing run says nothing about whether the rule is
# right. Behavior is covered elsewhere — the trigger and the review patch by
# deepening-trigger.test.sh (executed), the reviewers' judgments by
# tests/review-scenarios/ (run by hand).
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
lint_ok() { (cd "$REPO" && bash scripts/check-skill-descriptions.sh "$1" >/dev/null 2>&1) && echo pass || echo fail; }

CD="$SKILLS/codebase-design"
ICA="$SKILLS/improve-codebase-architecture"
TS="$SKILLS/thermo-nuclear-code-quality-review/SKILL.md"
DS="$REFS/deepening-subagent.md"
TC="$REFS/thermo-subagent.md"
SL="$SKILLS/review/slice.md"
PR="$SKILLS/review/prd.md"
RL="$SKILLS/review-loop/SKILL.md"
RS="$HERE/review-scenarios"
ADR="$REPO/docs/stenswf/decisions/2026-10-14-deepening-lens.md"

# --- 1. Files and front-matter ---------------------------------------------
for f in "$CD/SKILL.md" "$CD/deepening.md" "$CD/design-it-twice.md" "$ICA/SKILL.md" "$ICA/html-report.md" \
         "$DS" "$TC" "$ADR" "$RS/README.md"; do
  assert_file "${f#"$REPO"/} exists" "$f"
done
assert_match "codebase-design names itself" "$(frontmatter "$CD/SKILL.md")" "name: codebase-design"
assert_nomatch "codebase-design is model-invocable" "$(frontmatter "$CD/SKILL.md")" "disable-model-invocation"
assert_match "improve-codebase-architecture names itself" "$(frontmatter "$ICA/SKILL.md")" "name: improve-codebase-architecture"
assert_match "improve-codebase-architecture is user-invoked only" "$(frontmatter "$ICA/SKILL.md")" "disable-model-invocation: true"
for s in codebase-design improve-codebase-architecture thermo-nuclear-code-quality-review; do
  assert_eq "$s's description passes the one-sentence lint" "$(lint_ok "plugins/stenswf/skills/$s/SKILL.md")" "pass"
done

# --- 2. Relative links resolve ---------------------------------------------
for f in "$CD"/*.md "$ICA"/*.md "$DS" "$TC" "$SL" "$PR" "$RL" "$TS" \
         "$SKILLS"/{architecture,plan,plan-light,tdd,prd-from-grill-me}/SKILL.md \
         "$ROOT/README.md" "$HERE/README.md" "$RS/README.md" "$ADR"; do
  d=$(dirname "$f"); bad=""
  while IFS= read -r link; do
    [ -e "$d/$link" ] || bad="$bad $link"
  done < <(grep -oE '\]\([^)#:]+\)' "$f" | sed 's/^](//; s/)$//' | sort -u)
  assert_eq "links resolve: ${f#"$REPO"/}" "$bad" ""
done

# --- 3. Wiring: callers use the shared contracts ----------------------------
SLT=$(read_file "$SL"); PRT=$(read_file "$PR"); RLT=$(read_file "$RL")
assert_match "slice review dispatches the deepening contract" "$SLT" "(../../references/deepening-subagent.md)"
assert_match "slice review gates deepening on DEEPEN_HIT" "$SLT" "\`DEEPEN_HIT\`"
assert_match "slice review dispatches it in slice mode" "$SLT" "\`<MODE>=slice\`"
assert_match "slice review dispatches the thermo contract" "$SLT" "(../../references/thermo-subagent.md)"
assert_match "PRD review dispatches the deepening contract" "$PRT" "(../../references/deepening-subagent.md)"
assert_match "PRD review dispatches it in prd mode" "$PRT" "\`<MODE>=prd\`"
assert_match "review-loop names its commit range for the engine" "$RLT" "DIFF_RANGE=<last-reviewed-sha>..\$HEAD_SHA"
assert_match "review-loop runs the specialists on its first pass only" "$RLT" "**Thermo and deepening run on the first pass only.**"
assert_match "each review dispatches deepening at most once" "$(read_file "$DS")" "Each review dispatches it at most once."
assert_match "each review dispatches thermo at most once" "$(read_file "$TC")" "Each review dispatches it at most once."
assert_match "thermo hands module structure away" "$(read_file "$TS")" "**Module structure is out of scope.**"
assert_match "the workflow skill hands off as class: refactor" "$(read_file "$ICA/SKILL.md")" "class: refactor"
assert_match "prd-from-grill-me takes an inline brief" "$(read_file "$SKILLS/prd-from-grill-me/SKILL.md")" "**Inline brief.**"
for s in architecture plan plan-light tdd; do
  assert_match "$s links codebase-design" "$(read_file "$SKILLS/$s/SKILL.md")" "../codebase-design/SKILL.md"
done
assert_match "prd-from-grill-me consults codebase-design" "$(read_file "$SKILLS/prd-from-grill-me/SKILL.md")" "\`codebase-design\`"
assert_match "tdd stays in the plan dispatch prefix" "$(read_file "$REFS/plan-artifact-schemas.md")" "SKILLS TO LOAD: tdd, clean-code, lint-escape"

# --- 4. Output tokens other code parses ------------------------------------
DST=$(read_file "$DS"); TCT=$(read_file "$TC")
assert_match "deepening loads codebase-design" "$DST" "SKILLS TO LOAD: codebase-design, brevity"
assert_match "thermo loads its skill" "$TCT" "SKILLS TO LOAD: thermo-nuclear-code-quality-review, brevity"
for t in "$DST" "$TCT"; do
  assert_match "a finding block starts with its severity" "$t" "  severity: high | medium | low"
done
assert_match "deepening ends with its summary line" "$DST" "DEEPENING_SUMMARY: <H> high | <M> medium | <L> low"
assert_match "thermo ends with its summary line" "$TCT" "THERMO_SUMMARY: <H> high | <M> medium | <L> low"
assert_match "the follow-up line format" "$DST" "follow-up: <module> — <friction> — /stenswf:improve-codebase-architecture <module>"
assert_match "slice: the deepening skip line" "$SLT" "\`Deepening: skipped (no production code in diff).\`"
assert_match "slice: the uncounted follow-ups section" "$SLT" "## Follow-ups (not counted)"
assert_match "slice: the Summary schema" "$SLT" "Close with: \`Summary: N high | M medium | K low\`."
assert_match "slice: the Priority schema" "$SLT" "\`**Priority:** <level>\`"
assert_match "PRD: the finding schema" "$PRT" "<finding id=\"F<n>\" severity=\"high|medium|low\">"
assert_match "PRD: the follow-up element" "$PRT" "<follow-up module=\"<module>\">"
assert_match "review-loop: the specialists' skip line" "$RLT" "\`Thermo and deepening: skipped (run on the first pass only).\`"
# codebase-design's glossary is the vocabulary the deepening dispatch requires.
CDT=$(read_file "$CD/SKILL.md")
for entry in '**Module**:' '**Interface**:' '**Implementation**:' '**Depth**:' \
             '**Seam** _(Michael Feathers)_:' '**Adapter**:' '**Leverage**:' '**Locality**:'; do
  assert_match "the glossary defines $entry" "$CDT" "$entry"
done

# --- 5. The report's scripts are version-pinned ----------------------------
CDN=$(grep -oE 'https://cdn[^"]+' "$ICA/html-report.md" || true)
assert_eq "the report loads CDN scripts" "$([ -n "$CDN" ] && echo yes || echo no)" "yes"
UNPINNED=$(printf '%s\n' "$CDN" | grep -vE '[@/][0-9]+\.[0-9]+\.[0-9]+(/|$)' || true)
assert_eq "every CDN script URL pins an exact version" "$UNPINNED" ""

# --- 6. Replaced artifacts are gone ----------------------------------------
ICN='improve-codebase-architecture'
assert_absent "the stenswr port is gone" "$REPO/plugins/stenswr/skills/$ICN"
LEFT=$(cd "$REPO" && git grep -n "$ICN" -- ':!plugins/stenswf' ':!docs/stenswf' ':!sources.yaml' | grep -v "/stenswf:$ICN" || true)
assert_eq "outside stenswf, only /stenswf: pointers name the skill" "$LEFT" ""
assert_absent "the old tdd deep-modules page is gone" "$SKILLS/tdd/deep-modules"".md"
DM_PAT='deep-modules[.]md'
assert_eq "nothing in stenswf links the old tdd deep-modules page" "$(grep -rlE "$DM_PAT" "$ROOT" --include='*.md' --include='*.sh' || true)" ""
DAI="design-an""-interface"   # split so this file never names the dropped skill
assert_nomatch "architecture names no skill stenswf does not ship" "$(read_file "$SKILLS/architecture/SKILL.md")" "$DAI"

# --- 7. Upstream tracking in sources.yaml ----------------------------------
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
  assert_eq "$s is pinned to a full upstream commit" "$(printf '%s\n' "$E" | grep -cE '^  ref: "[0-9a-f]{40}"$')" "1"
  assert_eq "$s records when it was reviewed" "$(printf '%s\n' "$E" | grep -cE '^  last_reviewed: "[0-9]{4}-[0-9]{2}-[0-9]{2}"$')" "1"
done

# --- 8. Review scenarios are complete --------------------------------------
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
  assert_eq "$s's diff applies to its before tree" "$(scenario_applies "$RS/$s")" "yes"
done
assert_file "decision-settled-abstraction's parent anchor is archived, dated" \
  "$RS/decision-settled-abstraction/before/dot-stenswf/.archive/890-2026-09-30/decisions.md"
assert_file "discovery-to-prd-handoff has expected verdicts" "$RS/discovery-to-prd-handoff/expected.md"
assert_match "the handoff brief starts with its class line" "$(head -1 "$RS/discovery-to-prd-handoff/brief.md" 2>/dev/null)" "class: refactor"

# --- 9. Registration --------------------------------------------------------
RDT=$(read_file "$ROOT/README.md")
assert_match "the routing table lists the workflow skill" "$RDT" "\`/stenswf:improve-codebase-architecture\`"
assert_match "the craft table lists codebase-design" "$RDT" "\`/stenswf:codebase-design\`"
TRD=$(read_file "$HERE/README.md")
for t in "$HERE"/*.test.sh; do
  n=$(basename "$t")
  assert_match "tests/README describes $n" "$TRD" "[\`$n\`]($n)"
  assert_match "tests/README runs $n" "$TRD" "bash plugins/stenswf/tests/$n"
done

# --- footer (append new sections above this line) --------------------------
printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
