---
name: plan
description: Understand and plan a slice issue end-to-end. Produces a local plan
  tree under `.stenswf/<issue>/` with per-task fragments, a stable-prefix dispatch
  file, and a manifest. The issue body remains the conceptual contract.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response
in this session.** It governs all Phase 0 and Phase 1 dialogue, including
internal reasoning and tool-use narration. Self-check every message against
its rules before sending — do not drift into full prose on internal thinking.

Do not apply `brevity` to the Phase 2 plan artifacts themselves — task
fragments are written in full prose for a context-naive implementer agent.

---

Plan the implementation of issue number $ARGUMENTS.

## Audience

The planner (you, in this skill) is highly skilled and has full codebase
context. The implementer (the `ship` skill) is a skilled developer but:

- Has zero context for this codebase.
- Knows almost nothing about its toolset or problem domain.
- Has weak test-design instincts.
- May be a mid-tier LLM.
- Executes **one task at a time** in a fresh subagent session with no memory
  of previous tasks.

Write the plan for that implementer. Each task fragment must be fully
self-contained: document exactly which files to touch, which existing
code to read first, which tests to write, which commands to run, and
what to commit. Bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

## Where artifacts live

All plan artifacts are written under `.stenswf/$ARGUMENTS/` (gitignored,
repo-root). The issue body holds only the **conceptual plan** from
`prd-to-issues`: `What to build`, `Acceptance criteria`, `Conventions
(from PRD)`, `Files (hint)`, `Blocked by`, `## Type` marker. The fine
implementation plan never touches the issue. Labels are not used.

If `.stenswf/` does not yet exist, create it (or run the `bootstrap`
skill once). On re-run with `--resume`, preserve completed task entries
and regenerate the rest (see *Phase 3 — Resume*).

## Scope Check

If the issue spans multiple independent subsystems, stop and suggest
splitting it into sub-issues using the `prd-to-issues` skill before
planning. Each plan should produce working, testable software on its own.

---

## Phase 0 — Issue Pre-flight

Complete this phase before any codebase exploration or interview questions.

Fetch the issue and extract the conceptual slice into a scratch file —
never `cat` the issue body into context directly:

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
wc -l /tmp/slice-$ARGUMENTS.md   # confirm; do not cat
```

Extract and record (via `awk`, one section at a time):

- [ ] **Kind marker.** `awk '/^## Type/,/^## /' /tmp/slice-$ARGUMENTS.md | sed '$d' | tail -n +3`.
      Expect `slice — HITL`, `slice — AFK`, or `slice — spike`. If
      missing or says `PRD`, stop and tell the user this issue is not a
      slice.
- [ ] **Parent PRD** issue number (from `## Parent PRD` section).
- [ ] **Parent PRD body sections this slice needs** — fetch via
      redirect-then-awk:

      ```bash
      gh issue view <parent-prd> --json body -q .body > /tmp/prd-<parent-prd>.md
      awk '/^## User Stories/,/^## /'            /tmp/prd-<parent-prd>.md | sed '$d'
      awk '/^## Implementation Decisions/,/^## /' /tmp/prd-<parent-prd>.md | sed '$d'
      awk '/^## Out of Scope/,/^## /'             /tmp/prd-<parent-prd>.md | sed '$d'
      ```
- [ ] **Slice type.** From the kind marker (`HITL`, `AFK`, or `spike`).
- [ ] **Conventions (from PRD)** — extract the slice's `## Conventions
      (from PRD)` section verbatim; it becomes `conventions.md` in Phase 2.

      ```bash
      awk '/^## Conventions \(from PRD\)/,/^## /' /tmp/slice-$ARGUMENTS.md \
        | sed '$d' > /tmp/slice-$ARGUMENTS-conventions.md
      ```
- [ ] **Acceptance criteria** — list every criterion verbatim. Each must
      map to at least one plan task.
- [ ] **Blocked by** — for each blocker, read its local plan if available
      (`.stenswf/<blocker>/file-structure.md`, `.stenswf/<blocker>/acceptance-criteria.md`).
      If the blocker was shipped via `ship-light`, the issue body's
      `Files (hint)` is the only spec — fetch that.
- [ ] **Interview depth** — set based on slice type:
  - **AFK**: abbreviated interview. Confirm orientation, produce 3–5
    Design Decision entries, then proceed directly to Phase 2.
  - **HITL**: full interview. Resolve all design branches before Phase 2.
  - **spike**: abbreviated; the slice exists to land types / vocabulary.

---

## Phase 1 — Design Interview

### Orientation (complete before interview)

Dispatch an `Explore` subagent; do not read files directly in this session.

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

### Interview

Interview me relentlessly about every aspect of the plan until we reach a
shared understanding. Walk down each branch of the design tree and resolve
dependencies between decisions one-by-one.

- For each question, provide your recommended answer and reasoning.
- If a question can be answered by exploring the codebase, dispatch a
  targeted Explore subagent.
- Propose 2–3 different approaches with trade-offs.
- Lead with your recommended option and explain why.
- Go back and clarify when something doesn't make sense.
- Cite industry practice only when it actively distinguishes between two
  options currently in play.

Do not write any code in this phase.

### Design Decisions Log

Maintain a running log of resolved decisions at the top of your response:

    ## Design Decisions
    - [topic]: [chosen approach] — [one-sentence rationale]

If the log exceeds ~10 entries before the interview is complete, the
issue likely spans independent subsystems — stop and suggest splitting.

---

## Phase 2 — Write the local plan tree

Materialise the following files under `.stenswf/$ARGUMENTS/`:

```
.stenswf/$ARGUMENTS/
├── manifest.json
├── concept.md              # verbatim issue body at plan time (for drift)
├── stable-prefix.md        # assembled dispatch prefix (verbatim for cache)
├── conventions.md          # verbatim from slice body's Conventions section
├── house-rules.md
├── design-summary.md
├── acceptance-criteria.md
├── file-structure.md
├── assumptions.md
├── review-step.md
└── tasks/
    ├── T10.md
    ├── T20.md
    └── T<last>.md          # documentation task (always last)
```

Each file's content rules follow. Brevity Rules apply to
`house-rules.md`, `design-summary.md`, `assumptions.md`. They do NOT
apply to `conventions.md` (verbatim copy), task bodies, commands, file
paths, or `review-step.md`.

### manifest.json

```json
{
  "issue": $ARGUMENTS,
  "prd": <parent-prd-number>,
  "kind": "slice",
  "slice_type": "HITL|AFK|spike",
  "branch": null,
  "base_sha": null,
  "plan_created_at": "<ISO-8601>",
  "claude_md_sha": "<output of: git log -1 --format=%H -- CLAUDE.md AGENTS.md 2>/dev/null | head -1>",
  "concept_sha256": "<sha256 of /tmp/slice-$ARGUMENTS.md>",
  "section_hashes": {
    "acceptance_criteria": "<sha256>",
    "conventions": "<sha256>",
    "what_to_build": "<sha256>"
  },
  "tasks": [
    {"id": "T10", "name": "<slice name>", "file": "tasks/T10.md",
     "commit_subject": "<type>(<scope>): <subject>",
     "status": "pending", "sha": null},
    {"id": "T20", "name": "…", "file": "tasks/T20.md",
     "commit_subject": "…", "status": "pending", "sha": null}
  ],
  "refactor_pass": {"status": "pending", "sha": null},
  "review_step":   {"status": "pending", "sha": null},
  "pr":            {"status": "pending", "url": null}
}
```

Compute SHAs with `sha256sum <file> | cut -d' ' -f1`. `branch` and
`base_sha` are filled in by `ship` at dispatch time.

### concept.md

Full issue body copied verbatim at plan time. Used by drift detection
(`ship`, `review`, `apply` re-fetch the issue body and compare hashes).

### stable-prefix.md

This file is pasted **byte-identical** at the start of every subagent
dispatch `ship` makes, so prompt caching hits on dispatches 2..N.
Assemble it once here, at plan time, and never modify. Order:

```
SKILLS TO LOAD: tdd, clean-code, lint-escape

HARD CONSTRAINTS (from CLAUDE.md — non-negotiable, verbatim, compressed):
<the compressed hard-constraints block: untouchable files, forbidden
 suppressions, required tooling, enforced commands. Extract quotes
 verbatim; compress surrounding prose per brevity Rules.>

TEST COMMAND: <exact test command from orientation>
LINT COMMAND: <exact lint/check command from orientation>

HOUSE RULES (from the plan, read before every task):
<paste the contents of house-rules.md verbatim>

CONVENTIONS (from parent PRD — hard spec, follow verbatim):
<paste the contents of conventions.md verbatim>

REASONING STYLE: Keep internal reasoning terse. No pre-summaries, no
restating the task, no filler. Commit messages, PR bodies, and error
quotes remain verbatim.

CONTEXT HYGIENE: Do not re-read files you already read in this task. If
your harness supports `clear_tool_uses_20250919`, fire it with `keep: 3`
after each green test in this slice.

--- (stable prefix ends here; everything above is identical across tasks) ---
```

### conventions.md

Verbatim contents of the slice body's `## Conventions (from PRD)` section.
If it says `None — slice-local decisions only.`, write that single line.

### house-rules.md

Brevity Rules apply. Contents:

```
- Follow the `tdd` skill: one failing test, then minimal code, then next.
- Follow the `clean-code` skill.
- Follow `conventions.md` verbatim — do not invent alternative names, shapes, or layouts. Escalate if a convention conflicts with the codebase.
- DRY, YAGNI. No speculative abstractions. No error handling for impossible cases.
- Use the pre-written commit message at the end of each task verbatim.
- If a task conflicts with the codebase, pause and report — do not re-plan silently.
- One task at a time. Do not read ahead or attempt other tasks.
```

### design-summary.md

3–5 short sentences on the approach: key components, interfaces,
data/error flow. Brevity Rules apply.

### acceptance-criteria.md

Every AC from the issue, verbatim, one bullet each. Each must map to
exactly one task's `Done when` line.

### file-structure.md

```
- Create: `path/to/new_file.py` — <responsibility>
- Modify: `path/to/existing.py` — <what changes>
- Test:   `tests/path/to/test_file.py` — <what it covers>
```

### assumptions.md

3–5 load-bearing assumptions. Brevity Rules apply.

```
- <assumption 1>
- <assumption 2>
```

### review-step.md

```
# Slice-level Review Step — #$ARGUMENTS (<one-line title>)

Architectural invariants (enforced test file), recommended regression
tests (advisory), self-report checklist.

## Architectural Invariants
- [ ] **<Invariant name>.** <What the test asserts. Symbol paths only.>

## Recommended Regression Tests
- [ ] **<Scenario>.** <Setup, action, expected outcome.>

## Self-report Checklist
- [ ] `<lint command>` green.
- [ ] `<test command>` green.
- [ ] Invariants pass.
- [ ] Regression tests exist or absences justified in PR.
- [ ] No stale references to deleted symbols.
```

### tasks/T<id>.md (one file per task)

Tasks are **vertical slices**. Soft cap: if a slice needs more than ~5
test cases or touches more than ~4 files, split it.

IDs are gap-numbered from `T10` stepping by 10 (`T10`, `T20`, …).
The final task is always a documentation task (T<last>).

Each file is fully self-contained — a subagent receiving only this file
plus `stable-prefix.md` must be able to execute it correctly. Never
write "similar to Task N" or reference another task's code; repeat what
the implementer needs.

Task body template (full prose — brevity does NOT apply):

```
<task id="T10" name="<slice name>" commit="<type>(<scope>): <subject>">

**Goal:** <one sentence, behavior-level>
**Files:**
- Create: `exact/path/to/new_file.py` — <responsibility>
- Modify: `exact/path/to/existing.py` — <what changes>
- Test:   `tests/exact/path/to/test_file.py`
**Pre-reading (read before editing):**
- `path/to/analogous_code.py::symbol` — existing pattern to mirror
- `tdd` skill — if unsure about test shape
**Done when:** <crisp acceptance criterion — must match one AC>

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
  Run: `<exact command>`
  Expected: FAIL with `<expected error substring>`
- [ ] Step 3 — Implement minimal code in `<impl file>`.
  Approach: <1–3 sentences; reference analogous symbol by path>.
- [ ] Step 4 — Run test, confirm it passes:
  Run: `<same command>`
  Expected: PASS

After all tests in the slice are green:

- [ ] Refactor within the slice. Tests stay green.
- [ ] Verify: `<exact command>` — all PASS.
      If user-visible, also run: `<manual check>`.
- [ ] Commit using the task's `commit` attribute with a
      `Refs: #$ARGUMENTS T<id>` trailer:
  ```bash
  git add <paths>
  git commit -m "<commit attribute verbatim>" -m "Refs: #$ARGUMENTS T<id>"
  ```

</task>
```

The opening XML tag `<task id="T<id>" name="…" commit="…">` must be
present; `ship` does not re-parse the task file but other tools (review,
future tooling) may extract sub-sections via `awk`.

#### Documentation Task (always last)

Every plan ends with a doc task using the last T-ID:

```
<task id="T<last>" name="Update documentation" commit="docs(<scope>): update docs for issue $ARGUMENTS">

**Goal:** All affected documentation reflects the post-implementation state.
**Files:**
- Modify: `CLAUDE.md` — if new patterns or conventions were introduced
- Modify: `README.md` — if public shape changed
- Modify: `docs/<relevant>.md` — if applicable
**Pre-reading:** Orientation summary from Phase 1.
**Done when:** Every doc file from the orientation summary is either
updated or explicitly noted "no update needed".

- [ ] Review each file from the orientation summary's doc list.
- [ ] Update or note "no update needed" inline.
- [ ] Commit with a `Refs: #$ARGUMENTS T<last>` trailer.

</task>
```

### Prescriptiveness rules

- **Test steps:** write the full test code. Be prescriptive.
- **Implementation steps:** describe the approach and point at analogous
  symbols. Do not pre-write the full implementation unless no analog exists.
- Use exact file paths and exact commands everywhere.
- Never write: `TBD`, `TODO`, `implement later`, `similar to Task N`,
  test steps without test code, references to undefined symbols.

---

## Phase 3 — Resume (`plan --resume`)

When `plan` is invoked with `--resume` (typically by `ship` after
detecting drift):

1. Read existing `manifest.json`.
2. Preserve entries where `status == "done"` — their `sha` and
   `commit_subject` stay as-is.
3. Re-run Phase 0 + Phase 1 (orientation + relevant interview) to refresh
   the plan based on the current issue body.
4. Re-write `concept.md`, `stable-prefix.md`, `conventions.md`,
   `house-rules.md`, `acceptance-criteria.md`, `file-structure.md`,
   `assumptions.md`, `review-step.md`, `design-summary.md`.
5. Re-write `tasks/T<id>.md` files for every pending / blocked task
   (delete stale fragments that no longer map to an AC).
6. Update manifest hashes (`concept_sha256`, `section_hashes.*`,
   `claude_md_sha`) and bump `plan_created_at`.
7. Leave done-task fragments in place for forensic purposes.

---

## Self-review

After writing all files, validate mechanically:

```bash
D=.stenswf/$ARGUMENTS

# 1. Required files exist.
for f in manifest.json concept.md stable-prefix.md conventions.md house-rules.md \
         design-summary.md acceptance-criteria.md file-structure.md assumptions.md \
         review-step.md; do
  [ -s "$D/$f" ] || echo "FAIL: $f missing or empty"
done
[ -d "$D/tasks" ] || echo "FAIL: tasks/ dir missing"
ls "$D/tasks"/T*.md >/dev/null 2>&1 || echo "FAIL: no task fragments"

# 2. manifest.json parses and lists existing task files.
jq -e '.tasks[] | .file' "$D/manifest.json" | while read f; do
  f=${f%\"}; f=${f#\"}
  [ -s "$D/$f" ] || echo "FAIL: task file missing: $f"
done

# 3. Every <task> opening tag has id, name, commit attributes.
for f in "$D"/tasks/T*.md; do
  head -1 "$f" | grep -qE '<task id="T[0-9]+" name="[^"]+" commit="[^"]+">' \
    || echo "FAIL: malformed opening tag in $f"
done

# 4. Task IDs unique.
grep -ohE 'id="T[0-9]+"' "$D"/tasks/*.md | sort | uniq -d \
  | sed 's/^/FAIL: duplicate id /'

# 5. AC bullets each referenced by at least one Done-when.
grep -oE '^- AC[0-9]+' "$D/acceptance-criteria.md" \
  | while read ac; do
      grep -q "$ac" "$D"/tasks/*.md || echo "FAIL: $ac has no Done-when"
    done
```

Content checks (read yourself):

1. No placeholders (`TBD`, `TODO`, "similar to Task N").
2. Every task names at least one existing file/symbol.
3. Every task is self-contained — executable with only its file +
   `stable-prefix.md`.
4. Names, signatures, and paths consistent across tasks.
5. Every ambiguity resolved to one explicit choice.

Fix inline. No re-review pass.

---

## Wrap-up

Tell the user (no labels, no issue comments, no plan-index comment):

> Plan written to `.stenswf/$ARGUMENTS/`. Tasks: T10, T20, T30, … Run
> `/stenswf:ship $ARGUMENTS` to begin implementation.

Do not modify the issue. Do not implement any changes.
