# Curated decisions — stenswf

Committed, team-visible excerpts of per-issue decision anchors
(`.stenswf/<N>/decisions.md`).

One file per PRD: `prd-<N>.md`, written by `/stenswf:apply` in PRD-mode
at PRD close (after a `(y)/(e)/(n)` confirmation) and staged as part of
the cleanup PR.

This is the **top** of four tiers; the other three are defined in
[the stenswf README](../../../plugins/stenswf/README.md#four-tier-model-local-recorded-published-committed).
This file is for the small subset worth carrying as curated documentation.

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

## Finding a slice's decisions

Slice-only flows (no PRD) don't produce a curated excerpt. Their decisions
are already in the repo as commit trailers — read them there, no
`.stenswf/` and no live branch required:

```bash
git log --grep='^Decision: #<slice>/'          # one slice
git log --grep='^Touches:.*path/to/file'       # what was decided about a file
```

Grep, not `git interpret-trailers` —
[why](../../../plugins/stenswf/README.md#recording-in-git).

## Manual excerpt

If you want a curated file in the repo as well:

```bash
N=<slice-issue>
bash plugins/stenswf/scripts/publish-decisions.sh render --excerpt "$N" \
  > docs/stenswf/decisions/slice-$N.md
```

Same filter and the same live-or-archived anchor lookup that PRD-mode
uses. Review the output before committing.

## Schema

Matches the full schema at
[../../../plugins/stenswf/README.md](../../../plugins/stenswf/README.md#decision-anchor-contract).
Excerpts may drop the `Source:` field (origin is the excerpt filename)
but preserve title, category, rationale, and refs verbatim.
