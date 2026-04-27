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

You are in **plan-only mode**. Do not apply edits to source/test files
or run state-modifying git commands.

The only writes this skill performs are:

- the review artifact tree under `.stenswf/<issue>/review/`,
- a drift-accepted `decision` meta-entry appended to
  `.stenswf/<issue>/decisions.md` (only on the `(c)ontinue` drift
  branch, per
  [../../references/decision-anchor-link.md](../../references/decision-anchor-link.md)),
- a feedback record under `.stenswf/_feedback/<date>.jsonl` (per
  [../../references/feedback-log.md](../../references/feedback-log.md)),
- scratch files under `/tmp/`.

No other writes; no `git add/commit/push/reset/rebase/merge`, no
`gh issue comment`.

**Constraint reminder before loading mode-specific logic.** The mode
files (`slice.md`, `prd.md`) are long; the no-source-edits invariant
must survive that read. Restate before proceeding: **plan-only — no
edits to source/test files, no state-modifying git, no
`gh issue comment`. Permitted writes: `.stenswf/<issue>/review/`,
the drift-continue append to `.stenswf/<issue>/decisions.md`,
`.stenswf/_feedback/`, and `/tmp/`.**

## Mode Detection

**Ceremony invariant (TDD-as-lens).** This skill MUST NOT (a)
instruct skipping tests for ACs annotated `(behavior)`, (b) remove
`tdd` from any SKILLS TO LOAD list, (c) accept `manual check` or
"rely on existing suite" as completion evidence for a `(behavior)`
AC, or (d) emit guidance that contradicts `tdd/SKILL.md`. Detection
of behavior change is the gate; loading `tdd` is the lens; whether
to write a test follows from the AC tag, not from this skill. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

Detect mode (slice / PRD / bug-brief) per
[../../references/mode-detection.md](../../references/mode-detection.md),
then load the matching sub-file:

- `TYPE == "PRD"` → load [prd.md](prd.md).
- `TYPE == "bug-brief"` → load [bug-brief.md](bug-brief.md) (gates
  like PRD-mode, then iterates children running slice-mode logic).
- `TYPE` starts with `slice` → load [slice.md](slice.md).

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

## PRD-mode / bug-brief-mode local-state backfill

For PRDs or bug-briefs created before the seeding step existed:

```bash
source plugins/stenswf/scripts/extractors.sh
if { [ "$TYPE" = "PRD" ] || [ "$TYPE" = "bug-brief" ]; } \
   && [ ! -f ".stenswf/$ARGUMENTS/manifest.json" ]; then
  mkdir -p ".stenswf/$ARGUMENTS"
  cp "/tmp/slice-$ARGUMENTS.md" ".stenswf/$ARGUMENTS/concept.md"
  CONCEPT_SHA=$(sha256sum ".stenswf/$ARGUMENTS/concept.md" | awk '{print $1}')
  CLAUDE_SHA=$(git log -1 --format=%H -- CLAUDE.md AGENTS.md 2>/dev/null | head -1)
  PRD_BASE=$(get_fm prd_base_sha "/tmp/slice-$ARGUMENTS.md")
  [ -n "$PRD_BASE" ] || { echo "#$ARGUMENTS missing prd_base_sha in front-matter" >&2; exit 1; }
  KIND=$( [ "$TYPE" = "PRD" ] && echo prd || echo bug-brief )
  cat > ".stenswf/$ARGUMENTS/manifest.json" <<EOF
{
  "issue": $ARGUMENTS,
  "kind": "$KIND",
  "base_sha": "$PRD_BASE",
  "concept_sha256": "$CONCEPT_SHA",
  "claude_md_sha": "$CLAUDE_SHA",
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
