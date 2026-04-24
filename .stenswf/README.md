# `.stenswf/` — per-issue local state

This directory holds per-developer state produced by the [stenswf
plugin](../plugins/stenswf/README.md): plan fragments, manifests,
review findings, apply state, audit logs, and the cross-skill
**decision anchor** (`decisions.md`).

The directory is gitignored — except for this README, which is the
one file meant to be team-visible so the layout is discoverable from
a fresh clone.

```
.gitignore:
  .stenswf/
  !.stenswf/README.md
```

## Layout

```
.stenswf/
├── README.md                 (this file, committed)
├── <issue>/                  (per-issue; local only)
│   ├── manifest.json          (ship/plan state, drift hashes)
│   ├── concept.md             (issue body snapshot)
│   ├── decisions.md           ← DECISION ANCHOR (cross-skill memory)
│   ├── conventions.md         (verbatim slice-body conventions)
│   ├── stable-prefix.md, house-rules.md, design-summary.md,
│   │   acceptance-criteria.md, file-structure.md, review-step.md
│   ├── tasks/T10.md, T20.md, …
│   ├── plan-light.md / plan-light.json (plan-light artifacts)
│   ├── review/slice.md OR review/prd-review.xml
│   ├── apply-state.json
│   └── log.jsonl              (append-only audit events)
└── .archive/<issue>-<date>/   (archived on PR merge)
```

## The decision anchor (`decisions.md`)

One file per issue. Records **decisions that would otherwise be lost**
— architectural calls and non-obvious choices a `git blame` reader
could not reconstruct from code, conventions, commits, or PR bodies.

Schema, write contract, and severity rules live in
[plugins/stenswf/README.md](../plugins/stenswf/README.md#decision-anchor-contract)
(the canonical spec).

Curated cross-issue excerpts are committed to
[../docs/stenswf/decisions/](../docs/stenswf/decisions/) at PRD close.

### Reading anchors (recipes)

Active entries in one anchor (superseded entries use strikethrough
headers `### ~~D<n>~~` and are filtered out by these recipes):

```bash
# Active entry titles
grep -E '^### D[0-9]+ ' .stenswf/<N>/decisions.md

# One entry in full
awk '/^### D3 /,/^### /' .stenswf/<N>/decisions.md
```

**External reviewer** — find anchors relevant to a file path (works
from outside stenswf, including for tools that only see diffs):

```bash
grep -l 'path/to/file' \
  .stenswf/*/decisions.md \
  .stenswf/.archive/*/decisions.md 2>/dev/null
```

Each matching decision entry lists the implicated paths in its
`Refs:` field — this is the reverse-lookup primitive. No index file,
no staleness risk.

## When in doubt

- Full schema + write contract → [plugins/stenswf/README.md](../plugins/stenswf/README.md#decision-anchor-contract).
- Committed curated excerpts → [docs/stenswf/decisions/](../docs/stenswf/decisions/).
- Plugin commands and workflows → [plugins/stenswf/README.md](../plugins/stenswf/README.md).
