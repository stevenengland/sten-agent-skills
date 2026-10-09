#!/usr/bin/env bash
# Name the stenswf skill that owns the current branch, if any.
#
# Standalone visual-pr must not create a PR on a branch that ship,
# ship-light or apply owns: those skills run CI, merge and record decision
# trailers, and a PR created around them bypasses all of it. Ownership comes
# from authoritative branch identity only. Commit messages, trailers and issue
# mentions never establish it — people write "Refs #28" by hand on unrelated
# branches.
#
# Usage:
#   workflow-issue.sh        # prints "<skill> <N>" or nothing; always exit 0
#
# Rules, first match wins:
#   1. the branch recorded in .stenswf/<N>/manifest.json   → ship <N>
#   2. prd/<N>-cleanup                                      → apply <N>
#   3. impl/<N> or impl/<N>-…, with .stenswf/<N>/manifest.json → ship <N>
#      impl/<N> or impl/<N>-…, without one                  → ship-light <N>
#   4. anything else                                        → nothing
set -eu

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
BR=$(git branch --show-current 2>/dev/null || true)
[ -n "$BR" ] || exit 0

is_number() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }

for M in "$TOP"/.stenswf/[0-9]*/manifest.json; do
  [ -f "$M" ] || continue
  if [ "$(jq -r '.branch // ""' "$M" 2>/dev/null)" = "$BR" ]; then
    N=$(basename -- "$(dirname -- "$M")")
    is_number "$N" && { echo "ship $N"; exit 0; }
  fi
done

case "$BR" in
  prd/*-cleanup)
    N=${BR#prd/}; N=${N%-cleanup}
    is_number "$N" && echo "apply $N" ;;
  impl/*)
    N=${BR#impl/}; N=${N%%-*}
    if is_number "$N"; then
      if [ -f "$TOP/.stenswf/$N/manifest.json" ]; then echo "ship $N"; else echo "ship-light $N"; fi
    fi ;;
esac
exit 0
