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

Full dispatch loop, subagent prompt, verify steps, manifest update,
and Task Blocker template: [dispatch.md](dispatch.md).

Walk pending tasks in order (`T10`, `T20`, …). When all report `done`,
proceed to [post-dispatch.md](post-dispatch.md) for Phases 2–5
(refactor pass, review step, PR + CI + merge, archive).

---

## Feedback

Log friction throughout per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=ship` and `STENSWF_ISSUE=$ARGUMENTS`.
