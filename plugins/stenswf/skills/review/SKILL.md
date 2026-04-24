---
name: review
description: Review changes against an issue, slice, or PRD.
disable-model-invocation: true
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).
Review artifacts (slice suggestions, PRD capstone XML) are full-prose
artifacts.

---

You are in **plan-only mode**. Do not apply edits, create files outside
`.stenswf/<issue>/` or `/tmp/`, or run state-modifying git commands.
Output is a structured review artifact on disk.

## Mode Detection

Mode is detected from front-matter `type:` per
[../../references/extractors.md](../../references/extractors.md):

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
TYPE=$(get_fm type /tmp/slice-$ARGUMENTS.md)
```

- `TYPE == "PRD"` → PRD-mode (capstone review).
- `TYPE` starts with `slice` → Slice-mode.
- Unrecognised → check `.stenswf/$ARGUMENTS/manifest.json:.kind`.
  Otherwise ask the user and log `contract_violation`.

**Announce the detected mode** as your first line of output. Then load
only the matching reference body:

- Slice-mode → read [`slice.md`](slice.md) and execute it.
- PRD-mode → read [`prd.md`](prd.md) and execute it.

## Drift check (both modes)

Before reviewing: shared procedure at
[../../references/drift-check.md](../../references/drift-check.md).
On `(c)ontinue`, append `drift-accepted` to `log.jsonl`? No — log.jsonl
was removed. Instead, log `user_override` via
[../../references/feedback-log.md](../../references/feedback-log.md).
On `r`e-plan after user acceptance: overwrite `concept.md`, recompute
`concept_sha256`.

## PRD-mode local-state backfill

For PRDs created before the seeding step existed:

```bash
if [ "$TYPE" = "PRD" ] && [ ! -f ".stenswf/$ARGUMENTS/manifest.json" ]; then
  mkdir -p ".stenswf/$ARGUMENTS"
  cp "/tmp/slice-$ARGUMENTS.md" ".stenswf/$ARGUMENTS/concept.md"
  CONCEPT_SHA=$(sha256sum ".stenswf/$ARGUMENTS/concept.md" | awk '{print $1}')
  # Portable PRD-base resolution (no grep -oP / \K).
  PRD_BASE=$(git rev-parse "prd-$ARGUMENTS-base" 2>/dev/null)
  [ -z "$PRD_BASE" ] && PRD_BASE=$(get_fm prd_base_sha "/tmp/slice-$ARGUMENTS.md")
  [ -z "$PRD_BASE" ] && PRD_BASE=$(grep -oE 'prd_base_sha:[[:space:]]*[0-9a-f]{7,40}' \
    "/tmp/slice-$ARGUMENTS.md" | awk '{print $NF}' | head -1)
  cat > ".stenswf/$ARGUMENTS/manifest.json" <<EOF
{
  "issue": $ARGUMENTS,
  "kind": "prd",
  "base_sha": "$PRD_BASE",
  "concept_sha256": "$CONCEPT_SHA",
  "plan_created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "slices": [],
  "review_step": {"status": "pending", "sha": null}
}
EOF
fi
```

Announce the backfill so the user knows drift is seeded to current body.

---

## Feedback

Log friction via
[../../references/feedback-log.md](../../references/feedback-log.md).
Set `STENSWF_SKILL=review` and `STENSWF_ISSUE=$ARGUMENTS` before
calling `scripts/log-issue.sh`.
