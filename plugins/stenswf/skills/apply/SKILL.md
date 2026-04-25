---
name: apply
description: Apply a review — slice-mode (interactive per-suggestion) or PRD-mode (themed cleanup PR from local `<prd-review>` findings, mirrored onto the PR).
disable-model-invocation: true
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).

---

## Mode Detection

Capture feedback-session baseline per
[../../references/feedback-session.md](../../references/feedback-session.md).
Apply context-hygiene per
[../../references/context-hygiene.md](../../references/context-hygiene.md).

Detect mode (slice vs PRD) per
[../../references/mode-detection.md](../../references/mode-detection.md),
then load `slice.md` or `prd.md` accordingly.

## Prerequisites (both modes)

- Confirm the review artifact exists on disk:
  - Slice-mode: `.stenswf/$ARGUMENTS/review/slice.md`.
  - PRD-mode: `.stenswf/$ARGUMENTS/review/prd-review.xml`.

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
