# Bug-brief-mode — apply slice-mode reviews across children

Apply behavior:

- Gating mirrors PRD-mode: refuse to run while any child slice is
  still open.
- No themed cleanup PR — a single-defect retrospective does not need
  axis-grouped cleanup commits.
- Iterates child slices and runs the full slice-mode `apply` logic
  from [slice.md](slice.md) against each one.

## Step 0 — Strict gating

Refuse to run while any slice of this bug-brief is still open:

```bash
gh issue list --state open \
  --search "in:body \"Parent PRD\" \"#$ARGUMENTS\"" \
  --json number,title
```

If any rows return, stop:

> Bug-brief-apply blocked: slices still open (#A, #B, …). Ship them first.

## Step 1 — Enumerate children with reviews

Only children that have a `review/slice.md` artifact are eligible:

```bash
CHILDREN=$(gh issue list --state closed \
  --search "in:body \"Parent PRD\" \"#$ARGUMENTS\"" \
  --json number -q '.[].number')

ELIGIBLE=""
for C in $CHILDREN; do
  if [ -s ".stenswf/$C/review/slice.md" ]; then
    ELIGIBLE="$ELIGIBLE $C"
  fi
done

[ -n "$ELIGIBLE" ] || {
  echo "No reviewed child slices found. Run /stenswf:review on each child first." >&2
  exit 1
}
```

## Step 2 — Run slice-mode apply per child

For each child issue number `$CHILD` in `$ELIGIBLE`:

1. Re-bind `$ARGUMENTS = $CHILD` for the duration of the loop.
2. Run the freshness check from [slice.md](slice.md) Step 0 (refuse
   if `reviewed-at` SHA does not match current HEAD or if recorded
   `diff-sha256` does not match the live working diff).
3. Run the full slice-mode pipeline: drift-check, `apply-state.json`
   init/load (resume-safe), Phases 1-3.
4. Restore `$ARGUMENTS` to the bug-brief number for the next
   iteration.

The bug-brief itself receives **no** cleanup PR and no closing
operation here — child slices were already closed when their PRs
merged. Tell the user:

> Bug-brief #$ARGUMENTS apply complete: <list of children processed>.
> No bug-brief-level cleanup PR is opened (single-defect
> retrospective).

Emit the feedback-log boundary ping.
