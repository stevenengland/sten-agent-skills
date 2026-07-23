---
name: review-loop
description: Run the review engine over a live PR's new commits, post findings as fingerprinted resolvable threads, and approve on convergence.
disable-model-invocation: true
---

REASONING STYLE: terse internal reasoning, no pre-summaries, no filler.
Thread bodies, the approval comment, and the end-of-session summary
remain verbatim.

`review-loop` is the **reviewer** half of the PR conversation loop
(PRD #12). It is a thin orchestrator: it delegates the actual critique
to the existing `review` engine and turns that engine's findings into
**resolvable GitHub PR review threads**, then self-paces the next pass
and **approves** the PR once a fresh pass has nothing more to say. The
full contract — thread schema, fingerprint scheme, termination, cadence,
sole-writer rule, and the "handled" definition — lives in
[../../references/pr-conversation-loop.md](../../references/pr-conversation-loop.md).
Read it before proceeding.

## Constraint — read-only against git, PR-writer only

`review` runs **plan-only** (no writes outside `.stenswf/<issue>/review/`).
This skill **overrules that contract in exactly one direction**: it MAY
post PR review threads and submit a PR approval. It gains **no** other
write power — it MUST NOT edit source/test files, `git add/commit/push`,
or resolve threads. The implementer (`apply-loop`) is the **sole git
writer** (D4). Restate before loading the engine sub-file: **reviewer is
read-only against git; the only new writes are `add_thread` and
`signal_convergence` via
[../../scripts/pr-threads.sh](../../scripts/pr-threads.sh), plus the
disposable `.stenswf/<issue>/loop-state.json` cache.**

## Phase 0 — Resolve target + mode

```bash
source ../../scripts/extractors.sh
source ../../scripts/pr-threads.sh

PR=$(resolve_pr "$ARGUMENTS")          # arg (number/URL) or current branch's PR
[ -n "$PR" ] || { echo "ROUTE_HEAVY: no PR for arg/current branch"; exit 1; }

ISSUE=$(resolve_issue "$PR") || exit 1  # via closingIssuesReferences; loud on 0 or >1
STATE=".stenswf/$ISSUE/loop-state.json"

# GitHub refuses an approval from the PR's own author. Say so once, up
# front, rather than discovering it at the stop condition.
assert_can_approve "$PR" \
  || echo "note: this identity authored the PR — convergence will be signalled by comment"

gh issue view "$ISSUE" --json body -q .body > /tmp/rl-$ISSUE.md
TYPE=$(get_fm type /tmp/rl-$ISSUE.md)
parse_type                              # sets MODE (prd | slice)
```

Load the matching engine sub-file and drive its critique — but redirect
its output from local artifacts to PR threads (below):

- `MODE == prd` → [../review/prd.md](../review/prd.md).
- `MODE` is a slice → [../review/slice.md](../review/slice.md).

## Phase 1 — Delta pass

Start every pass by fetching the PR's head — the loop wakes on the
*remote* head moving, so reviewing the local working tree would review the
commit the last pass already saw:

```bash
HEAD_SHA=$(fetch_pr_head "$PR") || exit 1   # fetches the branch, prints its SHA
```

Then review only `<last-reviewed-sha>..$HEAD_SHA` (delta scope; the first
pass uses the PR base as `<last-reviewed-sha>`). Reading fetched objects
needs no checkout, so this stays read-only against the working tree.
Cache `last_reviewed_sha` in `$STATE` — a cache, not the record: the PR is
the authority, and this pass must be correct with `$STATE` deleted.

Run the engine sub-file's critique over that delta. For each finding it
produces:

1. Compute `fp=$(fingerprint <path> <anchor> <message>)` — `<anchor>` is
   a stable symbol/snippet, **never a line number** (D6).
2. Skip the finding if `fp` already appears in `list_fingerprints $PR`.
   That set spans **resolved** threads too, so a finding the implementer
   has already fixed and closed stays deduped rather than being posted
   afresh the next time the delta touches that code.
3. Otherwise post it: `add_thread $PR <path> <line> "$fp" "<message>"`.

**Carry forward.** Unresolved prior threads stay open — do not repost,
do not resolve (resolving is the implementer's job).

## Phase 2 — Converge or self-schedule

Read the handled state straight off the PR — column 4 of `list_threads`
is the `disposition` (`resolved` | `left-open` | `none`):

```bash
UNHANDLED=$(list_threads "$PR" | awk -F'\t' '$4=="none"' | wc -l)
```

- If this fresh delta pass produced **zero new findings** AND
  `$UNHANDLED` is 0:

  ```bash
  signal_convergence "$PR" "reviewer loop: nothing more to say" "$HEAD_SHA"
  ```

  Then stop. That approves the PR where this identity may, and posts the
  convergence marker where GitHub forbids self-approval — the implementer
  reads either. Pass `$HEAD_SHA`, the commit this pass actually read: the
  signal is pinned to it, so if the implementer pushed while you were
  reviewing, the marker names the revision you saw rather than silently
  blessing one you did not.
- Otherwise bump the cycle and wait for the implementer to move:

  ```bash
  loop_cycle_bump "$STATE" || { <post cap summary comment>; exit 0; }
  wait_for_change "$PR" "$HEAD_SHA"     # head-advanced <sha> | threads-changed | timeout
  ```

  Then start the next pass. Between passes HEAD advances as the
  implementer pushes fixes — the next delta picks those up.

**Cap.** `loop_cycle_bump` enforces `LOOP_MAX_CYCLES` (default 5) and
returns non-zero once it is passed; on that signal post a summary comment
listing still-open threads and stop — never loop forever.

## Out of scope (deliberate)

No code edits, no commits, no pushes, no thread resolution (all belong
to `apply-loop`, the sole git writer). No new review axes — the critique
is exactly what `review/slice.md` / `review/prd.md` produce; this skill
only changes where the findings land and adds the loop.

## Feedback

Log friction throughout per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=review-loop` and `STENSWF_ISSUE=$ISSUE`.
