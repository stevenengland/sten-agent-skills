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

Read and follow the shared finding-validation contract in
[../../references/review-finding-validation.md](../../references/review-finding-validation.md).

## Constraint — sole git writer

The implementer is the **sole git writer** (D4): `apply-loop` is the
only party that commits, pushes, and resolves threads; the reviewer
(`review-loop`) never does. Everything this skill writes to the PR goes
through [../../scripts/pr-threads.sh](../../scripts/pr-threads.sh)
(`add_reply`, `resolve_thread`) plus ordinary `git commit`/`push` on the
PR branch and the disposable `.stenswf/<issue>/loop-state.implementer.json`
cache.
`assert_pr_branch` enforces the "on the PR branch" half of that at Phase
0 — being the sole writer is only safe if it is also the *right* tree —
and `sync_to_pr_head` enforces the "current" half at the top of **every**
pass, because sole-agent-writer never meant sole writer.

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
  `.stenswf/<issue>/loop-state.implementer.json`, not apply's `entries.S<n>` in
  `apply-state.json`. That file is a cache; the PR is the record (see the
  reference's *Where the state lives*).

## Phase 0 — Resolve target + mode

```bash
source ../../scripts/extractors.sh
source ../../scripts/pr-threads.sh

PR=$(resolve_pr "$ARGUMENTS")          # arg (number/URL) or current branch's PR
[ -n "$PR" ] || { echo "ROUTE_HEAVY: no PR for arg/current branch"; exit 1; }

assert_pr_branch "$PR" || exit 1        # sole writer: never commit to another branch
ISSUE=$(resolve_issue "$PR") || exit 1  # via closingIssuesReferences; loud on 0 or >1
STATE=".stenswf/$ISSUE/loop-state.implementer.json"   # role-partitioned: see reference
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

**Start every pass on the PR's head.** Not once at startup — *every pass*.
The loop spends most of its life waiting, and `wait_for_change` reports
`head-advanced` precisely because someone else can push while it waits;
verifying and committing on top of what that push replaced is how a fix
silently reverts a human's:

```bash
sync_to_pr_head "$PR" || exit 1   # fast-forwards, or stops before any edit
```

It refuses rather than rebases when the branch has diverged — that is a
merge decision, and it belongs to the user, not to a sync step on its way
into an edit.

`list_open_threads $PR` yields every open thread as
`<node-id>\t<isResolved>\t<author>\t<disposition>\t<fingerprint>\t<body>`.
**Skip any row whose `disposition` is not `none`** — it is already
handled, and the PR says so, so a restarted harness never double-replies
even with `$STATE` deleted:

```bash
list_open_threads "$PR" | awk -F'\t' '$4=="none"'
```

For each remaining thread — **regardless of author** (the paired reviewer
*or* a human) — before any fix:

1. **Verify (mandatory — D7).** Apply
   [../../references/review-finding-validation.md](../../references/review-finding-validation.md).
   A behavior thread MUST NOT be marked applied without a reproducing
   failing test written first.

2. **Confirmed, safe, non-rollback remedy.** Fix it autonomously →
   conventional commit → `git push` → `add_reply <node-id> "<what changed>,
   fixed in <sha>"` → `resolve_thread <node-id>`.

3. **Rejected or inconclusive after verification (D8).** Leave the thread
   **open**: `add_reply <node-id>` with the verification result and a
   trailing `<!-- stenswf-left-open: <reason> -->` marker. Do **not**
   resolve. Collect it for the end-of-session summary.

4. **Rollback, or confirmed with no safe remedy.** The thread stays
   unresolved and unhandled — a rollback until the shared approval gate
   decides it, a missing safe remedy as a blocker.

A thread is **handled** when it is resolved OR carries a left-open
reply — and `list_threads` reports that as its `disposition`, so the
question is answered by reading the PR, never by trusting local memory.
Cache each node-id's disposition in `$STATE` to save re-verification
work; correctness must not depend on it.

## Phase 2 — Converge or wait

- **Stop** when every open thread is handled AND `read_convergence $PR`
  is `approved` or `converged` (D5) — the first is a formal approval, the
  second the marker the reviewer must fall back to when it shares an
  identity with the PR author. Both are gated on the PR's **current head**,
  so a signal from before your last push does not count. Then print the
  end-of-session summary (below), naming which one you got.

  ```bash
  case "$(read_convergence "$PR")" in
    approved|converged) CONVERGED=$(read_convergence "$PR") ;;
    *) CONVERGED="" ;;
  esac
  ```
- Otherwise bump the cycle and wait for the reviewer to move:

  ```bash
  loop_cycle_bump "$STATE" || { <post cap summary comment>; exit 0; }
  wait_for_change "$PR" "$(git rev-parse HEAD)"
  ```

  Between passes the reviewer may post new threads and HEAD may advance;
  the next pass re-lists and re-verifies. Pass the SHA you just pushed as
  `<since-sha>` so the wait ends on the reviewer's move, not on your own.

**Cap.** `loop_cycle_bump` enforces `LOOP_MAX_CYCLES` (default 5) and
returns non-zero once it is passed; on that signal post a summary comment
listing still-open threads and stop — never loop forever.

## End-of-session summary

Whether the loop converged or hit the cap, print every thread
**deliberately left open**, each with its node-id, author, and
`<!-- stenswf-left-open: <reason> -->` reason, so the user can
adjudicate the disputes. A converged run with nothing left open says so
explicitly.

State **how** it converged. `converged` means the reviewer shared the PR
author's identity and could only post the marker — the PR carries no
GitHub approval, and anything gating on one (branch protection, merge
automation, a human looking for the green check) still sees an unreviewed
PR. Say that plainly rather than reporting it as approval.

## Out of scope (deliberate)

No new review axes and no re-critique — findings come from the PR
threads the reviewer (or a human) posted. No auto-merge; converging and
resolving is the end state, merge stays a human/`ship` action.

## Feedback

Log friction throughout per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=apply-loop` and `STENSWF_ISSUE=$ISSUE`.
