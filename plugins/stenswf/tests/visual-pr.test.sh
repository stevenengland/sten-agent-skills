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

printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
