---
name: prd-to-issues
description: Break a PRD into independently-grabbable issues using tracer-bullet vertical
  slices.
---

## Token Efficiency

**Load and apply the `brevity` sibling skill now, before the first response.**
It governs dialogue, exploration narration, and slice reasoning. Issue
bodies (titles, descriptions, acceptance criteria) are full-prose artifacts
(already excluded by `brevity`'s Scope section) — write them normally.

---

# PRD to Issues

Break a PRD into independently-grabbable issues using vertical slices
(tracer bullets).

## Process

### 1. Locate the PRD

Ask the user for the PRD issue number (or URL).

If the PRD is not already in your context window, fetch the issue content
(including comments) using the project's issue tracker CLI (e.g.
`gh issue view`, `glab issue view`). If no CLI is available, ask the user
to provide the PRD content.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the
current state of the code.

### 3. Draft vertical slices

Break the PRD into **tracer bullet** issues. Each issue is a thin vertical
slice that cuts through ALL integration layers end-to-end, NOT a horizontal
slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such
as an architectural decision or a design review. AFK slices can be
implemented and merged without human interaction. Prefer AFK over HITL
where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer
  (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories from the PRD this addresses

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?

Iterate until the user approves the breakdown.

### 5. Create the issues

Use whichever issue-tracker CLI is available;
otherwise present the formatted issue body for manual creation. Lifecycle
labels (`slice`, `hitl`, `afk`, `needs-plan`, `sliced`) are created once per
repo via the `bootstrap` skill — assume they exist.

For each approved slice, create an issue in the project's issue tracker
using the body template below.

Create issues in dependency order (blockers first) so you can reference real
issue numbers in the "Blocked by" field.

Immediately after creating each slice issue, apply these labels:

- `slice` — marks it as a child of a parent PRD.
- `hitl` or `afk` — matches the slice's Type.
- `needs-plan` — indicates no implementation plan has been posted yet (the
  `plan` skill removes this label when it posts a plan).

After all slice issues have been created, apply the `sliced` label to the
parent PRD issue so it is clearly marked as broken down.

<issue-template>
## Parent PRD

#<prd-issue-number>

## Type

<!-- HITL or AFK -->

## What to build

A concise description of this vertical slice. Describe the end-to-end
behavior, not layer-by-layer implementation. Reference specific sections of
the parent PRD rather than duplicating content.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- Blocked by #<issue-number> (if any)

Or "None — can start immediately" if no blockers.

## User stories addressed

Reference by number from the parent PRD:

- User story 3
- User story 7

## Implementation log

<!-- Leave blank. The `plan` skill appends the
       implementation plan here as a comment, and `ship`
     appends progress entries during execution. -->

</issue-template>

Do NOT close or modify the parent PRD issue.

**After creating all issues, tell the user:**

> All slice issues created. For each issue, run the
> `plan` skill (passing the issue number) to produce
> an implementation plan. Start with issues that have no blockers.
