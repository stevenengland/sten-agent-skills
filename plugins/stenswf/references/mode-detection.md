# Mode detection (review + apply)

Shared front-matter `type:` dispatch. Consumed by `review` and `apply`.

## Detect

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
TYPE=$(get_fm type /tmp/slice-$ARGUMENTS.md)
```

(See `get_fm` in [extractors.md](extractors.md).)

## Dispatch

- `TYPE == "PRD"` → PRD-mode → read `prd.md` and execute (capstone
  review / themed cleanup).
- `TYPE == "bug-brief"` → bug-brief-mode → behaves as **slice-mode on
  children**: review/apply runs the slice-mode flow against the
  bug-brief's child slice(s), no capstone synthesis. Gating mirrors
  PRD-mode (refuses while any child slice is open). Bug-briefs typically
  have one child; capstone semantics are intentionally skipped because a
  single-defect retrospective is not the same as a feature retrospective.
- `TYPE` starts with `slice` → Slice-mode → read `slice.md` and execute.
- Unrecognised or missing → fall back to `.stenswf/$ARGUMENTS/manifest.json:.kind`
  (`prd` | `bug-brief` | `slice`). If still undetermined, ask the user
  and log `contract_violation`.

**Announce the detected mode** as the first line of output, then load
the matching sub-skill body.
