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
`submit_approval` via
[../../scripts/pr-threads.sh](../../scripts/pr-threads.sh), plus the
in-session `.stenswf/<issue>/loop-state.json` mirror.**

## Phase 0 — Resolve target + mode

```bash
source ../../scripts/extractors.sh
source ../../scripts/pr-threads.sh

PR=$(resolve_pr "$ARGUMENTS")          # arg (number/URL) or current branch's PR
[ -n "$PR" ] || { echo "ROUTE_HEAVY: no PR for arg/current branch"; exit 1; }

ISSUE=$(gh pr view "$PR" --json body -q .body \
  | sed -n 's/.*[Cc]loses #\([0-9]\+\).*/\1/p' | head -1)
gh issue view "$ISSUE" --json body -q .body > /tmp/rl-$ISSUE.md
TYPE=$(get_fm type /tmp/rl-$ISSUE.md)
parse_type                              # sets MODE (prd | slice)
```

Load the matching engine sub-file and drive its critique — but redirect
its output from local artifacts to PR threads (below):

- `MODE == prd` → [../review/prd.md](../review/prd.md).
- `MODE` is a slice → [../review/slice.md](../review/slice.md).

## Phase 1 — Delta pass

Per pass, review only `<last-reviewed-sha>..HEAD` (delta scope; the
first pass uses the PR base as `<last-reviewed-sha>`). Persist
`last_reviewed_sha` in `.stenswf/$ISSUE/loop-state.json`.

Run the engine sub-file's critique over that delta. For each finding it
produces:

1. Compute `fp=$(fingerprint <path> <anchor> <message>)` — `<anchor>` is
   a stable symbol/snippet, **never a line number** (D6).
2. Skip the finding if `fp` already appears among the fingerprints on
   the PR (`list_open_threads $PR` bodies). This dedups across passes so
   nothing is reposted.
3. Otherwise post it: `add_thread $PR <path> <line> "$fp" "<message>"`.

**Carry forward.** Unresolved prior threads stay open — do not repost,
do not resolve (resolving is the implementer's job).

## Phase 2 — Converge or self-schedule

- If this fresh delta pass produced **zero new findings** AND every
  thread `review-loop` has raised is **handled** (resolved, or open with
  a `<!-- stenswf-left-open: <reason> -->` reply — see the reference):
  `submit_approval $PR "reviewer loop: nothing more to say"`. Then stop.
- Otherwise, **self-schedule** the next pass via a scheduled wake-up
  (do not wrap `/loop`; D10). Between passes, HEAD may advance as the
  implementer pushes fixes — the next delta picks those up.

**Cap.** Bounded by `LOOP_MAX_CYCLES` (default 5). On reaching the cap,
post a summary comment listing still-open threads and stop — never loop
forever.

## Out of scope (deliberate)

No code edits, no commits, no pushes, no thread resolution (all belong
to `apply-loop`, the sole git writer). No new review axes — the critique
is exactly what `review/slice.md` / `review/prd.md` produce; this skill
only changes where the findings land and adds the loop.

## Feedback

Log friction throughout per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=review-loop` and `STENSWF_ISSUE=$ISSUE`.
