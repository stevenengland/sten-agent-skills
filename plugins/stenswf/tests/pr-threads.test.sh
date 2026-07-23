#!/usr/bin/env bash
# Behavior tests for the PR-thread plumbing.
#
# Exercises scripts/pr-threads.sh through the `gh` seam: a fake `gh` on
# PATH records what each function sends and returns canned responses, so
# the tests observe real behavior without a live GitHub PR. The fake
# keeps its threads in a mutable JSON file, so a reply or a resolve is
# observable by a LATER list call — that round trip is the point, not an
# incidental convenience: the loops converge on what the shared reader
# can see, not on what a writer believed it sent.
#
# Run:  bash plugins/stenswf/tests/pr-threads.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPTS="$HERE/../scripts"

# shellcheck source=../scripts/extractors.sh
source "$SCRIPTS/extractors.sh"
# shellcheck source=../scripts/pr-threads.sh
source "$SCRIPTS/pr-threads.sh"

PASS=0
FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()      { [ "$2" = "$3" ]  && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
assert_ne()      { [ "$2" != "$3" ] && ok "$1" || { fail "$1"; printf '    both were: %s\n' "$2"; }; }
assert_match()   { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || { fail "$1"; printf '    missing %q in: %s\n' "$3" "$2"; }; }
assert_nomatch() { printf '%s' "$2" | grep -qF -- "$3" && { fail "$1"; printf '    unexpected %q in: %s\n' "$3" "$2"; } || ok "$1"; }

# --- Fake gh harness -------------------------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STATE="$WORK/review-decision"     # holds the PR reviewDecision
POSTED="$WORK/posted-body"        # captures the body add_thread sends
REPLIED="$WORK/reply-body"        # captures the body add_reply sends
RESOLVED="$WORK/resolved-flag"    # touched when resolve_thread runs
THREADS="$WORK/threads.json"      # the fake PR's mutable thread store
PAGE0="$WORK/page0-calls"         # counts first-page list requests
HEADOID="$WORK/head-oid"          # the PR's headRefOid (remote)
HEADREF="$WORK/head-ref"          # the PR's headRefName
CLOSES="$WORK/closes"             # closingIssuesReferences numbers
AUTHOR="$WORK/pr-author"          # the PR's author login
ME="$WORK/me"                     # the login `gh` is authenticated as
PRCOMMENTS="$WORK/pr-comments"    # top-level PR comment bodies
BRANCH="$WORK/local-branch"       # the working tree's branch
LOCALSHA="$WORK/local-sha"        # the working tree's HEAD

printf 'REVIEW_REQUIRED' > "$STATE"
printf 'sha-base\n'      > "$HEADOID"
printf 'feature-branch\n' > "$HEADREF"
printf 'feature-branch\n' > "$BRANCH"
printf 'sha-base\n'      > "$LOCALSHA"
printf '121\n'           > "$CLOSES"
printf '0\n'             > "$PAGE0"
printf 'pr-author\n'     > "$AUTHOR"
printf 'reviewer-bot\n'  > "$ME"
: > "$PRCOMMENTS"

# Four threads: reviewer-open, human-open, one already resolved that
# still carries a fingerprint (the dedup set must not forget it), and one
# deep enough that its disposition is not in the newest page of replies.
cat > "$THREADS" <<'JSON'
[
  {"id":"RT_open","isResolved":false,"author":"reviewer-bot",
   "body":"null deref here\n\n<!-- stenswf-fp: deadbeef0001 -->","replies":[]},
  {"id":"RT_human","isResolved":false,"author":"human-dev",
   "body":"prefer a guard clause\n\n<!-- stenswf-fp: deadbeef0002 -->","replies":[]},
  {"id":"RT_done","isResolved":true,"author":"human",
   "body":"already fixed\n\n<!-- stenswf-fp: deadbeef0003 -->","replies":[]},
  {"id":"RT_deep","isResolved":false,"author":"reviewer-bot",
   "body":"chatty thread\n\n<!-- stenswf-fp: deadbeef0004 -->",
   "replies":["verified: out of scope\n\n<!-- stenswf-left-open: out-of-scope -->",
              "ack","and one more"]}
]
JSON

# A fake git, so branch/HEAD/fetch assertions do not depend on the real
# repository the suite happens to run in.
cat > "$WORK/git" <<GITEOF
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --abbrev-ref HEAD") cat "$BRANCH" ;;
  "rev-parse HEAD")              cat "$LOCALSHA" ;;
  # What the PR ref resolved to. Normally the PR head; the suite can point
  # it elsewhere to stand in for a ref that fetched the wrong commit.
  "rev-parse FETCH_HEAD")        cat "$WORK/fetched" 2>/dev/null || cat "$HEADOID" ;;
  fetch*)
    # Only the PR ref is fetchable — a fork's branch name is not on origin,
    # and this suite must notice if the plumbing goes back to asking for it.
    # The number in it must be a NUMBER: an unnormalised PR URL builds
    # refs/pull/https:/github.com/o/r/pull/77/head, which a real remote
    # rejects and a lenient fake would wave through.
    ref=\${!#}
    case "\$ref" in
      refs/pull/*[!0-9]*/head) echo "fake git: malformed ref: \$ref" >&2; exit 1 ;;
      refs/pull/*/head)        exit 0 ;;
      *) echo "fake git: no such ref: \$ref" >&2; exit 1 ;;
    esac ;;
  "merge-base --is-ancestor "*)
    # Fast-forwardable exactly when the suite says so.
    [ -f "$WORK/diverged" ] && exit 1 || exit 0 ;;
  "merge --ff-only "*)
    target=\${!#}; printf '%s\n' "\$target" > "$LOCALSHA" ;;
  *) echo "fake git: unhandled: \$*" >&2; exit 3 ;;
esac
GITEOF
chmod +x "$WORK/git"

cat > "$WORK/gh" <<GHEOF
#!/usr/bin/env bash
# Minimal fake gh. Branches on the sub-command and flags the plumbing uses.
STATE="$STATE"; POSTED="$POSTED"; REPLIED="$REPLIED"; RESOLVED="$RESOLVED"
THREADS="$THREADS"; PAGE0="$PAGE0"; HEADOID="$HEADOID"; HEADREF="$HEADREF"
CLOSES="$CLOSES"; WORK="$WORK"; AUTHOR="$AUTHOR"; ME="$ME"
PRCOMMENTS="$PRCOMMENTS"
args="\$*"

# Pull a named parameter out of the gh invocation (-f k=v / -F k=v).
param() { for a in "\$@"; do case "\$a" in \$1=*) printf '%s' "\${a#\$1=}"; return;; esac; done; }
flagval() { local want="\$1" prev=""; shift; for a in "\$@"; do [ "\$prev" = "\$want" ] && { printf '%s' "\$a"; return; }; prev="\$a"; done; }

case "\$1 \$2" in
  "repo view")
    echo "octo-org octo-repo" ;;                       # owner name (-q)
  "api user")
    cat "\$ME" ;;
  "pr view")
    if printf '%s' "\$args" | grep -q 'reviewDecision'; then
      cat "\$STATE"
    elif printf '%s' "\$args" | grep -q 'headRefName,headRefOid\|headRefOid,headRefName'; then
      printf '%s %s\n' "\$(cat "\$HEADREF")" "\$(cat "\$HEADOID")"
    elif printf '%s' "\$args" | grep -q 'headRefOid'; then
      cat "\$HEADOID"
    elif printf '%s' "\$args" | grep -q 'headRefName'; then
      cat "\$HEADREF"
    elif printf '%s' "\$args" | grep -q 'closingIssuesReferences'; then
      cat "\$CLOSES"
    elif printf '%s' "\$args" | grep -q 'author'; then
      cat "\$AUTHOR"
    elif printf '%s' "\$args" | grep -q 'comments'; then
      cat "\$PRCOMMENTS"
    elif printf '%s' "\$args" | grep -q '\.id'; then
      echo "PR_node_abc"                               # pull request node id
    else
      # \`gh\` resolves a number, a URL or a branch — and fails on a
      # reference that names no PR.
      [ -f "$WORK/no-such-pr" ] && { echo "no pull requests found" >&2; exit 1; }
      echo "77"                                        # current-branch PR number
    fi ;;
  "pr comment")
    flagval --body "\$@" >> "\$PRCOMMENTS"; echo >> "\$PRCOMMENTS" ;;
  "pr review")
    # GitHub refuses an approval from the PR's own author.
    [ "\$(cat "\$ME")" = "\$(cat "\$AUTHOR")" ] && {
      echo "GraphQL: Can not approve your own pull request" >&2; exit 1; }
    printf 'APPROVED' > "\$STATE" ;;                   # submit_approval
  "api graphql")
    if printf '%s' "\$args" | grep -q 'addPullRequestReviewThreadReply'; then
      tid=\$(param threadId "\$@"); body=\$(param body "\$@")
      printf '%s' "\$body" > "\$REPLIED"
      jq --arg id "\$tid" --arg b "\$body" \\
         'map(if .id == \$id then .replies += [\$b] else . end)' \\
         "\$THREADS" > "\$THREADS.t" && mv "\$THREADS.t" "\$THREADS"
      echo '{"data":{"addPullRequestReviewThreadReply":{"comment":{"id":"RC_new"}}}}'
    elif printf '%s' "\$args" | grep -q 'resolveReviewThread'; then
      tid=\$(param threadId "\$@")
      printf 'RESOLVED' > "\$RESOLVED"
      jq --arg id "\$tid" 'map(if .id == \$id then .isResolved = true else . end)' \\
         "\$THREADS" > "\$THREADS.t" && mv "\$THREADS.t" "\$THREADS"
      echo '{"data":{"resolveReviewThread":{"thread":{"id":"'"\$tid"'","isResolved":true}}}}'
    elif printf '%s' "\$args" | grep -q 'addPullRequestReviewThread'; then
      body=\$(param body "\$@")
      printf '%s' "\$body" > "\$POSTED"
      echo '{"data":{"addPullRequestReviewThread":{"thread":{"id":"RT_new"}}}}'
    elif printf '%s' "\$args" | grep -q 'node(id:'; then
      # One thread's full comment list, two per page. Reached only for a
      # thread whose newest page does not cover all of its replies.
      [ -f "\$WORK/deep-fetch-fails" ] && { echo "fake gh: comment query failed" >&2; exit 1; }
      tid=\$(param id "\$@"); cur=\$(param cursor "\$@")
      case "\$cur" in ''|null) off=0 ;; *) off=\$cur ;; esac
      jq -c --arg id "\$tid" --argjson off "\$off" --argjson size 2 '
        (map(select(.id == \$id)) | first | .replies) as \$r
        | { data: { node: { comments: {
              pageInfo: { hasNextPage: ((\$off + \$size) < (\$r | length)),
                          endCursor:   ((\$off + \$size) | tostring) },
              nodes: (\$r[\$off:\$off+\$size] | map({ body: . })) } } } }' "\$THREADS"
    else
      # Thread listing, two per page, so any correct reader must paginate.
      cur=\$(param cursor "\$@")
      case "\$cur" in ''|null) off=0; echo \$((\$(cat "\$PAGE0") + 1)) > "\$PAGE0" ;;
                      *) off=\$cur ;; esac
      src="\$THREADS"
      # After the first full sweep, optionally grow the thread list — this
      # is how a "the PR changed while you waited" event is simulated.
      if [ -f "\$WORK/mutate-on-next-sweep" ] && [ "\$(cat "\$PAGE0")" -gt 1 ]; then
        jq '. + [{"id":"RT_late","isResolved":false,"author":"reviewer-bot","body":"late finding\\n\\n<!-- stenswf-fp: deadbeef0009 -->","replies":[]}]' \\
          "\$THREADS" > "\$WORK/grown.json"
        src="\$WORK/grown.json"
      fi
      jq -c --argjson off "\$off" --argjson size 2 '{
        data: { repository: { pullRequest: { reviewThreads: {
          pageInfo: { hasNextPage: ((\$off + \$size) < length),
                      endCursor:   ((\$off + \$size) | tostring) },
          nodes: (.[\$off:\$off+\$size] | map({
            id, isResolved,
            root:   { nodes: [ { author: { login: .author }, body: .body } ] },
            # A capped newest-comments window, standing in for the
            # last:100 of the real query — totalCount reports the truth.
            recent: { totalCount: (.replies | length),
                      nodes: (.replies[-2:] | map({ body: . })) }
          }))
        }}}}}' "\$src"
    fi ;;
  *) echo "fake gh: unhandled: \$args" >&2; exit 3 ;;
esac
GHEOF
chmod +x "$WORK/gh"
PATH="$WORK:$PATH"

# --- fingerprint stability (offline) --------------------------------------
# Same finding located at different diff lines fingerprints identically,
# because line number is never an input; a different finding differs.
fp_line10=$(fingerprint "src/foo.js" "function bar" "unchecked null deref")
fp_line42=$(fingerprint "src/foo.js" "function bar" "unchecked null deref")
assert_eq "fingerprint is stable across a line-shifting diff" "$fp_line10" "$fp_line42"
fp_other=$(fingerprint "src/foo.js" "function baz" "unchecked null deref")
assert_ne "fingerprint discriminates distinct findings" "$fp_line10" "$fp_other"
[ "${#fp_line10}" -ge 8 ] && ok "fingerprint is a non-trivial hash" || fail "fingerprint is a non-trivial hash"

# --- add_thread embeds the fingerprint marker -----------------------------
fp=$(fingerprint "src/foo.js" "function bar" "unchecked null deref")
add_thread 77 "src/foo.js" 10 "$fp" "unchecked null deref" >/dev/null
assert_match "add_thread posts a body carrying the stenswf-fp marker" "$(cat "$POSTED")" "<!-- stenswf-fp: $fp -->"
assert_match "add_thread body keeps the finding text" "$(cat "$POSTED")" "unchecked null deref"

# --- pagination: every thread is returned, not just the first page --------
# The fake serves two threads per page. A reader that ignores pageInfo
# sees only two of three and reports false convergence over the rest.
listing=$(list_threads 77)
assert_eq "list_threads pages past the first page" "$(printf '%s\n' "$listing" | grep -c .)" "4"
assert_match "list_threads reaches a thread on the second page" "$listing" "RT_done"

# --- list_open_threads returns node-id + author + body --------------------
listing=$(list_open_threads 77)
assert_match "list_open_threads returns the open thread node-id" "$listing" "RT_open"
assert_match "list_open_threads returns the thread author"       "$listing" "reviewer-bot"
assert_match "list_open_threads surfaces the fingerprint body"   "$listing" "stenswf-fp: deadbeef0001"
assert_nomatch "list_open_threads excludes resolved threads"     "$listing" "RT_done"

# --- list surfaces open threads regardless of author ----------------------
# The implementer must act on every open thread, including human-authored
# ones — not just the paired reviewer's (PRD #12, D3/D7).
assert_match "list_open_threads surfaces a human-authored open thread" "$listing" "human-dev"

# --- dedup set spans resolved threads -------------------------------------
# A finding the implementer already fixed and resolved must still suppress
# a repost, so the fingerprint set is drawn from ALL threads.
fps=$(list_fingerprints 77)
assert_match "list_fingerprints includes an open thread's fingerprint"     "$fps" "deadbeef0001"
assert_match "list_fingerprints includes a RESOLVED thread's fingerprint"  "$fps" "deadbeef0003"

# --- disposition: an untouched open thread is not handled -----------------
disp_of() { list_threads 77 | awk -F'\t' -v id="$1" '$1==id{print $4}'; }
assert_eq "an untouched open thread has no disposition" "$(disp_of RT_human)" "none"

# --- a disposition older than the newest comment page is still found ------
# RT_deep's left-open reply sits behind newer chatter, outside the window
# the thread listing fetches. `totalCount` reveals that, and only such a
# thread pays for the extra paginated fetch.
assert_eq "a left-open marker behind a full comment page is still seen" "$(disp_of RT_deep)" "left-open"

# That second fetch must fail LOUDLY. Swallowed, it turns a handled thread
# into disposition `none` — the implementer would re-verify and re-reply to
# a thread it had already answered, and the reviewer would never converge.
: > "$WORK/deep-fetch-fails"
list_threads 77 >/dev/null 2>&1 \
  && fail "a failed comment query aborts the listing" \
  || ok "a failed comment query aborts the listing"
rm -f "$WORK/deep-fetch-fails"

# --- submit_approval / read_review_decision -------------------------------
assert_eq "review decision starts un-approved" "$(read_review_decision 77)" "REVIEW_REQUIRED"
submit_approval 77 "nothing more to say"
assert_eq "submit_approval flips reviewDecision to APPROVED" "$(read_review_decision 77)" "APPROVED"

# --- convergence when reviewer and author are ONE identity ----------------
# GitHub refuses an approval from the PR's own author, which is the normal
# case when one person runs both harnesses. Without a fallback the
# reviewer's stop condition could never be met and both loops would run to
# their cap forever.
printf 'REVIEW_REQUIRED' > "$STATE"; : > "$PRCOMMENTS"
printf 'pr-author\n' > "$ME"          # reviewer IS the author
assert_can_approve 77 && fail "assert_can_approve refuses the PR author" || ok "assert_can_approve refuses the PR author"
signal_convergence 77 "reviewer loop: nothing more to say"
assert_eq "a formal approval is not attempted" "$(read_review_decision 77)" "REVIEW_REQUIRED"
assert_match "convergence falls back to a marker comment" "$(cat "$PRCOMMENTS")" "<!-- stenswf-converged: sha-base -->"
# A marker is not an approval. Reporting it as one would tell the user the
# PR is reviewed while branch protection and every human still see it isn't.
assert_eq "a marker reads as converged, not approved" "$(read_convergence 77)" "converged"

# Convergence is a statement about a REVISION. Once the implementer pushes,
# an older signal must stop counting — or a fix no reviewer has seen reads
# as approval of itself.
printf 'sha-next' > "$HEADOID"
assert_eq "a signal from an earlier head reads as pending" "$(read_convergence 77)" "pending"
signal_convergence 77 "reviewer loop: nothing more to say"
assert_eq "re-signalling covers the new head" "$(read_convergence 77)" "converged"
printf 'sha-base' > "$HEADOID"

printf 'reviewer-bot\n' > "$ME"; : > "$PRCOMMENTS"; printf 'REVIEW_REQUIRED' > "$STATE"
assert_can_approve 77 && ok "assert_can_approve allows a distinct identity" || fail "assert_can_approve allows a distinct identity"
assert_eq "an un-approved PR reads as pending" "$(read_convergence 77)" "pending"
signal_convergence 77 "reviewer loop: nothing more to say"
assert_eq "a distinct identity approves formally" "$(read_review_decision 77)" "APPROVED"
assert_eq "a formal approval reads as approved" "$(read_convergence 77)" "approved"
# The SHA marker rides along with the approval so freshness has ONE rule:
# a GitHub approval otherwise survives new commits unless the repository
# happens to dismiss stale reviews, and the protocol must not depend on
# that setting.
assert_match "the approval is pinned to the head it approved" \
  "$(cat "$PRCOMMENTS")" "<!-- stenswf-converged: sha-base -->"
printf 'sha-next' > "$HEADOID"
assert_eq "an approval does not carry to a newer head" "$(read_convergence 77)" "pending"

# The reviewer signals about the commit it READ, which is not necessarily
# the head by the time it finishes — the implementer may have pushed mid-pass.
: > "$PRCOMMENTS"
signal_convergence 77 "reviewer loop: nothing more to say" "sha-reviewed"
assert_match "the marker names the reviewed commit, not the current head" \
  "$(cat "$PRCOMMENTS")" "<!-- stenswf-converged: sha-reviewed -->"
assert_eq "and a head the reviewer never read stays pending" "$(read_convergence 77)" "pending"
printf 'sha-base' > "$HEADOID"

# --- remote head synchronisation ------------------------------------------
# The loops wake on the REMOTE head moving; a pass that then reads a stale
# working tree reviews the very commit it already reviewed.
assert_eq "fetch_pr_head reports the PR's remote head" "$(fetch_pr_head 77)" "sha-base"
assert_pr_synced 77 2>/dev/null && ok "assert_pr_synced passes when local matches the PR head" || fail "assert_pr_synced passes when local matches the PR head"
printf 'sha-newer\n' > "$HEADOID"
assert_pr_synced 77 2>/dev/null && fail "assert_pr_synced refuses a stale working tree" || ok "assert_pr_synced refuses a stale working tree"
printf 'sha-base\n' > "$HEADOID"

# A PR opened from a fork has its branch on the fork, not on origin — and a
# same-named branch on origin fetches cleanly while pointing at a different
# commit, which is the failure that looks like success. The PR ref names the
# PR itself, and what it resolved to is checked against headRefOid.
printf 'sha-somewhere-else\n' > "$WORK/fetched"
fetch_pr_head 77 >/dev/null 2>&1 \
  && fail "fetch_pr_head refuses a ref that resolved to another commit" \
  || ok "fetch_pr_head refuses a ref that resolved to another commit"
rm -f "$WORK/fetched"

# --- sync_to_pr_head: re-established every pass ---------------------------
# The implementer waits between passes precisely because someone else may
# push. Checking once at startup proves only that the tree was current then.
printf 'sha-base\n' > "$LOCALSHA"; printf 'sha-base\n' > "$HEADOID"
sync_to_pr_head 77 >/dev/null 2>&1 \
  && ok "sync_to_pr_head is a no-op when already current" \
  || fail "sync_to_pr_head is a no-op when already current"

printf 'sha-pushed-by-a-human\n' > "$HEADOID"
sync_to_pr_head 77 >/dev/null 2>&1 \
  && ok "sync_to_pr_head fast-forwards onto a head someone else pushed" \
  || fail "sync_to_pr_head fast-forwards onto a head someone else pushed"
assert_eq "the working tree is now the PR head" "$(git rev-parse HEAD)" "sha-pushed-by-a-human"

# Diverged means this harness and someone else have both committed. How
# those reconcile is a merge decision, not something a sync step makes on
# its way into an edit.
: > "$WORK/diverged"; printf 'sha-divergent\n' > "$HEADOID"
sync_to_pr_head 77 >/dev/null 2>&1 \
  && fail "sync_to_pr_head refuses to reconcile a diverged branch" \
  || ok "sync_to_pr_head refuses to reconcile a diverged branch"
assert_eq "and leaves the tree exactly where it was" "$(git rev-parse HEAD)" "sha-pushed-by-a-human"
rm -f "$WORK/diverged"
printf 'sha-base\n' > "$LOCALSHA"; printf 'sha-base\n' > "$HEADOID"

# --- resolve_pr: explicit arg vs current-branch default -------------------
assert_eq "resolve_pr passes an explicit PR number through" "$(resolve_pr 55)" "55"
assert_eq "resolve_pr defaults to the current branch's PR" "$(resolve_pr "")" "77"

# A URL is advertised by both skill contracts, so it has to survive into the
# places the value is actually USED: a GraphQL `Int!`, and a path component
# of `refs/pull/<n>/head`. Passed through verbatim it would build the ref
# `refs/pull/https://github.com/octo-org/octo-repo/pull/77/head`.
assert_eq "resolve_pr normalises a PR URL to its number" \
  "$(resolve_pr https://github.com/octo-org/octo-repo/pull/77)" "77"
assert_eq "a normalised URL is usable where an Int is required" \
  "$(fetch_pr_head "$(resolve_pr https://github.com/octo-org/octo-repo/pull/77)")" "sha-base"

: > "$WORK/no-such-pr"
resolve_pr https://github.com/octo-org/octo-repo/pull/9999 >/dev/null 2>&1 \
  && fail "resolve_pr fails on a reference that names no PR" \
  || ok "resolve_pr fails on a reference that names no PR"
rm -f "$WORK/no-such-pr"

# --- resolve_issue: GitHub's own link resolution, and loud on ambiguity ---
assert_eq "resolve_issue returns the PR's linked issue" "$(resolve_issue 77)" "121"
printf '' > "$CLOSES"
resolve_issue 77 >/dev/null 2>&1 && fail "resolve_issue fails when no issue is linked" || ok "resolve_issue fails when no issue is linked"
printf '121\n122\n' > "$CLOSES"
resolve_issue 77 >/dev/null 2>&1 && fail "resolve_issue fails on several linked issues" || ok "resolve_issue fails on several linked issues"
printf '121\n' > "$CLOSES"

# --- assert_pr_branch guards the sole writer ------------------------------
assert_pr_branch 77 >/dev/null 2>&1 && ok "assert_pr_branch passes on the PR's branch" || fail "assert_pr_branch passes on the PR's branch"
printf 'some-other-branch\n' > "$HEADREF"
assert_pr_branch 77 >/dev/null 2>&1 && fail "assert_pr_branch refuses a mismatched branch" || ok "assert_pr_branch refuses a mismatched branch"
printf 'feature-branch\n' > "$HEADREF"

# --- linked-issue mode drives slice-vs-PRD dispatch -----------------------
prd_body="$WORK/issue-prd.md"
printf '<!-- stenswf:v1\ntype: PRD\n-->\n' > "$prd_body"
TYPE=$(get_fm type "$prd_body"); parse_type; assert_eq "PRD front-matter selects prd mode" "$MODE" "prd"
slice_body="$WORK/issue-slice.md"
printf '<!-- stenswf:v1\ntype: slice — AFK\n-->\n' > "$slice_body"
TYPE=$(get_fm type "$slice_body"); parse_type; assert_eq "slice front-matter selects slice mode" "$MODE" "slice"

# --- loop_cycle_bump is the concrete LOOP_MAX_CYCLES counter --------------
CYCLE="$WORK/loop-state.json"
assert_eq "loop_cycle_bump starts at 1"   "$(LOOP_MAX_CYCLES=2 loop_cycle_bump "$CYCLE")" "1"
assert_eq "loop_cycle_bump increments"    "$(LOOP_MAX_CYCLES=2 loop_cycle_bump "$CYCLE")" "2"
LOOP_MAX_CYCLES=2 loop_cycle_bump "$CYCLE" >/dev/null && fail "loop_cycle_bump fails past the cap" || ok "loop_cycle_bump fails past the cap"
assert_eq "loop_cycle_bump persists the count" "$(jq -r .cycle "$CYCLE")" "3"

# --- wake-up: waits on a condition, and says which one fired --------------
# timeout 0 keeps the suite fast: each case resolves on its first poll.
assert_eq "wait_for_change reports an advanced HEAD" \
  "$(wait_for_change 77 "sha-stale" 0 1)" "head-advanced sha-base"
assert_eq "wait_for_change times out when nothing moved" \
  "$(wait_for_change 77 "sha-base" 0 1)" "timeout"
printf '0\n' > "$PAGE0"; touch "$WORK/mutate-on-next-sweep"
assert_eq "wait_for_change notices a new thread" \
  "$(wait_for_change 77 "sha-base" 0 1)" "threads-changed"
rm -f "$WORK/mutate-on-next-sweep"

# --- add_reply posts a reply body (e.g. the fixing commit SHA) ------------
add_reply RT_open "fixed in abc1234" >/dev/null
assert_match "add_reply posts the given reply body" "$(cat "$REPLIED")" "fixed in abc1234"

# --- a left-open reply must be OBSERVABLE, not merely sent ----------------
# The disposition arrives as a LATER reply, so a reader that fetches only
# a thread's root comment cannot tell a disputed-but-handled thread from
# an ignored one — and the loops never converge.
add_reply RT_human "verified: intended behavior

<!-- stenswf-left-open: intended-behavior -->" >/dev/null
assert_match "add_reply carries a left-open marker" "$(cat "$REPLIED")" "<!-- stenswf-left-open: intended-behavior -->"
assert_eq "a left-open reply is visible to a later list" "$(disp_of RT_human)" "left-open"
assert_nomatch "a plain reply does not mark a thread handled" "$(disp_of RT_open)" "left-open"

# --- resolve_thread marks the thread resolved -----------------------------
assert_eq "resolve_thread reports the thread resolved" "$(resolve_thread RT_open)" "true"
[ -f "$RESOLVED" ] && ok "resolve_thread invoked resolveReviewThread" || fail "resolve_thread invoked resolveReviewThread"
assert_eq "a resolved thread is visible to a later list" "$(disp_of RT_open)" "resolved"
assert_nomatch "list_open_threads drops the newly resolved thread" "$(list_open_threads 77)" "RT_open"
assert_match "its fingerprint survives in the dedup set" "$(list_fingerprints 77)" "deadbeef0001"

# --- summary ---------------------------------------------------------------
printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
