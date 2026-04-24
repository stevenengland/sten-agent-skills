# Curated decisions — stenswf

Committed, team-visible excerpts of per-issue decision anchors
(`.stenswf/<N>/decisions.md`).

One file per PRD: `prd-<N>.md`, written silently by
`/stenswf:apply` in PRD-mode at PRD close and staged as part of the
cleanup PR.

## Curation filter

An entry is included iff all three hold:

1. `Category` ∈ {`arch`, `decision`}
2. Entry is **not superseded** (active header `### D<n> —`, not
   strikethrough `### ~~D<n>~~`)
3. `Refs:` contains at least one concrete file path (proves the
   decision landed in code)

`assumption` entries (and any silent resolutions tracked only in PR
bodies) are intentionally excluded — the committed excerpt is a
library of durable decisions, not a working log.

## Manual excerpt (solo-slice flows)

Slice-only flows (no PRD) don't produce excerpts by default. If you
want one, run:

```bash
N=<slice-issue>
awk '/^### D[0-9]+/,/^### /' .stenswf/$N/decisions.md \
  | grep -B1 -A5 -E 'Category: (arch|decision)' \
  > docs/stenswf/decisions/slice-$N.md
```

Review the output before committing.

## Schema

Matches the full schema at
[../../../plugins/stenswf/README.md](../../../plugins/stenswf/README.md#decision-anchor-contract).
Excerpts may drop the `Source:` field (origin is the excerpt filename)
but preserve title, category, rationale, and refs verbatim.
