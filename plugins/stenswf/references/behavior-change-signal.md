# Behavior-change signal — TDD-as-lens

Single source of truth for the AC-tag syntax, the heuristic ladder
that detects behavior change, and the canonical ceremony-invariant
clause that protects `tdd` against silent skip.

Loaded lazily by `prd-to-issues`, `triage-issue`, `plan`,
`plan-light`, `ship`, `ship-light`, `slice-e2e`, `apply`, `review`,
and `prd-from-grill-me`.

---

## Philosophy

- TDD is a **lens, not a quota**. Loading `tdd` = "agent now knows
  behavior-only-test discipline + RED-first." Not loading it = "no
  behavior change here, don't bother."
- Detection of *behavior change* is the gate, not test writing.
- Two-tier detection: planning tries first, ship verifies. **Ship
  wins on conflict.**

---

## AC-tag syntax (canonical)

In every issue body's `## Acceptance criteria` section, every checkbox
MUST carry exactly one of two tags as its first parenthesised token:

```markdown
- [ ] (behavior) Returns 401 on missing token
- [ ] (behavior) Persists user preference across sessions
- [ ] (structural) Rename `FooFactory` to `FooBuilder`; all call sites updated
- [ ] (structural) Move `helpers/` under `internal/`
```

Rules:

- Tag is a single word: `behavior` or `structural`. No other values
  permitted.
- The tag is the first parenthesised token after the checkbox.
- **Untagged ACs are a hard error.** No safe-default.
  `prd-to-issues`, `triage-issue`, `plan`, `plan-light`, `ship`,
  `ship-light` MUST refuse to proceed and log
  `contract_violation` with `untagged AC: <quote>` as evidence.
  Resolution: edit the issue body (or re-run `prd-to-issues` /
  `triage-issue`).

### AC IDs

AC IDs are **positional**, assigned at parse time by the consumer:
`AC1` for the first checkbox in `## Acceptance criteria`, `AC2` for
the second, and so on. IDs do NOT appear in the issue body — they
exist only in machine-readable mirrors (`manifest.json`,
`plan-light.json`, `BEHAVIOR FLAGS` block in `dispatch.md`). Every
consumer that parses the AC list MUST use this same positional
scheme so IDs round-trip across the planner/shipper boundary.

`prd-to-issues` is the primary author. `triage-issue` annotates
bug-brief slice ACs. `plan` / `plan-light` re-validate. `ship` /
`ship-light` re-validate, with rubberduck as backstop.

---

## Heuristic ladder

> An AC is a **behavior change** iff a black-box public-interface
> test could be written that fails before the change and passes
> after.

Apply rules in order; first match wins:

1. Done-when uses observable verbs (`returns | rejects | persists |
   emits | displays | restores | handles`) → `true`.
2. Done-when starts only with `Update docs | Rename | Remove unused
   | Reformat` → `false`.
3. AC introduces or modifies a public symbol / endpoint / CLI flag
   / config key / event payload / persisted shape → `true`.
4. AC is invariant-preservation only ("after refactor, all existing
   tests still pass") → `false`.
5. **Default `true`** when ambiguous.

The ladder runs at every detection checkpoint. Producers (PRD →
issue) tag from intent; planners re-tag against the ladder; shippers
re-tag once more against the diff.

---

## Manifest mirror (heavy path)

`.stenswf/<n>/manifest.json` mirrors AC tags as machine-readable
booleans. Per-task `behavior_change` is `any(acs.behavior_change)`;
per-slice is `any(tasks.behavior_change)`.

```json
{
  "tasks": [{
    "id": "T10",
    "behavior_change": true,
    "acs": [
      {"id": "AC1", "behavior_change": true,  "text": "..."},
      {"id": "AC2", "behavior_change": false, "text": "..."}
    ]
  }]
}
```

## Plan-light mirror

`.stenswf/<n>/plan-light.json` extends the 4-field stub to 5 fields:
`behavior_change_acs: ["AC1", "AC3"]`.

---

## Migration-mode override (`class: migration` only)

Front-matter `migration_mode: behavior-preserving |
contract-changing` is REQUIRED on slices whose parent PRD has
`class: migration`, and absent everywhere else. Plan / plan-light /
ship read it and bias the heuristic:

- `behavior-preserving` → heuristic rule 4 fires more eagerly;
  every AC starts as a `(structural)` candidate.
- `contract-changing` → heuristic rule 3 fires more eagerly; every
  AC starts as a `(behavior)` candidate.

Producers still tag explicitly; the override is advisory bias for
the heuristic ladder, not a substitute for tags.

---

## Ceremony invariant (canonical wording)

> **Ceremony invariant.** This skill MUST NOT (a) instruct skipping
> tests for ACs annotated `(behavior)`, (b) remove `tdd` from any
> SKILLS TO LOAD list, (c) accept `manual check` or "rely on
> existing suite" as completion evidence for a `(behavior)` AC, or
> (d) emit guidance that contradicts `tdd/SKILL.md`. Detection of
> behavior change is the gate; loading `tdd` is the lens; whether
> to write a test follows from the AC tag, not from this skill.

Inserted verbatim into every lifecycle skill. Re-read this file
when any of those skills changes — drift here is a hard regression.

---

## Bad-test audit (refactor-time diagnostic)

A test that breaks during refactor of code with no observable
behavior change is implementation-coupled and MUST be rewritten to
the public interface or deleted with one-line justification.
Implementation-coupled symptoms:

- Mocks an internal collaborator the AC does not name.
- Asserts on private state, internal storage, or framework
  internals.
- Re-implements production logic in fixture form.

`ship` Phase 2 + `ship-light` Phase 3 run this audit inline.
`review/slice.md` carries it as a capstone Test-quality
perspective. Behavior coverage MUST NOT drop.
