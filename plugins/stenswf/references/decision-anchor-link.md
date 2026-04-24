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
| `prd-to-issues` | yes | stub inheritance | inherited |
| `plan` | yes | Phase 1 interview | decision, arch |
| `plan-light` | rare | Phase 3 only | decision |
| `ship` | yes | drift-continue, BLOCKED override | decision |
| `ship-light` | rare | rubberduck-rejected alternatives | decision |
| `review` | no | — | — |
| `apply` | yes | Phase 2 override | matches superseded |

Severity rules for contradictions (consumed by `review`):

- `arch` → High
- `decision` → Medium (→ High if `Refs:` contains `AC#`)
- superseded (`### ~~D<n>~~`) → ignored
