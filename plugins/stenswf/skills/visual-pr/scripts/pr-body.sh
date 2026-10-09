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
#          byte, plus one newline only when it lacks a final one; missing or
#          empty evidence is omitted.
# file     replace the marked region in place. An unmarked body that follows
#          upstream's template has its owned sections migrated; any other
#          unmarked body gets the block prepended. Malformed markers (one alone, or out of order)
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

# Drop trailing blank lines, and end on a newline even when the file does
# not: agents often write files without one, and a marker glued onto a
# closing fence would swallow everything after it into the code block.
trim() { { cat "$1"; echo; } | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'; }

# A required input that cannot be read stops the run before anything is
# written: inside the trim pipeline its read failure would be masked, and an
# empty region would replace — and publish over — the real description.
readable() {
  for _f in "$@"; do
    [ -f "$_f" ] && [ -r "$_f" ] || { echo "pr-body: cannot read $_f" >&2; exit 1; }
  done
}

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
  readable "$_region"
  [ -z "$_header" ] || readable "$_header"

  mkdir -p "$(dirname -- "$_out")"
  # Missing or empty evidence is omitted, like every other absent part.
  # Build beside the output and move it in, so a failure leaves nothing.
  {
    if [ -n "$_header" ]; then trim "$_header"; echo; fi
    if [ -n "$_closing" ]; then printf '%s\n\n' "$_closing"; fi
    block "$_region"
    if [ -n "$_evidence" ] && [ -s "$_evidence" ]; then
      echo
      cat "$_evidence"
      if [ -n "$(tail -c1 "$_evidence")" ]; then echo; fi
    fi
  } > "$_out.tmp"
  mv "$_out.tmp" "$_out"
}

# legacy_span <body>: for an unmarked body that follows upstream's template,
# print "<first line> <last line>" of the content visual-pr demonstrably owns
# (Why / Special things / Change outline). Prints nothing when in doubt, and
# the caller then prepends instead. Conservative by design:
#   - CommonMark fences: nothing inside one counts; an unclosed fence is doubt.
#   - The three headings occur once each, in order, outside fences.
#   - The span stops before the first `#`/`##` heading (up to three leading
#     spaces, as CommonMark allows), HTML comment or closing-keyword
#     line after the outline, so a trailing `Closes #N` survives.
#   - An unrelated section or comment between the headings, or a closing
#     keyword reference inside the span, is doubt.
# No {n,m} intervals: mawk lacks them.
legacy_span() {
  awk '
    function kw(l) { l = tolower(l)
      return l ~ /(^|[^a-z0-9_])(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved):?[ \t]+([a-z0-9_.-]+\/[a-z0-9_.-]+)?#[0-9]+/ ||
             l ~ /(^|[^a-z0-9_])(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved):?[ \t]+https?:\/\/[^ ]*\/issues\/[0-9]+/ }
    { line = $0
      if (infence) {
        if (match(line, /^(   |  | )?(`+|~+)[ \t]*$/)) {
          run = line; sub(/^ +/, "", run); sub(/[ \t]+$/, "", run)
          if (substr(run, 1, 1) == fch && length(run) >= flen) infence = 0
        }
        if (cl && !stop) last = NR
        next
      }
      if (match(line, /^(   |  | )?(```+|~~~+)/)) {
        run = substr(line, RSTART, RLENGTH); sub(/^ +/, "", run)
        fch = substr(run, 1, 1); flen = length(run)
        if (!(fch == "`" && index(substr(line, RSTART + RLENGTH), "`"))) {
          infence = 1; if (cl && !stop) last = NR; next }
      }
      if (line == "## Why the change")              { w++; if (!wl) wl = NR }
      else if (line == "## Special things to note")  { s++; if (!sl) sl = NR }
      else if (line == "## Change outline")          { c++; if (!cl) cl = NR }
      else if (line ~ /^(   |  | )?##?([ \t]|$)/ || line ~ /^(   |  | )?<!--/ ||
               tolower(line) ~ /^[ \t]*(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved):?[ \t]/) {
        if (cl && !stop) stop = NR; else if (wl && !cl) other++ }
      if (wl && !stop && kw(line)) keyword++
      if (cl && !stop && line ~ /[^ \t]/) last = NR }
    END { if (infence) exit
          if (w == 1 && s == 1 && c == 1 && wl < sl && sl < cl && !other && !keyword) print wl, last }
  ' "$1"
}

# Bodies edited on the GitHub website arrive with CRLF line endings, where the
# marker lines would not match and a second region would be prepended.
# Normalise to LF, as publish-decisions.sh does.
lf() { tr -d '\r' < "${1:-/dev/stdin}"; }

# merge <body> <region>: merged body on stdout, or exit 1 on malformed markers.
merge() {
  _starts=$(grep -cxF "$MARK_START" "$1" || true)
  _ends=$(grep -cxF "$MARK_END" "$1" || true)
  if [ "$_starts" -eq 0 ] && [ "$_ends" -eq 0 ]; then
    _span=$(legacy_span "$1")
    if [ -n "$_span" ]; then
      _w=${_span% *}; _last=${_span#* }
      awk -v n=$((_w - 1)) 'NR <= n' "$1"
      block "$2"
      tail -n +$((_last + 1)) "$1"
    else
      block "$2"
      echo
      cat "$1"
    fi
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
  readable "$1" "$2"
  _tmp=$(mktemp)
  trap 'rm -f "$_tmp" "$_tmp.body"' EXIT
  lf "$1" > "$_tmp.body"
  merge "$_tmp.body" "$2" > "$_tmp"
  cat "$_tmp"
}

refresh_pr() {
  [ $# -eq 3 ] || usage
  _pr=$1; _region=$2; _desc=$3
  readable "$_region"
  _tmp=$(mktemp)
  trap 'rm -f "$_tmp" "$_tmp.raw" "$_tmp.body" "$_tmp.merged"' EXIT

  gh pr view "$_pr" --json body > "$_tmp" \
    && jq -j '.body // ""' "$_tmp" > "$_tmp.raw" || {
    echo "pr-body: cannot read PR $_pr" >&2
    exit 1
  }
  lf "$_tmp.raw" > "$_tmp.body"
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
