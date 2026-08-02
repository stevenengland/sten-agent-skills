# PR conversation loop (shared contract)

The coordination contract for the paired `review-loop` (reviewer) and
`apply-loop` (implementer) skills. Both loops talk **only** through a
live GitHub PR — its review threads are the shared medium; there is no
shared orchestrator and no shared working tree (PRD #12).

> **Canonical plumbing.** The reviewer-side functions that wrap the
> GraphQL below live in
> [`../scripts/pr-threads.sh`](../scripts/pr-threads.sh). Skills source
> that file — do not duplicate the function bodies here or in any skill.

## Prerequisite — reviewer identity

**GitHub refuses an approval from the PR's own author.** Two harnesses run
by one person share one `gh` credential, so in the ordinary single-user
setup the reviewer *is* the author and `gh pr review --approve` fails with
a 422 every time.

A separate reviewer account or bot identity is therefore the **preferred**
setup: it makes the stop signal a real approval, which is also what a
human looking at the PR expects to see. Where that is not available, the
reviewer must not simply fail — `signal_convergence` falls back to a
`<!-- stenswf-converged: <sha> -->` marker comment. Without that fallback
the reviewer's stop condition is unsatisfiable and both loops run to their
cap on every single run.

`read_convergence` prints **`approved`** (converged, with a formal
GitHub approval), **`converged`** (marker only — `reviewDecision` is
still `REVIEW_REQUIRED`) or **`pending`**. The two positive states stay
distinct on purpose: a marker satisfies *this protocol*, not branch
protection, not merge automation, and not a human scanning the PR for a
green check. A loop may stop on either; its summary must say which.

**Convergence is about a revision, not about a PR.** The marker carries
the head SHA it was posted for and `read_convergence` requires it to
match the PR's current `headRefOid`. A bare marker would stay true
forever, and a GitHub approval survives new commits unless the repository
dismisses stale reviews — so without the SHA gate an implementer could
push a fix and read a signal predating it as approval of code no reviewer
has seen. The marker is posted on **both** routes, formal approval
included, so freshness has exactly one rule.

Neither loop calls `submit_approval` / `read_review_decision` directly;
they call `signal_convergence` / `read_convergence`, which pick the right
signal for the identity they have.

## Roles — sole writer

The **implementer (`apply-loop`) is the sole git writer**: it is the
only party that commits, pushes, and resolves threads. The **reviewer
(`review-loop`) is read-only against git**: it fetches, reads, posts
review threads, and submits approvals — it never edits code, commits,
pushes, or resolves a thread (PRD #12, D4). This is what makes the two
loops safe to run in separate harnesses against the same PR.

## Where the state lives

**GitHub is authoritative.** Everything the two loops need to agree on —
which findings exist, which are handled, how — is readable from the PR
itself via `list_threads`. `.stenswf/<issue>/loop-state.<role>.json` is a
**disposable cache**: deleting it may cost a pass's worth of work, never
correctness. Neither loop may depend on it for a decision it could not
re-derive from GitHub, because the other loop runs in a different harness
and cannot see it.

**The filename carries the role** — `loop-state.implementer.json` and
`loop-state.reviewer.json` — so each loop owns its own file. The role is a
*key*, not a field: `loop_cycle_bump` reads a bare `.cycle`, so a shared
path would merge both loops' bumps into one counter and trip
`LOOP_MAX_CYCLES` on a count neither loop reached alone. Nothing enforces
the "no shared working tree" premise above, and `$STATE` is a relative
path, so one checkout running both harnesses is all it takes.

The consequence is that **every pass is idempotent**. Re-listing a thread
that is already handled, re-verifying a finding already fixed, or
re-running a pass after a crash are all no-ops. That is what makes a
restarted harness safe.

The cache's schema:

```json
{
  "cycle": 3,
  "last_reviewed_sha": "<sha>",
  "threads": {
    "<node-id>": { "disposition": "resolved|left-open|none",
                   "fp": "<hash>", "sha": "<fixing sha>" }
  }
}
```

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

The dedup set is `list_fingerprints <pr>`, which spans **every** thread
including **resolved** ones. Drawing it from the open threads alone would
forget each finding as the implementer fixed and resolved it, and a later
delta that re-encountered the same code would then post it again — a
duplicate thread for a finding already closed.

## Re-review scope — delta

Each reviewer pass reviews only `<last-reviewed-sha>..<pr-head>`, not the
whole PR. Unresolved prior findings are **carried forward** (their
threads stay open); new findings are posted only when their fingerprint
is absent from the set of fingerprints already on the PR.

**`<pr-head>` is the remote head, fetched.** Both loops wake on the PR's
remote `headRefOid` moving, so a pass that then reads the local working
tree would review the commit it already reviewed — the wake-up and the
review would be looking at different repositories. `fetch_pr_head <pr>`
fetches `refs/pull/<n>/head` — the PR itself, so a fork PR works and a
same-named branch on `origin` cannot impersonate one — verifies the
fetched object against `headRefOid`, and prints that SHA. The reviewer
diffs against it without checking anything out.

The implementer, which does write, calls **`sync_to_pr_head <pr>` at the
start of every pass**: it fast-forwards onto the PR head, and refuses
(rather than rebasing) when the branch has diverged. Once at startup is
not enough — the loop's whole purpose is to wait, and `head-advanced` is
one of the things it waits for. Being the sole *agent* writer never meant
being the only writer.

## "Handled" definition

A thread is **handled** when it is either:

- **resolved** (the implementer verified the finding and fixed it, or
  it was a duplicate), or
- left **open** carrying a `<!-- stenswf-left-open: <reason> -->` reply
  (the implementer verified it and judged it invalid or out of scope).

Every left-open thread is listed in the end-of-session summary so the
user can adjudicate. A thread with no such disposition is **not**
handled.

**Handled is read, not remembered.** `list_threads` computes this as a
`disposition` column (`resolved` | `left-open` | `none`) — no caller
re-derives it, and neither loop needs local memory to know where a thread
stands. This is why the thread query fetches replies and not just the
root comment: the left-open marker arrives as a *later* reply, so a
root-only read cannot distinguish a disputed-but-handled thread from an
ignored one, and the protocol never converges.

## Termination + `LOOP_MAX_CYCLES` + cadence

- **Reviewer stops** by calling `signal_convergence` when a fresh delta
  pass yields **zero new findings** and every thread it raised is
  handled — the cross-harness "nothing more to say" signal (D5).
- **Implementer stops** when every open thread is handled and
  `read_convergence` is `approved` **or** `converged` — both mean "for
  this head, the reviewer has nothing more to say"; the summary reports
  which one ended the run.
- Both loops are bounded by **`LOOP_MAX_CYCLES` (default 5)**, enforced
  by `loop_cycle_bump <state-file>`: it increments the counter and
  **returns non-zero** once the cap is passed. The bound is an exit
  status to handle, not a rule to remember. On reaching it, post a
  summary comment listing still-open threads and stop.
- Each loop **self-paces** within its own session — the user launches it
  once per harness (D10). It does not wrap `/loop`.

### The wake-up

A non-converged pass ends by calling:

```bash
wait_for_change "$PR" "$LAST_SHA" "${WAIT_TIMEOUT:-600}" "${WAIT_INTERVAL:-20}"
# => head-advanced <sha> | threads-changed | timeout
```

It blocks on a **condition**, not a duration, and prints exactly one
short line naming what woke it. Two properties matter:

- **It does not wake for nothing.** A fixed sleep usually returns to find
  the other side has not moved; this returns the moment HEAD advances or
  a thread appears or changes, and only falls back to `timeout` when the
  PR has genuinely been quiet.
- **It costs one line of context per cycle.** Everything it polls stays
  inside the subprocess. A loop that re-listed the PR itself each tick
  would spend its context on unchanged data and run out of room long
  before it ran out of cycles.

Where the harness supports backgrounding a command and re-invoking on
exit (Claude Code does), run it that way; otherwise it simply blocks.
Either way the next pass starts by re-reading GitHub, so a `timeout`
return is a valid cycle, not an error.

## GraphQL / gh snippets

The `gh` CLI is the host seam (swap it for `glab`/`gitea` adapters).
The snippets below are what `pr-threads.sh` wraps.

**List threads** — `list_threads <pr>` (all), `list_open_threads <pr>`
(unresolved only), `list_fingerprints <pr>` (the dedup set) all read the
same query:

```graphql
query($owner:String!,$name:String!,$pr:Int!,$cursor:String){
  repository(owner:$owner,name:$name){
    pullRequest(number:$pr){
      reviewThreads(first:50, after:$cursor){
        pageInfo{ hasNextPage endCursor }
        nodes{ id isResolved
          root:   comments(first:1){ nodes{ author{login} body } }
          recent: comments(last:100){ nodes{ body } } }
      }
    }
  }
}
```

Two things this query gets right, both of which a simpler one gets
wrong:

- **It pages.** The caller loops on `endCursor` until `hasNextPage` is
  false. A single unpaginated fetch silently truncates on a PR that has
  accumulated more threads than the page size, and the loops then report
  convergence over threads they never saw.
- **It reads both ends of a thread.** `root` carries the fingerprint;
  `recent` is where the left-open disposition lands. See
  ["Handled" definition](#handled-definition). `totalCount` says whether
  `recent` covered the whole thread — when it did not and no disposition
  was found, that one thread's comments are re-fetched with their own
  pagination, so a marker buried under a hundred later replies is still
  seen. Only a thread that deep pays for the extra round trip.

Emitted as TSV:

```
<node-id>\t<isResolved>\t<author>\t<disposition>\t<fingerprint>\t<first-comment-body>
```

**Resolve the linked issue** — `resolve_issue <pr>`:

```bash
gh pr view "$pr" --json closingIssuesReferences -q '.closingIssuesReferences[].number'
```

GitHub has already resolved the link, so this handles every closing
keyword and the qualified `owner/repo#123` form that a regex over the
body would miss. Zero or several matches are **errors** — the function
fails loudly rather than picking one and writing to the wrong issue.

**Guard the branch** — `assert_pr_branch <pr>` compares
`git rev-parse --abbrev-ref HEAD` against the PR's `headRefName` and
fails when they differ. The implementer calls it before any write, so a
mis-targeted session stops there instead of committing to another branch.

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

**Signal / read convergence** — `signal_convergence <pr> [body] [reviewed-sha]` and
`read_convergence <pr>` (`approved` | `converged` | `pending`, gated on
the current head SHA). These wrap the two primitives below and pick
between them on identity; see
[Prerequisite — reviewer identity](#prerequisite--reviewer-identity).

```bash
# submit_approval <pr> [body] — preferred, needs an identity that is not the author
gh pr review "$pr" --approve ${body:+--body "$body"}

# read_review_decision <pr>
gh pr view "$pr" --json reviewDecision -q .reviewDecision
# => APPROVED | CHANGES_REQUESTED | REVIEW_REQUIRED | (empty)

# assert_can_approve <pr> — 0 when `gh`'s login differs from the PR author
```

The next two are **implementer-side** (`apply-loop`) — the sole writer.
The reviewer never calls them.

**Reply to a thread** — `add_reply <thread-id> <body>` (keyed on the
thread node id, so it survives a moving diff). The body references the
fixing commit SHA, or carries a `<!-- stenswf-left-open: <reason> -->`
marker when the finding is left open:

```graphql
mutation($threadId:ID!,$body:String!){
  addPullRequestReviewThreadReply(input:{
    pullRequestReviewThreadId:$threadId, body:$body
  }){ comment{ id } }
}
```

**Resolve a thread** — `resolve_thread <thread-id>` (after the fix is
committed and pushed). Prints the post-resolution `isResolved` flag:

```graphql
mutation($threadId:ID!){
  resolveReviewThread(input:{threadId:$threadId}){ thread{ id isResolved } }
}
```
