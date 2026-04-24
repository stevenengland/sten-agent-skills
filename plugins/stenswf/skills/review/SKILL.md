---
name: review
description: Review changes against an issue, slice, or PRD.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs reasoning, axis-by-axis narration, and orchestration chatter.
The review artifacts (slice suggestions, PRD capstone XML) are full-prose
artifacts (already excluded by `brevity`'s Scope section).

---

You are in **plan-only mode**. Do not apply edits, create files outside
`.stenswf/<issue>/` or `/tmp/`, or run state-modifying git commands. Your
output is a structured review artifact on disk.

## Mode Detection

Mode is detected from the issue body's `## Type` marker. Fetch and parse:

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
TYPE=$(awk '/^## Type/,/^## /' /tmp/slice-$ARGUMENTS.md \
  | sed '$d' | tail -n +3 | head -1 | tr -d '[:space:]')
```

- `$TYPE == "PRD"` → **PRD-mode** (capstone review).
- `$TYPE` starts with `slice` → **Slice-mode**.
- Unrecognised or missing → check local `.stenswf/$ARGUMENTS/manifest.json`
  (`.kind` field) as cache. Otherwise ask the user.

**Announce the detected mode** as your first line of output. Then load
**only** the matching reference body below and follow it end to end.
Ignore the other reference entirely.

- Slice-mode → read [`slice.md`](slice.md) and execute it.
- PRD-mode → read [`prd.md`](prd.md) and execute it.

## Drift check (both modes)

Before reviewing, re-hash the current issue body and compare against
`.stenswf/$ARGUMENTS/manifest.json:concept_sha256` if it exists. On
mismatch, present the `(r)e-plan / (c)ontinue / (a)bort` menu (same
contract as `ship`). On the `r`e-plan branch, after the user accepts,
overwrite `concept.md` with the current body, recompute
`concept_sha256`, and append a `drift-replan` entry to `log.jsonl`.

## PRD-mode local-state backfill

PRD-mode assumes `.stenswf/$ARGUMENTS/{manifest.json,concept.md}` exist
(seeded by `prd-from-grill-me` at inception). For PRDs created before
the seeding step was added, backfill on first run if missing:

```bash
if [ "$TYPE" = "PRD" ] && [ ! -f ".stenswf/$ARGUMENTS/manifest.json" ]; then
  mkdir -p ".stenswf/$ARGUMENTS"
  cp "/tmp/slice-$ARGUMENTS.md" ".stenswf/$ARGUMENTS/concept.md"
  CONCEPT_SHA=$(sha256sum ".stenswf/$ARGUMENTS/concept.md" | awk '{print $1}')
  PRD_BASE=$(git rev-parse "prd-$ARGUMENTS-base" 2>/dev/null \
    || grep -oP 'PRD base SHA:\s*\K[0-9a-f]{7,40}' ".stenswf/$ARGUMENTS/concept.md")
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
  printf '{"ts":"%s","event":"prd-manifest-backfilled"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> ".stenswf/$ARGUMENTS/log.jsonl"
fi
```

Announce when a backfill happened so the user knows drift detection is
seeded against the current body (not a prior snapshot).
