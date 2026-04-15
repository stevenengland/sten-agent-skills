---
name: issue-review-two-phases-2
description: >
  Implement an issue by following an existing plan with TDD and clean code,
  then perform a refactor pass and wrap up. Stages changes only — does not
  commit. Use when a plan already exists on the issue. Part 2 of the
  issue-review-two-phases workflow.
disable-model-invocation: true
---

Implement issue number $ARGUMENTS by following the implementation plan
attached to the issue as a comment.

If no suitable implementation plan comment is available for this issue,
stop and ask the user to run the planning skill first.

## Phase 1 — ToDo Execution (TDD + Clean Code)

- For all code production, invoke your clean-code skill and your tdd skill.
- Walk through the plan tasks in order.
- For each task:
  - If helpful, translate the task into a short internal ToDo list.
  - Write or adjust tests first (TDD) unless the task is explicitly
    non-functional (e.g. docs-only).
  - Then implement the minimal code needed to make the tests pass.
- Keep changes focused on the scope described in the plan; avoid broad
  redesigns beyond what the issue and plan describe.
- If the plan is clearly inconsistent with the current codebase, pause and
  ask the user rather than silently re-planning.

Check off each task as you complete it in your running log.

## Phase 2 — Refactor Pass

Review every file touched against:

- Coding guidelines inferred from the repo.
- Known practices like clean-code, SOLID, DRY and KISS.

Perform a focused refactor pass:

- Eliminate duplication introduced during TDD steps.
- Clarify naming and structure where obviously beneficial.
- Do not introduce new scope beyond what the issue and plan describe.

This is the last coding step.

## Phase 3 — Wrap-up

- Update the issue description and/or comments with the decisions made and
  the approach taken, referencing the plan tasks.
- Stage all changes.
- Do **not** commit.