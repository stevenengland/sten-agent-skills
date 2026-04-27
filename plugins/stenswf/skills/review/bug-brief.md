# Bug-brief-mode — slice-mode review on children

A bug-brief is PRD-shaped but typically owns one slice (the fix).
Review behavior:

- Gating mirrors PRD-mode: refuse to run while any child slice is
  still open.
- No capstone synthesis — a single-defect retrospective is not a
  feature retrospective.
- Iterates child slices and runs the full slice-mode logic from
  [slice.md](slice.md) against each one.

## Step 0 — Strict gating

Refuse to run while any slice of this bug-brief is still open:

```bash
gh issue list --state open \
  --search "in:body \"Parent PRD\" \"#$ARGUMENTS\"" \
  --json number,title
```

If any rows return, stop:

> Bug-brief-review blocked: slices still open (#A, #B, …). Ship them first.

(Bug-brief-derived slices use `Parent PRD: #<bug-brief-N>` because the
bug-brief plays the PRD role — see
[../../references/bug-brief-class.md](../../references/bug-brief-class.md).)

Abandoned slices should be manually closed
(`gh issue close <N> --reason "not planned"`).

## Step 1 — Enumerate children

```bash
CHILDREN=$(gh issue list --state closed \
  --search "in:body \"Parent PRD\" \"#$ARGUMENTS\"" \
  --json number -q '.[].number')

[ -n "$CHILDREN" ] || {
  echo "No child slices found for bug-brief #$ARGUMENTS." >&2
  exit 1
}
```

## Step 2 — Run slice-mode review per child

For each child issue number `$CHILD` in `$CHILDREN`:

1. Re-bind `$ARGUMENTS = $CHILD` for the duration of the loop.
2. Fetch the child body and run the full slice-mode pipeline as
   defined in [slice.md](slice.md): Step 0 (synthesize conventions if
   missing), Step 1 (five-perspective inline critique), output
   artifact at `.stenswf/$CHILD/review/slice.md`, schema validation.
3. After the child review completes, restore `$ARGUMENTS` to the
   bug-brief number for the next iteration.

The bug-brief itself receives **no** `prd-review.xml` and **no**
`review/slice.md`. It is purely an orchestration step over its
children.

Tell the user:

> Bug-brief #$ARGUMENTS reviewed via children: <list>. Run
> `/stenswf:apply <child-N>` per child to walk suggestions
> interactively, or `/stenswf:apply $ARGUMENTS` to apply all
> children sequentially.

Emit the feedback-log boundary ping.
