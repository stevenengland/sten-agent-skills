---
name: issue-review-two-phases-4
description: >
  Apply an improvement plan interactively, then commit, push, and close the
  issue. Reviews each plan suggestion with the user before implementing.
  Use when asked to apply a plan, act on review feedback, or ship an issue.
  Part 4 of 4 in the issue-review-two-phases workflow.
disable-model-invocation: true
---

Work through the review plan for issue number $ARGUMENTS.

If no suitable plan comment is available on the issue (for example, a comment
containing a numbered list of suggestions with What / Why / Priority),
stop and ask the user to run the review skill first.

## YOLO Mode

If the user says **YOLO** at any point, switch to autonomous mode:

- Skip all interactive questions in Phase 1.
- Assess every suggestion yourself. Implement only those that provide
  meaningful value — skip trivial or unnecessary code improvements.
- Proceed directly to Phase 2 with your self-approved list.
- Before starting Phase 2, show a brief summary of what you chose to implement
  and what you skipped, using this format:

  Implementing:
  - #N: one-line reason
  - #M: one-line reason

  Skipped:
  - #K: one-line reason
  - #L: one-line reason

## Phase 1 — Evaluation

For each numbered suggestion in the plan:

1. Assess independently whether it is a good idea given the codebase context.
2. If you conclude it is worth doing, ask me explicitly:
   _"Suggestion #N: [one-line summary] — implement this?"_
3. Wait for my yes/no before moving to the next suggestion.
4. Track the approved list.

Do not implement anything during this phase.

_(Skipped entirely in YOLO mode.)_

## Phase 2 — Implementation

Implement all approved suggestions from Phase 1 (or the self-approved list
in YOLO mode) in a single pass.

When a suggestion involves code changes:

- Use TDD where appropriate: add or adjust tests first, then implement the
  minimal code to satisfy those tests.
- Apply your clean-code skill to keep the implementation simple, readable,
  and consistent with the existing codebase.

Keep changes focused on the scope of the approved suggestions.

## Phase 3 — Wrap-up

- Update the issue description and/or comments to reflect what was changed
  and why, referencing the suggestion numbers.
- Ask me to confirm the final review is complete.
- After confirmation: craft a **single** conventional commit that covers the
  entire issue — all changes from phase 1 through phase 3. The commit message
  must describe the overall feature, fix, or change delivered by the issue,
  not just the refactoring applied in this phase. Phase 3 refinements are part
  of that delivery, not a separate scope.
- Push the branch and close the issue.