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

- [ ] **Establish the feature branch** (adopt-or-create, resume-safe). On a
  non-default branch, adopt it; on the default branch, create
  `impl/$ARGUMENTS-$SLUG` off `origin/$DEFAULT`. Never dispatch tasks onto
  the default branch:

  ```bash
  set -euo pipefail
  D=.stenswf/$ARGUMENTS
  DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
  [ -n "$DEFAULT" ] || { echo "ERROR: could not resolve default branch"; exit 1; }

  # Resume-safe: branch + base_sha persist in the manifest after the first run.
  SAVED_BR=$(jq -r '.branch // ""' "$D/manifest.json")
  CUR=$(git branch --show-current)

  if [ -n "$SAVED_BR" ]; then
    # Resume — ensure we are on the recorded branch; never re-create or
    # clobber base_sha (Phase 2 refactor diff reads the original .base_sha).
    [ "$CUR" = "$SAVED_BR" ] || git checkout "$SAVED_BR" || {
      echo "ERROR: cannot resume on recorded branch $SAVED_BR"; exit 1; }
  else
    # First run — adopt-or-create.
    if [ -n "$CUR" ] && [ "$CUR" != "$DEFAULT" ]; then
      # Adopt the current branch — but refuse a stale branch from another
      # issue (e.g. left on impl/42-* after shipping #42, now shipping #43).
      case "$CUR" in
        "impl/$ARGUMENTS"|"impl/$ARGUMENTS-"*) BR="$CUR" ;;  # our own — adopt
        impl/*) echo "ERROR: on $CUR — looks like another issue's branch; switch to $DEFAULT and re-run"; exit 1 ;;
        *) BR="$CUR" ;;                                      # user's own named branch — adopt
      esac
    else
      git fetch origin "$DEFAULT"
      SLUG=$(gh issue view $ARGUMENTS --json title -q .title \
        | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | cut -c1-40)
      BR="impl/$ARGUMENTS-$SLUG"
      git checkout -b "$BR" "origin/$DEFAULT" || {
        echo "ERROR: branch creation failed (stale $BR from a prior run? delete or check it out, then re-run)"
        exit 1; }
    fi
    BASE_SHA=$(git rev-parse HEAD)
    jq --arg b "$BR" --arg s "$BASE_SHA" \
      '.branch=$b | .base_sha=$s' "$D/manifest.json" \
      > "$D/manifest.json.tmp" && mv "$D/manifest.json.tmp" "$D/manifest.json"
  fi
  ```

- [ ] **Resume detection** — find first `manifest.tasks[].status != "done"`.
  All done → go straight to [post-dispatch.md](post-dispatch.md).

---

## Phase 1 — Task Execution (Orchestrator Loop)

**Branch gate — HARD INVARIANT (before the first dispatch).** No task may be
dispatched while HEAD is on the default branch:

```bash
CUR=$(git branch --show-current)
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
BR=$(jq -r '.branch // ""' .stenswf/$ARGUMENTS/manifest.json)
[ -n "$BR" ] && [ "$CUR" = "$BR" ] && [ "$CUR" != "$DEFAULT" ] || {
  echo "ERROR: branch gate failed (on=$CUR expected=$BR default=$DEFAULT) — refusing to dispatch onto the default branch"
  exit 1; }
```

Do NOT recover a gate violation by retroactively branching off a dirty HEAD —
abort and let the user recover.

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
