# Wayfinder tracker plumbing — canonical shell library for the `wayfinder`
# skill's concurrency-sensitive operations.
#
# Sourced, not executed. From a skill directory:
#   source ../../scripts/wayfinder.sh
#
# Templates, the frontier query, and the map's local-tree seed live in
# ../references/wayfinder-map.md. Function bodies below are the single
# source of truth — do not duplicate them.
#
# The map lives on the issue tracker and several sessions may work it at
# once, so every function here assumes a concurrent writer and is safe to
# re-run: claiming detects a collision, the map append verifies it stuck,
# and the handoff generator rebuilds its output from scratch.
#
# All tracker access goes through the `gh` CLI so the host is swappable
# and the functions are testable by injecting a fake `gh` on PATH.

_WF_HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./extractors.sh
. "$_WF_HERE/extractors.sh"

# Repository owner and name, space-separated. Internal helper.
_wf_repo() {
  gh repo view --json owner,name -q '.owner.login + " " + .name'
}

# This session's claim token. Unique per invocation — NOT per GitHub
# user, which is the whole point: two of the same human's sessions
# authenticate identically, so an identity-based token could not tell
# them apart. Overridable so tests can drive a deterministic collision.
_wf_session_id() {
  if [ -n "${STENSWF_SESSION_ID:-}" ]; then
    printf '%s\n' "$STENSWF_SESSION_ID"
  else
    printf 'wf-%s-%s%s\n' "$(date +%s)" "$$" "${RANDOM:-0}"
  fi
}

# The session id of the earliest claim comment on a ticket, or empty when
# there is none. Ordering is by the comment's numeric id: GitHub assigns
# those server-side and monotonically, so every session computes the same
# winner from the same data — unlike `createdAt`, which is only
# second-granular and can tie.
_wf_first_claim() {
  gh issue view "$1" --json comments -q '
    [ .comments[]
      | { n:   (.url  | [scan("issuecomment-([0-9]+)")] | flatten | first // "0" | tonumber),
          sid: (.body | [scan("<!-- stenswf-claim: ([A-Za-z0-9._-]+) -->")] | flatten | first) }
      | select(.sid != null) ]
    | sort_by(.n) | first | .sid // ""'
}

# Claim a ticket for this session. Prints the winning session id and
# returns 0 when we own it; returns non-zero when another session got
# there first, after withdrawing our own claim so the frontier is left
# clean.
#
# Assignment alone cannot do this. GitHub's assignee field is a set with
# no compare-and-set, and when two sessions share one identity the second
# `--add-assignee @me` is a silent no-op that reports success — so the
# loser could not detect the loss by reading assignees. The claim comment
# supplies the missing per-session token and a total order to break the
# tie with. Assignment is kept because it is what a human sees.
#
# Residual window: between our read of the frontier and our claim comment
# landing, another session may claim and start work. That window is
# narrow and the loser detects it on the very next read, but it is not
# zero — the tracker offers no atomic primitive to close it.
#   claim_ticket <ticket>
claim_ticket() {
  local ticket="$1" sid winner
  sid=$(_wf_session_id)
  gh issue edit "$ticket" --add-assignee @me >/dev/null || return 1
  gh issue comment "$ticket" --body "$(printf 'Claiming this ticket for a wayfinder session.\n\n<!-- stenswf-claim: %s -->' "$sid")" >/dev/null || return 1
  winner=$(_wf_first_claim "$ticket")
  if [ "$winner" = "$sid" ]; then
    printf '%s\n' "$sid"
    return 0
  fi
  withdraw_claim "$ticket" "$sid"
  printf 'CLAIM_LOST: #%s is already claimed by session %s — take the next frontier ticket\n' \
    "$ticket" "$winner" >&2
  return 1
}

# Drop this session's claim: delete its claim comment and, only if
# nobody else is left holding the ticket, unassign.
#
# The conditional unassign matters. Two sessions of one human share an
# assignee, so an unconditional `--remove-assignee @me` by the loser
# would strip the WINNER's assignment too — the ticket would then look
# unclaimed to every later session while someone was actively working
# it. Remaining claim comments are what distinguish "nobody holds this"
# from "someone else does".
#   withdraw_claim <ticket> <session-id>
withdraw_claim() {
  local ticket="$1" sid="$2" owner name url cid
  read -r owner name < <(_wf_repo)
  url=$(gh issue view "$ticket" --json comments -q "
    [ .comments[] | select(.body | test(\"<!-- stenswf-claim: $sid -->\")) | .url ]
    | first // \"\"")
  cid=${url##*issuecomment-}
  case "$cid" in
    ''|*[!0-9]*) : ;;   # no comment of ours to delete
    *) gh api -X DELETE "repos/$owner/$name/issues/comments/$cid" >/dev/null 2>&1 ;;
  esac
  if [ -z "$(_wf_first_claim "$ticket")" ]; then
    gh issue edit "$ticket" --remove-assignee @me >/dev/null 2>&1
  fi
  return 0
}

# --- Map-body mutual exclusion -------------------------------------------
# Every write to the map body is a whole-document read-modify-write, and
# the tracker offers no compare-and-set to make one safe. Verifying after
# the write is not enough: a session that read the body before ours can
# land its stale copy AFTER we verified, and both calls report success.
#
# So map-body edits are serialised by a lock built out of the same
# primitive as the ticket claim — post, then read, earliest server-issued
# comment id wins. Because every contender posts before it reads, all of
# them compute the same winner.

_WF_LOCK_TTL=${STENSWF_MAP_LOCK_TTL:-300}

# The session id holding the map lock, ignoring locks older than the TTL
# so a crashed holder cannot block the map forever. A stale comment is
# left in place rather than deleted — deleting another session's comment
# on a guess is worse than a little noise.
_wf_lock_holder() {
  local map="$1" now
  now=$(date +%s)
  gh issue view "$map" --json comments -q "
    [ .comments[]
      | { n:   (.url  | [scan(\"issuecomment-([0-9]+)\")] | flatten | first // \"0\" | tonumber),
          sid: (.body | [scan(\"<!-- stenswf-maplock: ([A-Za-z0-9._-]+) at [0-9]+ -->\")] | flatten | first),
          at:  (.body | [scan(\"<!-- stenswf-maplock: [A-Za-z0-9._-]+ at ([0-9]+) -->\")] | flatten | first // \"0\" | tonumber) }
      | select(.sid != null)
      | select($now - .at < $_WF_LOCK_TTL) ]
    | sort_by(.n) | first | .sid // \"\""
}

# Take the map lock, retrying while another session holds it. Prints the
# lock id to pass back to `release_map_lock`.
acquire_map_lock() {
  local map="$1" sid attempt holder
  sid="lock-$(_wf_session_id)"
  for attempt in 1 2 3 4 5; do
    gh issue comment "$map" \
      --body "$(printf 'Holding the map body for an edit.\n\n<!-- stenswf-maplock: %s at %s -->' "$sid" "$(date +%s)")" \
      >/dev/null || return 1
    holder=$(_wf_lock_holder "$map")
    if [ "$holder" = "$sid" ]; then
      printf '%s\n' "$sid"
      return 0
    fi
    _wf_delete_comments_matching "$map" "stenswf-maplock: $sid"
    sleep "${STENSWF_MAP_LOCK_BACKOFF:-2}"
  done
  printf 'MAP_LOCKED: #%s is held by %s — retry later\n' "$map" "$holder" >&2
  return 1
}

release_map_lock() {
  _wf_delete_comments_matching "$1" "stenswf-maplock: $2"
}

# Run a command holding the map lock, releasing it whatever happens.
#   with_map_lock <map> <command> [args...]
with_map_lock() {
  local map="$1"; shift
  local lock rc
  lock=$(acquire_map_lock "$map") || return 1
  "$@"
  rc=$?
  release_map_lock "$map" "$lock"
  return $rc
}

# Delete every comment on an issue whose body matches a literal marker.
# Internal.
_wf_delete_comments_matching() {
  local issue="$1" marker="$2" owner name url cid
  read -r owner name < <(_wf_repo)
  while :; do
    url=$(gh issue view "$issue" --json comments -q "
      [ .comments[] | select(.body | contains(\"$marker\")) | .url ] | first // \"\"")
    cid=${url##*issuecomment-}
    case "$cid" in
      ''|*[!0-9]*) return 0 ;;
      *) gh api -X DELETE "repos/$owner/$name/issues/comments/$cid" >/dev/null 2>&1 || return 0 ;;
    esac
  done
}

# --- Resolution records ---------------------------------------------------

# Read one key out of a ticket's resolution block. Internal.
_wf_resolution_field() {
  sed -n '/^<!-- stenswf-resolved:v1/,/^-->/p' "$2" \
    | sed -n 's/^'"$1"':[[:space:]]*\(.*\)$/\1/p' \
    | head -1
}

# Has this ticket already been resolved?
#
# Keyed on the resolution marker itself, NOT on the decision fields: a
# `task` ticket resolves without a decision (there was nothing to decide),
# and keying on the decision would make exactly those tickets re-post
# their resolution comment on every retry.
_wf_has_resolution() {
  gh issue view "$1" --json comments -q '
    [ .comments[].body | select(test("<!-- stenswf-resolved:v1")) ] | length' \
    2>/dev/null | grep -qv '^0$'
}

# Is this issue a ticket of THIS map? Internal — the body search that
# finds candidates can false-positive, so every candidate is validated
# against its own front-matter.
_wf_is_ticket_of() {
  local map="$1" body="$2"
  [ "$(get_fm type "$body")" = "wayfinder-ticket" ] || return 1
  [ "$(get_fm map_ref "$body")" = "$map" ] || return 1
}

# The map's RESOLVED tickets as TSV `<number>\t<title>\t<url>`, oldest
# resolution first.
#
# "Resolved" means *carries a resolution block* — not "closed". The two
# differ for exactly one ticket at exactly the moment it matters: the one
# `resolve_ticket` is working on, whose comment has landed but whose close
# comes last, by design. Deriving from `--state closed` would omit that
# ticket from the rebuild it triggered, and since nothing rebuilds after
# the close, its decision would sit on the map only once some *later*
# ticket resolved — leaving every map's final decision missing.
# Sorting on the resolution comment rather than `closedAt` follows from
# the same choice: the comment is what the order is actually about.
#
# Fails loudly rather than truncating: a silently short list would produce
# a map index or an anchor missing decisions, with nothing to indicate it.
_wf_resolved_tickets() {
  local map="$1" limit="${STENSWF_TICKET_LIMIT:-1000}" cands rows jf body rc=0
  local number title url at
  cands=$(gh issue list --state all --limit "$limit" \
    --search "in:body \"Parent map: #$map\"" \
    --json number,title,url \
    -q '.[] | [(.number|tostring), .title, .url] | @tsv') || return 1
  if [ "$(printf '%s\n' "$cands" | grep -c .)" -ge "$limit" ]; then
    printf 'TICKET_LIMIT: map #%s has at least %s tickets — raise STENSWF_TICKET_LIMIT\n' \
      "$map" "$limit" >&2
    return 1
  fi

  rows=$(mktemp) || return 1
  jf=$(mktemp); body=$(mktemp)
  # A ticket that could not be READ and a ticket that is genuinely not a
  # member of this map are indistinguishable downstream — both are simply
  # an absent bullet — so they must not be treated alike here. Deciding to
  # skip is a judgement about content, and it needs the content: only a
  # fetch that SUCCEEDED earns a `continue`. A failed one aborts, because
  # a short list is what turns a rebuild into an erasure.
  while IFS=$'\t' read -r number title url; do
    [ -n "$number" ] || continue
    # One fetch serves both filters — membership reads the body, the sort
    # key reads the comments.
    if ! gh issue view "$number" --json body,comments > "$jf" 2>/dev/null; then
      printf 'TICKET_READ: could not read ticket #%s of map #%s\n' "$number" "$map" >&2
      rc=1; break
    fi
    if ! jq -r '.body // ""' "$jf" > "$body" 2>/dev/null; then
      printf 'TICKET_READ: malformed response for ticket #%s\n' "$number" >&2
      rc=1; break
    fi
    _wf_is_ticket_of "$map" "$body" || continue
    if ! at=$(jq -r '[ .comments[]? | select(.body | test("<!-- stenswf-resolved:v1")) ]
                     | last | .createdAt // ""' "$jf" 2>/dev/null); then
      printf 'TICKET_READ: malformed comments for ticket #%s\n' "$number" >&2
      rc=1; break
    fi
    [ -n "$at" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$at" "$number" "$title" "$url" >> "$rows"
  done <<EOF
$cands
EOF

  [ "$rc" -eq 0 ] && sort "$rows" | cut -f2-
  rm -f "$rows" "$jf" "$body"
  return "$rc"
}

# --- Map index ------------------------------------------------------------

# Rebuild the map body's `## Decisions so far` from the resolved tickets.
#
# The index is DERIVED, not accumulated. Appending a line and hoping it
# sticks cannot be made safe against a concurrent whole-body write; a
# rebuild can, because it converges: whatever a lost update dropped, the
# next rebuild puts back. The lock makes a clobber unlikely, and this
# makes one survivable.
#
# Call it through `with_map_lock` — `sync_map_index` is the locked entry
# point below.
_wf_sync_map_index() {
  local map="$1" cur bullets hf kf tf out block cands rc
  local ticket title url gist
  cur=$(mktemp); bullets=$(mktemp); block=$(mktemp); cands=$(mktemp)
  hf=$(mktemp); kf=$(mktemp); tf=$(mktemp); out=$(mktemp)
  _wf_tmp="$cur $bullets $block $cands $hf $kf $tf $out"

  if ! gh issue view "$map" --json body -q .body > "$cur"; then
    rm -f $_wf_tmp
    return 1
  fi

  # Materialised, and the failure checked, BEFORE the rebuild starts. Read
  # through a process substitution the ticket query's exit status is lost,
  # and a query that failed — a hit ticket limit, a network blip — reads as
  # "this map has no decisions", which would replace a full index with an
  # empty one and report success.
  if ! _wf_resolved_tickets "$map" > "$cands"; then
    rm -f $_wf_tmp
    return 1
  fi

  while IFS=$'\t' read -r ticket title url; do
    [ -n "$ticket" ] || continue
    # The gist has to be read, not guessed. Falling back to the placeholder
    # on a FAILED read would quietly overwrite a real one-line summary with
    # the word "resolved" — a rebuild that loses information while looking
    # like it worked.
    if ! gh issue view "$ticket" --json comments -q '
      [ .comments[].body | select(test("<!-- stenswf-resolved:v1")) ] | last // ""' \
      > "$block" 2>/dev/null; then
      printf 'TICKET_READ: could not read the resolution of ticket #%s\n' "$ticket" >&2
      rm -f $_wf_tmp
      return 1
    fi
    gist=$(_wf_resolution_field gist "$block")
    printf -- '- [%s](%s) — %s\n' "$title" "$url" "${gist:-resolved}" >> "$bullets"
  done < "$cands"

  # Split the body around the section. Prose and comments a human put
  # there are kept; only the bullet list is replaced.
  awk -v h="$hf" -v k="$kf" -v t="$tf" '
    part==0 { print > h; if ($0 ~ /^## Decisions so far[ \t]*$/) part=1; next }
    part==1 {
      if ($0 ~ /^## /) { part=2; print > t; next }
      if ($0 ~ /^-[ \t]/) next
      if ($0 ~ /^[ \t]*$/) next
      print > k; next
    }
    { print > t }
  ' "$cur"

  {
    cat "$hf"
    grep -q '^## Decisions so far' "$hf" || printf '\n## Decisions so far\n'
    if [ -s "$kf" ]; then printf '\n'; cat "$kf"; fi
    printf '\n'
    cat "$bullets"
    if [ -s "$tf" ]; then printf '\n'; cat "$tf"; fi
  } > "$out"

  gh issue edit "$map" --body-file "$out"
  rc=$?
  rm -f $_wf_tmp
  return $rc
}

# Rebuild the map index under the map lock.
#   sync_map_index <map>
sync_map_index() {
  with_map_lock "$1" _wf_sync_map_index "$1"
}

# --- Resolution -----------------------------------------------------------

# Record a ticket's resolution: comment, map index, then close — in that
# order, with the close LAST.
#
# The order is the durability guarantee, which is why it is a function
# and not a numbered list someone follows. Closing first would drop the
# ticket off the frontier while its decision might still be missing from
# the map, leaving no signal that anything is owed. Closing last means a
# failure at any step leaves the ticket open, visible, and retryable —
# and every earlier step checks for its own effect before repeating it,
# so the retry is a no-op where the write already landed.
#   resolve_ticket <map> <ticket> <resolution-body-file>
resolve_ticket() {
  local map="$1" ticket="$2" resolution="$3"
  if ! _wf_has_resolution "$ticket"; then
    gh issue comment "$ticket" --body-file "$resolution" >/dev/null || return 1
  fi
  sync_map_index "$map" || return 1
  gh issue close "$ticket" >/dev/null || return 1
}

# --- Handoff --------------------------------------------------------------

# Generate `.stenswf/<map>/decisions.md` from the map's resolved tickets.
#
# The anchor is built ONCE, here, at handoff — it is not appended to as
# each ticket resolves. The tracker is the map's only live state, so the
# anchor is a derived artifact: regenerating it is always safe and
# parallel sessions never write to the same local file. Entries come out
# in resolution order and are numbered D1..Dn locally, per the Decision
# Anchor Contract.
#
# The file is assembled in a temporary and renamed into place, so a crash
# leaves the previous anchor intact rather than a truncated one.
#   generate_decisions <map>
generate_decisions() {
  local map="$1"
  local out=".stenswf/$map/decisions.md"
  local cands comment tmp n ticket title url dtitle category rationale refs

  cands=$(mktemp) || return 1
  _wf_resolved_tickets "$map" > "$cands" || { rm -f "$cands"; return 1; }

  mkdir -p ".stenswf/$map"
  # Alongside the destination, not in /tmp: `mv` is atomic only within one
  # filesystem, and a workspace on a different mount than /tmp would turn
  # the rename into a copy that a crash can truncate — the very failure the
  # temp file exists to prevent.
  tmp=$(mktemp ".stenswf/$map/.decisions.XXXXXX") || { rm -f "$cands"; return 1; }
  {
    printf '# Decisions — #%s\n\n' "$map"
    printf '<!-- Generated by wayfinder at handoff from the map'\''s resolved tickets.\n'
    printf '     Schema: plugins/stenswf/README.md#decision-anchor-contract -->\n'
  } > "$tmp"

  comment=$(mktemp)
  n=0
  while IFS=$'\t' read -r ticket title url; do
    [ -n "$ticket" ] || continue
    # Abort, don't skip. An anchor missing an entry reads exactly like an
    # effort that never made that decision, and it is the durable record
    # a PRD is written from — better no new anchor than a plausible one
    # with a hole in it.
    if ! gh issue view "$ticket" --json comments -q '
      [ .comments[].body | select(test("<!-- stenswf-resolved:v1")) ] | last // ""' \
      > "$comment" 2>/dev/null; then
      printf 'TICKET_READ: could not read the resolution of ticket #%s\n' "$ticket" >&2
      rm -f "$cands" "$comment" "$tmp"
      return 1
    fi
    [ -s "$comment" ] || continue

    category=$(_wf_resolution_field category "$comment")
    rationale=$(_wf_resolution_field rationale "$comment")
    # A ticket that decided nothing — a `task` — is resolved but is not
    # an anchor entry. Both fields are what make it one.
    [ -n "$category" ] && [ -n "$rationale" ] || continue

    refs=$(_wf_resolution_field refs "$comment")
    dtitle=$(_wf_resolution_field title "$comment")
    [ -n "$dtitle" ] || dtitle="$title"

    n=$((n + 1))
    {
      printf '\n### D%d — %s\n\n' "$n" "$dtitle"
      printf -- '- **Category:** %s\n' "$category"
      printf -- '- **Source:** wayfinder\n'
      printf -- '- **Rationale:** %s\n' "$rationale"
      printf -- '- **Refs:** #%s%s\n' "$ticket" "${refs:+, $refs}"
    } >> "$tmp"
  done < "$cands"

  mv "$tmp" "$out"
  rm -f "$cands" "$comment"
  printf '%s\n' "$out"
  [ "$n" -gt 0 ]
}
