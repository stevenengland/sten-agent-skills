---
name: apply
description: Apply a review — slice-mode (interactive per-suggestion) or PRD-mode (themed cleanup PR from local `<prd-review>` findings, mirrored onto the PR).
disable-model-invocation: true
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).

---

## Mode Detection

**Ceremony invariant (TDD-as-lens).** This skill MUST NOT (a)
instruct skipping tests for ACs annotated `(behavior)`, (b) remove
`tdd` from any SKILLS TO LOAD list, (c) accept `manual check` or
"rely on existing suite" as completion evidence for a `(behavior)`
AC, or (d) emit guidance that contradicts `tdd/SKILL.md`. Detection
of behavior change is the gate; loading `tdd` is the lens; whether
to write a test follows from the AC tag, not from this skill. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

Capture feedback-session baseline per
[../../references/feedback-session.md](../../references/feedback-session.md).
Apply context-hygiene per
[../../references/context-hygiene.md](../../references/context-hygiene.md).

Detect mode (slice / PRD / bug-brief) per
[../../references/mode-detection.md](../../references/mode-detection.md),
then load the matching sub-file:

- `TYPE == "PRD"` → load [prd.md](prd.md).
- `TYPE == "bug-brief"` → load [bug-brief.md](bug-brief.md) (gates
  like PRD-mode, then iterates children running slice-mode apply).
- `TYPE` starts with `slice` → load [slice.md](slice.md).

## Prerequisites (slice + PRD modes)

*(Skipped in bug-brief-mode — see [bug-brief.md](bug-brief.md), which
enforces per-child prerequisites.)*

- Confirm the review artifact exists on disk:
  - Slice-mode: `.stenswf/$ARGUMENTS/review/slice.md`.
  - PRD-mode: `.stenswf/$ARGUMENTS/review/prd-review.xml`.
  - Bug-brief-mode delegates this check to each child slice; see
    [bug-brief.md](bug-brief.md).

  If missing, stop: `Run /stenswf:review $ARGUMENTS first.` Log
  `missing_artifact`.

- Drift check: [../../references/drift-check.md](../../references/drift-check.md).

- Initialise/load `.stenswf/$ARGUMENTS/apply-state.json`. Both modes
  share one schema; entry-ID prefix differs. Slice-mode `S<n>` (from
  `review/slice.md`); PRD-mode `F<n>` (from `review/prd-review.xml`).

  ```json
  {
    "mode": "slice",
    "entries": {
      "S1": {"status": "pending", "commit_sha": null, "reason": null},
      "S2": {"status": "pending", "commit_sha": null, "reason": null}
    }
  }
  ```

  `status`: `pending | approved | applied | skipped`. `commit_sha` set
  when landed; `reason` set when skipped.

  On init, set `mode` to the detected mode and pre-populate `entries`
  by enumerating suggestion/finding IDs. On re-run, load and resume —
  do not overwrite `applied`/`skipped` entries.

**Constraint reminder before handing off to mode-specific logic.**
The single most dangerous failure of this skill is corrupting
`apply-state.json` on resume. Restate before proceeding: **on re-run,
load and resume — never overwrite entries with `status: applied` or
`status: skipped`. New runs only mutate `pending`/`approved` entries.
If state looks inconsistent, stop and surface, do not heal silently.**

---

## Feedback

Log friction throughout per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=apply` and `STENSWF_ISSUE=$ARGUMENTS`.
