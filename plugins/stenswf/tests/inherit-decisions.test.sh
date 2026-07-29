#!/usr/bin/env bash
# Behavior tests for inherited PRD decision stubs.
#
# Run: bash plugins/stenswf/tests/inherit-decisions.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../scripts/inherit-decisions.sh"

PASS=0
FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()      { [ "$2" = "$3" ] && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
assert_match()   { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || { fail "$1"; printf '    missing %q in: %s\n' "$3" "$2"; }; }
assert_nomatch() { printf '%s' "$2" | grep -qF -- "$3" && { fail "$1"; printf '    unexpected %q in: %s\n' "$3" "$2"; } || ok "$1"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/.stenswf/999"

cat > "$WORK/.stenswf/999/decisions.md" <<'EOF'
# Decisions — #999

### D1 — Active before superseded

- **Category:** arch
- **Refs:** src/a.py

### ~~D2~~ — Superseded

- **Category:** arch
- **Refs:** src/b.py

### D3 — Active before active

- **Category:** decision
- **Refs:** src/c.py

### D4 — Active at EOF

- **Category:** arch
- **Refs:** src/d.py
EOF

(
  cd "$WORK" || exit
  bash "$SCRIPT" 999 1000 1001
)

for SLICE in 1000 1001; do
  ANCHOR=$(cat "$WORK/.stenswf/$SLICE/decisions.md")
  assert_eq "slice $SLICE inherits every active anchor" \
    "$(printf '%s\n' "$ANCHOR" | grep -c '^### D')" "3"
  assert_match "slice $SLICE keeps the anchor before a supersession" \
    "$ANCHOR" "### D1 — Active before superseded (inherited from #999)"
  assert_match "slice $SLICE keeps an anchor before another active anchor" \
    "$ANCHOR" "### D3 — Active before active (inherited from #999)"
  assert_match "slice $SLICE keeps the final anchor" \
    "$ANCHOR" "### D4 — Active at EOF (inherited from #999)"
  assert_match "slice $SLICE preserves refs from the flushed anchor" \
    "$ANCHOR" "- **Refs:** src/a.py"
  assert_nomatch "slice $SLICE excludes the superseded anchor" \
    "$ANCHOR" "D2"
  assert_nomatch "slice $SLICE excludes refs from the superseded anchor" \
    "$ANCHOR" "src/b.py"
done

FIRST_1000=$(cat "$WORK/.stenswf/1000/decisions.md")
FIRST_1001=$(cat "$WORK/.stenswf/1001/decisions.md")
(
  cd "$WORK" || exit
  bash "$SCRIPT" 999 1000 1001
)
assert_eq "an exact rerun leaves slice 1000 byte-equivalent" \
  "$(cat "$WORK/.stenswf/1000/decisions.md")" "$FIRST_1000"
assert_eq "an exact rerun leaves slice 1001 byte-equivalent" \
  "$(cat "$WORK/.stenswf/1001/decisions.md")" "$FIRST_1001"

cat >> "$WORK/.stenswf/999/decisions.md" <<'EOF'

### D5 — Added after slicing

- **Category:** arch
- **Refs:** src/e.py
EOF
(
  cd "$WORK" || exit
  bash "$SCRIPT" 999 1000 1001
)
for SLICE in 1000 1001; do
  ANCHOR=$(cat "$WORK/.stenswf/$SLICE/decisions.md")
  assert_eq "slice $SLICE appends a later PRD anchor once" \
    "$(printf '%s\n' "$ANCHOR" | grep -c '^### D5 ')" "1"
  assert_match "slice $SLICE preserves refs from a later PRD anchor" \
    "$ANCHOR" "- **Refs:** src/e.py"
done

cat >> "$WORK/.stenswf/1000/decisions.md" <<'EOF'

### ~~D6~~ — Superseded local decision

- **Category:** decision
- **Source:** plan
- **Refs:** src/local.py
EOF
cat >> "$WORK/.stenswf/999/decisions.md" <<'EOF'

### D6 — Later PRD anchor with a local collision

- **Category:** arch
- **Refs:** src/f.py
EOF
(
  cd "$WORK" || exit
  bash "$SCRIPT" 999 1000 1001
)
ANCHOR_1000=$(cat "$WORK/.stenswf/1000/decisions.md")
ANCHOR_1001=$(cat "$WORK/.stenswf/1001/decisions.md")
assert_nomatch "a superseded destination ID still blocks reuse" \
  "$ANCHOR_1000" "- **Source:** #999/D6"
assert_match "the colliding local decision remains intact" \
  "$ANCHOR_1000" "### ~~D6~~ — Superseded local decision"
assert_match "a non-colliding slice imports the same PRD anchor" \
  "$ANCHOR_1001" "- **Source:** #999/D6"

(
  cd "$WORK" || exit
  bash "$SCRIPT" 999 1000 1001
)
assert_eq "the incremental rerun does not duplicate slice 1000" \
  "$(grep -c '^### D5 ' "$WORK/.stenswf/1000/decisions.md")" "1"
assert_eq "the incremental rerun does not duplicate slice 1001" \
  "$(grep -c '^### D6 ' "$WORK/.stenswf/1001/decisions.md")" "1"

printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
