---
name: review
description: Review changes against an issue, slice, or PRD.
disable-model-invocation: true
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).
Review artifacts (slice suggestions, PRD capstone XML) are full-prose
artifacts.
Apply context-hygiene per
[../../references/context-hygiene.md](../../references/context-hygiene.md).

---

You are in **plan-only mode**. Do not apply edits, create files outside
`.stenswf/<issue>/` or `/tmp/`, or run state-modifying git commands.
Output is a structured review artifact on disk.

**Constraint reminder before loading mode-specific logic.** The mode
files (`slice.md`, `prd.md`) are long; the no-edits invariant must
survive that read. Restate before proceeding: **plan-only — no
edits, no file creation outside `.stenswf/<issue>/` or `/tmp/`, no
state-modifying git, no `git commit/push/reset/rebase/merge`. Output
is a review artifact on disk and nothing else.**

## Mode Detection

Detect mode (slice vs PRD) per
[../../references/mode-detection.md](../../references/mode-detection.md),
then load `slice.md` or `prd.md` accordingly.

## Drift check (both modes)

Before reviewing: shared procedure at
[../../references/drift-check.md](../../references/drift-check.md).
On `(c)ontinue`, append a drift-accepted `decision` meta-entry to
`.stenswf/$ARGUMENTS/decisions.md` (per
[../../references/decision-anchor-link.md](../../references/decision-anchor-link.md))
and log `user_override` via
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

Log friction per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=review` and `STENSWF_ISSUE=$ARGUMENTS`.
