# Deliberation plumbing — canonical shell library for the stenswf peer
# deliberation loop (`deliberate` agent A + `deliberate-peer` agent B).
#
# Sourced, not executed. From a skill directory:
#   source ../../scripts/deliberation.sh
#
# Contract, move rules and the reasons behind them live in
# ../references/deliberation-loop.md. Function bodies below are the single
# source of truth — do not duplicate them.
#
# State is one directory of numbered moves, `NN-<role>-<kind>.md`. The
# highest NN is the latest move, and nothing else records state:
# `delib_status` derives everything from it and `delib_move` is the only
# writer.

# The plugin root, resolved from this file's own location so the
# bootstrap can name an installed skill without a hardcoded layout.
_DELIB_HOME=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-.}")/.." 2>/dev/null && pwd -P)

_DELIB_TERMINAL=' agreed parked escalated cancelled '

_delib_err() { printf 'delib: %s\n' "$*" >&2; }

# Six hex chars from the kernel's RNG. A function so a test can force a
# collision.
_delib_id() { od -An -N3 -tx1 /dev/urandom | tr -d ' \n'; }

# The latest move's file name, or nothing for an empty directory.
_delib_last_file() {
  local f last=""
  for f in "$1"/[0-9][0-9]-[AB]-*.md; do [ -e "$f" ] && last=${f##*/}; done
  printf '%s' "$last"
}

# The latest move as `<seq> <role> <kind>`, or nothing.
_delib_last() {
  local base rest
  base=$(_delib_last_file "$1"); base=${base%.md}
  [ -n "$base" ] || return 0
  rest=${base#*-}
  printf '%s %s %s\n' "${base%%-*}" "${rest%%-*}" "${rest#*-}"
}

# One line: `open A` | `open B` | `capped` | `ended <outcome>` | `none`.
#
# Whose move it is follows from who moved last. `capped` means the round
# cap is spent and only a terminal move remains; an owed verdict, and the
# `agreed` an acceptance makes possible, are still allowed past the cap.
#   delib_status <dir>
delib_status() {
  local seq role kind max="${DELIB_MAX_ROUNDS:-6}"
  read -r seq role kind <<EOF
$(_delib_last "$1")
EOF
  [ -n "$seq" ] || { printf 'none\n'; return 0; }
  case "$_DELIB_TERMINAL" in *" $kind "*) printf 'ended %s\n' "$kind"; return 0 ;; esac
  case "$kind" in
    turn|reject|tension)
      [ $((10#$seq)) -ge $((2 * max)) ] && { printf 'capped\n'; return 0; } ;;
  esac
  [ "$role" = A ] && printf 'open B\n' || printf 'open A\n'
}

# Write the next move and print its path. The only writer.
#
#   kind       who    when
#   tension    A      move 00, once
#   turn       A|B    their move; not owed a verdict
#   proposal   A      A's move
#   accept     B      the latest move is a proposal (src ignored: the
#   reject     B        hash is computed here)
#   agreed     A      the latest move is an accept that still verifies
#   parked     A      any time
#   escalated  A      any time
#   cancelled  A|B    any time
#
# Returns 1 when the move is not allowed, 2 on bad arguments, and 3 when
# the round cap is spent — close it with a terminal move.
#   delib_move <dir> <A|B> <kind> [source-file]
delib_move() {
  local dir="$1" role="$2" kind="$3" src="${4:-}"
  local status seq lrole lkind next dest
  case "$role" in A|B) ;; *) _delib_err "role must be A or B, got $role"; return 2 ;; esac
  status=$(delib_status "$dir")
  read -r seq lrole lkind <<EOF
$(_delib_last "$dir")
EOF
  case "$status" in
    ended*) _delib_err "$dir is $status — a deliberation ends once"; return 1 ;;
    none)   [ "$kind" = tension ] || { _delib_err "no tension in $dir"; return 1; } ;;
  esac

  case "$kind" in
    tension)
      [ "$status" = none ] && [ "$role" = A ] \
        || { _delib_err "the tension is A's move 00, once"; return 1; } ;;
    turn|proposal|accept|reject)
      [ "$status" = capped ] && {
        _delib_err "round cap (${DELIB_MAX_ROUNDS:-6}) reached — close with parked, escalated or cancelled"; return 3; }
      [ "$status" = "open $role" ] || { _delib_err "not $role's move ($status)"; return 1; }
      case "$kind" in
        turn)     [ "$lkind" != proposal ] || { _delib_err "proposal $seq is owed a verdict, not a turn"; return 1; } ;;
        proposal) [ "$role" = A ] || { _delib_err "only A proposes"; return 1; } ;;
        *)        [ "$role" = B ] && [ "$lkind" = proposal ] \
                    || { _delib_err "only B judges, and only a proposal that is the latest move"; return 1; } ;;
      esac ;;
    agreed)
      [ "$role" = A ] && [ "$lkind" = accept ] \
        || { _delib_err "agreed needs B's accept as the latest move"; return 1; }
      [ "$(proposal_verify "$dir")" = accepted ] \
        || { _delib_err "the proposal changed after B accepted it (stale)"; return 1; } ;;
    parked|escalated)
      [ "$role" = A ] || { _delib_err "only A escalates or parks"; return 1; } ;;
    cancelled) ;;
    *) _delib_err "unknown kind: $kind"; return 2 ;;
  esac
  [ "$kind" = accept ] || [ -f "$src" ] || { _delib_err "no source file: $src"; return 2; }

  [ -n "$seq" ] && next=$(printf '%02d' $((10#$seq + 1))) || next=00
  dest="$dir/$next-$role-$kind.md"
  # mkdir is atomic: two sides racing for the same number cannot both win.
  mkdir "$dir/.seq-$next" 2>/dev/null \
    || { _delib_err "move $next was taken concurrently — re-read the state"; return 1; }
  if [ "$kind" = accept ]; then
    printf -- '- **Proposal:** %s\n- **Hash:** %s\n' \
      "$seq-$lrole-$lkind.md" "$(proposal_hash "$dir/$seq-$lrole-$lkind.md")" > "$dest.tmp"
  else
    cp "$src" "$dest.tmp"
  fi && mv "$dest.tmp" "$dest" || { rmdir "$dir/.seq-$next"; return 1; }
  printf '%s\n' "$dest"
}

# Open a deliberation with A's tension as move 00 and print its path.
# A fresh id per wall, and never a directory that already exists.
#   delib_new <issue> <tension-file>
delib_new() {
  local base=".stenswf/$1/deliberations" src="$2" dir i
  [ -f "$src" ] || { _delib_err "no tension file: $src"; return 2; }
  mkdir -p "$base" || return 1
  for i in 1 2 3 4 5; do
    dir="$base/$(_delib_id)"
    mkdir "$dir" 2>/dev/null || continue
    delib_move "$dir" A tension "$src" >/dev/null || return 1
    printf '%s\n' "$dir"
    return 0
  done
  _delib_err "could not allocate a fresh id under $base"; return 1
}

# The 12-hex digest of a proposal's text. Normalises CRLF, trailing
# whitespace and blank-line runs; any rewording changes it.
#   proposal_hash <file>
proposal_hash() {
  tr -d '\r' < "$1" | sed 's/[[:space:]]*$//' | cat -s | sha256sum | cut -c1-12
}

# Whether the latest acceptance still covers its proposal, by RECOMPUTING
# the hash. Prints `accepted` | `stale` | `pending`; non-zero unless accepted.
#   proposal_verify <dir>
proposal_verify() {
  local f a="" prop stored
  for f in "$1"/[0-9][0-9]-B-accept.md; do [ -e "$f" ] && a=$f; done
  [ -n "$a" ] || { printf 'pending\n'; return 1; }
  prop=$(sed -n 's/^- \*\*Proposal:\*\* //p' "$a")
  stored=$(sed -n 's/^- \*\*Hash:\*\* //p' "$a")
  [ -f "$1/$prop" ] || { printf 'pending\n'; return 1; }
  [ "$(proposal_hash "$1/$prop")" = "$stored" ] && { printf 'accepted\n'; return 0; }
  printf 'stale\n'; return 1
}

# Block until it is <role>'s move or the deliberation ends, then print ONE
# line: the status and the latest move's file, or `timeout`. A is also
# woken by `capped`, since only A can close a capped deliberation.
#
# Role-aware, so there is no cursor to pass: a side never wakes on its own
# move, and never sleeps through the other side's.
#   delib_wait <dir> <A|B> [timeout] [interval]
delib_wait() {
  local dir="$1" role="$2"
  local timeout="${3:-${DELIB_PEER_TIMEOUT:-1800}}" interval="${4:-${DELIB_WAIT_INTERVAL:-5}}"
  local deadline status
  deadline=$(( $(date +%s) + timeout ))
  while :; do
    status=$(delib_status "$dir")
    case "$status" in
      none) _delib_err "no deliberation at $dir"; return 1 ;;
      "open $role"|ended*) printf '%s %s\n' "$status" "$(_delib_last_file "$dir")"; return 0 ;;
      capped) [ "$role" = A ] && { printf 'capped %s\n' "$(_delib_last_file "$dir")"; return 0; } ;;
    esac
    [ "$(date +%s)" -ge "$deadline" ] && { printf 'timeout\n'; return 0; }
    sleep "$interval"
  done
}

# Deliberations for one issue that have not ended, one path per line. With
# a host seam, only those whose tension names it — so `review-loop` never
# answers a deliberation that was opened for some other peer.
#   delib_open_for_issue <issue> [host-seam]
delib_open_for_issue() {
  local d
  for d in ".stenswf/$1/deliberations"/*; do
    [ -d "$d" ] || continue
    case "$(delib_status "$d")" in none|ended*) continue ;; esac
    if [ -n "${2:-}" ]; then
      grep -Eq "^- \*\*Host seam:\*\*[[:space:]]*\`?$2\`?[[:space:]]*\$" "$d/00-A-tension.md" || continue
    fi
    printf '%s\n' "$d"
  done
  return 0
}

# The lines A hands over so B can be started in another harness: the
# installed skill first, the resolved skill file for a harness without the
# plugin. Paths are absolute — B's working directory is not A's concern.
#   delib_bootstrap <dir>
delib_bootstrap() {
  local abs skill="$_DELIB_HOME/skills/deliberate-peer/SKILL.md"
  abs=$(CDPATH= cd -- "$1" 2>/dev/null && pwd -P) || { _delib_err "no directory: $1"; return 1; }
  printf 'Start the peer in the other harness with:\n\n  /stenswf:deliberate-peer %s\n' "$abs"
  [ -f "$skill" ] && printf '\nWhere that harness has no stenswf plugin:\n\n  Read %s and follow it.\n  Deliberation: %s\n' "$skill" "$abs"
  return 0
}

# Whether `review-loop` can be the peer: the user opted in to a shared
# checkout, and the reviewer's own state file is present in this tree.
#   delib_pr_peer_ready <issue>
delib_pr_peer_ready() {
  [ "${STENSWF_DELIB_SHARED_CHECKOUT:-}" = 1 ] || {
    _delib_err "STENSWF_DELIB_SHARED_CHECKOUT is not 1 — review-loop is not known to share this checkout"; return 1; }
  [ -f ".stenswf/$1/loop-state.reviewer.json" ] || {
    _delib_err "no .stenswf/$1/loop-state.reviewer.json here — review-loop is not running in this checkout"; return 1; }
}

# The `## Refs` paths of a proposal, one per line, normalised: list
# bullets, backticks and quotes, a leading `./` and a trailing `:12` or
# `#L12` are stripped; `delib#…` and `none` are dropped.
_delib_refs() {
  awk '/^#+ Refs[[:space:]]*$/{f=1;next} /^#+ /{f=0} f' "$1" \
    | tr ',' '\n' | tr -d "\`\"'" \
    | sed -E 's/^[[:space:]]*([-*][[:space:]]+)?//; s/[[:space:]]*$//; s#^\./##; s/:[0-9]+(-[0-9]+)?$//; s/#L[0-9]+(-L?[0-9]+)?$//' \
    | grep -vE '^$|^delib#|^none$|^\(none\)$' || true
}

# Candidate conflicts between a proposal and what is already on record,
# one `<tier>\t<evidence>` line each. Candidates only: A judges which are
# real. Paths match literally, every hit is printed, and a git-tier
# overflow is announced rather than dropped. The house tier is always
# printed.
#   delib_contradictions <issue> <proposal-file>
delib_contradictions() {
  local issue="$1" p f log n max="${DELIB_GIT_HITS:-20}"
  while IFS= read -r p; do
    [ -n "$p" ] || continue

    # Active entries (`### D<n> `, so strikethrough is excluded) whose own
    # body carries the path. `index()`, not `~`: a path is a literal.
    for f in .stenswf/*/decisions.md .stenswf/.archive/*/decisions.md; do
      [ -f "$f" ] || continue
      dl_path="$p" awk '
        function cites(h, b) { return h ~ /^### D[0-9]+ / && index(b, ENVIRON["dl_path"]) > 0 }
        function out()       { if (hdr != "" && cites(hdr, body)) print "anchor\t" FILENAME " — " hdr }
        /^### / { out(); hdr = $0; body = ""; next }
                { body = body "\n" $0 }
        END     { out() }
      ' "$f"
    done

    for f in docs/stenswf/decisions/*.md; do
      [ -f "$f" ] || continue
      grep -Fq -- "$p" "$f" && printf 'committed\t%s references %s\n' "$f" "$p"
    done

    # Whole messages, not just `Touches:` trailers: a literal pattern
    # cannot carry the `^Touches:` anchor, and a squash buries trailers.
    log=$(git log --fixed-strings --grep="$p" --format='%h %s' 2>/dev/null || true)
    [ -n "$log" ] || continue
    n=$(printf '%s\n' "$log" | wc -l | tr -d ' ')
    printf '%s\n' "$log" | head -n "$max" | while IFS= read -r f; do
      printf 'git\t%s in commit message — %s\n' "$p" "$f"
    done
    [ "$n" -gt "$max" ] && printf 'git\t%s: %s more not shown — git log --fixed-strings --grep=%q\n' \
      "$p" "$((n - max))" "$p"
  done <<EOF
$(_delib_refs "$2")
EOF

  for f in CLAUDE.md AGENTS.md ".stenswf/$issue/conventions.md"; do
    [ -f "$f" ] && printf 'house\t%s — read before overruling\n' "$f"
  done
  return 0
}
