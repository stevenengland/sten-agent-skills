---
name: issue-review-two-phases-2
description: Implement an issue by following an existing plan with TDD and clean code, then perform a refactor pass, file a PR, and monitor CI to green.
disable-model-invocation: true
---

## Token Efficiency

Activate the `caveman` sibling skill for running log entries (task tracking,
tier logs, status notes). Deactivate it for code, commit messages, PR body,
`LINT_BLOCKER` reports, and the Phase 3 wrap-up comment.

---

Implement issue number $ARGUMENTS by following the implementation plan
attached to the issue as a comment.

The implementation plan comment is the **definitive specification**. The issue
description states the goal; the plan governs. Where they conflict, the plan
wins.

If no suitable implementation plan comment is available for this issue,
stop and ask the user to run the `issue-review-two-phases-1` planning skill
first.

## Prerequisites (complete before any task)

- [ ] Read `CLAUDE.md` and note all hard constraints: untouchable files,
  forbidden suppressions, required tooling, enforced commands. These
  constraints are non-negotiable and supersede all other instructions.
- [ ] Load the `lint-escape` sibling skill. Apply it whenever a lint or
  static-analysis error cannot be resolved with clean code.
- [ ] Load the `tdd`, `clean-code`, and `conventional-commits` sibling skills.
- [ ] Confirm the test command and lint/check command from the plan's
  Assumptions section.

## Phase 1 — Task Execution (TDD + Clean Code)

Walk through the plan tasks in order. Check off each task in the running log
as you complete it.

For each task:

- Translate the task into a short internal to-do list if helpful.
- Write or adjust tests first (TDD) unless the task is explicitly
  non-functional (e.g. docs-only).
- Implement the minimal code needed to make the tests pass.
- After all tests in the slice are green, run the full lint/check command.
  Resolve any errors using the `lint-escape` skill before proceeding.
- Keep changes focused on the scope described in the plan. Avoid redesigns
  beyond what the issue and plan describe.
- If the plan is clearly inconsistent with the current codebase, stop and
  report — do not silently re-plan.

**The last task in every plan is a documentation task. Do not skip it or
mark it done without actually reviewing each listed file.**

**Never commit without running hooks. Never use `--no-verify` or equivalent.**

After each task's tests are green and lint is clean, commit using the
pre-written commit message from the plan.

## Phase 2 — Refactor Pass

Review every file touched against:

- Hard constraints from `CLAUDE.md`.
- Coding guidelines inferred from the repo.
- `clean-code`, SOLID, DRY, KISS.

Perform a focused refactor pass:

- Eliminate duplication introduced during TDD steps.
- Clarify naming and structure where obviously beneficial.
- Do not introduce new scope beyond what the issue and plan describe.

Run the full lint/check command and test suite after the refactor. Apply
`lint-escape` if needed. This is the last coding step.

## Phase 3 — Review Step

Work through the **Review Step** section of the plan (if present). For each
block:

- **Architectural Invariants:** run the invariant test file. All must pass.
- **Recommended Regression Tests:** confirm each listed test exists, or note
  the justified absence in the PR body.
- **Self-report Checklist:** execute each item. Fix any failure before
  proceeding. Do not mark an item done without running the command.

## Phase 4 — PR and CI Loop

### File the PR

- Stage all changes.
- Commit any remaining staged files (hooks must run and pass).
- Push the branch.
- Open a PR against the default branch. PR body must include:
  - One-sentence summary of what this delivers.
  - Link to the issue (`Closes #$ARGUMENTS`).
  - Summary of any Tier 2 or Tier 3 `lint-escape` actions taken, with
    rationale (copy from running log).
  - Any justified absences from the Review Step checklist.

### CI Loop (max 3 fix cycles)

After the PR is filed, monitor CI. For each failed run:

1. Read the failure output.
2. Identify the root cause (test failure, lint error, type error, hook
   failure).
3. Apply the appropriate fix: clean code change, or `lint-escape` protocol
   if a lint/type error.
4. Commit the fix (hooks must run). Push. Wait for CI.

**Cap: 3 fix cycles.** If CI is still failing after 3 cycles, stop and write
the following report as a PR comment and to the running log:

    CI_BLOCKER
    ─────────────────────────────────────────────
    Cycle:     3 of 3 exhausted
    Failing:   <job name and step>
    Error:     <exact error output>
    Cycles tried:
      Cycle 1: <approach and outcome>
      Cycle 2: <approach and outcome>
      Cycle 3: <approach and outcome>
    Options for resolution (choose one):
      A) <concrete fix — specific file, line, change>
      B) <config or environment change required>
    ─────────────────────────────────────────────

Do not push further commits after writing the CI_BLOCKER report.

## Phase 5 — Wrap-up

Once CI is green:

- Update the issue comment with a brief summary of the approach taken,
  referencing plan tasks completed and any lint-escape actions logged.
- Do not close the issue — the PR merge closes it via `Closes #$ARGUMENTS`.
