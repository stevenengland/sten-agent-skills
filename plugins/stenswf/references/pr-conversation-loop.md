# PR conversation loop (shared contract)

The coordination contract for the paired `review-loop` (reviewer) and
`apply-loop` (implementer) skills. Both loops talk **only** through a
live GitHub PR — its review threads are the shared medium; there is no
shared orchestrator and no shared working tree (PRD #12).

> **Canonical plumbing.** The reviewer-side functions that wrap the
> GraphQL below live in
> [`../scripts/pr-threads.sh`](../scripts/pr-threads.sh). Skills source
> that file — do not duplicate the function bodies here or in any skill.

## Roles — sole writer

The **implementer (`apply-loop`) is the sole git writer**: it is the
only party that commits, pushes, and resolves threads. The **reviewer
(`review-loop`) is read-only against git**: it fetches, reads, posts
review threads, and submits approvals — it never edits code, commits,
pushes, or resolves a thread (PRD #12, D4). This is what makes the two
loops safe to run in separate harnesses against the same PR.

## Thread schema

Each finding is one **resolvable PR review thread** anchored to a
`path` + `line`. The first comment body carries a hidden fingerprint
marker on its own trailing line:

```
<human-readable finding text>

<!-- stenswf-fp: <hash> -->
```

The implementer may append a reply and (when it acts as sole writer)
resolve the thread, or leave it open with a disposition marker:

```
<!-- stenswf-left-open: <reason> -->
```

## Fingerprint scheme

`<hash>` is produced by `fingerprint <path> <anchor> <message>` in
`pr-threads.sh`: a 12-hex-char `sha256` over `path`, a stable code
**anchor** (a symbol name or normalised snippet — **never a line
number**), and the finding **message**, joined by `\x1f`.

Excluding the line number is deliberate: the same finding keeps the
same fingerprint across a line-shifting diff, so a delta re-review that
re-encounters an already-posted finding **skips** it rather than
reposting (PRD #12, D6). A finding whose fingerprint is already present
on the PR is never posted twice.

## Re-review scope — delta

Each reviewer pass reviews only `<last-reviewed-sha>..HEAD`, not the
whole PR. Unresolved prior findings are **carried forward** (their
threads stay open); new findings are posted only when their fingerprint
is absent from the set of fingerprints already on the PR.

## "Handled" definition

A thread is **handled** when it is either:

- **resolved** (the implementer verified the finding and fixed it, or
  it was a duplicate), or
- left **open** carrying a `<!-- stenswf-left-open: <reason> -->` reply
  (the implementer verified it and judged it invalid or out of scope).

Every left-open thread is listed in the end-of-session summary so the
user can adjudicate. A thread with no such disposition is **not**
handled.

## Termination + `LOOP_MAX_CYCLES` + cadence

- **Reviewer stops** by submitting a PR **approval** when a fresh delta
  pass yields **zero new findings** and every thread it raised is
  handled — the cross-harness "nothing more to say" signal (D5).
- **Implementer stops** when every open thread is handled and
  `reviewDecision == APPROVED`.
- Both loops are bounded by **`LOOP_MAX_CYCLES` (default 5)**. On
  reaching the cap, post a summary comment and stop instead of
  looping forever.
- Each loop **self-paces** via scheduled wake-ups within its own
  session — the user launches it once per harness (D10). It does not
  wrap `/loop`. Fingerprint/handled state is kept in-session and
  mirrored to `.stenswf/<issue>/loop-state.json` so a restarted harness
  resumes without duplicating threads.

## GraphQL / gh snippets

The `gh` CLI is the host seam (swap it for `glab`/`gitea` adapters).
The snippets below are what `pr-threads.sh` wraps.

**List open threads** — `list_open_threads <pr>`:

```graphql
query($owner:String!,$name:String!,$pr:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$pr){
      reviewThreads(first:100){
        nodes{ id isResolved comments(first:1){ nodes{ author{login} body } } }
      }
    }
  }
}
```

Emit TSV `<node-id>\t<author>\t<body>` for `isResolved == false`.

**Add a fingerprinted thread** — `add_thread <pr> <path> <line> <fp> <body>`:

```graphql
mutation($prId:ID!,$body:String!,$path:String!,$line:Int!){
  addPullRequestReviewThread(input:{
    pullRequestId:$prId, body:$body, path:$path, line:$line, subjectType:LINE
  }){ thread{ id } }
}
```

The `<!-- stenswf-fp: <hash> -->` marker is appended to `$body` before
the mutation runs.

**Submit approval** — `submit_approval <pr> [body]`:

```bash
gh pr review "$pr" --approve ${body:+--body "$body"}
```

**Read review decision** — `read_review_decision <pr>`:

```bash
gh pr view "$pr" --json reviewDecision -q .reviewDecision
# => APPROVED | CHANGES_REQUESTED | REVIEW_REQUIRED | (empty)
```
