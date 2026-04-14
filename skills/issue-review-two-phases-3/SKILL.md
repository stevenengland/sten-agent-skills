---
name: issue-review-two-phases-3
description: >
  Apply an improvement plan interactively, then commit, push, and close the
  issue. Reviews each plan suggestion with the user before implementing.
  Use when asked to apply a plan, act on review feedback, or ship an issue.
  Part 3 of 3 in the issue-review-two-phases workflow.
disable-model-invocation: true
---

Work through the plan at $ARGUMENTS. If the plan file is missing look for a review comment on the issue online. Without this plan you are not good to go.

## YOLO Mode

If the user says **YOLO** at any point, switch to autonomous mode:

- Skip all interactive questions in Phase 1.
- Assess every suggestion yourself. Implement only those that provide
  meaningful value — skip trivial or unnecessary code improvements.
- Proceed directly to Phase 2 with your self-approved list.
- Still show a brief summary of what you chose to implement and what you
  skipped (with one-line reasons) before starting Phase 2.

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

Implement all approved suggestions from Phase 1 (or the self-approved list in
YOLO mode) in a single pass.
Use code quality skills like clean-code and tdd.

## Phase 3 — Wrap-up

- Update the issue description to reflect what was changed and why.
- Ask me to confirm the final review is complete.
- After confirmation: craft a **single** conventional commit that covers the
  entire issue — all changes from phase 1 through phase 3. The commit message
  must describe the overall feature, fix, or change delivered by the issue, not
  just the refactoring applied in this phase. Phase 3 refinements are part of
  that delivery, not a separate scope.
- Push the branch and close the issue.
