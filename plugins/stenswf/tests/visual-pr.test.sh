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

printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
