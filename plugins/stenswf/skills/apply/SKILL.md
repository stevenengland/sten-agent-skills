---
name: apply
description: Apply a review — slice-mode (interactive per-suggestion) or PRD-mode
  (themed cleanup PR from local `<prd-review>` findings, mirrored onto the PR).
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs the interactive loop, YOLO-mode summaries, and reasoning.
Commit messages, PR bodies, and mirrored PR comments are full-prose
artifacts (already excluded by `brevity`'s Scope section).

---

## Mode Detection

Mode is detected from the issue body's `## Type` marker (not labels).

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
TYPE=$(awk '/^## Type/,/^## /' /tmp/slice-$ARGUMENTS.md \
  | sed '$d' | tail -n +3 | head -1 | tr -d '[:space:]')
```

- `$TYPE == "PRD"` → **PRD-mode**.
- `$TYPE` starts with `slice` → **Slice-mode**.
- Fallback: `.stenswf/$ARGUMENTS/manifest.json:.kind`.

**Announce the detected mode** as your first line of output. Then load
**only** the matching reference body below and follow it end to end.
Ignore the other reference entirely.

- Slice-mode → read [`slice.md`](slice.md) and execute it.
- PRD-mode → read [`prd.md`](prd.md) and execute it.

## Prerequisites (both modes)

- Confirm the review artifact exists on disk:

  - Slice-mode: `.stenswf/$ARGUMENTS/review/slice.md`.
  - PRD-mode: `.stenswf/$ARGUMENTS/review/prd-review.xml`.

  If missing, stop: `Run /stenswf:review $ARGUMENTS first.`

- Drift check (same contract as `ship`): if issue body hash differs
  from `manifest.json:concept_sha256`, present the re-plan / continue /
  abort menu.

- Initialise or load `.stenswf/$ARGUMENTS/apply-state.json`. Both modes
  share one schema; only the entry-ID prefix differs. Slice-mode uses
  `S<n>` (suggestion index from `review/slice.md`); PRD-mode uses `F<n>`
  (finding IDs from `review/prd-review.xml`).

  ```json
  {
    "mode": "slice",
    "entries": {
      "S1": {"status": "pending", "commit_sha": null, "reason": null},
      "S2": {"status": "pending", "commit_sha": null, "reason": null}
    }
  }
  ```

  `status` values: `pending | approved | applied | skipped`.
  `commit_sha` is set when a change lands; `reason` is set when skipped.

  On init, set `mode` to the detected mode (`"slice"` or `"prd"`) and
  pre-populate `entries` by enumerating suggestion IDs from
  `review/slice.md` (slice-mode) or finding IDs from
  `review/prd-review.xml` (PRD-mode), each with
  `{"status":"pending","commit_sha":null,"reason":null}`. If the file
  already exists from a previous run, load it and resume — do not
  overwrite applied/skipped entries.
