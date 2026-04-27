---
name: plan-light
description: Lightweight planning for a well-scoped slice issue — `plan-light.md` plus a 5-field JSON identity card consumable by `ship-light`.
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
ABORT_NOT_SLICE: route to prd-to-issues
```

---

## Phase 0 — Preflight

Fetch the issue body and read front-matter via
[../../references/extractors.md](../../references/extractors.md)
(canonical source: `plugins/stenswf/scripts/extractors.sh`):

```bash
source plugins/stenswf/scripts/extractors.sh
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
# Version guard + key reads per extractors.md
TYPE=$(get_fm type /tmp/slice-$ARGUMENTS.md)
LITE=$(get_fm lite_eligible /tmp/slice-$ARGUMENTS.md)
DISQ=$(get_fm disqualifier /tmp/slice-$ARGUMENTS.md)
OVERRIDE=$(get_fm lite_override /tmp/slice-$ARGUMENTS.md)
BLOCKED=$(get_fm blocked_by /tmp/slice-$ARGUMENTS.md)
```

Gate:

- `TYPE == "PRD"` or missing → abort to the user:
  *"Not a slice issue — use `/stenswf:prd-to-issues` to break the PRD
  down first."* Log `contract_violation`. Emit
  `ABORT_NOT_SLICE: route to prd-to-issues` as FINAL line, then exit.
  (`ABORT_NOT_SLICE` is intentionally distinct from `ROUTE_HEAVY`
  because the user does NOT need heavy `plan` + `ship` here — they
  need a different stage entirely. `slice-e2e` recognises this
  envelope and routes accordingly.)
- `TYPE == "slice — HITL"` → emit
  `ROUTE_HEAVY: HITL slice not eligible for lite path` as FINAL line
  and exit. HITL slices are structurally unfit for the lite path;
  the `lite_override` escape hatch below does not apply.
- `TYPE` starts with `slice` (and is not HITL) → continue.

Extract envelope-check inputs (body sections):

```bash
CONV_SRC=$(get_fm conventions_source /tmp/slice-$ARGUMENTS.md)
extract_section 'What to build'            /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-what.md
if [ "$CONV_SRC" = "none" ]; then
  : > /tmp/slice-$ARGUMENTS-conv.md
else
  extract_section 'Conventions \(from PRD\)' /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-conv.md
fi
extract_section 'Acceptance criteria'      /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-acs.md
extract_section 'Files \(hint\)'           /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-files.md
```

**Manual override (`lite_override`).** A non-empty `lite_override`
field bypasses the `LITE == "false"` gate ONLY when the disqualifier
is blast-radius (`files>15` or `cross-module`). For
`schema-migration`, `arch-unknown`, or `hitl-cat3`, the override is
ignored and `ROUTE_HEAVY` still fires — these disqualifiers signal
work the lite path is structurally unfit to handle (irreversible
change, unresolved architecture, mandatory human-in-loop). When the
override is honored, log `user_override` with the reason as evidence
and continue normally:

```bash
if [ "$LITE" = "false" ] && [ -n "$OVERRIDE" ]; then
  case "$DISQ" in
    files\>15|cross-module)
      bash plugins/stenswf/scripts/log-issue.sh user_override \
        "lite_override honored on #$ARGUMENTS ($DISQ)" "$OVERRIDE"
      LITE=true   # treat as lite for the remaining gate checks
      ;;
  esac
fi
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

Exception: when `lite_override` was honored above, the blast-radius
sub-bullets (>15 files, multi-module) are also waived for this run —
the override IS the attestation that those signals are acceptable.
The schema-migration and architectural-decision sub-bullets remain
in force regardless of override.

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

**AC-tag validation.** Use `extract_acs` from
[../../references/extractors.md](../../references/extractors.md) to
parse the AC section into `AC<n>\t<tag>\t<text>` records (IDs are
positional). The extractor itself hard-errors and logs
`contract_violation` on any untagged AC — abort with
`ROUTE_HEAVY: untagged AC — re-run prd-to-issues / triage-issue`.
Re-evaluate each parsed tag against the heuristic ladder in
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md);
disagreement with the issue body → re-tag silently for the
manifest mirror only (do NOT rewrite the issue body — heavy `plan`
does that). Mirror tagged-`behavior` AC ids into `plan-light.json`
`behavior_change_acs` per [artifacts.md](artifacts.md).

**Migration-mode bias.** If the slice front-matter carries
`migration_mode` (only present when the parent PRD is
`class: migration`; see
[../../references/front-matter-schema.md](../../references/front-matter-schema.md)),
apply the bias when the heuristic ladder falls through to rule 5
("default on ambiguity"):

- `behavior-preserving` → default to `(structural)`.
- `contract-changing` → default to `(behavior)`.
- absent → default to `(behavior)` (the bare rule 5).

Producer tags still win where they are unambiguous; the bias only
shifts the rule-5 fallback.

Walk each AC. For every ambiguity:

1. Covered by `## Conventions (from PRD)` → use silently.
2. Codebase analog exists → mirror silently, record in `## Assumptions`.
   When two analogs are equally supported, prefer the one that better
   matches [../tdd/interface-design.md](../tdd/interface-design.md)
   (deps as params, return-don't-mutate, small surface).
3. Two materially different paths, no tiebreaker → abort:
   `ROUTE_HEAVY: arch decision needed — <one sentence>`. Log `ambiguous_instruction`.
4. AC wording ambiguous enough for two behaviors → abort:
   `ROUTE_HEAVY: AC ambiguity — <quote AC, propose two reads>`. Log `ambiguous_instruction`.
5. Convention conflicts with codebase → abort:
   `ROUTE_HEAVY: convention conflicts with <path> — <one sentence>`. Log `contract_violation`.
6. Implied interface violates the testability lens (no params,
   hidden mutation, sprawling surface; see
   [../tdd/interface-design.md](../tdd/interface-design.md)) and no
   analog supports a sane shape → abort:
   `ROUTE_HEAVY: testability conflict — <one sentence>`. Log
   `ambiguous_instruction`.

No interview. Either resolve silently or escalate.

**Silent interface and behavior checklist (agent-side, mirrors heavy
`plan`'s interview).** `plan-light` cannot ask the user, so walk the
same checks against the codebase + conventions and resolve in-line.
Per slice:

- [ ] Name the public interface each `(behavior)` AC implies (signature,
      inputs, return). If the conventions + analog do not pin a shape,
      escalate `ROUTE_HEAVY: arch decision needed — <one sentence>`.
- [ ] Prioritize behaviors to test. **You can't test everything.** The
      AC list is fixed, but per task you decide which behaviors get
      RED-first dedicated tests vs. coverage-by-composition. Lead with
      critical paths and complex logic; record deferred edge cases in
      `## Assumptions`.
- [ ] Identify deep-module opportunities for any *new* module the slice
      introduces (small interface, deep implementation; see
      [../tdd/deep-modules.md](../tdd/deep-modules.md)). Record the
      chosen shape in `## Assumptions`. Do NOT propose restructuring
      existing modules — that is heavy `plan` territory.
- [ ] Confirm the implied interface satisfies
      [../tdd/interface-design.md](../tdd/interface-design.md) (deps
      as params, return-don't-mutate, small surface). Lens violations
      are caught by ladder rule 6 above.

Resolutions go in `## Assumptions` (non-decisions) per the link rule
below. Anything that genuinely needs a user becomes `ROUTE_HEAVY`.

Tier-1/tier-2 resolutions are non-decisions — they go in `## Assumptions`,
never the anchor. See [../../references/decision-anchor-link.md](../../references/decision-anchor-link.md).

---

## Phase 3 — Write the artifact

**Ceremony invariant (TDD-as-lens).** This phase MUST NOT (a)
instruct skipping tests for ACs annotated `(behavior)`, (b) remove
`tdd` from any SKILLS TO LOAD list, (c) accept `manual check` or
"rely on existing suite" as completion evidence for a `(behavior)`
AC, or (d) emit guidance that contradicts `tdd/SKILL.md`. Detection
of behavior change is the gate; loading `tdd` is the lens; whether
to write a test follows from the AC tag, not from this skill. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

```bash
mkdir -p ".stenswf/$ARGUMENTS"
```

Write the three artifacts per
[artifacts.md](artifacts.md):

1. `plan-light.md` — the readable plan (soft cap 200 lines, hard cap 6 tasks).
2. `plan-light.json` — 5-field identity stub with `source_signature`
   and `behavior_change_acs`.
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

**Pre-finalize reflection — before printing `READY`.** The checklist
above verifies *shape*; this verifies *reasoning*. Pause and step
back:

- Is this slice genuinely lite, or did I bury complexity under task
  titles to fit the 6-task cap?
- Did I treat any non-trivial decision as "obvious" without recording
  it as an assumption or `decision` entry?
- Did any AC remain partially covered (e.g., happy-path only, error
  path implicit)?
- Would emitting `ROUTE_HEAVY` actually be more honest here?

If the answer changes the plan, revise. Only then print the final line.

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

No `manifest.json` beyond the 5-field stub. No `stable-prefix.md`. No
separate conventions/house-rules/design-summary files. No `--resume`.
Re-running overwrites in place.
