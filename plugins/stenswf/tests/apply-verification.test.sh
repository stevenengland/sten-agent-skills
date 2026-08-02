#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REF="references/review-finding-validation.md"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -f "$ROOT/$REF" ] || fail "missing $REF"

for skill in skills/apply/SKILL.md skills/apply-loop/SKILL.md \
  skills/apply/slice.md skills/apply/prd.md; do
  grep -Fq 'review-finding-validation.md' "$ROOT/$skill" \
    || fail "$skill must load the shared validation contract"
done

grep -Fq '**Rollback**' "$ROOT/$REF" \
  || fail 'validation contract lost its rollback gate'
grep -Fq 'decision-escalation.md' "$ROOT/$REF" \
  || fail 'rollback gate must route through decision-escalation'

# Every relative link in the contract must resolve.
grep -o '](\.\{0,2\}/\?[A-Za-z0-9./_-]*\.md)' "$ROOT/$REF" \
  | sed 's/^](//;s/)$//' \
  | while read -r target; do
      [ -e "$ROOT/references/$target" ] || fail "broken contract link: $target"
    done

printf 'OK: apply finding-validation contract is wired up.\n'
