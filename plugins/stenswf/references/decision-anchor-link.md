# Decision anchor — link

Full contract: [stenswf README — Decision Anchor Contract](../README.md#decision-anchor-contract).

Quick recipes (copy verbatim):

- **Bootstrap** (run before first append in a session): see Contract.
- **Append** (new entry, auto-incremented ID): see Contract.
- **Supersede** (strikethrough old, append new): see Contract.

Write contract by skill (one-line summary):

| Skill | Writes? | When | Category |
|---|---|---|---|
| `prd-from-grill-me` | yes | seed | arch, decision |
| `triage-issue` | yes | Phase 5 convert | arch (root cause), decision (introduced convention) |
| `prd-to-issues` | yes | stub inheritance | inherited |
| `plan` | yes | Phase 1 interview, ASK-resolved fork | decision, arch |
| `plan-light` | yes | ASK-resolved or parked heavy fork; HITL escape-hatch resolution; Phase 3 | decision, arch |
| `ship` | yes | drift-continue, BLOCKED override, ASK-resolved or parked fork | decision |
| `ship-light` | yes | rubberduck-rejected alternatives, ASK-resolved or parked fork, HITL escape-hatch resolution | decision, arch |
| `review` | no | — | — |
| `review-loop` | no | — | — |
| `apply` | yes | Phase 2 override, ASK-resolved or parked fork | matches superseded |
| `apply-loop` | yes | via the `apply` engine | matches superseded |

Publishing an entry is a separate contract from writing one — it is what
makes the entry survive the machine it was made on, since `.stenswf/` is
gitignored. Renderer:
[../scripts/publish-decisions.sh](../scripts/publish-decisions.sh); who
publishes where is stated once, in
[the Publication section](../README.md#publication).

Recording is a third contract again: every skill that **commits** also emits
`Decision:` / `Rationale:` / `Touches:` trailers for whatever this branch has
not recorded yet, which is what puts the reasoning in the repository rather
than only on GitHub. `ship`, `ship-light`, `apply` and `apply-loop` do; the
planners commit nothing, so their entries reach git with the first
implementation commit. Form and query recipes:
[conventional-commits.md](conventional-commits.md) and
[Recording in git](../README.md#recording-in-git).

A **parked** entry is written and published but deliberately **not**
recorded — it is an open question, and it joins the git journal when it
resolves.

ASK-resolved and parked forks come from
[decision-escalation.md](decision-escalation.md); HITL escape-hatch resolutions
from [hitl-escape-hatch.md](hitl-escape-hatch.md). Provenance stays with the
host seam — there is no `decision-escalation` or `hitl-escape-hatch` source.

## Parked decisions

A heavy decision reached with no answer obtainable (unattended) is
**parked**: write a pending `decision` anchor carrying a
`- **Status:** parked` field line, pointing at the PR/issue location where
the full tension lives. On resume the anchor is answered and the `Status:`
line is removed (it becomes an ordinary resolved `decision`).

Field form only — see the [schema](../README.md#schema). A bare
`status: parked` paragraph is the legacy form: still parsed by
[publish-decisions.sh](../scripts/publish-decisions.sh) so old anchors keep
their `⚠`, never written by a new one.

Severity rules for contradictions (consumed by `review`):

- `arch` → High
- `decision` → Medium (→ High if `Refs:` contains `AC#`)
- `parked` (a `decision` anchor with `status: parked`) → **High / blocking** —
  the work is not done until the parked decision is resolved
- superseded (`### ~~D<n>~~`) → ignored
