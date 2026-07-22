---
name: apply-loop
description: Verify every open PR review thread regardless of author, fix and resolve the valid ones, leave disputed ones open with a reason, and converge on approval.
disable-model-invocation: true
---

REASONING STYLE: terse internal reasoning, no pre-summaries, no filler.
Reply bodies, the left-open reasons, the cap summary comment, and the
end-of-session summary remain verbatim.

`apply-loop` is the **implementer** half of the PR conversation loop
(PRD #12). It is a thin orchestrator: it delegates the actual fix logic
to the existing `apply` engine and drives it from **open GitHub PR
review threads** instead of a local review artifact, independently
**verifying every thread** before acting, then self-paces until every
thread is handled and the PR is approved. The full contract — thread
schema, fingerprint scheme, the "handled" definition, termination,
cadence, and the sole-writer rule — lives in
[../../references/pr-conversation-loop.md](../../references/pr-conversation-loop.md).
Read it before proceeding.

## Constraint — sole git writer

The implementer is the **sole git writer** (D4): `apply-loop` is the
only party that commits, pushes, and resolves threads; the reviewer
(`review-loop`) never does. Everything this skill writes to the PR goes
through [../../scripts/pr-threads.sh](../../scripts/pr-threads.sh)
(`add_reply`, `resolve_thread`) plus ordinary `git commit`/`push` on the
PR branch and the in-session `.stenswf/<issue>/loop-state.json` mirror.

## Overrules of the `apply` engine

`apply` is driven by a **local review artifact** and refuses to run
against a moving diff. This skill **overrules three parts** of that
contract (D2) and keeps everything else — the TDD-as-lens ceremony
invariant especially:

- *Input source.* Read **all open PR review threads (any author)** via
  `list_open_threads $PR`, NOT `.stenswf/<issue>/review/slice.md`.
  Overrules apply's "review artifact exists on disk / else stop"
  prerequisite.
- *Freshness guard removed.* The diff moves by design. Overrules
  apply/slice Step 0's stale-diff refusal — re-fetch HEAD and re-verify
  each thread against current code every pass instead of refusing.
- *State keys.* Key handled/verify state on the **PR thread node-id** in
  `.stenswf/<issue>/loop-state.json`, not apply's `entries.S<n>` in
  `apply-state.json`.

## Phase 0 — Resolve target + mode

```bash
source ../../scripts/extractors.sh
source ../../scripts/pr-threads.sh

PR=$(resolve_pr "$ARGUMENTS")          # arg (number/URL) or current branch's PR
[ -n "$PR" ] || { echo "ROUTE_HEAVY: no PR for arg/current branch"; exit 1; }

ISSUE=$(gh pr view "$PR" --json body -q .body \
  | sed -n 's/.*[Cc]loses #\([0-9]\+\).*/\1/p' | head -1)
gh issue view "$ISSUE" --json body -q .body > /tmp/al-$ISSUE.md
TYPE=$(get_fm type /tmp/al-$ISSUE.md)
parse_type                              # sets MODE (prd | slice)
```

Load the matching engine sub-file for fix logic — but drive it from PR
threads, not a local artifact:

- `MODE == prd` → [../apply/prd.md](../apply/prd.md). Overrule its
  "themed cleanup PR on a separate branch" — fix on the existing PR
  branch and resolve threads there.
- `MODE` is a slice → [../apply/slice.md](../apply/slice.md).

## Phase 1 — Per-thread pass

`list_open_threads $PR` yields every open thread as
`<node-id>\t<author>\t<body>`. For each — **regardless of author** (the
paired reviewer *or* a human) — before any fix:

1. **Verify (tag-driven, mandatory — D7).** Never trust a thread on its
   author. A thread claiming a **behavior** defect is reproduced with a
   failing test first (`tdd` red→green) before the fix; a non-behavior
   finding is confirmed by tracing the code. A behavior thread MUST NOT
   be marked applied without a reproducing test written first — the
   TDD-as-lens gate is inherited unchanged and MUST NOT contradict
   [../tdd/SKILL.md](../tdd/SKILL.md).

2. **Valid after verification.** Fix it → conventional commit → `git
   push` → `add_reply <node-id> "<what changed>, fixed in <sha>"` →
   `resolve_thread <node-id>`.

3. **Invalid after verification (D8).** Leave the thread **open**:
   `add_reply <node-id>` with the verification result and a trailing
   `<!-- stenswf-left-open: <reason> -->` marker. Do **not** resolve.
   Collect it for the end-of-session summary.

A thread is **handled** when it is resolved OR carries a left-open
reply. Record each node-id's disposition in
`.stenswf/$ISSUE/loop-state.json` so a restarted harness resumes without
re-verifying or double-replying.

## Phase 2 — Converge or self-schedule

- **Stop** when every open thread is handled AND
  `read_review_decision $PR == APPROVED` (D5). Then print the
  end-of-session summary (below).
- Otherwise **self-schedule** the next pass via a scheduled wake-up (do
  not wrap `/loop`; D10). Between passes the reviewer may post new
  threads and HEAD may advance; the next pass re-lists and re-verifies.

**Cap.** Bounded by `LOOP_MAX_CYCLES` (default 5). On reaching the cap,
post a summary comment listing still-open threads and stop — never loop
forever.

## End-of-session summary

Whether the loop converged or hit the cap, print every thread
**deliberately left open**, each with its node-id, author, and
`<!-- stenswf-left-open: <reason> -->` reason, so the user can
adjudicate the disputes. A converged run with nothing left open says so
explicitly.

## Out of scope (deliberate)

No new review axes and no re-critique — findings come from the PR
threads the reviewer (or a human) posted. No auto-merge; converging and
resolving is the end state, merge stays a human/`ship` action.

## Feedback

Log friction throughout per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=apply-loop` and `STENSWF_ISSUE=$ISSUE`.
