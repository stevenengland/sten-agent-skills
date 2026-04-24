---
name: plan-light
description: Lightweight planning for a well-scoped slice issue — `plan-light.md` plus a 4-field JSON identity card consumable by `ship-light`.
disable-model-invocation: true
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).
Apply context-hygiene per
[../../references/context-hygiene.md](../../references/context-hygiene.md).

Plan the implementation of slice issue number $ARGUMENTS.

## Audience

Unlike heavy `plan`, `plan-light` assumes the same model class will
ship. Do **not** over-document. One markdown file, one JSON stub, no
subtree.

This skill never interrupts the user. It either writes a plan and
returns `READY`, or aborts to heavy `plan` + `ship` by returning
`ROUTE_HEAVY: <one-sentence reason>`. No interviews.

Final line of output must be exactly one of:

```
READY
ROUTE_HEAVY: <one-sentence reason>
```

---

## Phase 0 — Preflight

Fetch the issue body and read front-matter via
[../../references/extractors.md](../../references/extractors.md):

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
# Version guard + key reads per extractors.md
TYPE=$(get_fm type /tmp/slice-$ARGUMENTS.md)
LITE=$(get_fm lite_eligible /tmp/slice-$ARGUMENTS.md)
DISQ=$(get_fm disqualifier /tmp/slice-$ARGUMENTS.md)
BLOCKED=$(get_fm blocked_by /tmp/slice-$ARGUMENTS.md)
```

Gate:

- `TYPE == "PRD"` or missing → abort to the user:
  *"Not a slice issue — use `/stenswf:prd-to-issues` to break the PRD
  down first."* Log `contract_violation`. Emit `ROUTE_HEAVY: not a
  slice — route to prd-to-issues` as FINAL line, then exit.
- `TYPE` starts with `slice` → continue.

Extract envelope-check inputs (body sections):

```bash
extract_section 'What to build'            /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-what.md
extract_section 'Conventions \(from PRD\)' /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-conv.md
extract_section 'Acceptance criteria'      /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-acs.md
extract_section 'Files \(hint\)'           /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-files.md
```

Lite envelope check — emit `ROUTE_HEAVY` as FINAL line and exit if any:

- `LITE == "false"` → `ROUTE_HEAVY: lite-ineligible — $DISQ`.
- `BLOCKED` non-empty → `ROUTE_HEAVY: blocked — $BLOCKED`.
- Scope plausibly exceeds the Lite envelope:
  - > 15 files likely changed.
  - Crosses >1 top-level module directory.
  - Schema migration implied.
  - Architectural decision not resolved in `## Conventions (from PRD)`.

Exception: `TYPE == "slice — spike"` ignores `arch-unknown` —
spikes exist to resolve unknowns.

---

## Phase 1 — Quick orientation (conditional)

If `## Files (hint)` exists and lists ≤4 concrete paths, skip orientation —
the hint IS the orientation. Proceed to Phase 2.

Otherwise dispatch ONE `Explore` subagent (thoroughness: quick, ≤300 words):

> For issue #$ARGUMENTS, return a ≤300-word orientation:
>
> 1. Exact test command and test runner config path.
> 2. 1–2 structurally analogous files (symbol paths only, no file contents).
> 3. `CLAUDE.md` / `AGENTS.md` hard lines.
> 4. Naming / module-layout conventions in the affected area.
>
> Symbol paths only. Do not paste file contents.

---

## Phase 2 — Self-resolve decisions (silent)

Walk each AC. For every ambiguity:

1. Covered by `## Conventions (from PRD)` → use silently.
2. Codebase analog exists → mirror silently, record in `## Assumptions`.
3. Two materially different paths, no tiebreaker → abort:
   `ROUTE_HEAVY: arch decision needed — <one sentence>`. Log `ambiguous_instruction`.
4. AC wording ambiguous enough for two behaviors → abort:
   `ROUTE_HEAVY: AC ambiguity — <quote AC, propose two reads>`. Log `ambiguous_instruction`.
5. Convention conflicts with codebase → abort:
   `ROUTE_HEAVY: convention conflicts with <path> — <one sentence>`. Log `contract_violation`.

No interview. Either resolve silently or escalate.

Tier-1/tier-2 resolutions are non-decisions — they go in `## Assumptions`,
never the anchor. See [../../references/decision-anchor-link.md](../../references/decision-anchor-link.md).

---

## Phase 3 — Write the artifact

```bash
mkdir -p ".stenswf/$ARGUMENTS"
```

Write the three artifacts per
[artifacts.md](artifacts.md):

1. `plan-light.md` — the readable plan (soft cap 200 lines, hard cap 6 tasks).
2. `plan-light.json` — 4-field identity stub with `source_signature`.
3. `lite-notes.md` — soft-constraint handoff to slice review.

If >6 tasks required, abort with
`ROUTE_HEAVY: scope >6 tasks — needs heavy plan`.

---

## Phase 4 — Self-check and final line

- [ ] **AC ↔ task coverage.** Every AC maps to exactly one task's `Done when`.
- [ ] **No placeholders.** No `TODO`, `FIXME`, unreplaced `<...>`.
- [ ] **Task count ≤ 6.** >6 → `ROUTE_HEAVY`.

If Phase 2 rejected a concrete alternative, append one `decision`
entry (source `plan-light`) to `.stenswf/$ARGUMENTS/decisions.md` per
[../../references/decision-anchor-link.md](../../references/decision-anchor-link.md).
Otherwise skip.

Then tell the user:

> Plan written to `.stenswf/$ARGUMENTS/plan-light.md`. Run
> `/stenswf:ship-light $ARGUMENTS` or `/stenswf:slice-e2e $ARGUMENTS`.

Print exactly one final line: `READY` (or `ROUTE_HEAVY: <reason>`).

---

## Feedback

Log workflow issues per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=plan-light` and `STENSWF_ISSUE=$ARGUMENTS`.

## Out of scope (deliberate)

No `manifest.json` beyond the 4-field stub. No `stable-prefix.md`. No
separate conventions/house-rules/design-summary files. No `--resume`.
Re-running overwrites in place.
