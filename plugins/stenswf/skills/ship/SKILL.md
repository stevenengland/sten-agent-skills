---
name: ship
description: Implement a slice issue by dispatching one subagent per local task fragment (TDD + clean code), run a refactor pass, file a PR, monitor CI to green, and archive the local plan on merge.
disable-model-invocation: true
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).
Subagents do NOT load `brevity`. A terse-reasoning rule is inlined in
`stable-prefix.md` instead.

---

Implement issue number $ARGUMENTS by dispatching subagents against the
local plan tree at `.stenswf/$ARGUMENTS/`. The local plan is the
**definitive specification**; issue body states the goal. On conflict,
local plan wins unless the issue body has drifted (see drift check).

**Ceremony invariant (TDD-as-lens).** This skill MUST NOT (a)
instruct skipping tests for ACs annotated `(behavior)`, (b) remove
`tdd` from any SKILLS TO LOAD list, (c) accept `manual check` or
"rely on existing suite" as completion evidence for a `(behavior)`
AC, or (d) emit guidance that contradicts `tdd/SKILL.md`. Detection
of behavior change is the gate; loading `tdd` is the lens; whether
to write a test follows from the AC tag, not from this skill. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

If `.stenswf/$ARGUMENTS/` missing, stop and ask the user to run
`/stenswf:plan $ARGUMENTS` first. Log `missing_artifact`.

---

## Prerequisites

- [ ] Capture feedback-session baseline per
  [../../references/feedback-session.md](../../references/feedback-session.md).
  Apply context-hygiene per
  [../../references/context-hygiene.md](../../references/context-hygiene.md).

- [ ] Detect the issue-tracker CLI (`gh`, `glab`, `tea`) and use it
  for every issue/PR command below.

- [ ] Confirm the local plan tree exists:

  ```bash
  D=.stenswf/$ARGUMENTS
  [ -s "$D/manifest.json" ]     || { echo "run /stenswf:plan $ARGUMENTS first"; exit 1; }
  [ -s "$D/stable-prefix.md" ]  || { echo "stable-prefix missing; re-run /stenswf:plan"; exit 1; }
  ```

- [ ] **Drift check** — full procedure at
  [../../references/drift-check.md](../../references/drift-check.md).
  On `(c)ontinue`, append a drift-accepted meta-entry to
  `decisions.md` and log `user_override`.

- [ ] Record `BASE_SHA`:

  ```bash
  BASE_SHA=$(git rev-parse HEAD)
  BRANCH=$(git branch --show-current)
  jq --arg b "$BRANCH" --arg s "$BASE_SHA" \
    '.branch=$b | .base_sha=$s' "$D/manifest.json" \
    > "$D/manifest.json.tmp" && mv "$D/manifest.json.tmp" "$D/manifest.json"
  ```

- [ ] **Resume detection** — find first `manifest.tasks[].status != "done"`.
  All done → go straight to [post-dispatch.md](post-dispatch.md).

---

## Phase 1 — Task Execution (Orchestrator Loop)

**Pre-dispatch behavior-change re-validation (per task).** Before
dispatching each task, re-fetch the issue body and re-evaluate the
AC tags against the heuristic ladder in
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).
On disagreement with the manifest's `tasks[].acs[].behavior_change`:

- Update the manifest in place.
- Regenerate the per-task `BEHAVIOR FLAGS` block emitted by the
  dispatch tail (see [dispatch.md](dispatch.md)). Task fragment
  files on disk are NOT modified — the flags live only in the
  per-dispatch tail so the cached `stable-prefix.md` stays
  identical across all tasks.
- Log `behavior_change_override` with `<ac> <old>→<new> <reason>`
  as evidence, where `<old>` and `<new>` are each `behavior` or
  `structural`. Subagent reports use the same wire format — no
  translation. See [dispatch.md](dispatch.md).

Ship wins on conflict. Untagged ACs at this checkpoint are a
`contract_violation` — stop and surface to the user; do not silently
default.

**Migration-mode bias (rule-5 fallback only).** If the slice
front-matter carries `migration_mode` (only present when the parent
PRD is `class: migration`; see
[../../references/front-matter-schema.md](../../references/front-matter-schema.md)),
shift the heuristic's rule-5 default before re-evaluating:

- `behavior-preserving` → ambiguous AC defaults to `(structural)`.
- `contract-changing` → ambiguous AC defaults to `(behavior)`.
- absent → default to `(behavior)` (the bare rule 5).

Producer tags still win where unambiguous; the bias only changes
the fallback for ACs the ladder cannot otherwise classify.

Full dispatch loop, subagent prompt, verify steps, manifest update,
and Task Blocker template: [dispatch.md](dispatch.md).

Walk pending tasks in order (`T10`, `T20`, …). When all report `done`,
proceed to [post-dispatch.md](post-dispatch.md) for Phases 2–5
(refactor pass, review step, PR + CI + merge, archive).

**Cross-task seam reflection — before handoff to `post-dispatch.md`.**
Per-task `done` ≠ slice-level integration `done`. Each subagent
verified its own fragment in isolation; nobody verified the seams
between fragments. Pause and step back: are there contracts or
assumptions spanning two tasks that no single task owned? If yes,
file a follow-up task fragment and resume the orchestrator loop
instead of advancing.

---

## Feedback

Log friction throughout per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=ship` and `STENSWF_ISSUE=$ARGUMENTS`.
