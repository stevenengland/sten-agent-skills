---
name: plan
description: Plan a slice issue end-to-end, producing a per-task fragment tree and dispatch manifest under `.stenswf/<issue>/`.
disable-model-invocation: true
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).
Task fragments are full prose — `brevity` does NOT apply to artifact bodies.
Apply context-hygiene per
[../../references/context-hygiene.md](../../references/context-hygiene.md).

Plan the implementation of issue number $ARGUMENTS.

## Audience

Planner has full codebase context. Implementer (`ship`) is a fresh
subagent per task with:

- Zero context for this codebase.
- Weak test-design instincts.
- One task at a time, no memory of prior tasks.

Write fully self-contained fragments: files to touch, code to read first,
tests to write, commands to run, what to commit. Bite-sized. DRY. YAGNI.
TDD. Frequent commits.

## Where artifacts live

Under `.stenswf/$ARGUMENTS/` (excluded per-clone via `.git/info/exclude`, repo-root). Issue body holds
only the conceptual plan (front-matter + `What to build`, `Acceptance
criteria`, `Conventions (from PRD)`, `Files (hint)`). No labels.

If `.stenswf/` missing, create it (or run `bootstrap` once). On
`--resume`, preserve completed task entries and regenerate the rest.

## Scope Check

If the issue spans multiple independent subsystems, stop and suggest
splitting via `prd-to-issues`.

---

## Phase 0 — Issue Pre-flight

Fetch the issue and read front-matter via
[../../references/extractors.md](../../references/extractors.md):

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
wc -l /tmp/slice-$ARGUMENTS.md   # confirm; do not cat

TYPE=$(get_fm type /tmp/slice-$ARGUMENTS.md)
PRD_REF=$(get_fm prd_ref /tmp/slice-$ARGUMENTS.md)
BLOCKED=$(get_fm blocked_by /tmp/slice-$ARGUMENTS.md)
```

Record:

- [ ] **Kind.** `TYPE` must be `slice — HITL`, `slice — AFK`, or
  `slice — spike`. If missing or `PRD`, stop: this is not a slice.
  Log `contract_violation`.
- [ ] **Parent PRD.** `PRD_REF`.
- [ ] **Parent PRD body sections this slice needs** — fetch and extract:

      ```bash
      gh issue view $PRD_REF --json body -q .body > /tmp/prd-$PRD_REF.md
      extract_section 'User Stories'            /tmp/prd-$PRD_REF.md
      extract_section 'Implementation Decisions' /tmp/prd-$PRD_REF.md
      extract_section 'Out of Scope'             /tmp/prd-$PRD_REF.md
      ```
- [ ] **Slice type.** `HITL | AFK | spike` — derived from `TYPE`.
- [ ] **Conventions (from PRD).**

      ```bash
      extract_section 'Conventions \(from PRD\)' /tmp/slice-$ARGUMENTS.md \
        > /tmp/slice-$ARGUMENTS-conventions.md
      ```
      The extracted content may be `None — slice-local decisions only.`
      verbatim — that is a valid value, not an error.
- [ ] **Acceptance criteria** — list verbatim. Each must map to at
  least one task. Use `extract_acs` from
  [../../references/extractors.md](../../references/extractors.md)
  to parse the section into `AC<n>\t<tag>\t<text>` records (IDs are
  positional). The extractor itself hard-errors and logs
  `contract_violation` on any untagged AC — stop and surface to
  the user. Re-validate each parsed tag against the heuristic
  ladder in
  [../../references/behavior-change-signal.md](../../references/behavior-change-signal.md);
  on disagreement with the issue body, **rewrite the issue body via
  `gh issue edit` so it remains the canonical source** (a comment
  alone is NOT sufficient — the body must reflect the corrected
  tags), then log `behavior_change_override` with `<ac> <old>→<new>
  <reason>` as evidence and proceed.

  **Migration-mode bias.** If the slice front-matter carries
  `migration_mode` (only present when the parent PRD is
  `class: migration`; see
  [../../references/front-matter-schema.md](../../references/front-matter-schema.md)),
  apply the bias from
  [../../references/behavior-change-signal.md](../../references/behavior-change-signal.md):

  ```bash
  MM=$(get_fm migration_mode /tmp/slice-$ARGUMENTS.md)
  case "$MM" in
    behavior-preserving) AMBIGUOUS_DEFAULT=structural ;; # rule 4 stronger
    contract-changing)   AMBIGUOUS_DEFAULT=behavior   ;; # rule 3 stronger
    "")                  AMBIGUOUS_DEFAULT=behavior   ;; # default rule 5
  esac
  ```

  When the heuristic falls through to rule 5 ("default on ambiguity"),
  use `$AMBIGUOUS_DEFAULT` instead of the bare `behavior` default.
  Producer tags still win where they are unambiguous — the bias only
  shifts the rule-5 fallback.

  Mirror every AC into `manifest.json` `tasks[].acs[]` with
  `behavior_change` set per the (re-validated) tag, per
  [../../references/plan-artifact-schemas.md](../../references/plan-artifact-schemas.md).
- [ ] **Blocked by** — for each blocker in `$BLOCKED`, read its local
  plan (`.stenswf/<blocker>/file-structure.md`,
  `acceptance-criteria.md`). If shipped via `ship-light` only, read
  `.stenswf/<blocker>/plan-light.md` if present; else the issue body's
  `Files (hint)`.
- [ ] **Interview depth:**
  - **AFK**: abbreviated. 3–5 Design Decision entries, then Phase 2.
  - **HITL**: full. Resolve all branches.
  - **spike**: abbreviated; exists to land types/vocabulary.

---

## Phase 1 — Design Interview

### Orientation

Dispatch `Explore` subagent (don't read files directly):

> For issue #$ARGUMENTS, return a concise orientation (≤300 words):
>
> 1. Test runner config path + exact test command + any markers.
> 2. Test file most analogous to the affected module: path, structure,
>    fixture patterns, naming.
> 3. 1–3 existing implementations structurally similar to what the
>    issue proposes, as symbol paths.
> 4. `CLAUDE.md` / `AGENTS.md` hard lines.
> 5. `README.md` + `docs/*` files likely needing updates.
> 6. Naming conventions (class names, module layout, error handling).
>
> No file contents. Symbol paths + 1-sentence descriptions only.

### Interview

Interview relentlessly about every aspect until shared understanding:

- Recommended answer + reasoning per question.
- Codebase questions → targeted Explore subagents.
- Propose 2–3 approaches with trade-offs. Lead with recommendation.
- Clarify when something doesn't make sense.
- Industry practice citations only when they distinguish options in play.

No code in this phase.

### Interface and behavior interview

Before recording Design Decisions, work through the following with the
user. Lead with your recommendation; iterate.

- [ ] Confirm with user what interface changes are needed.
- [ ] Confirm with user which behaviors to test (prioritize).
- [ ] Identify opportunities for [deep modules](../tdd/deep-modules.md)
      (small interface, deep implementation).
- [ ] Design interfaces for [testability](../tdd/interface-design.md).
- [ ] List the behaviors to test (not implementation steps).
- [ ] Get user approval on the plan.

Ask: "What should the public interface look like? Which behaviors are
most important to test?"

**You can't test everything.** Confirm with the user exactly which
behaviors matter most. Focus testing effort on critical paths and
complex logic, not every possible edge case.

### Design Decisions Log

Running log at the top of your response:

    ## Design Decisions
    - [topic]: [chosen approach] — [one-sentence rationale]

> 10 entries before interview completes → likely multi-subsystem. Stop
and suggest splitting.

For each Design Decision passing the grep-blame + surfaces test,
append one entry to `.stenswf/$ARGUMENTS/decisions.md` (category
`decision`|`arch`, source `plan`) per
[../../references/decision-anchor-link.md](../../references/decision-anchor-link.md).

---

## Phase 2 — Write the local plan tree

**Ceremony invariant (TDD-as-lens).** This phase MUST NOT (a)
instruct skipping tests for ACs annotated `(behavior)`, (b) remove
`tdd` from any SKILLS TO LOAD list, (c) accept `manual check` or
"rely on existing suite" as completion evidence for a `(behavior)`
AC, or (d) emit guidance that contradicts `tdd/SKILL.md`. Detection
of behavior change is the gate; loading `tdd` is the lens; whether
to write a test follows from the AC tag, not from this skill. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

Full schema + file bodies: see
[../../references/plan-artifact-schemas.md](../../references/plan-artifact-schemas.md).

Task fragment template: see
[../../references/plan-task-template.md](../../references/plan-task-template.md).

Compute SHAs with `sha256sum <file> | cut -d' ' -f1`. `branch` and
`base_sha` are filled by `ship` at dispatch time.

Brevity Rules apply to `house-rules.md`, `design-summary.md`. They do
NOT apply to `conventions.md` (verbatim copy), `decisions.md` (cross-skill
anchor), task bodies, commands, file paths, or `review-step.md`.

---

## Phase 3 — Resume (`plan --resume`)

When invoked with `--resume`:

1. Read existing `manifest.json`.
2. Preserve `status == "done"` entries — their `sha` and `commit_subject`
   stay as-is.
3. Re-run Phase 0 + Phase 1 (orientation + relevant interview) against
   current issue body.
4. Re-write `concept.md`, `stable-prefix.md`, `conventions.md`,
   `house-rules.md`, `acceptance-criteria.md`, `file-structure.md`,
   `review-step.md`, `design-summary.md`. **Do not touch
   `decisions.md`** — append-only; supersede via
   [../../references/decision-anchor-link.md](../../references/decision-anchor-link.md).
5. Re-write `tasks/T<id>.md` for every pending/blocked task.
6. Update manifest hashes and bump `plan_created_at`.
7. Leave done-task fragments in place for forensics.

---

## Self-review

After writing all files, run the externalized validator:

```bash
bash plugins/stenswf/skills/plan/scripts/plan-self-review.sh "$ARGUMENTS"
```

Fix any failures and re-run until `OK`. Log `tool_failure` if the
validator cannot run (missing `jq`, etc.).

Then run a **semantic** pre-finalize reflection — the validator checks
artifact shape, not reasoning quality. Pause and step back:

- Could a zero-context implementer execute every task fragment from
  the local plan alone, without re-reading this issue?
- Does each task's `Done when` map to at least one acceptance
  criterion, and vice-versa?
- Did any task grow past the size where a fresh subagent could finish
  it in one sitting? Should it split?
- Did the plan miss a `first-read` file that the implementer will
  certainly need?
- Are any inter-task dependencies implicit (shared types, config
  keys, schema fields) but not declared in `blocked_by`?

If the answer changes the plan, revise and re-run the validator.

---

## Feedback

Log friction per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=plan` and `STENSWF_ISSUE=$ARGUMENTS`.
