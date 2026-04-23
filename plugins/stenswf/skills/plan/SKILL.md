---
name: plan
description: Understand and plan an issue end-to-end. Produces an implementation plan
  posted as a comment on the issue.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response
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
- [ ] **Parent PRD body** — fetch via redirect-then-awk so only the
      sections this slice needs enter context. Never `cat` the PRD body.

      ```bash
      gh issue view <parent-prd> --json body -q .body > /tmp/prd-<parent-prd>.md
      wc -l /tmp/prd-<parent-prd>.md   # confirm; do not cat
      # Extract only the sections this plan needs:
      awk '/^## User Stories/,/^## /'            /tmp/prd-<parent-prd>.md | sed '$d'
      awk '/^## Implementation Decisions/,/^## /' /tmp/prd-<parent-prd>.md | sed '$d'
      awk '/^## Out of Scope/,/^## /'             /tmp/prd-<parent-prd>.md | sed '$d'
      ```

      Record which user-story bullets this slice addresses and any
      `Out of Scope` line items to avoid.
- [ ] **Type** — HITL or AFK (from `## Type` section). If absent, treat as
      HITL.
- [ ] **Acceptance criteria** — list every criterion verbatim. Each must map
      to at least one plan task.
- [ ] **Blocked by** — for each blocking issue, fetch its implementation
      plan comment using the redirect-then-awk pattern below so only the
      interfaces you need enter context. These are available to use; do not
      re-derive or re-implement them.

      ```bash
      gh issue view <blocker> --json comments \
        -q '.comments[] | select(.body|contains("Implementation plan for issue")) | .body' \
        > /tmp/plan-<blocker>.md
      wc -l /tmp/plan-<blocker>.md   # confirm file wrote; do not cat it
      awk '/<file-structure>/,/<\/file-structure>/'  /tmp/plan-<blocker>.md
      awk '/<acceptance-criteria>/,/<\/acceptance-criteria>/'  /tmp/plan-<blocker>.md
      ```

      Only the extracted tagged sections enter context. Never `cat` the file.
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

Before asking any interview questions, ground your recommendations in the
codebase. Do **not** read these files directly into this session — delegate
to a read-only exploration subagent and let it distill the findings.

Dispatch an `Explore` subagent with this prompt:

> For issue #$ARGUMENTS, return a concise orientation summary (≤300 words):
>
> 1. Test runner config path + exact test command + any markers.
> 2. Test file most analogous to the issue's affected module: path,
>    structure in one sentence, fixture patterns, naming conventions.
> 3. 1–3 existing implementations structurally similar to what the issue
>    proposes, as symbol paths (`path/to/file.py::ClassName.method`).
> 4. `CLAUDE.md` / `AGENTS.md` highlights (hard constraints, untouchable
>    files, forbidden suppressions, required tooling).
> 5. `README.md` + relevant `docs/*` files that will likely need updating
>    after implementation, listed by path.
> 6. Naming conventions (class names, module layout, error handling).
>
> Do NOT paste file contents. Symbol paths and 1-sentence descriptions only.

**Escape hatch:** if during the interview the user asks to see a specific
file verbatim, read it directly then — not during orientation.

Do not ask the first interview question until the orientation summary is
in hand.

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

Write the plan as a single markdown document. Wrap each major section in
XML-style anchors so downstream agents (ship, review, apply) can extract
exact sections via `awk`. The prose inside tags is plain markdown.

**Brevity scope in the plan document:**
- `brevity` Rules APPLY to: `<house-rules>`, `<design-summary>`,
  `<assumptions>`. These are read repeatedly across subagents — keep them
  tight (short sentences, no filler, bullets for 3+ items).
- `brevity` Rules DO NOT apply to task bodies, test code, commands, file
  paths, `<file-structure>` descriptions, or the `<review-step>` — these
  are prescriptive artifacts for a weak-test-instinct implementer. Full
  prose, exact details.

Produce the document compactly: reference existing code by symbol path
(`path/to/file.py::ClassName.method`) rather than pasting it. Write new
code in the plan only where no analogous code exists in the repo, and only
as much as the implementer needs.

The `tdd` and `clean-code` skills are invoked by the implementer; do
not duplicate their content here — reference them by name. Commit messages
are pre-written verbatim in each task (see `<task>` template below) — the
implementer copies them; no commit-format skill needed.

**Conventional commit format for `commit="…"` attributes** (inlined for
the planner — no skill load needed):

```
<type>(<scope>): <imperative summary, lower case, no period, ≤72 chars>
```

`type` is one of: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`,
`chore`, `build`, `ci`, `style`, `revert`. `scope` is optional; use the
top-level module or area touched. Breaking changes: add `!` after the
type/scope. The `Refs: #$ARGUMENTS T<id>` trailer is added by the
implementer at commit time, not written into the `commit="…"` attribute.

### Plan header

```
# Implementation plan for issue $ARGUMENTS — <one-line title>

**Parent PRD:** #<prd-issue-number>
**Goal:** <one sentence: what this delivers>
**Blocked by:** #<issue-number> — its plan exposes interfaces; do not re-derive them. Or "None".

<design-summary>
3–5 short sentences on the approach: key components, interfaces, data/error flow.
Brevity Rules apply — no filler, no hedges.
</design-summary>

<acceptance-criteria>
List every AC from the issue verbatim, each as a bullet. Each must map to
exactly one `<task>` `Done when` below.
- AC1: …
- AC2: …
</acceptance-criteria>

<house-rules>
Read before starting every task. Brevity Rules apply.

- Follow the `tdd` skill: one failing test, then minimal code, then next. No writing all tests up front.
- Follow the `clean-code` skill.
- DRY, YAGNI. No speculative abstractions. No error handling for impossible cases.
- Use the pre-written commit message at the end of each task verbatim.
- If a task conflicts with the codebase, pause and report — do not re-plan silently.
- One task at a time. Do not read ahead or attempt other tasks.
</house-rules>
```

### File structure

Before the task list, map every file that will be created or modified, with a
one-line responsibility for each. Wrap in `<file-structure>` tags. This
locks decomposition before tasks start and lets the implementer (and the
PRD-scoped review / apply sessions) see the whole shape. Follow established
patterns in the codebase; do not unilaterally restructure unrelated files.

```
<file-structure>
- Create: `path/to/new_file.py` — <responsibility>
- Modify: `path/to/existing.py` — <what changes>
- Test:   `tests/path/to/test_file.py` — <what it covers>
</file-structure>
```

### Assumptions

List 3–5 load-bearing assumptions the plan depends on (e.g. "Postgres 15+",
"no feature-flag system exists", "logger is `structlog`"). These are the
implementer's trigger for "pause and ask." Wrap in `<assumptions>` tags.
Brevity Rules apply.

```
<assumptions>
- <assumption 1>
- <assumption 2>
- <assumption 3>
</assumptions>
```

### Tasks

Tasks are **vertical slices**. A slice is the smallest change that delivers
one observable behavior end-to-end and could ship alone. Soft cap: if a
slice needs more than ~5 test cases or touches more than ~4 files, split
it. One commit per slice, at the end, after refactor.

**Task IDs.** Use gap-numbered IDs starting at `T10`, stepping by 10
(`T10`, `T20`, `T30` …). Gap numbering lets you insert tasks later without
renumbering (e.g., `T15` between `T10` and `T20`). Each task's opening tag
attributes MUST include `id`, `name`, and `commit`. These are the keys the
`ship` skill uses to extract one task block deterministically.

Each task must be **fully self-contained** — a subagent receiving only this
task block (with no other plan context) must be able to execute it
correctly. Never write "similar to Task N" or reference a previous task's
code; repeat what the implementer needs.

Each task uses this structure (task body is full prose — brevity does NOT
apply here):

```
<task id="T10" name="<slice name>" commit="<type>(<scope>): <subject>">

**Goal:** <one sentence, behavior-level>
**Files:**
- Create: `exact/path/to/new_file.py` — <responsibility>
- Modify: `exact/path/to/existing.py` — <what changes>
- Test: `tests/exact/path/to/test_file.py`
**Pre-reading (read before editing):**
- `path/to/analogous_code.py::symbol` — existing pattern to mirror
- `tdd` skill — if unsure about test shape
- <any external doc only if genuinely non-obvious>
**Done when:** <crisp acceptance criterion — must match one AC from `<acceptance-criteria>`>

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
- [ ] Commit using the pre-written message in this task's `commit` attribute,
  with a `Refs: #$ARGUMENTS T<id>` trailer:
  ```bash
  git add <paths>
  git commit -m "<commit attribute>" -m "Refs: #$ARGUMENTS T10"
  ```

</task>
```

#### Documentation Task (always last)

Every plan must end with a documentation task using the T-ID pattern.
Fill in the actual file list from the Phase 1 orientation summary.

```
<task id="T<last>" name="Update documentation" commit="docs(<scope>): update documentation for issue $ARGUMENTS">

**Goal:** All affected documentation reflects the post-implementation state.
**Files:**
- Modify: `CLAUDE.md` — update if new patterns or conventions were introduced
- Modify: `README.md` — update architecture or usage sections if public shape
  changed
- Modify: `docs/<relevant>.md` — update API or design doc if applicable
**Pre-reading:**
- Orientation summary from Phase 1
**Done when:** Every doc file from the orientation summary has been
reviewed. Files that required changes are updated and committed. Files
requiring no changes are noted explicitly ("no update needed — not affected
by this issue").

- [ ] Review each file from the orientation summary's doc list.
- [ ] For each file: update if needed, or note "no update needed" inline.
- [ ] Commit using this task's `commit` attribute with a `Refs: #$ARGUMENTS T<last>` trailer.

</task>
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
Wrap in `<review-step>` tags so `ship` Phase 3 can extract it directly.

```
---

<review-step>

# Slice-level Review Step — #$ARGUMENTS (<one-line title>)

Guardrails to check before marking the PR done. This is the per-slice
self-review. (The PRD-scoped `review` skill operates at a higher altitude
once every slice has merged.) Coverage is enforced by the pipeline; the
architectural invariants below run in CI as part of
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

</review-step>
```

### Self-review

After writing the plan, validate it mechanically. Write the plan to
`/tmp/plan-draft-$ARGUMENTS.md` first, then run these checks. Fix any
failures inline; no re-review pass.

**Structural checks (must all pass before posting):**

```bash
P=/tmp/plan-draft-$ARGUMENTS.md

# 1. Every required top-level tag exists exactly once.
for tag in design-summary acceptance-criteria house-rules file-structure assumptions review-step; do
  n=$(grep -c "<$tag>" "$P")
  [ "$n" = "1" ] || echo "FAIL: <$tag> appears $n times (expected 1)"
done

# 2. Every <task> has id, name, commit attributes.
awk '/<task /{
  if ($0 !~ /id="T[0-9]+"/) print "FAIL: task missing id — " $0
  if ($0 !~ /name="[^"]+"/)   print "FAIL: task missing name — " $0
  if ($0 !~ /commit="[^"]+"/) print "FAIL: task missing commit — " $0
}' "$P"

# 3. Task IDs are unique.
grep -o 'id="T[0-9]*"' "$P" | sort | uniq -d | sed 's/^/FAIL: duplicate task id — /'

# 4. Every AC bullet has a matching Done-when in some task.
awk '/<acceptance-criteria>/,/<\/acceptance-criteria>/' "$P" \
  | grep -oE '^- AC[0-9]+' \
  | while read ac; do
      grep -q "$ac" "$P" || echo "FAIL: $ac has no Done-when reference"
    done
```

**Content checks (read the plan yourself):**

1. **Placeholder scan** — no `TBD`, `TODO`, `implement later`, `similar to
   Task N`, or test step without test code. Fix.
2. **Pointer check** — every task names at least one existing file/symbol
   to read, modify, or mirror, or explicitly states "net-new, no analogous
   code in repo."
3. **Self-containment** — every `<task>` block can be handed to a
   context-naive subagent with no other plan context and executed
   correctly.
4. **Type consistency** — names, signatures, paths used in later tasks
   match earlier tasks.
5. **Scope** — focused enough for a single plan, or split via `prd-to-issues`.
6. **Ambiguity** — any requirement readable two ways? Pick one; make it
   explicit.

Fix issues inline. No re-review.

---

## Wrap-up

1. **Post the plan comment.** Comment title line exactly:
   `Implementation plan for issue $ARGUMENTS`
   Body is the XML-tagged plan document from Phase 2.

2. **Post the plan-index comment.** A separate, tiny second comment that
   `ship` reads to bootstrap. Comment title line exactly:
   `Implementation plan-index for issue $ARGUMENTS`

   Body format (brevity applies):

   ```
   Implementation plan-index for issue $ARGUMENTS

   Tasks:
   - T10: <name>
   - T20: <name>
   - T30: <name>
   - ...

   CLAUDE.md SHA: <output of `git log -1 --format=%H -- CLAUDE.md` or "none">
   Plan comment URL: <permalink to the plan comment>
   ```

3. **Swap lifecycle labels on the issue:** add `planned`, remove
   `needs-plan`. (Labels are created once per repo via the `bootstrap`
   skill. Use whichever issue-tracker CLI is available.)

4. **Append the implementation log table to the issue body** under the
   `## Implementation log` heading. Create the section if absent. Use task
   IDs as row keys (NOT task numbers):

   ```
   ## Implementation log

   | Task | Status | Commit SHA |
   |------|--------|------------|
   | T10: <name> | ⬜ pending | — |
   | T20: <name> | ⬜ pending | — |
   | ...         | ...       | ... |
   | Review step | ⬜ pending | — |
   | PR / CI     | ⬜ pending | — |
   ```

5. **Stop.** Do not implement any changes. Tell the user:

   > Plan posted on issue #$ARGUMENTS. Run the `ship` skill with this issue number to begin implementation.
