# Curated decisions — stenswf

Committed, team-visible excerpts of per-issue decision anchors
(`.stenswf/<N>/decisions.md`).

One file per PRD: `prd-<N>.md`, written by `/stenswf:apply` in PRD-mode
at PRD close (after a `(y)/(e)/(n)` confirmation) and staged as part of
the cleanup PR.

This is the **top** of three tiers. Below it sits the *published* tier:
`ship` and `ship-light` render every active entry into a
marker-delimited `## Decisions` block in the PR body and a wrap-up issue
comment, and `apply` refreshes it once supersessions land. That tier is
unfiltered and needs no curation — it is where a slice's decisions go to
survive, since `.stenswf/` is gitignored. This file is for the small
subset worth carrying in the repo forever. See
[the Publication section](../../../plugins/stenswf/README.md#publication).

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

Slice-only flows (no PRD) don't produce a committed excerpt by default —
their decisions live in the published tier (PR body + issue comment),
which is usually enough. If you want one in the repo as well:

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
