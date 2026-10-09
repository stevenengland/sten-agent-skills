#!/usr/bin/env bash
# Own the visual-pr region of a PR description.
#
# visual-pr writes the reviewer-facing part of a PR body (Why / Special
# things / Change outline) between two marker lines. Everything else in the
# body — links header, closing line, shipper evidence, the `## Decisions`
# block — belongs to other writers, so this script never touches a byte
# outside the markers. Only this script writes the markers: the region file
# holds the inner content, so no caller can misspell them.
#
# Usage:
#   pr-body.sh compose --out <path> --region <file> [--header <file>]
#                      [--closing <line>] [--evidence <file>]
#   pr-body.sh file <body> <region>                  # merged body on stdout
#   pr-body.sh pr <pr> <region> <description-path>   # refresh a PR in place
#
# compose  header, closing line, region block and evidence, one blank line
#          apart; absent parts are omitted. The evidence is appended byte for
#          byte, plus one newline only when it lacks a final one.
# file     replace the marked region in place; an unmarked body gets the
#          block prepended. Malformed markers (one alone, or out of order)
#          exit 1 and print nothing.
# pr       fetch the body as JSON (never `-q .body`: the CLI appends a
#          newline, so every refresh would grow the body), merge, save the
#          complete result at <description-path>, publish that same file.
#          Nothing is written when the merge fails.
set -eu

MARK_START='<!-- stenswf:visual-pr:start -->'
MARK_END='<!-- stenswf:visual-pr:end -->'

usage() {
  echo "usage: pr-body.sh compose --out <path> --region <file> [--header <file>] [--closing <line>] [--evidence <file>] | file <body> <region> | pr <pr> <region> <description-path>" >&2
  exit 2
}

# Drop trailing blank lines.
trim() { sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$1"; }

block() {
  printf '%s\n' "$MARK_START"
  trim "$1"
  printf '%s\n' "$MARK_END"
}

compose() {
  _out=""; _region=""; _header=""; _closing=""; _evidence=""
  while [ $# -gt 1 ]; do
    case "$1" in
      --out)      _out=$2 ;;
      --region)   _region=$2 ;;
      --header)   _header=$2 ;;
      --closing)  _closing=$2 ;;
      --evidence) _evidence=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  [ $# -eq 0 ] && [ -n "$_out" ] && [ -n "$_region" ] || usage

  mkdir -p "$(dirname -- "$_out")"
  {
    if [ -n "$_header" ]; then trim "$_header"; echo; fi
    if [ -n "$_closing" ]; then printf '%s\n\n' "$_closing"; fi
    block "$_region"
    if [ -n "$_evidence" ]; then
      echo
      cat "$_evidence"
      if [ -s "$_evidence" ] && [ -n "$(tail -c1 "$_evidence")" ]; then echo; fi
    fi
  } > "$_out"
}

# merge <body> <region>: merged body on stdout, or exit 1 on malformed markers.
merge() {
  _starts=$(grep -cxF "$MARK_START" "$1" || true)
  _ends=$(grep -cxF "$MARK_END" "$1" || true)
  if [ "$_starts" -eq 0 ] && [ "$_ends" -eq 0 ]; then
    block "$2"
    echo
    cat "$1"
    return 0
  fi
  if [ "$_starts" -eq 1 ] && [ "$_ends" -eq 1 ]; then
    _s=$(grep -nxF "$MARK_START" "$1" | cut -d: -f1)
    _e=$(grep -nxF "$MARK_END" "$1" | cut -d: -f1)
    if [ "$_s" -lt "$_e" ]; then
      awk -v n=$((_s - 1)) 'NR <= n' "$1"
      block "$2"
      tail -n +$((_e + 1)) "$1"
      return 0
    fi
  fi
  echo "pr-body: malformed visual-pr markers" >&2
  return 1
}

merge_file() {
  [ $# -eq 2 ] || usage
  _tmp=$(mktemp)
  trap 'rm -f "$_tmp"' EXIT
  merge "$1" "$2" > "$_tmp"
  cat "$_tmp"
}

refresh_pr() {
  [ $# -eq 3 ] || usage
  _pr=$1; _region=$2; _desc=$3
  _tmp=$(mktemp)
  trap 'rm -f "$_tmp" "$_tmp.body" "$_tmp.merged"' EXIT

  gh pr view "$_pr" --json body > "$_tmp" \
    && jq -j '.body // ""' "$_tmp" > "$_tmp.body" || {
    echo "pr-body: cannot read PR $_pr" >&2
    exit 1
  }
  merge "$_tmp.body" "$_region" > "$_tmp.merged"
  mkdir -p "$(dirname -- "$_desc")"
  cp "$_tmp.merged" "$_desc"
  gh pr edit "$_pr" --body-file "$_desc"
}

CMD="${1:-}"
shift || true
case "$CMD" in
  compose) compose "$@" ;;
  file)    merge_file "$@" ;;
  pr)      refresh_pr "$@" ;;
  *)       usage ;;
esac
