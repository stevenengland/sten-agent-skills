---
name: plan
description: Plan a slice issue end-to-end, producing a per-task fragment tree and dispatch manifest under `.stenswf/<issue>/`.
disable-model-invocation: true
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).
Task fragments are full prose — `brevity` does NOT apply to artifact bodies.

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

Under `.stenswf/$ARGUMENTS/` (gitignored, repo-root). Issue body holds
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
  least one task.
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

---

## Feedback

Log friction via
[../../references/feedback-log.md](../../references/feedback-log.md).
Set `STENSWF_SKILL=plan` and `STENSWF_ISSUE=$ARGUMENTS` before calling
`scripts/log-issue.sh`.
