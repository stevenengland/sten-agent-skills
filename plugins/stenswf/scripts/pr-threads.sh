# PR review-thread plumbing — canonical shell library for the stenswf
# PR conversation loop (`review-loop` reviewer + `apply-loop` implementer).
#
# Sourced, not executed. From a skill directory:
#   source ../../scripts/pr-threads.sh
#
# Contract, thread schema, fingerprint scheme, and the GraphQL these
# functions wrap live in ../references/pr-conversation-loop.md. Function
# bodies below are the single source of truth — do not duplicate them.
#
# The file hosts both sides, but the sole-writer rule still binds by
# caller (PRD #12, D4): the reviewer-side functions (fetch, read, post
# threads, approve) NEVER commit, push, or resolve; only the implementer
# (`apply-loop`) calls the implementer-side functions (reply, resolve).
#
# All GitHub access goes through the `gh` CLI so the host is swappable
# and the functions are testable by injecting a fake `gh` on PATH.

# Stable fingerprint for a finding. Deliberately excludes the line
# number so the same finding survives a line-shifting diff and is not
# reposted on a later pass (PRD #12, D6). Inputs are the file path, a
# stable code anchor (symbol name or normalised snippet — never a line
# number), and the finding message.
fingerprint() {
  local path="$1" anchor="$2" message="$3"
  printf '%s\x1f%s\x1f%s' "$path" "$anchor" "$message" \
    | sha256sum | cut -c1-12
}

# Resolve the target PR to a NUMBER. An explicit arg (number or URL);
# empty falls back to the current branch's PR.
#
# Always a number, never whatever the caller typed. Downstream the value
# is a GraphQL `Int!` and a path component of `refs/pull/<n>/head`, so a
# URL passed through verbatim would produce an invalid integer and the
# nonsense ref `refs/pull/https://github.com/o/r/pull/77/head`. A URL is
# advertised in both skill contracts, so it has to actually work.
#
# A numeric arg is taken as given — the common path costs no round trip.
# Anything else is handed to the host to resolve, rather than being
# pattern-matched here: `gh` already knows every form it accepts, and a
# reference it cannot resolve is an error worth failing on before the
# loop starts writing to a PR that may not be the intended one.
resolve_pr() {
  local arg="${1:-}" num
  if [ -z "$arg" ]; then
    gh pr view --json number -q .number
    return
  fi
  case "$arg" in
    *[!0-9]*) num=$(gh pr view "$arg" --json number -q .number) || return 1 ;;
    *)        num="$arg" ;;
  esac
  [ -n "$num" ] || { printf 'PR: could not resolve %s to a PR number\n' "$arg" >&2; return 1; }
  printf '%s\n' "$num"
}

# The issue a PR closes, via GitHub's own link resolution rather than a
# regex over the body: `closingIssuesReferences` already understands every
# closing keyword and the qualified `owner/repo#123` form. Ambiguity is an
# error, not a coin flip — zero or several linked issues both fail loudly
# so the caller routes heavy instead of writing to the wrong issue.
resolve_issue() {
  local pr="$1" nums count
  nums=$(gh pr view "$pr" --json closingIssuesReferences \
    -q '.closingIssuesReferences[].number')
  count=$(printf '%s\n' "$nums" | grep -c '^[0-9][0-9]*$' || true)
  if [ "$count" -eq 0 ]; then
    printf 'ROUTE_HEAVY: PR #%s closes no issue — add "Closes #<n>" to its body\n' \
      "$pr" >&2
    return 1
  fi
  if [ "$count" -gt 1 ]; then
    printf 'ROUTE_HEAVY: PR #%s closes several issues (%s) — pass the target explicitly\n' \
      "$pr" "$(printf '%s' "$nums" | tr '\n' ' ')" >&2
    return 1
  fi
  printf '%s\n' "$nums"
}

# Guard the sole-writer rule at the filesystem level: refuse to act when
# the working tree is not on the PR's head branch, so a mis-targeted
# session fails here instead of committing fixes to the wrong branch.
assert_pr_branch() {
  local pr="$1" want have
  want=$(gh pr view "$pr" --json headRefName -q .headRefName)
  have=$(git rev-parse --abbrev-ref HEAD)
  if [ -n "$want" ] && [ "$want" = "$have" ]; then
    return 0
  fi
  printf 'ROUTE_HEAVY: on branch %s but PR #%s targets %s — check out the PR branch first\n' \
    "$have" "$pr" "$want" >&2
  return 1
}

# Repository owner and name, space-separated. Internal helper.
_owner_repo() {
  gh repo view --json owner,name -q '.owner.login + " " + .name'
}

# The pull request's GraphQL node id. Internal helper.
_pr_node_id() {
  gh pr view "$1" --json id -q .id
}

# The review-thread query. Two aliased comment connections, because the
# two markers live at opposite ends of a thread: the fingerprint is on the
# root comment, while the `stenswf-left-open` disposition arrives as a
# later reply. Fetching only the root (as this query once did) makes a
# left-open thread indistinguishable from an unhandled one, and the loops
# then cannot converge from PR state alone.
_THREADS_QUERY='query($owner:String!,$name:String!,$pr:Int!,$cursor:String){repository(owner:$owner,name:$name){pullRequest(number:$pr){reviewThreads(first:50,after:$cursor){pageInfo{hasNextPage endCursor}nodes{id isResolved root:comments(first:1){nodes{author{login} body}} recent:comments(last:100){totalCount nodes{body}}}}}}}'

# Every comment on ONE thread, paginated. Only reached for a thread
# deeper than a single comment page — see `_threads_json`.
_THREAD_COMMENTS_QUERY='query($id:ID!,$cursor:String){node(id:$id){... on PullRequestReviewThread{comments(first:100,after:$cursor){pageInfo{hasNextPage endCursor}nodes{body}}}}}'

_thread_reply_bodies() {
  local tid="$1" cursor="" page has_next
  while :; do
    if [ -z "$cursor" ]; then
      page=$(gh api graphql -f query="$_THREAD_COMMENTS_QUERY" \
        -f id="$tid" -F cursor=null) || return 1
    else
      page=$(gh api graphql -f query="$_THREAD_COMMENTS_QUERY" \
        -f id="$tid" -f cursor="$cursor") || return 1
    fi
    printf '%s' "$page" | jq -r '.data.node.comments.nodes[].body'
    has_next=$(printf '%s' "$page" | jq -r '.data.node.comments.pageInfo.hasNextPage')
    [ "$has_next" = "true" ] || break
    cursor=$(printf '%s' "$page" | jq -r '.data.node.comments.pageInfo.endCursor')
  done
}

# Every review thread on a PR as one compact JSON object per line:
#   {id, resolved, author, fp, disposition, replies, body}
# `disposition` is resolved | left-open | none — the "handled" test from
# the contract, computed once here so no caller re-derives it.
#
# Pages until `hasNextPage` is false: a PR that accumulates more than one
# page of threads must not silently truncate, or the loops report false
# convergence over the threads they never saw.
_threads_json() {
  local pr="$1" owner name cursor="" page has_next rows bodies deep tid obj
  read -r owner name < <(_owner_repo)
  while :; do
    if [ -z "$cursor" ]; then
      page=$(gh api graphql -f query="$_THREADS_QUERY" \
        -F owner="$owner" -F name="$name" -F pr="$pr" -F cursor=null) || return 1
    else
      page=$(gh api graphql -f query="$_THREADS_QUERY" \
        -F owner="$owner" -F name="$name" -F pr="$pr" -f cursor="$cursor") || return 1
    fi
    rows=$(printf '%s' "$page" | jq -r '
      .data.repository.pullRequest.reviewThreads.nodes[]
      | (.root.nodes[0].body // "")            as $root
      | ([$root | scan("<!-- stenswf-fp: ([0-9a-f]+) -->")] | flatten | first // "") as $fp
      | ([.recent.nodes[]?.body // "" | test("<!-- stenswf-left-open:")] | any) as $left
      | {
          id,
          resolved: .isResolved,
          author: (.root.nodes[0].author.login // "unknown"),
          fp: $fp,
          disposition: (if .isResolved then "resolved"
                        elif $left      then "left-open"
                        else                 "none" end),
          replies: (.recent.nodes | length),
          total: (.recent.totalCount // 0),
          body: $root
        }
      # Flagged here rather than re-inspected per object downstream: a
      # thread deeper than one comment page may be hiding its left-open
      # marker behind the newest replies, and only such a thread should
      # pay for a second round trip.
      | [ (if .disposition == "none" and .total > .replies then "1" else "0" end),
          .id, tojson ] | @tsv') || return 1

    # Read from a here-doc, not a pipe: a `while` fed by a pipeline runs in
    # a subshell, and a failure to page a thread's comments could not then
    # abort the listing — it would surface as a thread whose disposition
    # silently reads `none`, which is to say a handled thread reported as
    # unhandled. Same reason the marker test consumes the whole result
    # first instead of `grep -q`, whose early exit closes the pipe under
    # the writer and makes `gh` spray broken-pipe errors.
    while IFS=$'\t' read -r deep tid obj; do
      [ -n "$obj" ] || continue
      if [ "$deep" = "1" ]; then
        bodies=$(_thread_reply_bodies "$tid") || {
          printf 'THREAD_COMMENTS: could not page comments for %s\n' "$tid" >&2
          return 1
        }
        case "$bodies" in
          *'<!-- stenswf-left-open:'*)
            obj=$(printf '%s' "$obj" | jq -c '.disposition = "left-open"') ;;
        esac
      fi
      printf '%s\n' "$obj"
    done <<EOF
$rows
EOF
    has_next=$(printf '%s' "$page" \
      | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')
    [ "$has_next" = "true" ] || break
    cursor=$(printf '%s' "$page" \
      | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor')
  done
}

# Every review thread — resolved ones included — as TSV:
#   <node-id>\t<isResolved>\t<author>\t<disposition>\t<fingerprint>\t<first-comment-body>
list_threads() {
  _threads_json "$1" | jq -r '[.id, (.resolved | tostring), .author,
                               .disposition, .fp, (.body | gsub("\n"; " "))]
                              | @tsv'
}

# The same TSV restricted to open (unresolved) threads — the implementer's
# work list.
list_open_threads() {
  _threads_json "$1" | jq -r 'select(.resolved == false)
                              | [.id, (.resolved | tostring), .author,
                                 .disposition, .fp, (.body | gsub("\n"; " "))]
                              | @tsv'
}

# Every fingerprint present on the PR, one per line, **including resolved
# threads**. This is the reviewer's dedup set: a finding the implementer
# already fixed and resolved must still suppress a repost, so this
# deliberately does not filter on `isResolved`.
list_fingerprints() {
  _threads_json "$1" | jq -r 'select(.fp != "") | .fp'
}

# Post a resolvable review thread on a PR line. The fingerprint marker is
# appended to the body so a later pass can dedup by fingerprint.
#   add_thread <pr> <path> <line> <fingerprint> <body>
add_thread() {
  local pr="$1" path="$2" line="$3" fp="$4" body="$5" pr_id
  pr_id=$(_pr_node_id "$pr")
  local full="$body

<!-- stenswf-fp: $fp -->"
  gh api graphql \
    -f query='mutation($prId:ID!,$body:String!,$path:String!,$line:Int!){addPullRequestReviewThread(input:{pullRequestId:$prId,body:$body,path:$path,line:$line,subjectType:LINE}){thread{id}}}' \
    -f prId="$pr_id" -f body="$full" -f path="$path" -F line="$line" \
    | jq -r '.data.addPullRequestReviewThread.thread.id'
}

# Submit a PR approval — the cross-harness "nothing more to say" signal
# (PRD #12, D5). Optional review body.
submit_approval() {
  local pr="$1" body="${2:-}"
  if [ -n "$body" ]; then
    gh pr review "$pr" --approve --body "$body"
  else
    gh pr review "$pr" --approve
  fi
}

# Report the PR's review decision (APPROVED | CHANGES_REQUESTED |
# REVIEW_REQUIRED | empty).
read_review_decision() {
  gh pr view "$1" --json reviewDecision -q .reviewDecision
}

# Can the current `gh` identity formally approve this PR? GitHub refuses
# an approval from the PR's own author (422), and two harnesses run by
# one person share one credential — so for the ordinary single-user setup
# the answer is no. Returns 0 when approval is possible.
assert_can_approve() {
  local pr="$1" me author
  me=$(gh api user -q .login 2>/dev/null)
  author=$(gh pr view "$pr" --json author -q .author.login)
  [ -n "$me" ] && [ -n "$author" ] && [ "$me" != "$author" ]
}

# The convergence marker, carrying the SHA it was said about.
#   _converged_marker <sha>
_converged_marker() {
  printf '<!-- stenswf-converged: %s -->' "$1"
}

# Signal "nothing more to say" (D5) by whatever means this identity has.
#
# A formal approval is preferred — it is the signal a human reviewer of
# the PR will look for. When the reviewer harness IS the PR author, that
# route is closed by GitHub, and falling back to a marker comment is what
# keeps the pair able to converge at all: without it the reviewer's stop
# condition can never be satisfied and both loops run to their cap on
# every single run.
#
# The SHA marker is posted on BOTH routes, so freshness has exactly one
# rule. Convergence is a statement about a revision, not about a PR: a
# bare marker stays true forever, and a GitHub approval survives new
# commits unless the repository happens to dismiss stale reviews. Either
# way the implementer could push a fix and then read a signal that
# predates it as approval of code no reviewer has seen.
# Pass the SHA the pass actually reviewed. Defaulting to the current head
# is only right when nothing moved during the pass; the reviewer knows what
# it read and should say so.
#   signal_convergence <pr> [body] [reviewed-sha]
signal_convergence() {
  local pr="$1" body="${2:-reviewer loop: nothing more to say}" sha="${3:-}"
  [ -n "$sha" ] || sha=$(gh pr view "$pr" --json headRefOid -q .headRefOid) || return 1
  [ -n "$sha" ] || { echo "CONVERGE: no head SHA for PR $pr" >&2; return 1; }
  if assert_can_approve "$pr"; then
    submit_approval "$pr" "$body" || return 1
  fi
  gh pr comment "$pr" --body "$body

$(_converged_marker "$sha")"
}

# Has the reviewer said "nothing more to say" ABOUT THE CURRENT HEAD?
# Prints one of:
#
#   approved   — converged, and GitHub carries a formal approval
#   converged  — converged by marker only; `reviewDecision` is unchanged
#   pending    — no convergence signal for this head
#
# The two positive states are deliberately not collapsed. A marker is not
# an approval: branch protection, merge automation and a human reading the
# PR all see `REVIEW_REQUIRED`, and a loop that reported that as "approved"
# would be lying to its own end-of-session summary. Callers that only need
# "may I stop?" accept either; the summary says which one it got.
#
# The SHA gate applies to both, so a signal never outlives the revision it
# was made about.
read_convergence() {
  local pr="$1" sha
  sha=$(gh pr view "$pr" --json headRefOid -q .headRefOid) || return 1
  if ! gh pr view "$pr" --json comments -q '.comments[].body' 2>/dev/null \
       | grep -qF "$(_converged_marker "$sha")"; then
    printf 'pending\n'
    return 0
  fi
  if [ "$(read_review_decision "$pr")" = "APPROVED" ]; then
    printf 'approved\n'
  else
    printf 'converged\n'
  fi
}

# Fetch the PR's head from the remote and print its SHA.
#
# The loops wake on the REMOTE head moving, so a pass that then reads the
# local working tree reviews whatever was last pulled — which is exactly
# the commit the reviewer already reviewed. Fetching costs one round trip
# and makes "review the delta" mean the delta that actually exists.
# Fetched by PR ref, not by branch name. A PR opened from a fork has its
# branch on the fork, where `origin` cannot see it — and worse, an
# unrelated branch of the same name on `origin` fetches cleanly and gives
# you the wrong commit under the right name, which is a failure that looks
# like success. `refs/pull/<n>/head` names the PR itself and is identical
# for same-repo and fork PRs. (GitHub's ref shape; GitLab exposes
# `refs/merge-requests/<n>/head` — host-specific, like the CLI itself.)
#
# The fetched object is then checked against the PR's own `headRefOid`, so
# a ref that resolved to something unexpected stops the pass rather than
# seeding a review of the wrong tree.
fetch_pr_head() {
  local pr="$1" oid got
  oid=$(gh pr view "$pr" --json headRefOid -q .headRefOid) || return 1
  [ -n "$oid" ] || { printf 'PR_HEAD: PR %s reports no head\n' "$pr" >&2; return 1; }
  git fetch --quiet origin "refs/pull/$pr/head" || return 1
  got=$(git rev-parse FETCH_HEAD 2>/dev/null)
  if [ -n "$got" ] && [ "$got" != "$oid" ]; then
    printf 'PR_HEAD: fetched %s but PR %s reports head %s\n' "$got" "$pr" "$oid" >&2
    return 1
  fi
  printf '%s\n' "$oid"
}

# Refuse to act when the working tree is behind the PR's head. The
# implementer is the sole writer, but a human can still push to the
# branch, and committing on top of a stale head is how a fix silently
# reverts someone else's.
assert_pr_synced() {
  local pr="$1" remote local_sha
  remote=$(fetch_pr_head "$pr") || return 1
  local_sha=$(git rev-parse HEAD)
  [ "$remote" = "$local_sha" ] && return 0
  printf 'ROUTE_HEAVY: local HEAD %s is not the PR head %s — pull before writing\n' \
    "$local_sha" "$remote" >&2
  return 1
}

# Bring the working tree onto the PR's head, or refuse to continue.
#
# Checking once at startup only proves the tree was current THEN. The
# implementer waits between passes precisely because someone else may
# push, and `wait_for_change` reports `head-advanced` when they do — so
# every pass has to re-establish the invariant rather than inherit it.
#
# Fast-forward only. A diverged local branch means this harness and
# someone else have both committed, and choosing how those reconcile is a
# merge decision — not something a sync step should make silently on the
# way to editing code.
#   sync_to_pr_head <pr>
sync_to_pr_head() {
  local pr="$1" remote local_sha
  remote=$(fetch_pr_head "$pr") || return 1
  local_sha=$(git rev-parse HEAD)
  [ "$remote" = "$local_sha" ] && return 0
  if git merge-base --is-ancestor "$local_sha" "$remote" 2>/dev/null \
     && git merge --ff-only "$remote" >/dev/null 2>&1; then
    printf 'synced %s -> %s\n' "$local_sha" "$remote"
    return 0
  fi
  printf 'ROUTE_HEAVY: local HEAD %s cannot fast-forward to PR head %s — reconcile by hand\n' \
    "$local_sha" "$remote" >&2
  return 1
}

# A short hash over the thread list's shape — ids, resolution, disposition,
# and reply counts. Cheap change detector for `wait_for_change`; never
# printed on its own.
_thread_digest() {
  _threads_json "$1" \
    | jq -r '[.id, (.resolved | tostring), .disposition, (.replies | tostring)] | @tsv' \
    | sha256sum | cut -c1-16
}

# Block until the PR has something new to say, then print ONE line:
#   head-advanced <sha> | threads-changed | timeout
#
# This is the loops' wake-up. It waits on a *condition* rather than a
# duration, so a pass never wakes to find nothing changed, and every byte
# it polls stays inside this subprocess — the caller pays one short line
# of context per cycle no matter how large the PR is.
#
# `since-sha` is the head the caller last reviewed: if HEAD has already
# moved past it the function returns at once rather than sleeping.
#   wait_for_change <pr> <since-sha> [timeout-seconds] [interval-seconds]
wait_for_change() {
  local pr="$1" since="$2" timeout="${3:-600}" interval="${4:-20}"
  local deadline base head digest
  deadline=$(( $(date +%s) + timeout ))
  base=$(_thread_digest "$pr")
  while :; do
    head=$(gh pr view "$pr" --json headRefOid -q .headRefOid)
    if [ -n "$head" ] && [ "$head" != "$since" ]; then
      printf 'head-advanced %s\n' "$head"
      return 0
    fi
    digest=$(_thread_digest "$pr")
    if [ "$digest" != "$base" ]; then
      printf 'threads-changed\n'
      return 0
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      printf 'timeout\n'
      return 0
    fi
    sleep "$interval"
  done
}

# Increment the loop's cycle counter and enforce the cap. Prints the new
# cycle number; returns non-zero once it exceeds `LOOP_MAX_CYCLES`
# (default 5), so the bound is an exit status the caller must handle
# rather than a rule it is trusted to remember.
#   loop_cycle_bump <state-file>
loop_cycle_bump() {
  local f="$1" max="${LOOP_MAX_CYCLES:-5}" n
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || printf '{"cycle":0}\n' > "$f"
  n=$(jq -r '.cycle // 0' "$f")
  n=$((n + 1))
  jq --argjson n "$n" '.cycle = $n' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  printf '%s\n' "$n"
  [ "$n" -le "$max" ]
}

# --- Implementer-side (apply-loop) ---------------------------------------
# The implementer is the sole git writer (PRD #12, D4): only apply-loop
# calls the two functions below. The reviewer never replies or resolves.

# Post a reply to an existing review thread, keyed on its node id. The
# body may reference the fixing commit SHA (a verified-valid finding that
# was fixed) or carry a `<!-- stenswf-left-open: <reason> -->` marker (a
# finding left open after verification). Prints the new comment's id.
#   add_reply <thread-id> <body>
add_reply() {
  local thread_id="$1" body="$2"
  gh api graphql \
    -f query='mutation($threadId:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId,body:$body}){comment{id}}}' \
    -f threadId="$thread_id" -f body="$body" \
    | jq -r '.data.addPullRequestReviewThreadReply.comment.id'
}

# Mark a review thread resolved, once its finding is fixed and pushed.
# Prints the thread's post-resolution isResolved flag (`true`).
#   resolve_thread <thread-id>
resolve_thread() {
  local thread_id="$1"
  gh api graphql \
    -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{id isResolved}}}' \
    -f threadId="$thread_id" \
    | jq -r '.data.resolveReviewThread.thread.isResolved'
}
