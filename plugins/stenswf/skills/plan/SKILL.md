---
name: plan
description: Understand and plan an issue end-to-end. Produces an implementation plan
  posted as a comment on the issue.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` sibling skill now, before the first response
in this session.** It governs all Phase 0 and Phase 1 dialogue, including
internal reasoning and tool-use narration. Self-check every message against
its rules before sending — do not drift into full prose on internal thinking.

Do not apply `brevity` to the Phase 2 plan document itself — the plan is
written in full prose for a context-naive implementer agent.

---

Plan the implementation of issue number $ARGUMENTS.

## Audience

The planner (you, in this skill) is highly skilled and has full codebase
context. The implementer (the `ship` skill) is a skilled
developer but:

- Has zero context for this codebase.
- Knows almost nothing about its toolset or problem domain.
- Has weak test-design instincts.
- May be a mid-tier LLM.
- Executes **one task at a time** in a fresh subagent session with no memory
  of previous tasks.

Write the plan for that implementer. Each task must be fully self-contained:
document exactly which files to touch, which existing code to read first,
which tests to write, which commands to run, and what to commit. Bite-sized
tasks. DRY. YAGNI. TDD. Frequent commits.

## Scope Check

If the issue spans multiple independent subsystems, stop and suggest splitting
it into sub-issues using the `prd-to-issues` skill before planning. Each plan
should produce working, testable software on its own.

---

## Phase 0 — Issue Pre-flight

Complete this phase before any codebase exploration or interview questions.

Fetch the issue and read it fully:

```
gh issue view $ARGUMENTS   # or glab issue view $ARGUMENTS
```

Extract and record:

- [ ] **Parent PRD** issue number (from `## Parent PRD` section).
- [ ] **Type** — HITL or AFK (from `## Type` section). If absent, treat as
      HITL.
- [ ] **Acceptance criteria** — list every criterion verbatim. Each must map
      to at least one plan task.
- [ ] **Blocked by** — fetch and skim each blocking issue's implementation
      plan comment to note what interfaces it exposes. These are available
      to use; do not re-derive or re-implement them.
- [ ] **Interview depth** — set based on Type:
  - **AFK**: abbreviated interview. Confirm orientation checklist, produce
    3–5 Design Decision entries, then proceed directly to Phase 2. Skip
    speculative design branches.
  - **HITL**: full interview. Resolve all design branches before proceeding.

If the issue body is missing required sections (Type, Acceptance criteria),
note the gaps and proceed with HITL mode.

---

## Phase 1 — Design Interview

### Orientation (complete before interview)

Before asking any interview questions, explore the codebase to ground your
recommendations. Complete all items:

- [ ] Locate the test runner config (`pytest.ini`, `pyproject.toml`,
  `Makefile`, or equivalent). Note the test command and any markers.
- [ ] Find the test file most analogous to the issue's affected module. Note
  its structure, fixture patterns, and naming conventions.
- [ ] Identify 1–3 existing implementations that are structurally similar to
  what the issue proposes. Record their symbol paths
  (`path/to/file.py::ClassName.method`).
- [ ] Read `CLAUDE.md` (if present) for project-specific conventions and
  constraints.
- [ ] Read `README.md` and any `docs/` files relevant to the issue domain.
  Note which of these will likely need updating after implementation.
- [ ] Identify the naming conventions in use (class names, module layout,
  error handling patterns).

Do not ask the first interview question until this checklist is complete.

### Interview

Interview me relentlessly about every aspect of the plan until we reach a
shared understanding. Walk down each branch of the design tree and resolve
dependencies between decisions one-by-one.

- For each question, provide your recommended answer and reasoning.
- If a question can be answered by exploring the codebase, explore the
  codebase instead.
- Propose 2–3 different approaches with trade-offs.
- Lead with your recommended option and explain why.
- Go back and clarify when something doesn't make sense.

When a recommendation touches a problem that an industry leader has solved
publicly, research how they approach it and briefly weave the relevant pattern
or practice into your recommendation. Cite the company and the specific
practice so I can evaluate the reasoning. Only cite a company or industry
practice when it actively distinguishes between two approaches currently under
consideration. Do not reference a practice to validate a decision already made.

Do not write any code in this phase.

### Design Decisions Log

After each major design branch is resolved, append a one-line entry to a
running log at the top of your response under the heading
`## Design Decisions`:

    ## Design Decisions
    - [topic]: [chosen approach] — [one-sentence rationale]
    - [topic]: [chosen approach] — [one-sentence rationale]

This log is the primary input to Phase 2. If the log exceeds ~10 entries
before the interview is complete, the issue likely spans independent
subsystems — stop and suggest splitting via the `prd-to-issues` skill before
continuing.

---

## Phase 2 — Implementation Plan

The `brevity` skill does not apply to the plan document (see its Scope
section). Write the plan in full prose.

Produce a single plan document with the structure below. Keep it compact:
reference existing code by symbol path (`path/to/file.py::ClassName.method`)
rather than pasting it. Write new code in the plan only where no analogous
code exists in the repo, and only as much as the implementer needs.

Sibling skills `tdd`, `clean-code`, and `conventional-commits` are invoked by
the implementer; do not duplicate their content here — reference them by name.

### Plan header

```
# Implementation plan for issue $ARGUMENTS — <one-line title>

**Parent PRD:** #<prd-issue-number>
**Goal:** <one sentence: what this delivers>
**Acceptance criteria addressed:** <copy criteria verbatim from the issue>
**Blocked by:** #<issue-number> — read its plan comment for available
interfaces before starting. Or "None".

**Design summary:** <3–5 sentences on the approach: key components,
interfaces, data/error flow.>

**House rules (read before starting):**
- Follow the `tdd` skill — one failing test, then minimal code, then next
  test. No writing all tests up front.
- Follow the `clean-code` skill.
- DRY, YAGNI. No speculative abstractions. No error handling for impossible
  cases.
- Commit at the end of every slice using the pre-written message. Format per
  the `conventional-commits` skill.
- If a task is inconsistent with the codebase, pause and report — do not
  re-plan silently.
- You will receive one task at a time. Do not read ahead or attempt other
  tasks.
```

### File structure

Before the task list, map every file that will be created or modified, with a
one-line responsibility for each. This locks decomposition before tasks start
and lets the implementer see the whole shape. Follow established patterns in
the codebase; do not unilaterally restructure unrelated files.

### Assumptions

List 3–5 load-bearing assumptions the plan depends on (e.g. "Postgres 15+",
"no feature-flag system exists", "logger is `structlog`"). These are the
implementer's trigger for "pause and ask."

### Tasks

Tasks are **vertical slices**. A slice is the smallest change that delivers
one observable behavior end-to-end and could ship alone. Soft cap: if a slice
needs more than ~5 test cases or touches more than ~4 files, split it. One
commit per slice, at the end, after refactor.

Each task must be **fully self-contained** — a subagent receiving only this
task block (with no other plan context) must be able to execute it correctly.
Never write "similar to Task N" or reference a previous task's code; repeat
what the implementer needs.

Each task uses this structure, with every step as a `- [ ]` checkbox:

```
### Task N: <slice name>

**Goal:** <one sentence, behavior-level>
**Files:**
- Create: `exact/path/to/new_file.py` — <responsibility>
- Modify: `exact/path/to/existing.py` — <what changes>
- Test: `tests/exact/path/to/test_file.py`
**Pre-reading (read before editing):**
- `path/to/analogous_code.py::symbol` — existing pattern to mirror
- `tdd` skill — if unsure about test shape
- <any external doc only if genuinely non-obvious>
**Done when:** <crisp acceptance criterion — must match an issue AC>
**Commit:** `<type>(<scope>): <subject>` (conventional-commits format)

Per test in this slice, repeat steps 1–4:

- [ ] Step 1 — Write failing test `test_<name>` in `<test file>`:
  ```python
  def test_<name>():
      # given
      ...
      # when
      ...
      # then
      assert ...
  ```
- [ ] Step 2 — Run test, confirm it fails:
  Run: `<exact command, e.g. pytest tests/path/test_file.py::test_name -v>`
  Expected: FAIL with `<expected error substring>`
- [ ] Step 3 — Implement minimal code in `<impl file>`.
  Approach: <1–3 sentences; reference analogous symbol by path>.
  Only include code here if no analog exists in the repo.
- [ ] Step 4 — Run test, confirm it passes:
  Run: `<same command>`
  Expected: PASS

After all tests in the slice are green:

- [ ] Refactor within the slice (naming, duplication). Tests stay green.
- [ ] Verify: `<exact command to run the slice's tests>` — all PASS.
      If the slice is user-visible, also run: `<manual check, e.g. curl, CLI>`.
- [ ] Commit:
  ```bash
  git add <paths>
  git commit -m "<type>(<scope>): <subject>"
  ```
```

#### Documentation Task (always last)

Every plan must end with a documentation task. Fill in the actual file list
from the Phase 1 orientation checklist.

```
### Task N: Update documentation

**Goal:** All affected documentation reflects the post-implementation state.
**Files:**
- Modify: `CLAUDE.md` — update if new patterns or conventions were introduced
- Modify: `README.md` — update architecture or usage sections if public shape
  changed
- Modify: `docs/<relevant>.md` — update API or design doc if applicable
**Pre-reading:**
- Results of Phase 1 orientation doc checklist
**Done when:** Every doc file from the orientation checklist has been
reviewed. Files that required changes are updated and committed. Files
requiring no changes are noted explicitly ("no update needed — not affected
by this issue").
**Commit:** `docs(<scope>): update documentation for issue $ARGUMENTS`

- [ ] Review each file from the Phase 1 orientation doc checklist.
- [ ] For each file: update if needed, or note "no update needed" inline.
- [ ] Commit.
```

### Prescriptiveness rules

- **Test steps:** write the full test code (given/when/then). Tests are short,
  and the implementer is explicitly weak at test design — be prescriptive here.
- **Implementation steps:** describe the approach and point at analogous
  symbols by path. Do not pre-write the full implementation unless no analog
  exists.
- Use exact file paths and exact commands everywhere.

### No placeholders

These are plan failures — never write them:

- "TBD", "TODO", "implement later", "fill in details".
- "Add appropriate error handling" / "add validation" / "handle edge cases"
  without saying which cases.
- "Write tests for the above" without the actual test code.
- "Similar to Task N" — repeat the test code; the implementer reads tasks in
  isolation.
- Test steps without test code.
- References to types, functions, or methods not defined in any task and not
  already present in the repo at a named path.

### Review Step

Append the following section to the end of every plan, after all tasks.

```
---

# Review Step — #$ARGUMENTS (<one-line title>)

Guardrails to check before marking the PR done. Coverage is enforced by the
pipeline; the architectural invariants below run in CI as part of
`<test command from orientation>`.

## Architectural Invariants (enforced test file)

New file: `tests/architecture/test_<issue_topic>_invariants.py`

- [ ] **<Invariant name>.** <What the test asserts. Reference exact symbol
  paths and file paths. State the ast/pathlib check method.>

## Recommended Regression Tests (advisory)

Add to `tests/<module>/test_<topic>.py`. These cover the highest-risk
behavior changes.

- [ ] **<Scenario name>.** <Setup, action, expected outcome. One sentence.>

## Self-report Checklist

- [ ] `<lint/check command>` green.
- [ ] `<test command>` green.
- [ ] Architectural invariants above pass.
- [ ] Recommended regression tests above exist, or absences justified in PR.
- [ ] `git grep` confirms no stale references to deleted symbols.
```

### Self-review

After writing the plan, look at it with fresh eyes:

1. **AC coverage** — every acceptance criterion from the issue maps to a
   task's "Done when" field. List gaps, then add tasks for them.
2. **Placeholder scan** — search for patterns in "No placeholders" above.
   Fix them.
3. **Pointer check** — every task names at least one existing file/symbol to
   read, modify, or mirror, or explicitly states "net-new, no analogous code
   in repo."
4. **Self-containment check** — every task can be handed to a context-naive
   subagent with no other plan context and executed correctly.
5. **Type consistency** — names, signatures, and paths used in later tasks
   match earlier tasks.
6. **Scope** — focused enough for a single plan, or does it need splitting?
7. **Ambiguity** — any requirement readable two ways? Pick one, make it
   explicit.

Fix issues inline. No re-review.

---

## Wrap-up

- Post the plan as a comment on issue $ARGUMENTS.
- Prefix the comment clearly: "Implementation plan for issue $ARGUMENTS".
- Swap lifecycle labels on the issue: add `planned`, remove `needs-plan`.
  (Labels are created once per repo via the `bootstrap` skill. Use whichever
  issue-tracker CLI is available.)
- Append a progress table to the **issue body** (not a comment) under the
  `## Implementation log` section. Create the section if absent.

  ```
  ## Implementation log

  | Task | Status | Commit SHA |
  |------|--------|------------|
  | Task 1: <name> | ⬜ pending | — |
  | Task 2: <name> | ⬜ pending | — |
  | ...  | ...    | ...        |
  | Review step    | ⬜ pending | — |
  | PR / CI        | ⬜ pending | — |
  ```

- Stop after the plan and log table are posted. Do not implement any changes.
- Tell the user:

  > Plan posted on issue #$ARGUMENTS. Run the `ship`
  > skill with this issue number to begin implementation.
