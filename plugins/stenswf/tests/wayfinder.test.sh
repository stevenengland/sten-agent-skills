#!/usr/bin/env bash
# Behavior tests for the wayfinder tracker plumbing.
#
# Exercises scripts/wayfinder.sh through the `gh` seam. The fake `gh`
# keeps issue bodies, comments, assignees and state in files under a
# temp dir, so two "sessions" can race the same ticket and the same map
# body the way two real sessions do — including the case that matters
# most here, where both authenticate as the SAME GitHub user and neither
# assignment nor identity can tell them apart.
#
# Run:  bash plugins/stenswf/tests/wayfinder.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPTS="$HERE/../scripts"

# shellcheck source=../scripts/wayfinder.sh
source "$SCRIPTS/wayfinder.sh"

PASS=0
FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()      { [ "$2" = "$3" ]  && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
assert_match()   { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || { fail "$1"; printf '    missing %q in: %s\n' "$3" "$2"; }; }
assert_nomatch() { printf '%s' "$2" | grep -qF -- "$3" && { fail "$1"; printf '    unexpected %q in: %s\n' "$3" "$2"; } || ok "$1"; }

# Retries and backoff are exercised, not slept through.
export STENSWF_MAP_LOCK_BACKOFF=0

# --- Fake gh harness -------------------------------------------------------
WORK=$(mktemp -d)
ORIG=$PWD
trap 'cd "$ORIG"; rm -rf "$WORK"' EXIT

cat > "$WORK/gh" <<'GHEOF'
#!/usr/bin/env bash
# Minimal fake gh for issue/tracker operations, backed by files in $WFT.
D="$WFT"
printf '%s\n' "$1 $2" >> "$D/calls"

# The value of the -q/--jq flag, if any.
qexpr() { local prev=""; for a in "$@"; do case "$prev" in -q|--jq) printf '%s' "$a"; return;; esac; prev="$a"; done; }
# The value of a --flag that takes an argument.
flagval() { local want="$1" prev=""; shift; for a in "$@"; do [ "$prev" = "$want" ] && { printf '%s' "$a"; return; }; prev="$a"; done; }

case "$1 $2" in
  "repo view") echo "octo-org octo-repo" ;;

  "issue view")
    n=$3
    # Two ways a read can fail: the whole ticket, or just the fetch of its
    # resolution comment. They abort different parts of the plumbing.
    [ -f "$D/read-fails-$n" ] && { echo "fake gh: read failed" >&2; exit 1; }
    if printf '%s' "$*" | grep -q -- '--json body,comments'; then
      # One fetch serving both the membership filter and the sort key.
      [ -f "$D/body-$n.md" ] || exit 1
      q=$(qexpr "$@")
      jq -n --rawfile b "$D/body-$n.md" --slurpfile c "$D/comments-$n.json" \
        '{body: $b, comments: $c[0]}' | { [ -n "$q" ] && jq -r "$q" || cat; }
    elif printf '%s' "$*" | grep -q -- '--json comments'; then
      [ -f "$D/block-fails-$n" ] && { echo "fake gh: comment read failed" >&2; exit 1; }
      jq -n --slurpfile c "$D/comments-$n.json" '{comments: $c[0]}' \
        | jq -r "$(qexpr "$@")"
    else
      cat "$D/body-$n.md"
    fi ;;

  "issue comment")
    n=$3
    body=$(flagval --body "$@")
    if [ -z "$body" ]; then bf=$(flagval --body-file "$@"); body=$(cat "$bf"); fi
    id=$(( $(cat "$D/next-comment-id") ))
    echo $((id + 1)) > "$D/next-comment-id"
    # Server-assigned timestamps advance with the id, as the real ones do:
    # resolution order is read off these.
    s=$((id - 1000))
    at=$(printf '2026-07-20T11:%02d:%02dZ' $((s / 60)) $((s % 60)))
    jq --arg b "$body" --arg u "https://x/issues/$n#issuecomment-$id" --arg t "$at" \
       '. + [{url: $u, body: $b, createdAt: $t}]' "$D/comments-$n.json" > "$D/t" \
       && mv "$D/t" "$D/comments-$n.json"
    echo "https://x/issues/$n#issuecomment-$id" ;;

  "issue edit")
    n=$3
    if bf=$(flagval --body-file "$@"); [ -n "$bf" ]; then
      if [ -f "$D/clobber-once" ]; then
        # Simulate a concurrent session whose whole-body write lands on
        # top of ours: our edit is silently discarded exactly once.
        rm -f "$D/clobber-once"
      else
        cp "$bf" "$D/body-$n.md"
      fi
    fi
    # Assignees are a SET, as on GitHub: a second add by the same identity
    # is a silent no-op that still reports success.
    if a=$(flagval --add-assignee "$@"); [ -n "$a" ]; then
      grep -qxF "$a" "$D/assignees-$n" 2>/dev/null || echo "$a" >> "$D/assignees-$n"
    fi
    if r=$(flagval --remove-assignee "$@"); [ -n "$r" ]; then
      grep -vxF "$r" "$D/assignees-$n" > "$D/t" 2>/dev/null; mv "$D/t" "$D/assignees-$n"
    fi ;;

  "issue close") echo "CLOSED" > "$D/state-$3" ;;

  "issue list")
    # The map's tickets in EVERY state — which state a ticket is in is not
    # what makes it indexable; carrying a resolution block is.
    [ -f "$D/list-fails" ] && { echo "fake gh: issue list failed" >&2; exit 1; }
    jq -r "$(qexpr "$@")" "$D/ticket-list.json" ;;

  "api -X"|"api DELETE")
    # gh api -X DELETE repos/o/r/issues/comments/<id>
    target=${!#}; target=${target##*/}
    for f in "$D"/comments-*.json; do
      jq --arg id "$target" 'map(select((.url | endswith("issuecomment-" + $id)) | not))' \
        "$f" > "$D/t" && mv "$D/t" "$f"
    done ;;

  *) echo "fake gh: unhandled: $*" >&2; exit 3 ;;
esac
GHEOF
chmod +x "$WORK/gh"
PATH="$WORK:$PATH"
export WFT="$WORK"
: > "$WORK/calls"
echo 1000 > "$WORK/next-comment-id"

# The map. Decisions-so-far carries the template's HTML comment and a
# section follows it, so a rebuild has to land in the right place and
# preserve prose it did not write.
cat > "$WORK/body-41.md" <<'MD'
<!-- stenswf:v1
type: wayfinder
-->

## Destination

Enough clarity to write the PRD.

## Decisions so far

<!-- the index — rebuilt from the resolved tickets -->

## Not yet specified

- how the loops wake up
MD
echo '[]' > "$WORK/comments-41.json"

mk_ticket() {   # mk_ticket <n> <ticket_type>
  cat > "$WORK/body-$1.md" <<MD
<!-- stenswf:v1
type: wayfinder-ticket
ticket_type: $2
map_ref: 41
-->

Parent map: #41

## Question

Question $1?
MD
  echo '[]' > "$WORK/comments-$1.json"
  : > "$WORK/assignees-$1"
  echo "OPEN" > "$WORK/state-$1"
}
mk_ticket 47 grilling
mk_ticket 48 grilling
mk_ticket 49 task

# Every ticket of the map, in whatever state — because what makes a ticket
# indexable is carrying a resolution block, not being closed. Seeded once:
# the tests move tickets through resolution, and the query sees them all
# throughout, exactly as the real one does.
cat > "$WORK/ticket-list.json" <<'JSON'
[
  {"number": 47, "title": "Which wake-up mechanism?", "url": "https://x/47"},
  {"number": 48, "title": "How is a ticket claimed?",  "url": "https://x/48"},
  {"number": 49, "title": "Provision API access",      "url": "https://x/49"}
]
JSON

# --- claim: two sessions, ONE GitHub identity ------------------------------
# Both sessions run `--add-assignee @me` successfully, so the assignee
# list cannot identify a loser. The claim comment supplies the per-session
# token, and the earliest one wins.
winner=$(STENSWF_SESSION_ID=sess-a claim_ticket 47)
assert_eq "the first session wins the claim" "$winner" "sess-a"

loser_out=$(STENSWF_SESSION_ID=sess-b claim_ticket 47 2>&1)
rc=$?
[ "$rc" -ne 0 ] && ok "the second session's claim fails" || fail "the second session's claim fails"
assert_match "the loser is told who holds the ticket" "$loser_out" "sess-a"

claims=$(cat "$WORK/comments-47.json")
assert_match "the winner's claim comment stays"      "$claims" "stenswf-claim: sess-a"
assert_nomatch "the loser withdrew its claim comment" "$claims" "stenswf-claim: sess-b"

# The loser must not strip the assignment it shares with the winner.
assert_eq "the winner is still assigned after the loser withdraws" \
  "$(grep -c '@me' "$WORK/assignees-47")" "1"

# --- map lock: mutual exclusion over the whole body ------------------------
# Verifying after a write cannot stop a stale whole-body write that lands
# AFTER the verify. Serialising the writes can.
lock_a=$(STENSWF_SESSION_ID=sess-a acquire_map_lock 41)
assert_eq "a session takes the map lock" "$lock_a" "lock-sess-a"

STENSWF_SESSION_ID=sess-b acquire_map_lock 41 >/dev/null 2>&1 \
  && fail "a second session cannot take a held lock" \
  || ok "a second session cannot take a held lock"
assert_nomatch "the blocked session left no lock comment behind" \
  "$(cat "$WORK/comments-41.json")" "lock-sess-b"

release_map_lock 41 "$lock_a"
assert_nomatch "releasing removes the lock comment" \
  "$(cat "$WORK/comments-41.json")" "stenswf-maplock"

lock_b=$(STENSWF_SESSION_ID=sess-b acquire_map_lock 41)
assert_eq "the lock is takeable once released" "$lock_b" "lock-sess-b"
release_map_lock 41 "$lock_b"

# A crashed holder must not block the map forever.
jq --arg b "stale holder

<!-- stenswf-maplock: lock-sess-dead at 1 -->" \
   '. + [{url: "https://x/issues/41#issuecomment-900", body: $b}]' \
   "$WORK/comments-41.json" > "$WORK/t" && mv "$WORK/t" "$WORK/comments-41.json"
lock_c=$(STENSWF_SESSION_ID=sess-c acquire_map_lock 41)
assert_eq "a lock older than the TTL is ignored" "$lock_c" "lock-sess-c"
release_map_lock 41 "$lock_c"

# --- map index: derived from the tracker, so it converges ------------------
resolution() {   # resolution <file> <gist> [category] [title] [rationale]
  { printf '%s\n\n<!-- stenswf-resolved:v1\ngist: %s\n' "Full prose answer." "$2"
    [ -n "${3:-}" ] && printf 'category: %s\ntitle: %s\nrationale: %s\nrefs: scripts/wayfinder.sh\n' "$3" "$4" "$5"
    printf -- '-->\n'
  } > "$1"
}
resolution "$WORK/r47.md" "block on a condition, not a duration" \
  arch "Wake the loops on a condition" "A blind sleep wakes with nothing to do."
resolution "$WORK/r48.md" "earliest claim comment wins" \
  arch "Arbitrate claims by claim comment" "Assignment has no compare-and-set."
resolution "$WORK/r49.md" "access provisioned"          # a task: no decision

gh issue comment 47 --body-file "$WORK/r47.md" >/dev/null
gh issue comment 48 --body-file "$WORK/r48.md" >/dev/null

sync_map_index 41
body=$(cat "$WORK/body-41.md")
assert_match "the index lists the first resolved ticket"  "$body" "block on a condition, not a duration"
assert_match "the index lists the second resolved ticket" "$body" "earliest claim comment wins"
assert_match "prose already in the section is preserved" "$body" "<!-- the index — rebuilt from the resolved tickets -->"
assert_match "the following section survives"            "$body" "## Not yet specified"
assert_eq "the bullets land inside Decisions so far" \
  "$(awk '/^## Decisions so far/{f=1;next} /^## /{f=0} f&&/^- /{n++} END{print n+0}' "$WORK/body-41.md")" "2"

sync_map_index 41
assert_eq "re-syncing does not duplicate entries" \
  "$(grep -c 'earliest claim comment wins' "$WORK/body-41.md")" "1"

# A stale whole-body write landing after another session verified its own
# is the case a verify-after-write cannot catch. A derived index does not
# need to catch it: the next rebuild puts back whatever was dropped.
awk '!/earliest claim comment wins/' "$WORK/body-41.md" > "$WORK/t" && mv "$WORK/t" "$WORK/body-41.md"
assert_nomatch "a concurrent write drops an entry" "$(cat "$WORK/body-41.md")" "earliest claim comment wins"
sync_map_index 41
assert_match "the next sync restores the lost entry" \
  "$(cat "$WORK/body-41.md")" "earliest claim comment wins"

# --- a failed ticket query must not read as "this map decided nothing" -----
# The rebuild replaces the whole bullet list, so the query's failure has to
# stop it. Consumed through a pipe that failure is invisible, and an empty
# result is indistinguishable from a map with no decisions — one blip would
# erase the index and report success.
count_bullets() { awk '/^## Decisions so far/{f=1;next} /^## /{f=0} f&&/^- /{n++} END{print n+0}' "$WORK/body-41.md"; }
before=$(count_bullets)
: > "$WORK/list-fails"
sync_map_index 41 2>/dev/null \
  && fail "sync_map_index fails when the ticket query does" \
  || ok "sync_map_index fails when the ticket query does"
rm -f "$WORK/list-fails"
assert_eq "a failed query leaves the index intact" "$(count_bullets)" "$before"

# The same argument one level down. A ticket that could not be READ looks
# exactly like a ticket that was never a member of this map — both are an
# absent bullet — so a read failure must abort rather than skip, or the
# rebuild quietly replaces a complete index with a partial one.
: > "$WORK/read-fails-48"
sync_map_index 41 2>/dev/null \
  && fail "sync_map_index fails when a ticket cannot be read" \
  || ok "sync_map_index fails when a ticket cannot be read"
rm -f "$WORK/read-fails-48"
assert_eq "an unreadable ticket leaves the index intact" "$(count_bullets)" "$before"

# And once more for the gist itself: a failed read must not fall through to
# the "resolved" placeholder, which would overwrite a real summary with a
# word that says nothing, while reporting success.
: > "$WORK/block-fails-48"
sync_map_index 41 2>/dev/null \
  && fail "sync_map_index fails when a resolution cannot be read" \
  || ok "sync_map_index fails when a resolution cannot be read"
rm -f "$WORK/block-fails-48"
assert_eq "no placeholder gist replaces a real one" "$(count_bullets)" "$before"
assert_match "the real gist is still there" \
  "$(cat "$WORK/body-41.md")" "earliest claim comment wins"

# --- resolve ordering: the close is LAST ----------------------------------
: > "$WORK/calls"
resolve_ticket 41 47 "$WORK/r47.md"
assert_eq "resolve_ticket closes the ticket last" "$(tail -1 "$WORK/calls")" "issue close"
assert_eq "the ticket ends up closed" "$(cat "$WORK/state-47")" "CLOSED"

# A failure before the close must leave the ticket open and retryable.
echo "OPEN" > "$WORK/state-47"
: > "$WORK/calls"
mv "$WORK/body-41.md" "$WORK/body-41.saved"        # make the map unreadable
resolve_ticket 41 47 "$WORK/r47.md" 2>/dev/null \
  && fail "a failed map write aborts the resolution" || ok "a failed map write aborts the resolution"
assert_eq "the ticket stays open when the map write fails" "$(cat "$WORK/state-47")" "OPEN"
assert_nomatch "no close was issued" "$(cat "$WORK/calls")" "issue close"
mv "$WORK/body-41.saved" "$WORK/body-41.md"

assert_eq "the resolution comment was posted once" \
  "$(jq '[.[] | select(.body | test("stenswf-resolved:v1"))] | length' "$WORK/comments-47.json")" "1"

# --- a TASK resolution is idempotent too ----------------------------------
# Task tickets resolve without a decision block by design. Keying "already
# resolved?" on the decision rather than the resolution would make exactly
# these tickets re-post their comment on every retry.
resolve_ticket 41 49 "$WORK/r49.md"
resolve_ticket 41 49 "$WORK/r49.md"
assert_eq "retrying a task resolution posts one comment" \
  "$(jq '[.[] | select(.body | test("stenswf-resolved:v1"))] | length' "$WORK/comments-49.json")" "1"
assert_match "a task still reaches the map index" \
  "$(cat "$WORK/body-41.md")" "access provisioned"

# --- generate_decisions: derived, filtered, and atomic --------------------
cd "$WORK"
out=$(generate_decisions 41)
cd "$ORIG"
assert_eq "generate_decisions writes the map's anchor" "$out" ".stenswf/41/decisions.md"
anchor=$(cat "$WORK/.stenswf/41/decisions.md")
assert_match "entries are numbered locally from D1" "$anchor" "### D1 — Wake the loops on a condition"
assert_match "entries follow resolution order"      "$anchor" "### D2 — Arbitrate claims by claim comment"
assert_match "the category is carried through"      "$anchor" "**Category:** arch"
assert_match "the rationale is carried through"     "$anchor" "blind sleep wakes with nothing to do"
assert_match "refs cite the ticket and the files"   "$anchor" "**Refs:** #48, scripts/wayfinder.sh"
assert_nomatch "a task contributes no anchor entry" "$anchor" "Provision API access"
assert_eq "only the deciding tickets are entries" \
  "$(grep -c '^### D' "$WORK/.stenswf/41/decisions.md")" "2"

# Regenerating is safe — the anchor is derived, never appended to.
cd "$WORK"; generate_decisions 41 >/dev/null; cd "$ORIG"
assert_eq "regenerating does not duplicate entries" \
  "$(grep -c '^### D' "$WORK/.stenswf/41/decisions.md")" "2"

# A run that fails must leave the previous anchor intact, not a truncated
# one — which is why the file is assembled elsewhere and renamed in.
cd "$WORK"
STENSWF_TICKET_LIMIT=1 generate_decisions 41 >/dev/null 2>&1 \
  && fail "generate_decisions fails when the ticket list is truncated" \
  || ok "generate_decisions fails when the ticket list is truncated"
cd "$ORIG"
assert_eq "a failed run leaves the previous anchor intact" \
  "$(grep -c '^### D' "$WORK/.stenswf/41/decisions.md")" "2"

# An anchor with a hole in it reads exactly like an effort that never made
# that decision — and it is the durable record a PRD gets written from.
# Better no new anchor than a plausible one that is missing an entry.
cd "$WORK"
: > "$WORK/block-fails-48"
generate_decisions 41 >/dev/null 2>&1 \
  && fail "generate_decisions fails when a resolution cannot be read" \
  || ok "generate_decisions fails when a resolution cannot be read"
rm -f "$WORK/block-fails-48"
cd "$ORIG"
assert_eq "an unreadable resolution leaves the previous anchor intact" \
  "$(grep -c '^### D' "$WORK/.stenswf/41/decisions.md")" "2"
assert_eq "and leaves no half-written temporary behind" \
  "$(find "$WORK/.stenswf/41" -name '.decisions.*' | wc -l)" "0"

# --- the ticket being resolved appears in its OWN rebuild ------------------
# `resolve_ticket` syncs the index before it closes — that ordering is the
# durability guarantee. An index derived from *closed* tickets would then
# omit the very decision that triggered the rebuild, and nothing rebuilds
# after the close: each map's newest decision would surface only when some
# later ticket resolved, and its last decision never.
mk_ticket 50 grilling
jq '. + [{number: 50, title: "How does the index stay honest?", url: "https://x/50"}]' \
  "$WORK/ticket-list.json" > "$WORK/t" && mv "$WORK/t" "$WORK/ticket-list.json"
resolution "$WORK/r50.md" "derive the index from resolved, not closed, tickets" \
  arch "Derive the index from resolution blocks" \
  "Closing last leaves the resolver open during its own rebuild."
assert_eq "the ticket is open when its rebuild runs" "$(cat "$WORK/state-50")" "OPEN"
resolve_ticket 41 50 "$WORK/r50.md"
assert_match "the just-resolved ticket is in the index it triggered" \
  "$(cat "$WORK/body-41.md")" "derive the index from resolved, not closed, tickets"
assert_eq "and the close still lands afterwards" "$(cat "$WORK/state-50")" "CLOSED"

# --- summary ---------------------------------------------------------------
printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
