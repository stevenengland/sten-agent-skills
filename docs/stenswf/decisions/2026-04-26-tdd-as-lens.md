# Decision: TDD-as-lens (2026-04-26)

Status: **adopted**.
Source: [`tmp/stenswf-tdd-enforcement-plan.md`](../../../tmp/stenswf-tdd-enforcement-plan.md).
Refs: `plugins/stenswf/references/behavior-change-signal.md`,
`plugins/stenswf/references/issue-template.md`,
`plugins/stenswf/references/plan-artifact-schemas.md`,
`plugins/stenswf/references/front-matter-schema.md`.

## Decision

`tdd` is invoked as a **lens**, not a quota:

- Always load `tdd` in every implementation skill's SKILLS TO LOAD
  list. Loading is cheap; mis-skipping is expensive.
- Gate the RED-first loop **per AC** based on a tag on the AC
  checkbox: `(behavior)` or `(structural)`.
- Detect behavior change at three checkpoints (planner, pre-dispatch,
  pre-push rubberduck). **Ship wins on conflict.**
- Untagged ACs are a hard `contract_violation`; **no safe-default**.

## Rejected alternatives

| Option | Why rejected |
|---|---|
| Conditional load — only load `tdd` when behavior change is detected upfront | Mis-detection costs an entire slice's behavior coverage. Loading is cheap. |
| Per-task or per-slice granularity | Misses Pocock's "one test per behavior" rhythm. ACs are the natural unit. |
| Safe-default `(behavior)` for untagged ACs | Hides upstream tagging gaps. Forces every producer (`prd-to-issues`, `triage-issue`) to think about behavior intent at emission time. |
| Skip the rubberduck override | Planner tags drift over the lifetime of a slice. The diff IS the irrefutable backstop. |
| Schema version bump (`stenswf:v2`) | Tag lives inside AC text; `migration_mode` is additive front-matter on `class: migration` only. No breaking change. |

## Carved invariants

1. Ceremony invariant pasted into every lifecycle skill: no skill
   may instruct skipping tests for `(behavior)` ACs, remove `tdd`
   from any SKILLS TO LOAD list, accept `manual check` as
   completion evidence for a `(behavior)` AC, or contradict
   `tdd/SKILL.md`.
2. Behavior-change signal lives at
   `plugins/stenswf/references/behavior-change-signal.md` —
   single source of truth for tag syntax, heuristic ladder, and
   ceremony clause text.
3. Heavy-path cache: `stable-prefix.md` keeps `tdd` unconditionally
   in SKILLS TO LOAD; the per-task tail in `dispatch.md` carries
   the per-task `BEHAVIOR FLAGS` block.
4. `lite_override` waives blast-radius disqualifiers only;
   behavior-change detection is unaffected.

## Bad-test audit

A test that breaks during refactor of code with no observable
behavior change is implementation-coupled and MUST be rewritten or
deleted with justification. `ship` Phase 2 + `ship-light` Phase 3
run the audit inline; `review/slice.md` carries it as a capstone
Test-quality perspective. Behavior coverage MUST NOT drop.
