#!/usr/bin/env bash
# Behavior and wiring tests for the visual-pr skill.
#
#   1. pr-body.sh owns the `<!-- stenswf:visual-pr:start/end -->` region. A
#      refresh that touches anything outside it can drop the closing line,
#      the validation evidence, or the `## Decisions` block — silently.
#      Exact preservation is checked on files with cmp: `$(...)` would strip
#      trailing newlines and hide exactly the bytes that matter.
#   2. workflow-issue.sh keeps standalone visual-pr from creating PRs on
#      branches that ship, ship-light or apply own.
#   3. Wiring: shippers, templates and planning skills must actually
#      reference the skills; a correct skill wired nowhere does nothing.
#
# Run: bash plugins/stenswf/tests/visual-pr.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$ROOT/../.." && pwd)
PRBODY="$ROOT/skills/visual-pr/scripts/pr-body.sh"
PUBLISH="$ROOT/scripts/publish-decisions.sh"

PASS=0
FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()      { [ "$2" = "$3" ] && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
assert_match()   { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || { fail "$1"; printf '    missing %q in: %s\n' "$3" "$2"; }; }
assert_nomatch() { printf '%s' "$2" | grep -qF -- "$3" && { fail "$1"; printf '    unexpected %q in: %s\n' "$3" "$2"; } || ok "$1"; }
same()           { cmp -s "$1" "$2" && echo same || echo changed; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

START='<!-- stenswf:visual-pr:start -->'
END='<!-- stenswf:visual-pr:end -->'
outside()         { sed "/^$START\$/,/^$END\$/d" "$1"; }
region_position() { awk -v s="$START" '$0==s{a=NR} /^## Tests added/{b=NR} END{print (a && b && a<b) ? "above" : "not above"}' "$1"; }
after_end()       { n=$(grep -nxF "$END" "$1" | cut -d: -f1); tail -n +$((n + 2)) "$1"; }

# --- Fake gh ---------------------------------------------------------------
# The PR body round-trips through a file, so a second run reads back the
# first's write. Like the real CLI, `pr view --json body` returns JSON and
# `-q .body` appends a newline — a fake that just cat'ed the file would hide
# exactly the transport drift that breaks idempotence. Every `pr edit` logs
# the --body-file it was given, so "wrote nothing" and "published the saved
# file" are both observable.
BODY="$WORK/pr-body"
EDITS="$WORK/pr-edits"
cat > "$WORK/gh" <<GHEOF
#!/usr/bin/env bash
BODY="$BODY"; EDITS="$EDITS"
flagval() { local want="\$1" prev=""; shift; for a in "\$@"; do [ "\$prev" = "\$want" ] && { printf '%s' "\$a"; return; }; prev="\$a"; done; }
case "\$1 \$2" in
  "pr view")   # like the real CLI: JSON for --json, and -q/--jq appends a newline
    if printf '%s\n' "\$@" | grep -qxE -- '-q|--jq'; then cat "\$BODY"; echo
    else jq -Rs '{body: .}' < "\$BODY"; fi ;;
  "pr edit")
    f=\$(flagval --body-file "\$@")
    [ -n "\$f" ] || { echo "fake gh: pr edit without --body-file" >&2; exit 3; }
    echo "\$f" >> "\$EDITS"
    cp "\$f" "\$BODY" ;;
  *) echo "fake gh: unhandled: \$*" >&2; exit 3 ;;
esac
GHEOF
chmod +x "$WORK/gh"
export PATH="$WORK:$PATH"

# --- Fixtures --------------------------------------------------------------
seed_body() {
  cat > "$BODY" <<'EOF'
[#28](https://github.com/o/r/issues/28)

Closes #901

<!-- stenswf:visual-pr:start -->
## Why the change

The old reason.
<!-- stenswf:visual-pr:end -->

## Tests added (red → green)
- `test_old_behaviour`
EOF
  rm -f "$EDITS"
}
REGION="$WORK/region.md"
printf '## Why the change\n\nThe new reason.\n\n## Change outline\n\n~~~text\nsubmitForm\n  createSession\n~~~\n\n' > "$REGION"
EVID="$WORK/pr-evidence.md"
printf '## Validation\n- `bash tests/run.sh` — 41 passed\n- lint clean\n\n## Tests added (red → green)\n- `test_new_flow`\n' > "$EVID"
printf '[#28](https://github.com/o/r/issues/28)\n\n' > "$WORK/header.md"

# --- 1. pr-body.sh -------------------------------------------------------------
# 1a. compose
bash "$PRBODY" compose --out "$WORK/new/pr-description.md" --region "$REGION" \
  --header "$WORK/header.md" --closing "Closes #901" --evidence "$EVID"; RC=$?
NEW="$WORK/new/pr-description.md"
assert_eq "compose exits 0" "$RC" "0"
tail -c "$(( $(wc -c < "$EVID") ))" "$NEW" > "$WORK/new-tail"
assert_eq "compose ends with the evidence, byte for byte" "$(same "$WORK/new-tail" "$EVID")" "same"
assert_eq "compose starts with the header" "$(head -1 "$NEW")" "[#28](https://github.com/o/r/issues/28)"
assert_eq "compose writes the closing line once" "$(grep -cxF 'Closes #901' "$NEW")" "1"
assert_eq "compose writes one region" "$(grep -cxF "$START" "$NEW")/$(grep -cxF "$END" "$NEW")" "1/1"
assert_eq "the closing line sits above the region" \
  "$(awk -v s="$START" '/^Closes #901$/{a=NR} $0==s{b=NR} END{print (a && b && a<b) ? "above" : "not above"}' "$NEW")" "above"
bash "$PRBODY" compose --out "$WORK/bare.md" --region "$REGION"
assert_eq "compose without optional parts starts with the region" "$(head -1 "$WORK/bare.md")" "$START"
assert_eq "compose without evidence ends with the region" "$(tail -1 "$WORK/bare.md")" "$END"
printf '## Validation\n- ok' > "$WORK/ev-nonl.md"
bash "$PRBODY" compose --out "$WORK/nonl.md" --region "$REGION" --evidence "$WORK/ev-nonl.md"
{ cat "$WORK/ev-nonl.md"; echo; } > "$WORK/ev-nonl.expected"
tail -c "$(( $(wc -c < "$WORK/ev-nonl.expected") ))" "$WORK/nonl.md" > "$WORK/nonl.tail"
assert_eq "evidence without a final newline is followed by exactly one" "$(same "$WORK/nonl.tail" "$WORK/ev-nonl.expected")" "same"

# 1b. pr: in-place refresh, saved and published
seed_body
cp "$BODY" "$WORK/before.md"
DESC="$WORK/saved/pr-description.md"
( cd "$WORK" && bash "$PRBODY" pr 77 "$REGION" "$DESC" ) >/dev/null; RC=$?
assert_eq "pr mode exits 0" "$RC" "0"
assert_match "pr mode publishes the new region" "$(cat "$BODY")" "The new reason."
assert_nomatch "pr mode drops the old region" "$(cat "$BODY")" "The old reason."
outside "$WORK/before.md" > "$WORK/out-before"; outside "$BODY" > "$WORK/out-after"
assert_eq "pr mode keeps every byte outside the markers" "$(same "$WORK/out-before" "$WORK/out-after")" "same"
assert_eq "pr mode saves the complete body at the description path" "$(same "$DESC" "$BODY")" "same"
assert_eq "pr mode publishes the saved file itself" "$(cat "$EDITS")" "$DESC"
assert_eq "pr mode leaves one region" "$(grep -cxF "$START" "$BODY")/$(grep -cxF "$END" "$BODY")" "1/1"
assert_eq "pr mode replaces the region where it was" "$(region_position "$BODY")" "above"

# 1b'. transport: the fetched bytes are exactly the stored bytes
printf 'Closes #901\n\n%s\nold\n%s\n\n## Tests added (red → green)\n- `t`' "$START" "$END" > "$BODY"   # no final newline
tail -c 12 "$BODY" > "$WORK/tail.before"
( cd "$WORK" && bash "$PRBODY" pr 77 "$REGION" "$DESC" ) >/dev/null
tail -c 12 "$BODY" > "$WORK/tail.after"
assert_eq "a refresh keeps the body's final bytes (no added newline)" "$(same "$WORK/tail.before" "$WORK/tail.after")" "same"
cp "$BODY" "$WORK/transport-first"
( cd "$WORK" && bash "$PRBODY" pr 77 "$REGION" "$DESC" ) >/dev/null
assert_eq "repeated refreshes do not grow the body" "$(same "$BODY" "$WORK/transport-first")" "same"

# 1c. malformed markers: nothing is written anywhere
printf 'Closes #7\n\n%s\n## Why the change\nhalf a region\n' "$START" > "$WORK/half.md"
OUT=$(bash "$PRBODY" file "$WORK/half.md" "$REGION" 2>"$WORK/err"); RC=$?
assert_eq "a lone start marker exits 1" "$RC" "1"
assert_eq "a lone start marker prints no body" "$OUT" ""
assert_match "a lone start marker says why" "$(cat "$WORK/err")" "malformed"
printf '%s\nbackwards\n%s\n' "$END" "$START" > "$WORK/backwards.md"
bash "$PRBODY" file "$WORK/backwards.md" "$REGION" >/dev/null 2>&1; RC=$?
assert_eq "markers out of order exit 1" "$RC" "1"
cp "$WORK/half.md" "$BODY"; rm -f "$EDITS"
BAD_DESC="$WORK/bad/pr-description.md"
( cd "$WORK" && bash "$PRBODY" pr 77 "$REGION" "$BAD_DESC" ) >/dev/null 2>&1; RC=$?
assert_eq "pr mode on a malformed body exits 1" "$RC" "1"
assert_eq "pr mode on a malformed body never calls gh pr edit" "$([ -e "$EDITS" ] && echo edited || echo untouched)" "untouched"
assert_eq "pr mode on a malformed body writes no description" "$([ -e "$BAD_DESC" ] && echo written || echo none)" "none"

# 1d. idempotence
seed_body
( cd "$WORK" && bash "$PRBODY" pr 77 "$REGION" "$DESC" ) >/dev/null
cp "$BODY" "$WORK/after-first"
( cd "$WORK" && bash "$PRBODY" pr 77 "$REGION" "$DESC" ) >/dev/null
assert_eq "a second run with the same region changes no byte" "$(same "$BODY" "$WORK/after-first")" "same"

# 1e. legacy upstream-template bodies: migrate owned content only, else prepend
migrated() { [ "$(grep -cx '## Special things to note' "$1")" = 0 ] && echo migrated || echo kept; }   # REGION has no Special heading
LEG="$WORK/legacy.md"
cat > "$LEG" <<'EOF'
[#28](https://github.com/o/r/issues/28)

Closes #902

## Why the change

The old upstream reason.

## Special things to note

- None.

## Change outline

Shape before:

~~~markdown
## Not a heading — inside a fence
~~~

## Tests added (red → green)
- `test_kept`

<!-- stenswf:decisions:start -->
## Decisions
- kept
<!-- stenswf:decisions:end -->
EOF
bash "$PRBODY" file "$LEG" "$REGION" > "$WORK/legacy.out"; RC=$?
LOUT="$WORK/legacy.out"
assert_eq "migration exits 0" "$RC" "0"
assert_eq "an upstream-template body is migrated" "$(migrated "$LOUT")" "migrated"
assert_eq "migration leaves one region" "$(grep -cxF "$START" "$LOUT")/$(grep -cxF "$END" "$LOUT")" "1/1"
assert_nomatch "migration drops the old explanation" "$(cat "$LOUT")" "The old upstream reason."
assert_nomatch "migration drops the old outline, fenced lines included" "$(cat "$LOUT")" "Not a heading"
assert_eq "migration keeps the header and closing line" "$(head -3 "$LOUT")" "$(head -3 "$LEG")"
sed -n '/^## Tests added/,$p' "$LEG" > "$WORK/leg-tail.before"
sed -n '/^## Tests added/,$p' "$LOUT" > "$WORK/leg-tail.after"
assert_eq "migration keeps evidence and decisions byte for byte" "$(same "$WORK/leg-tail.before" "$WORK/leg-tail.after")" "same"
bash "$PRBODY" file "$LOUT" "$REGION" > "$WORK/legacy.again"
assert_eq "a migrated body refreshes idempotently" "$(same "$LOUT" "$WORK/legacy.again")" "same"

T3='## Why the change\n\nOld.\n\n## Special things to note\n\n- None.\n\n## Change outline\n\n'
printf "$T3"'Old shape.\n\nCloses #29\n' > "$WORK/leg-closes.md"
bash "$PRBODY" file "$WORK/leg-closes.md" "$REGION" > "$WORK/leg-closes.out"
assert_eq "a trailing closing line ends the span (still migrated)" "$(migrated "$WORK/leg-closes.out")" "migrated"
assert_eq "a trailing closing line survives migration" "$(grep -cx 'Closes #29' "$WORK/leg-closes.out")" "1"

printf "$T3"'Old shape.\n\n<!-- stenswf:decisions:start -->\n## Decisions\n- kept\n<!-- stenswf:decisions:end -->\n' > "$WORK/leg2.md"
bash "$PRBODY" file "$WORK/leg2.md" "$REGION" > "$WORK/leg2.out"
sed -n '/^<!-- stenswf:decisions:start -->$/,$p' "$WORK/leg2.md" > "$WORK/leg2.before"
sed -n '/^<!-- stenswf:decisions:start -->$/,$p' "$WORK/leg2.out" > "$WORK/leg2.after"
assert_eq "an HTML comment ends the span" "$(same "$WORK/leg2.before" "$WORK/leg2.after")" "same"
assert_nomatch "the span before the comment was replaced" "$(cat "$WORK/leg2.out")" "Old shape."

printf "$T3"'````markdown\n```\n## inner, still fenced\n````\n\n## Validation\n- `kept`\n' > "$WORK/leg-fence4.md"
bash "$PRBODY" file "$WORK/leg-fence4.md" "$REGION" > "$WORK/leg-fence4.out"
sed -n '/^## Validation$/,$p' "$WORK/leg-fence4.md" > "$WORK/leg-fence4.before"
sed -n '/^## Validation$/,$p' "$WORK/leg-fence4.out" > "$WORK/leg-fence4.after"
assert_eq "a shorter fence run inside a longer fence does not close it" "$(migrated "$WORK/leg-fence4.out")" "migrated"
assert_eq "the section after a four-backtick fence survives" "$(same "$WORK/leg-fence4.before" "$WORK/leg-fence4.after")" "same"

for CASE in unclosed prose-keyword incomplete unrelated; do
  case $CASE in
    unclosed)      printf "$T3"'```text\nnever closed\n\n## Validation\n- kept\n' ;;
    prose-keyword) printf '## Why the change\n\nThis fixes #12 for good.\n\n## Special things to note\n\n- None.\n\n## Change outline\n\nShape.\n' ;;
    incomplete)    printf 'Closes #7\n\n## Why the change\n\nHand-written.\n\n## Notes\n- keep\n' ;;
    unrelated)     printf '## Why the change\n\nA.\n\n## Notes\n\nB.\n\n## Special things to note\n\n- C.\n\n## Change outline\n\nD.\n' ;;
  esac > "$WORK/amb-$CASE.md"
  bash "$PRBODY" file "$WORK/amb-$CASE.md" "$REGION" > "$WORK/amb-$CASE.out"
  assert_eq "ambiguous ($CASE): the region is prepended" "$(head -1 "$WORK/amb-$CASE.out")" "$START"
  after_end "$WORK/amb-$CASE.out" > "$WORK/amb-$CASE.rest"
  assert_eq "ambiguous ($CASE): the original bytes follow unchanged" "$(same "$WORK/amb-$CASE.rest" "$WORK/amb-$CASE.md")" "same"
done

# 1f. coexistence with the decisions block, both orders
mkdir -p "$WORK/.stenswf/901"
cat > "$WORK/.stenswf/901/decisions.md" <<'EOF'
# Decisions — #901

### D1 — Retry with exponential backoff

- **Category:** decision
- **Source:** ship-light
- **Rationale:** Fixed retries hammer the API during an outage.
- **Refs:** src/worker.py
EOF

check_combined() {   # check_combined <label>
  assert_eq "$1: one visual-pr marker pair" "$(grep -cxF "$START" "$BODY")/$(grep -cxF "$END" "$BODY")" "1/1"
  assert_eq "$1: one decisions marker pair" \
    "$(grep -cxF '<!-- stenswf:decisions:start -->' "$BODY")/$(grep -cxF '<!-- stenswf:decisions:end -->' "$BODY")" "1/1"
  assert_eq "$1: the decisions block is last" "$(grep -v '^[[:space:]]*$' "$BODY" | tail -1)" "<!-- stenswf:decisions:end -->"
  assert_eq "$1: the region stays above the evidence" "$(region_position "$BODY")" "above"
  assert_match "$1: the new region is in" "$(cat "$BODY")" "The new reason."
}
seed_body
( cd "$WORK" && bash "$PUBLISH" pr 901 77 && bash "$PRBODY" pr 77 "$REGION" "$DESC" ) >/dev/null
check_combined "decisions then region"
seed_body
( cd "$WORK" && bash "$PRBODY" pr 77 "$REGION" "$DESC" && bash "$PUBLISH" pr 901 77 ) >/dev/null
check_combined "region then decisions"

# --- 2. Standalone guard: workflow-issue.sh ---------------------------------
GUARD="$ROOT/skills/visual-pr/scripts/workflow-issue.sh"
GREPO="$WORK/guard-repo"
git init -q -b master "$GREPO"
gitc()  { git -C "$GREPO" -c user.name=t -c user.email=t@example.com "$@"; }
guard() { ( cd "$GREPO" && bash "$GUARD" ); }
art()   { mkdir -p "$GREPO/.stenswf/$1" && printf '%s\n' "$3" > "$GREPO/.stenswf/$1/$2"; }   # art <N> <file> <json>
gitc commit -q --allow-empty -m "chore: base"

art 42 manifest.json '{"kind":"slice","branch":"feature/custom"}'
gitc checkout -q -b feature/custom master
assert_eq "a branch recorded in a heavy manifest belongs to ship" "$(guard)" "ship 42"

art 43 plan-light.json '{"issue":43}'
gitc checkout -q -b impl/43-lite-thing master
assert_eq "a Lite impl branch with plan-light.json belongs to ship-light" "$(guard)" "ship-light 43"

gitc checkout -q -b impl/44-direct master
assert_eq "a direct ship-light run (no artifacts yet) belongs to ship-light" "$(guard)" "ship-light 44"

art 45 manifest.json '{"kind":"slice","branch":null}'
gitc checkout -q -b impl/45-heavy master
assert_eq "an impl branch with a heavy manifest belongs to ship" "$(guard)" "ship 45"

gitc checkout -q -b prd/50-cleanup master
assert_eq "a PRD cleanup branch belongs to apply" "$(guard)" "apply 50"

art 46 anchor.json '{"issue":46}'
gitc checkout -q -b feature/notes master
gitc commit -q --allow-empty -m "feat(stenswf): add thing" -m "Refs: #46 T10"
assert_eq "a Refs trailer on an unrelated branch is not ownership" "$(guard)" ""

art 28 manifest.json '{"kind":"prd"}'
gitc checkout -q -b feature/prd-followup master
gitc commit -q --allow-empty -m "docs: follow-up for #28"
assert_eq "a mention of a PRD is not ownership (no route to apply)" "$(guard)" ""

gitc checkout -q -b impl/notanumber master
assert_eq "a non-numeric impl branch is not a workflow branch" "$(guard)" ""

# --- 3. Skill files: tokens, descriptions, fidelity, contract -------------------
SHOWME="$ROOT/skills/show-me/SKILL.md"
VPR="$ROOT/skills/visual-pr/SKILL.md"
VPR_REFS="$ROOT/skills/visual-pr/references"
vpr() { cat "$VPR" 2>/dev/null; }

( cd "$REPO_ROOT" && bash scripts/check-skill-descriptions.sh "$SHOWME" "$VPR" ) >/dev/null 2>&1; RC=$?
assert_eq "both skills pass the one-line description check" "$RC" "0"
assert_eq "show-me keeps the upstream description" "$(grep '^description:' "$SHOWME")" \
  "description: Help the user understand the current topic visually with concise diagrams, code-shape sketches, and focused HTML artifacts."
assert_eq "visual-pr carries the stenswf description" "$(grep '^description:' "$VPR" 2>/dev/null)" \
  "description: Create or update a pull request description that explains why the change exists and shows its shape with show-me-style visual outlines."

for F in "$SHOWME" "$VPR" "$VPR_REFS/pr_description_template.md" "$VPR_REFS/show-me.md" "$VPR_REFS/describe_pr_final_answer.md"; do
  assert_eq "${F#"$ROOT/"} exists" "$([ -s "$F" ] && echo yes || echo no)" "yes"
  for TOKEN in 'disable-model-invocation' '{SKILLBASE}' '.humanlayer/' 'task-artifact' '${CLAUDE_PLUGIN_ROOT}'; do
    assert_nomatch "${F#"$ROOT/"} has no $TOKEN" "$(cat "$F" 2>/dev/null)" "$TOKEN"
  done
done
for F in "$SHOWME" "$VPR"; do
  assert_eq "${F#"$ROOT/"} has no \$-digit token (Claude Code expands it, #30)" \
    "$(grep -cE '\$[0-9]|\$\{[0-9]' "$F" 2>/dev/null)" "0"
done

# Upstream sentences that must survive the port verbatim.
assert_match "show-me keeps upstream's opening" "$(cat "$SHOWME")" "Pick the smallest view that makes the key point clear."
assert_match "show-me keeps upstream's restraint rule" "$(cat "$SHOWME")" "it is unlikely you will use all of them"
assert_match "visual-pr keeps the one-sentence rule" "$(vpr)" "Keep **Why the change** to exactly one sentence."
assert_match "visual-pr keeps the voice rule" "$(vpr)" "Write as one human talking to another"
assert_match "the template keeps upstream's story guidance" "$(cat "$VPR_REFS/pr_description_template.md" 2>/dev/null)" \
  "Tell the story in the order that makes it easiest to understand."

# The stenswf adaptations and contracts.
TEMPLATE=$(cat "$VPR_REFS/pr_description_template.md" 2>/dev/null)
assert_match "the template opens the visual-pr region" "$TEMPLATE" "$START"
assert_match "the template closes the visual-pr region" "$TEMPLATE" "$END"
assert_match "the template keeps the closing line" "$TEMPLATE" "Closes #{N}"
assert_match "the template appends evidence byte for byte" "$TEMPLATE" "byte for byte"
assert_match "standalone guards workflow branches" "$(vpr)" "bash scripts/workflow-issue.sh"
assert_match "standalone ensures local state first" "$(vpr)" "bash ../../scripts/ensure-stenswf-dir.sh"
assert_match "standalone refreshes through pr-body.sh pr" "$(vpr)" "bash scripts/pr-body.sh pr {number} {region-path} {description-path}"
assert_match "a PR outline describes the delivered change" "$(vpr)" "Describe the change actually delivered."
assert_match "a tiny change may get a prose outline" "$(vpr)" "one or two plain sentences are enough"
assert_match "body-only compares against the PR target" "$(vpr)" "the same comparison GitHub shows"
BODY_ONLY=$(sed -n '/^## Body-only mode/,$p' "$VPR" 2>/dev/null)
for INPUT in '**issue context**' '**base ref**' '**evidence**' '**closing line**' '**output**'; do
  assert_match "body-only mode names the input $INPUT" "$BODY_ONLY" "$INPUT"
done
assert_match "body-only mode composes through pr-body.sh" "$BODY_ONLY" "bash scripts/pr-body.sh compose"
assert_match "body-only mode forbids gh calls" "$BODY_ONLY" "make no \`gh\` calls"
assert_nomatch "body-only mode runs no gh pr command" "$BODY_ONLY" "gh pr "
assert_nomatch "body-only mode runs no gh issue command" "$BODY_ONLY" "gh issue "
assert_match "show-me opens HTML through the shared opener" "$(cat "$SHOWME")" "bash ../../scripts/open-html.sh"
assert_match "show-me ensures local state first" "$(cat "$SHOWME")" "bash ../../scripts/ensure-stenswf-dir.sh"
assert_match "visual-pr's show-me copy keeps HTML a local aside" "$(cat "$VPR_REFS/show-me.md" 2>/dev/null)" "bash ../../scripts/open-html.sh"

# --- 4. Wiring: ship-light and slice-e2e ----------------------------------------
SL=$(cat "$ROOT/skills/ship-light/SKILL.md")
assert_match "ship-light loads visual-pr in body-only mode" "$SL" 'Load `visual-pr` in body-only mode'
assert_match "ship-light passes the issue context" "$SL" '- issue context: `/tmp/slice-$ARGUMENTS.md`'
assert_match "ship-light passes the base ref" "$SL" '- base ref: `origin/$DEFAULT`'
assert_match "ship-light passes its evidence file" "$SL" '- evidence: `.stenswf/$ARGUMENTS/pr-evidence.md`'
assert_match "ship-light passes the closing line" "$SL" '- closing line: `Closes #$ARGUMENTS`'
assert_match "ship-light passes the output path" "$SL" '- output: `.stenswf/$ARGUMENTS/pr-description.md`'
assert_match "ship-light points PR_BODY_FILE at the visual-pr output" "$SL" 'PR_BODY_FILE=".stenswf/$ARGUMENTS/pr-description.md"'
assert_match "ship-light still appends the decisions render" "$SL" 'publish-decisions.sh render "$ARGUMENTS" >> "$PR_BODY_FILE"'
PB=$(cat "$ROOT/skills/ship-light/pr-body.md")
assert_match "pr-body.md has the validation summary" "$PB" '## Validation'
assert_match "pr-body.md keeps the TDD evidence heading" "$PB" '## Tests added (red → green)'
assert_match "pr-body.md keeps Notable assumptions" "$PB" '## Notable assumptions'
assert_match "pr-body.md keeps the assumptions-vs-decisions paragraph" "$PB" 'is a transient review surface'
assert_match "pr-body.md names the evidence file" "$PB" '.stenswf/$ARGUMENTS/pr-evidence.md'
assert_nomatch "pr-body.md drops the superseded Summary template" "$PB" '## Summary'
E2E=$(grep 'SKILLS TO LOAD: ship-light' "$ROOT/skills/slice-e2e/SKILL.md")
assert_match "slice-e2e loads visual-pr for ship-light" "$E2E" "visual-pr"
assert_match "slice-e2e keeps tdd for ship-light" "$E2E" "tdd"

# --- 5. Wiring: ship and apply PRD-mode -------------------------------------------
SH=$(cat "$ROOT/skills/ship/post-dispatch.md")
assert_match "ship loads visual-pr in body-only mode" "$SH" 'Load `visual-pr` in body-only mode'
assert_match "ship passes the concept snapshot as issue context" "$SH" '- issue context: `.stenswf/$ARGUMENTS/concept.md`'
assert_match "ship compares against the PR target" "$SH" '- base ref: `origin/$DEFAULT` — the PR'"'"'s target'
assert_match "ship passes the closing line" "$SH" '- closing line: `Closes #$ARGUMENTS`'
assert_match "ship hands over lint escapes as evidence" "$SH" '## Lint escapes'
assert_match "ship hands over review-step absences as evidence" "$SH" '## Review-step absences'
assert_match "ship points PR_BODY_FILE at the visual-pr output" "$SH" 'PR_BODY_FILE=".stenswf/$ARGUMENTS/pr-description.md"'
assert_match "ship still appends the decisions render" "$SH" 'publish-decisions.sh render "$ARGUMENTS" >> "$PR_BODY_FILE"'
AP=$(cat "$ROOT/skills/apply/prd.md")
assert_match "apply PRD-mode loads visual-pr in body-only mode" "$AP" 'Load `visual-pr` in body-only mode'
assert_match "apply PRD-mode passes the PRD snapshot as issue context" "$AP" '- issue context: `.stenswf/$ARGUMENTS/concept.md`'
assert_match "apply PRD-mode keeps the capstone closing line" "$AP" '- closing line: `Closes #$ARGUMENTS (capstone cleanup).`'
assert_match "apply PRD-mode hands over addressed findings" "$AP" '## Findings addressed'
assert_match "apply PRD-mode hands over skipped findings" "$AP" '## Findings skipped'
assert_match "apply PRD-mode names the decisions excerpt" "$AP" 'docs/stenswf/decisions/prd-$ARGUMENTS.md'
assert_match "apply PRD-mode keeps its PR title" "$AP" '**PR title:** `fix(PRD): #$ARGUMENTS cleanup — capstone findings`.'
assert_match "apply PRD-mode points PR_BODY_FILE at the visual-pr output" "$AP" 'PR_BODY_FILE=".stenswf/$ARGUMENTS/pr-description.md"'
assert_match "apply PRD-mode appends the decisions render" "$AP" 'publish-decisions.sh render "$ARGUMENTS" >> "$PR_BODY_FILE"'

# --- 6. Slice template: optional Change outline + extractors -----------------------
source "$ROOT/scripts/extractors.sh"
export ARGUMENTS=0
FIX="$HERE/fixtures/issue-slice-change-outline.md"
sed '/^## Change outline$/,/^## Conventions (from PRD)$/{/^## Conventions (from PRD)$/!d}' "$FIX" > "$WORK/no-outline.md"
assert_eq "the fixture has a Change outline" "$(grep -c '^## Change outline$' "$FIX")" "1"
assert_eq "the stripped copy lacks it" "$(grep -c '^## Change outline$' "$WORK/no-outline.md")" "0"
extract_section 'What to build' "$FIX" > "$WORK/wtb.with"; extract_section 'What to build' "$WORK/no-outline.md" > "$WORK/wtb.without"
assert_eq "What to build is unchanged by a Change outline after it" "$(same "$WORK/wtb.with" "$WORK/wtb.without")" "same"
extract_acs "$FIX" > "$WORK/acs.with"; extract_acs "$WORK/no-outline.md" > "$WORK/acs.without"
assert_eq "AC records are unchanged by a Change outline" "$(same "$WORK/acs.with" "$WORK/acs.without")" "same"
assert_eq "both ACs still parse" "$(wc -l < "$WORK/acs.with" | tr -d ' ')" "2"
assert_match "the outline itself is extractable" "$(extract_section 'Change outline' "$FIX")" "healthz.ts"
IT="$ROOT/references/issue-template.md"
assert_eq "the slice template puts the outline right after What to build" \
  "$(grep -E '^## (What to build|Change outline|Conventions \(from PRD\))$' "$IT" | tr '\n' '|')" \
  "## What to build|## Change outline|## Conventions (from PRD)|"
assert_match "the slice template makes the outline optional" "$(cat "$IT")" "Optional — include it when it clarifies the slice's shape."
assert_match "the slice template says outlines add no obligations" "$(cat "$IT")" "it adds no obligations"
P2I=$(cat "$ROOT/skills/prd-to-issues/SKILL.md")
assert_match "prd-to-issues adds an outline when it clarifies" "$P2I" "When it clarifies a slice's shape, give the slice body a \`## Change outline\`"
assert_match "prd-to-issues trims it from the PRD outline" "$P2I" "extract_section 'Change outline'"

printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
