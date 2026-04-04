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

## Phase 1 — Evaluation

For each numbered suggestion in the plan:

1. Assess independently whether it is a good idea given the codebase context.
2. If you conclude it is worth doing, ask me explicitly:
   _"Suggestion #N: [one-line summary] — implement this?"_
3. Wait for my yes/no before moving to the next suggestion.
4. Track the approved list.

Do not implement anything during this phase.

## Phase 2 — Implementation

Implement all approved suggestions from Phase 1 in a single pass.
Use code quality skills like clean-code and tdd.

## Phase 3 — Wrap-up

- Update the issue description to reflect what was changed and why.
- Ask me to confirm the final review is complete.
- After confirmation: commit (conventional commit format), push the branch,
  and close the issue.
