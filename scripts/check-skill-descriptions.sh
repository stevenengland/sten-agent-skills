#!/usr/bin/env bash
# Guard: skill SKILL.md descriptions must be a single-line, single-sentence
# string per the repo rule in CLAUDE.md ("Skill descriptions MUST NOT exceed
# one line/sentence.").
#
# Failure modes:
#   1. YAML folded scalar (`description: >` or `description: |`).
#   2. Description value spans more than one physical line.
#   3. Description contains more than one terminal punctuation mark
#      (`.`, `!`, `?`) before the final character.
#
# Usage:
#   bash scripts/check-skill-descriptions.sh [path...]
# Default path: plugins/**/skills/*/SKILL.md
set -euo pipefail

paths=("$@")
if [ "${#paths[@]}" -eq 0 ]; then
  shopt -s nullglob globstar
  paths=(plugins/**/skills/*/SKILL.md)
fi

fail=0

for f in "${paths[@]}"; do
  awk -v file="$f" '
    BEGIN { fences=0 }
    /^---[[:space:]]*$/ { fences++; if (fences==2) exit; next }
    fences==1 && /^description:[[:space:]]*[>|]/ {
      printf "%s: folded/literal YAML scalar not allowed (description must be a single line)\n", file > "/dev/stderr"
      bad=1; exit 2
    }
    fences==1 && /^description:[[:space:]]*/ {
      desc=$0
      sub(/^description:[[:space:]]*/, "", desc)
      # consume continuation lines (any line that does NOT start a new key)
      while ((getline next_line) > 0) {
        if (next_line ~ /^---[[:space:]]*$/) break
        if (next_line ~ /^[A-Za-z_-]+:[[:space:]]*/) break
        if (next_line ~ /^[[:space:]]*$/) continue
        printf "%s: description spans multiple lines\n", file > "/dev/stderr"
        bad=1; exit 2
      }
      # Count interior sentence boundaries: a period/!/? followed by
      # whitespace and an uppercase or backtick letter (next sentence).
      # Periods inside file paths or identifiers (e.g. plan-light.md,
      # .stenswf/<issue>/) do not trigger because they are not followed
      # by whitespace + capital.
      core=desc
      sub(/[[:space:]]+$/, "", core)
      n=0
      tmp=core
      while (match(tmp, /[.!?][[:space:]]+[A-Z`]/)) {
        n++
        tmp=substr(tmp, RSTART+RLENGTH)
      }
      if (n > 0) {
        printf "%s: description contains more than one sentence (n=%d): %s\n", file, n+1, core > "/dev/stderr"
        bad=1; exit 2
      }
      exit 0
    }
    END { if (bad) exit 2 }
  ' "$f" || fail=1
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "OK: all skill descriptions are one-line / one-sentence."
