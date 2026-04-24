# Mode detection (review + apply)

Shared front-matter `type:` dispatch. Consumed by `review` and `apply`.

## Detect

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
TYPE=$(get_fm type /tmp/slice-$ARGUMENTS.md)
```

(See `get_fm` in [extractors.md](extractors.md).)

## Dispatch

- `TYPE == "PRD"` → PRD-mode → read `prd.md` and execute.
- `TYPE` starts with `slice` → Slice-mode → read `slice.md` and execute.
- Unrecognised or missing → fall back to `.stenswf/$ARGUMENTS/manifest.json:.kind`.
  If still undetermined, ask the user and log `contract_violation`.

**Announce the detected mode** as the first line of output, then load
the matching sub-skill body.
