---
name: issue-review-two-phases-1
description: >
  Implement a GitHub issue end-to-end with a design interview, architecture
  review, TDD, clean code, and a final refactor pass. Stages changes only —
  does not commit. Use when asked to implement, build, or work on a specific
  issue number. Part 1 of 3 in the issue-review-two-phases workflow.
disable-model-invocation: true
---

Implement issue number $ARGUMENTS.

## Phase 1 — Design Interview

Interview me relentlessly about every aspect of the plan until we reach a
shared understanding. Walk down each branch of the design tree and resolve
dependencies between decisions one-by-one. Do not write any code yet.

## Phase 2 — Planning

- If the change has architectural implications, invoke your architecture skill.
- Derive a structured ToDo list from the agreed design. Show it to me and wait
for my approval before proceeding.

## Phase 3 — Implementation

- For all code production, invoke your clean-code skill and your tdd skill.
- Work through the approved ToDo list step-by-step. Check off each item.

## Phase 4 — Refactor Pass

Review every file touched against the coding guidelines inferred from the repo and known ones like clean-code, SOLID, DRY, etc. Fix any drift. This is the last coding step.

## Wrap-up

- Update the issue description with the decisions made and the approach taken.
- Stage all changes.
- Do **not** commit.