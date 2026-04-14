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
dependencies between decisions one-by-one. For each question, provide your recommended answer.

If a question can be answered by exploring the codebase, explore the codebase instead.

When a recommendation touches a problem that well-known companies (e.g. Stripe, Spotify, GitHub, AWS, Shopify) have solved publicly, research how those industry leaders approach it and weave the relevant patterns or practices into your recommendation. Cite the company and the specific practice so I can evaluate the reasoning.

Do not write any code yet.

## Phase 2 — Planning

- If the change has architectural implications, invoke your architecture skill.
- Derive a structured ToDo list from the agreed design. Show it to me and wait
for my approval before proceeding.

## Phase 3 — Implementation

- For all code production, invoke your clean-code skill and your tdd skill.
- Work through the approved ToDo list step-by-step. Check off each item.

## Phase 4 — Refactor Pass

Review every file touched against the coding guidelines inferred from the repo and known ones like clean-code, SOLID, DRY, etc. Fix any drift. Make sure you were efficient and did not introduce any issues. 
This is the last coding step.

## Wrap-up

- Update the issue description with the decisions made and the approach taken.
- Stage all changes.
- Do **not** commit.