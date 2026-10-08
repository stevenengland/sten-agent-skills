# Deliberation plumbing — canonical shell library for the stenswf peer
# deliberation loop (`deliberate` agent A + `deliberate-peer` agent B).
#
# Sourced, not executed. From a skill directory:
#   source ../../scripts/deliberation.sh
#
# Contract and turn schemas live in ../references/deliberation-loop.md.
# Function bodies below are the single source of truth — do not duplicate
# them.
#
# The protocol is files in one directory. A creates the directory and
# hands B its exact path; there is no discovery, no search, and no
# environment variable, because every one of those turns "which
# deliberation is this?" into a question that can be answered wrongly.
#
# Two rules the functions enforce rather than document:
#
#   1. Turn and proposal files are IMMUTABLE. A write that would clobber
#      an existing file fails. A transcript you can rewrite is not
#      evidence of anything, and a rejected proposal has to stay readable
#      next to the one that replaced it.
#   2. Acceptance is verified by RECOMPUTING the proposal's hash, never
#      by comparing two stored signatures. Otherwise editing an accepted
#      proposal leaves the acceptance looking valid.

# Create a new deliberation and print its path.
#
# The id makes a second deliberation on the same issue a sibling rather
# than a collision — a slice can hit more than one wall, and the second
# must not overwrite the first's transcript.
#   delib_new <issue>
delib_new() {
  local issue="$1" id
  id=$(date +%s%N 2>/dev/null | sha256sum | cut -c1-6)
  [ -n "$id" ] || id=$$
  local dir=".stenswf/$issue/deliberations/$id"
  mkdir -p "$dir" || return 1
  printf '%s\n' "$dir"
}

# The highest turn number present. `tension.md` is turn 0; turn files are
# `NN-<role>.md`. Prints -1 when the directory holds no tension at all,
# so "not a deliberation" is distinguishable from "opened, unanswered".
#   delib_turn <dir>
delib_turn() {
  local dir="$1" n=-1 f base r
  [ -f "$dir/tension.md" ] || { printf '%s\n' "$n"; return 0; }
  n=0
  for f in "$dir"/[0-9][0-9]-[AB].md; do
    [ -e "$f" ] || continue
    base=${f##*/}; r=${base%%-*}
    r=$((10#$r))
    [ "$r" -gt "$n" ] && n=$r
  done
  printf '%s\n' "$n"
}

# Whose turn it is: A opens at turn 0, so odd turns are B's and even are
# A's. Prints nothing once `result.md` exists — that, and only that, ends
# a deliberation.
#
# Deliberately NOT keyed on the presence of a proposal: a proposal awaits
# a verdict, so the exchange is still live. Ending it there is what makes
# a proposal impossible to reject.
#   delib_next_role <dir>
delib_next_role() {
  local dir="$1" n p
  [ -f "$dir/result.md" ] && return 0
  n=$(delib_turn "$dir")
  [ "$n" -lt 0 ] && return 0
  # Once a proposal exists it, not the turn parity, says whose move it is.
  # Turn parity is only meaningful during the free-form exchange: a
  # proposal and its verdict are moves of their own, and letting parity
  # answer over them puts the wrong agent on both ends of the handover.
  p=$(delib_proposal_version "$dir")
  if [ "$p" -gt 0 ]; then
    # A verdict of EITHER kind returns control to A — to revise after a
    # rejection, or to run the contradiction gate and finalize after an
    # acceptance. Only an unjudged proposal is B's move.
    if [ -f "$dir/proposal-$p.accepted-B" ] || [ -f "$dir/proposal-$p.rejected-B.md" ]; then
      printf 'A\n'
    else
      printf 'B\n'
    fi
    return 0
  fi
  if [ $(( n % 2 )) -eq 0 ]; then printf 'B\n'; else printf 'A\n'; fi
}

# Write turn <n> for <role>, atomically and only once.
#
# Refuses rather than overwrites: the temp-then-mv closes the half-written
# read, and the existence check closes the rewritten-history one.
#   delib_turn_write <dir> <n> <A|B> <source-file>
delib_turn_write() {
  local dir="$1" n="$2" role="$3" src="$4" dest
  case "$role" in A|B) ;; *) printf 'delib: role must be A or B, got %s\n' "$role" >&2; return 2 ;; esac
  mkdir -p "$dir"
  if [ "$n" -eq 0 ]; then dest="$dir/tension.md"; else dest=$(printf '%s/%02d-%s.md' "$dir" "$n" "$role"); fi
  [ -e "$dest" ] && { printf 'delib: %s already exists — turns are immutable\n' "$dest" >&2; return 1; }
  cp "$src" "$dest.tmp" && mv "$dest.tmp" "$dest"
}

# The highest proposal version present, or 0 when there is none.
#   delib_proposal_version <dir>
delib_proposal_version() {
  local dir="$1" n=0 f base r
  for f in "$dir"/proposal-*.md; do
    [ -e "$f" ] || continue
    base=${f##*/}; r=${base#proposal-}; r=${r%.md}
    case "$r" in ''|*[!0-9]*) continue ;; esac
    [ "$r" -gt "$n" ] && n=$r
  done
  printf '%s\n' "$n"
}

# Write the next complete proposal and print its version. A only.
#
# Versioned rather than edited in place: a rejection has to leave the
# rejected text standing next to its replacement, or "B rejected clause 3"
# refers to something no longer readable.
#   delib_propose <dir> <source-file>
delib_propose() {
  local dir="$1" src="$2" n dest
  n=$(( $(delib_proposal_version "$dir") + 1 ))
  dest="$dir/proposal-$n.md"
  [ -e "$dest" ] && { printf 'delib: %s already exists\n' "$dest" >&2; return 1; }
  cp "$src" "$dest.tmp" && mv "$dest.tmp" "$dest" || return 1
  printf '%s\n' "$n"
}

# The 12-hex digest of a proposal's text.
#
# Normalisation (CRLF, trailing whitespace, blank-line runs) forgives an
# editor and nothing else: a reworded clause always changes the digest.
#   proposal_hash <file>
proposal_hash() {
  tr -d '\r' < "$1" | sed 's/[[:space:]]*$//' | cat -s | sha256sum | cut -c1-12
}

# B accepts proposal <n> by recording the hash IT computed. B only.
#
# A's acceptance is its authorship — it wrote the proposal — so there is
# no counterpart file for A and nothing for A to sign.
#   delib_accept <dir> <n>
delib_accept() {
  # Derived paths get their own statement: a single `local` does not
  # reliably see the variables it is itself declaring, and the failure is
  # silent — the path expands to `/proposal-.md` and the guard below
  # reports a missing proposal that is sitting right there.
  local dir="$1" n="$2"
  local f="$dir/proposal-$n.md" dest="$dir/proposal-$n.accepted-B"
  [ -f "$f" ] || { printf 'delib: no proposal-%s.md\n' "$n" >&2; return 1; }
  [ -e "$dest" ] && { printf 'delib: proposal %s is already accepted\n' "$n" >&2; return 1; }
  # A verdict is as immutable as a turn. Accepting a version already
  # rejected would leave the proposal carrying both verdicts, and every
  # reader — `delib_next_role`, `delib_finish`, a human — would have to
  # guess which one counts. B revises its mind by accepting A's next
  # version, not by overwriting its last answer.
  [ -e "$dir/proposal-$n.rejected-B.md" ] && { printf 'delib: proposal %s is already rejected\n' "$n" >&2; return 1; }
  proposal_hash "$f" > "$dest.tmp" && mv "$dest.tmp" "$dest"
}

# B rejects proposal <n>, naming the clauses that fail. B only.
#
# A rejection needs a machine-readable artifact for the same reason an
# acceptance does: prose in a turn file tells a reader that B disagreed,
# but nothing in the protocol can see it, so the proposal stays "awaiting
# a verdict" forever and control never returns to A.
#   delib_reject <dir> <n> <source-file>
delib_reject() {
  local dir="$1" n="$2" src="$3"
  local f="$dir/proposal-$n.md" dest="$dir/proposal-$n.rejected-B.md"
  [ -f "$f" ] || { printf 'delib: no proposal-%s.md\n' "$n" >&2; return 1; }
  [ -e "$dir/proposal-$n.accepted-B" ] && { printf 'delib: proposal %s is already accepted\n' "$n" >&2; return 1; }
  [ -e "$dest" ] && { printf 'delib: proposal %s is already rejected\n' "$n" >&2; return 1; }
  cp "$src" "$dest.tmp" && mv "$dest.tmp" "$dest"
}

# Whether proposal <n> stands accepted RIGHT NOW. Prints
# `accepted` | `stale` | `pending`; returns non-zero for the latter two.
#
# `stale` is the case worth having: the proposal was accepted and has
# since changed, so the acceptance no longer covers what the file says.
# Comparing two stored hashes would call that `accepted` forever.
#   proposal_verify <dir> <n>
proposal_verify() {
  local dir="$1" n="$2"
  local f="$dir/proposal-$n.md" a="$dir/proposal-$n.accepted-B" live stored
  [ -f "$f" ] || { printf 'pending\n'; return 1; }
  [ -f "$a" ] || { printf 'pending\n'; return 1; }
  live=$(proposal_hash "$f")
  stored=$(tr -d '[:space:]' < "$a")
  [ "$live" = "$stored" ] && { printf 'accepted\n'; return 0; }
  printf 'stale\n'; return 1
}

# Block until the peer moves, then print ONE line:
#   turn <n> | proposal <n> | accepted <n> | result | timeout
#
# Waits on a condition rather than a duration, and everything it polls
# stays in this subprocess, so a deliberation costs one short line of
# context per round however long the turns are.
#
# The timeout is the peer-absent bound: a peer that never arrives is a
# different failure from a peer that argues to a standstill, and the
# caller must not mistake the first for progress.
#   delib_wait <dir> <after-turn> <after-proposal> [timeout] [interval]
delib_wait() {
  local dir="$1" at="$2" ap="$3"
  local timeout="${4:-${DELIB_PEER_TIMEOUT:-1800}}" interval="${5:-${DELIB_WAIT_INTERVAL:-5}}"
  local deadline t p
  deadline=$(( $(date +%s) + timeout ))
  while :; do
    [ -f "$dir/result.md" ] && { printf 'result\n'; return 0; }
    p=$(delib_proposal_version "$dir")
    if [ "$p" -gt "$ap" ]; then printf 'proposal %s\n' "$p"; return 0; fi
    if [ "$p" -gt 0 ] && [ -f "$dir/proposal-$p.accepted-B" ]; then
      printf 'accepted %s\n' "$p"; return 0
    fi
    if [ "$p" -gt 0 ] && [ -f "$dir/proposal-$p.rejected-B.md" ]; then
      printf 'rejected %s\n' "$p"; return 0
    fi
    t=$(delib_turn "$dir")
    if [ "$t" -gt "$at" ]; then printf 'turn %s\n' "$t"; return 0; fi
    if [ "$(date +%s)" -ge "$deadline" ]; then printf 'timeout\n'; return 0; fi
    sleep "$interval"
  done
}

# Enforce the round cap. Prints the current turn count; returns non-zero
# once it exceeds `DELIB_MAX_ROUNDS` (default 6), so the bound is an exit
# status the caller handles rather than a rule it is trusted to remember.
#   delib_round_guard <dir>
delib_round_guard() {
  local dir="$1" max="${DELIB_MAX_ROUNDS:-6}" n
  n=$(delib_turn "$dir")
  printf '%s\n' "$n"
  [ "$n" -le "$max" ]
}

# Close the deliberation with its result. A only.
#
# The presence of `result.md` is what every other function treats as
# "this is over", so producing it is a state transition and not a file
# write. Guarded, because each way it can be wrong is silent: a result
# over an unaccepted proposal records a decision the peer never agreed
# to; a result over a superseded version records the one B rejected; and
# a second result would quietly replace the first.
#
# `delib_wait` reports `result`, so a peer still waiting learns the
# deliberation ended rather than timing out.
#   delib_finish <dir> <proposal-number> <result-source>
delib_finish() {
  local dir="$1" n="$2" src="$3"
  local dest="$dir/result.md" latest
  [ -e "$dest" ] && { printf 'delib: %s already exists — a deliberation ends once\n' "$dest" >&2; return 1; }
  proposal_verify "$dir" "$n" >/dev/null 2>&1 || {
    printf 'delib: proposal %s is %s, not accepted — nothing to finish\n' \
      "$n" "$(proposal_verify "$dir" "$n" 2>/dev/null)" >&2; return 1; }
  latest=$(delib_proposal_version "$dir")
  [ "$n" = "$latest" ] || {
    printf 'delib: proposal %s is not the latest (%s) — finish the version B accepted last\n' \
      "$n" "$latest" >&2; return 1; }
  cp "$src" "$dest.tmp" && mv "$dest.tmp" "$dest"
}

# Open deliberations for one issue, one path per line.
#
# Scoped to an issue on purpose. The standalone skills never call this —
# A hands B an exact path. It exists for the PR loop pair, where the two
# harnesses share a repository and an issue number but have no other way
# to pass one to each other.
#   delib_open_for_issue <issue>
delib_open_for_issue() {
  local d
  for d in ".stenswf/$1/deliberations"/*; do
    [ -d "$d" ] && [ -f "$d/tension.md" ] && [ ! -f "$d/result.md" ] && printf '%s\n' "$d"
  done
  return 0
}

# Candidate conflicts between a decision and what is already on record.
#
# Prints one `<tier>\t<evidence>` line per candidate. These are
# CANDIDATES: grep narrows the field, the caller judges. Whether one
# decision contradicts another is a question about meaning, and a path
# match cannot answer it.
#
# Anchor hits name the ENTRY whose own `Refs:` carries the path, not every
# active header in a file that happens to mention it — pointing a
# sign-off request at ten unrelated decisions is how a real contradiction
# gets waved through.
#   delib_contradictions <issue> <file-with-refs>
delib_contradictions() {
  local issue="$1" src="$2" refs p f hit
  refs=$(awk '/^#+ Refs[[:space:]]*$/{flag=1;next} /^#+ /{flag=0} flag' "$src" \
         | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
         | grep -E '/|\.' | grep -v '^delib#' | grep -v '^$' || true)
  [ -n "$refs" ] || return 0

  while IFS= read -r p; do
    [ -n "$p" ] || continue

    for f in .stenswf/*/decisions.md .stenswf/.archive/*/decisions.md; do
      [ -f "$f" ] || continue
      # Per entry: active header (strikethrough is already retired and
      # cannot be contradicted) whose own body cites this path.
      #
      # `index()`, not `~`: a path is a literal string, and matching it as
      # a regex silently loses every real path containing regex
      # metacharacters — `app/[id]/page.tsx`, `pages/(group)/x.ts`,
      # `lib/a+b.ts`. The path comes in through ENVIRON rather than -v so
      # awk does not process backslash escapes in it either.
      hit=$(dl_path="$p" awk '
        function cites(h, b) { return h ~ /^### D[0-9]+ / && index(b, ENVIRON["dl_path"]) > 0 }
        /^### /   { if (hdr != "" && cites(hdr, body)) print hdr
                    hdr = $0; body = ""; next }
                  { body = body "\n" $0 }
        END       { if (hdr != "" && cites(hdr, body)) print hdr }
      ' "$f" | head -3 | tr '\n' ';')
      [ -n "$hit" ] && printf 'anchor\t%s — %s\n' "$f" "$hit"
    done

    for f in docs/stenswf/decisions/*.md; do
      [ -f "$f" ] || continue
      grep -Fq -- "$p" "$f" && printf 'committed\t%s references %s\n' "$f" "$p"
    done

    # Grep, never `git interpret-trailers`: a squash concatenates messages
    # and the trailer parser only reads the last paragraph.
    #
    # `--fixed-strings`, so the whole pattern is literal — which means the
    # `^Touches:` anchor goes with it and this matches the path anywhere
    # in a commit message, not only in a trailer. That is the right trade:
    # over-reporting costs A one judgement call, while under-reporting
    # walks a real contradiction past a mandatory human sign-off.
    hit=$(git log --fixed-strings --grep="$p" --format='%h %s' 2>/dev/null | head -3 | tr '\n' ';')
    [ -n "$hit" ] && printf 'git\t%s in commit message — %s\n' "$p" "$hit"
  done <<EOF
$refs
EOF

  for f in CLAUDE.md AGENTS.md ".stenswf/$issue/conventions.md"; do
    [ -f "$f" ] && printf 'house\t%s — read before overruling\n' "$f"
  done
  return 0
}
