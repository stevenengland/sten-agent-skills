# PR review-thread plumbing — canonical shell library for the stenswf
# reviewer loop (`review-loop`).
#
# Sourced, not executed. From a skill directory:
#   source ../../scripts/pr-threads.sh
#
# Contract, thread schema, fingerprint scheme, and the GraphQL these
# functions wrap live in ../references/pr-conversation-loop.md. Function
# bodies below are the single source of truth — do not duplicate them.
#
# Reviewer-side only: these functions fetch, read, post threads, and
# approve. They NEVER commit, push, or resolve — the implementer
# (`apply-loop`) is the sole git writer (PRD #12, D4).
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

# Resolve the target PR. An explicit arg (number or URL) passes through;
# empty falls back to the current branch's PR.
resolve_pr() {
  local arg="${1:-}"
  if [ -n "$arg" ]; then
    printf '%s\n' "$arg"
  else
    gh pr view --json number -q .number
  fi
}

# Repository owner and name, space-separated. Internal helper.
_owner_repo() {
  gh repo view --json owner,name -q '.owner.login + " " + .name'
}

# The pull request's GraphQL node id. Internal helper.
_pr_node_id() {
  gh pr view "$1" --json id -q .id
}

# List open (unresolved) review threads on a PR as TSV:
#   <node-id>\t<author-login>\t<first-comment-body>
# The body carries the `<!-- stenswf-fp: <hash> -->` marker used for
# dedup. Resolved threads are omitted.
list_open_threads() {
  local pr="$1" owner name
  read -r owner name < <(_owner_repo)
  gh api graphql \
    -f query='query($owner:String!,$name:String!,$pr:Int!){repository(owner:$owner,name:$name){pullRequest(number:$pr){reviewThreads(first:100){nodes{id isResolved comments(first:1){nodes{author{login} body}}}}}}}' \
    -F owner="$owner" -F name="$name" -F pr="$pr" \
    | jq -r '.data.repository.pullRequest.reviewThreads.nodes[]
             | select(.isResolved == false)
             | [.id, (.comments.nodes[0].author.login // "unknown"),
                (.comments.nodes[0].body | gsub("\n"; " "))]
             | @tsv'
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
