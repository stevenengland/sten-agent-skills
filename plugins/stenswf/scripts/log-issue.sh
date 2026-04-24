#!/usr/bin/env bash
# stenswf feedback logger — canonical writer for .stenswf/_feedback/<date>.jsonl.
# Schema: references/feedback-log.md.
#
# Usage:
#   log-issue.sh <category> <summary> [evidence]
#
# Env (optional, set by the caller):
#   STENSWF_SKILL        — current skill name (e.g. ship-light). Default: "unknown".
#   STENSWF_PHASE        — current phase (e.g. preflight). Default: "".
#   STENSWF_ISSUE        — current issue number. Default: "".
#
# Fixed categories: contract_violation | ambiguous_instruction |
#                   missing_artifact  | tool_failure | user_override

set -eu

CATEGORY="${1:-}"
SUMMARY="${2:-}"
EVIDENCE="${3:-}"

if [ -z "$CATEGORY" ] || [ -z "$SUMMARY" ]; then
  echo "usage: log-issue.sh <category> <summary> [evidence]" >&2
  exit 2
fi

case "$CATEGORY" in
  contract_violation|ambiguous_instruction|missing_artifact|tool_failure|user_override) ;;
  *)
    echo "unknown category: $CATEGORY (see references/feedback-log.md)" >&2
    exit 2
    ;;
esac

DATE_UTC=$(date -u +%Y-%m-%d)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DIR=".stenswf/_feedback"
mkdir -p "$DIR"
LOG="$DIR/$DATE_UTC.jsonl"

# Portable JSON field escaper (\ -> \\, " -> \", drop control chars).
esc() {
  printf '%s' "$1" | awk '
    BEGIN { ORS="" }
    {
      s = $0
      gsub(/\\/, "\\\\", s)
      gsub(/"/, "\\\"", s)
      gsub(/\t/, "\\t", s)
      gsub(/\r/, "", s)
      print s
    }
    NR < ORS_N { print "\\n" }
  ' ORS_N=999999
}

SKILL_ESC=$(esc "${STENSWF_SKILL:-unknown}")
PHASE_ESC=$(esc "${STENSWF_PHASE:-}")
SUM_ESC=$(esc "$SUMMARY")
EV_ESC=$(esc "$EVIDENCE")
ISSUE="${STENSWF_ISSUE:-}"

# Emit one JSON line.
{
  printf '{"ts":"%s",' "$TS"
  printf '"skill":"%s",' "$SKILL_ESC"
  printf '"phase":"%s",' "$PHASE_ESC"
  if [ -n "$ISSUE" ]; then
    printf '"issue":%s,' "$ISSUE"
  else
    printf '"issue":null,'
  fi
  printf '"category":"%s",' "$CATEGORY"
  printf '"summary":"%s",' "$SUM_ESC"
  printf '"evidence":"%s"}\n' "$EV_ESC"
} >> "$LOG"
