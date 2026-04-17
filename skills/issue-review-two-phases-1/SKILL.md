---
name: issue-review-two-phases-1
description: >
  Understand and plan an issue end-to-end. Run a design interview,
  explore the codebase, and produce a compact, executable implementation plan
  including a testing strategy. No code changes applied. Use when asked to
  design or plan an issue before implementation. Part 1 of the
  issue-review-two-phases workflow.
disable-model-invocation: true
---

Plan the implementation of issue number $ARGUMENTS.

## Phase 1 — Design Interview

Interview me relentlessly about every aspect of the plan until we reach a
shared understanding. Walk down each branch of the design tree and resolve
dependencies between decisions one-by-one. For each question, provide your
recommended answer.

If a question can be answered by exploring the codebase, explore the codebase
instead.

When a recommendation touches a problem that well-known companies
(e.g. Stripe, Spotify, GitHub, AWS, Shopify) have solved publicly, research
how those industry leaders approach it and briefly weave the relevant patterns
or practices into your recommendation. Cite the company and the specific
practice so I can evaluate the reasoning. Do not force-fit references —
only include them when genuinely relevant.

Do not write any code in this phase.

## Phase 2 — Architecture & Testing Strategy

- Identify whether the change has architectural implications.
- If it does, invoke your architecture skill to shape the design.
- Describe the main design decisions:
  - Key components and their responsibilities.
  - Interfaces and boundaries.
  - Data and error flow.
- Outline a testing strategy:
  - Which layers to test.
  - Critical cases and edge conditions.
  - Any regression tests to add or adjust.

Stay at a level that a competent implementation model can follow without
redoing architecture work, but do not include concrete code snippets longer
than a few lines.

## Phase 3 — Implementation Plan

Derive a structured ToDo list from the agreed design and testing strategy:

- Group tasks logically (e.g. “Add domain object X”, “Update API Y”,
  “Adjust tests in Z”).
- For each task, provide:
  1. **What** — 1–3 sentences describing the change, naming files/functions.
  2. **Why** — why this task exists (link it to the design decisions).
  3. **Tests** — which tests to write or adjust.

Constraints:

- Do not paste large chunks of existing code; refer to symbols and files
  by name instead.
- Keep tasks as small as needed for TDD, but avoid micro-tasks that a
  competent model can trivially decompose.
- Avoid long, repetitive prose; make the plan compact and scannable.

Present the final plan as a numbered list of tasks.

## Wrap-up

- Add the implementation plan to the issue as a comment.
- Clearly label it as the implementation plan for issue $ARGUMENTS.
- Stop after the plan is produced. Do not implement any changes.