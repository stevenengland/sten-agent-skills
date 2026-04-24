---
name: apply
description: Apply a review — slice-mode (interactive per-suggestion) or PRD-mode (themed cleanup PR from local `<prd-review>` findings, mirrored onto the PR).
disable-model-invocation: true
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).

---

## Mode Detection

Capture feedback-log baseline for the session boundary ping
(see [../../references/feedback-log.md](../../references/feedback-log.md)):

```bash
FB_LOG=".stenswf/_feedback/$(date -u +%F).jsonl"
mkdir -p "$(dirname "$FB_LOG")"
SESSION_START_N=$(wc -l < "$FB_LOG" 2>/dev/null || echo 0)
export SESSION_START_N
```

Mode is detected from front-matter `type:` per
[../../references/extractors.md](../../references/extractors.md):

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
TYPE=$(get_fm type /tmp/slice-$ARGUMENTS.md)
```

- `TYPE == "PRD"` → PRD-mode.
- `TYPE` starts with `slice` → Slice-mode.
- Fallback: `.stenswf/$ARGUMENTS/manifest.json:.kind`.

**Announce the detected mode** as the first line of output. Then load
only the matching reference body:

- Slice-mode → read [`slice.md`](slice.md) and execute it.
- PRD-mode → read [`prd.md`](prd.md) and execute it.

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

---

## Feedback

Log friction via
[../../references/feedback-log.md](../../references/feedback-log.md).
Set `STENSWF_SKILL=apply` and `STENSWF_ISSUE=$ARGUMENTS` before
calling `scripts/log-issue.sh`.

On exit, emit the boundary ping:

```bash
FB_LOG=".stenswf/_feedback/$(date -u +%F).jsonl"
N=$(wc -l < "$FB_LOG" 2>/dev/null || echo 0)
SESSION_N=$((N - ${SESSION_START_N:-0}))
if [ "$SESSION_N" -gt 0 ]; then
  echo "stenswf: $SESSION_N workflow issues reported this session — see .stenswf/_feedback/"
fi
```
