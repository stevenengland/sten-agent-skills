#!/usr/bin/env bash
# plan — self-review validation for .stenswf/$1/ tree.
# Exits non-zero if any structural check fails.
# Usage: plan-self-review.sh <issue-number>

set -eu

ARG="${1:-}"
if [ -z "$ARG" ]; then
  echo "usage: plan-self-review.sh <issue-number>" >&2
  exit 2
fi

D=".stenswf/$ARG"
FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=1; }

# 1. Required files exist and non-empty.
for f in manifest.json concept.md stable-prefix.md conventions.md decisions.md \
         house-rules.md design-summary.md acceptance-criteria.md \
         file-structure.md review-step.md; do
  [ -s "$D/$f" ] || fail "$f missing or empty"
done
[ -d "$D/tasks" ] || fail "tasks/ dir missing"
ls "$D/tasks"/T*.md >/dev/null 2>&1 || fail "no task fragments"

# 2. manifest.json parses and every listed task file exists.
if [ -s "$D/manifest.json" ]; then
  if ! jq -e . "$D/manifest.json" >/dev/null 2>&1; then
    fail "manifest.json does not parse"
  else
    # Count missing task files via a temp marker (subshell can't mutate FAIL).
    MISS=$(jq -r '.tasks[].file' "$D/manifest.json" | while read -r f; do
      [ -s "$D/$f" ] || printf 'x'
    done)
    [ -z "$MISS" ] || fail "manifest-listed task file(s) missing: ${#MISS} entries"

    # 2a. TDD-as-lens: every task must carry a boolean `behavior_change`
    # and an `acs[]` array (each AC: id + boolean + text). Per-task
    # `behavior_change` must be `any(acs.behavior_change)`.
    BAD_TASK=$(jq -r '
      .tasks[] | select(
        (.behavior_change | type) != "boolean"
        or (.acs | type)          != "array"
        or any(.acs[]?;
             (.id            | type) != "string"
          or (.behavior_change| type) != "boolean"
          or (.text          | type) != "string")
      ) | .id' "$D/manifest.json")
    [ -z "$BAD_TASK" ] || fail "tasks missing/invalid behavior_change|acs[]: $BAD_TASK"

    BAD_AGG=$(jq -r '
      .tasks[]
      | select((.acs | length) > 0)
      | select(.behavior_change != ([.acs[].behavior_change] | any))
      | .id' "$D/manifest.json")
    [ -z "$BAD_AGG" ] || fail "tasks where behavior_change != any(acs.behavior_change): $BAD_AGG"
  fi
fi

# 3. Every <task> opening tag has id, name, commit attributes.
for f in "$D"/tasks/T*.md; do
  [ -s "$f" ] || continue
  if ! head -1 "$f" | grep -qE '<task id="T[0-9]+" name="[^"]+" commit="[^"]+">'; then
    fail "malformed opening tag in $f"
  fi
done

# 4. Task IDs unique across fragments.
DUPES=$(grep -ohE 'id="T[0-9]+"' "$D"/tasks/*.md 2>/dev/null | sort | uniq -d || true)
[ -z "$DUPES" ] || fail "duplicate task IDs: $DUPES"

# 5. Every AC in acceptance-criteria.md is referenced by at least one task's Done-when.
if [ -s "$D/acceptance-criteria.md" ]; then
  AC_COUNT=$(grep -cE '^[-*] ' "$D/acceptance-criteria.md" || true)
  DONE_COUNT=$(grep -hcE '^\*\*Done when:\*\*' "$D"/tasks/T*.md 2>/dev/null | paste -sd+ | bc || echo 0)
  [ "$DONE_COUNT" -ge "$AC_COUNT" ] || fail "fewer Done-when lines ($DONE_COUNT) than ACs ($AC_COUNT)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "plan self-review: OK"
else
  exit 1
fi
