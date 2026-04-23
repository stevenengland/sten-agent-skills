---
name: prd-to-issues
description: Break a PRD into independently-grabbable issues using tracer-bullet vertical
  slices.
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs dialogue, exploration narration, and slice reasoning. Issue
bodies (titles, descriptions, acceptance criteria) are full-prose artifacts
(already excluded by `brevity`'s Scope section) — write them normally.

---

# PRD to Issues

Break a PRD into independently-grabbable issues using vertical slices
(tracer bullets).

## Process

### 1. Locate the PRD

**Fast-path:** if the PRD is already in your context from a chained
`prd-from-grill-me` run in this session, skip the fetch — note the issue
number and continue.

Otherwise, ask the user for the PRD issue number (or URL).

If the PRD is not already in your context window, fetch the issue content
(including comments) using the project's issue tracker CLI (e.g.
`gh issue view`, `glab issue view`). If no CLI is available, ask the user
to provide the PRD content.

### 2. Explore the codebase (optional, via subagent)

**Fast-path:** if module exploration on the same modules (named in the
PRD's Implementation Decisions) was already performed in this session,
skip — proceed to Step 3 using prior findings.

If you have not already explored the codebase in this session, **delegate
exploration to an Explore subagent** rather than reading files directly.
The subagent returns a ≤300-word report that stays compact in the
orchestrator trajectory.

First, extract the list of modules named in the PRD's **Implementation
Decisions** section — those are the only modules the subagent should
read. For each named module, the subagent reads **only the primary source
file + its most relevant test file**. Do not let the subagent wander the
repo.

Dispatch message:

> For each module listed below (from the PRD's Implementation Decisions),
> read ONLY its primary source file and the most directly associated test
> file. Do not read other files.
>
> Modules:
> - <module 1 name> — likely path: <path or "search by name">
> - <module 2 name> — likely path: <path or "search by name">
> - …
>
> Return a single report of ≤300 words total covering, per module: current
> shape in one sentence, integration points, and where a tracer-bullet
> slice would likely cut in. Thoroughness: quick.

Escape hatch: if the returned report leaves specific ambiguities, dispatch
a targeted follow-up subagent for just those files. Do not read the
codebase in the parent session.

### 3. HITL triage

Before drafting slices, list every decision that would normally trigger a
HITL slice. For each, classify:

- **Bikeshed** (naming, shape, layout, test layout, error surfacing,
  vocabulary) → should already live in the PRD's `## Conventions` section.
  If missing, stop and ask the user to add it before continuing. These do
  NOT warrant HITL slices.
- **Novel pattern** (new architectural idea, action vocabulary for a state
  machine, etc.) → two options:
  - Lock the shape in the PRD's `## Conventions` section, then treat the
    slice as AFK.
  - Introduce a **spike slice**: a tiny AFK+Lite slice that lands the
    types / vocabulary / one representative test — no consumers. Later
    slices consume the locked shape. Use this when the shape is hard to
    fully specify without touching code.
- **Genuine judgment call** (irreducible — the decision truly can only be
  made once implementation starts) → keep HITL, but write the escape hatch
  into the slice: state the fallback plan if the judgment call goes the
  "wrong" way.

Goal: zero HITL slices at the end of triage except irreducible judgment
calls. Present the triage table to the user for confirmation before
drafting slices.

### 4. Draft vertical slices (Lite-first)

Break the PRD into **tracer bullet** issues. Each issue is a thin vertical
slice that cuts through ALL integration layers end-to-end, NOT a horizontal
slice of one layer.

**Draft slices assuming each MUST fit the Lite envelope.** The `ship-light`
envelope is:

- ≤ 15 files changed (no distinction between src and test files)
- One top-level module directory. Intra-directory helpers are allowed and
  do not count as a second subsystem.
- No schema migration
- No architectural unknowns (resolved in PRD `## Conventions` or a spike
  slice)
- AFK-typed

A slice may exceed the envelope only if it is genuinely irreducible —
splitting would break the vertical-slice rule (no observable behavior) or
introduce a doc-only slice that ships nothing.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such
as an architectural decision or a design review. AFK slices can be
implemented and merged without human interaction. Prefer AFK over HITL
where possible — the Step 3 triage should have already eliminated most
HITL candidates.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer
  (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

### 5. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories from the PRD this addresses
- **Lite-eligible**: `true` / `false`. Default `true` when borderline —
  set `false` only when you can name a specific disqualifier (see below).
- **If `false`**: cite the disqualifier tag and the split axis you
  considered and rejected.

Disqualifier tags (pick exactly one for non-Lite slices):

- `files>15` — exceeds file cap
- `cross-module` — touches more than one top-level module directory
- `schema-migration` — includes a schema change
- `arch-unknown` — architectural decision not resolved in PRD
- `hitl-cat3` — genuine irreducible judgment call

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further? **For every non-Lite
  slice, is the rejected split axis convincing? If weak, split.**
- Are the correct slices marked as HITL and AFK?
- Are the `Lite-eligible` flags and disqualifier tags right?

> *Note: solo-dev assumption. On mid-batch failure, manually delete partial
> slice issues before re-running, or duplicates will be created.*

Iterate until the user approves the breakdown.

### 6. Create the issues

Use whichever issue-tracker CLI is available;
otherwise present the formatted issue body for manual creation. Lifecycle
labels (`slice`, `hitl`, `afk`, `needs-plan`, `sliced`) are created once per
repo via the `bootstrap` skill — assume they exist.

Before creating issues, extract the PRD's `## Conventions` section into a
scratch file:

```bash
gh issue view <prd-number> --json body -q .body > /tmp/prd-<prd-number>.md
awk '/^## Conventions/,/^## /' /tmp/prd-<prd-number>.md | sed '$d' \
  > /tmp/prd-<prd-number>-conventions.md
wc -l /tmp/prd-<prd-number>-conventions.md   # confirm; do not cat
```

For each approved slice, create an issue in the project's issue tracker
using the body template below, inlining the Conventions file verbatim
where indicated.

Create issues in dependency order (blockers first) so you can reference real
issue numbers in the "Blocked by" field.

Immediately after creating each slice issue, apply these labels:

- `slice` — marks it as a child of a parent PRD.
- `hitl` or `afk` — matches the slice's Type.
- `needs-plan` — indicates no implementation plan has been posted yet (the
  `plan` skill removes this label when it posts a plan).
- `spike` — only for spike slices (see Step 3). `ship-light` preflight
  skips the `arch-unknown` disqualifier for spike slices since their
  purpose is to resolve unknowns.

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

## Conventions (from PRD)

<!--
Copy the PRD's `## Conventions` section verbatim here (contents only —
do not repeat the `## Conventions` heading from the PRD). Slices are
self-contained; downstream skills (plan, ship, ship-light) read this
section as hard spec without chasing back to the PRD.

If the PRD's Conventions section says `None — slice-local decisions
only.`, copy that line verbatim.
-->

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

## Files (hint)

Optional bridge for `ship-light`. List the files this slice will likely
touch, with a one-line responsibility each. Best-effort only — drawn
from the Step 2 module exploration. Omit the section if exploration
produced nothing reliable.

- Create: `path/to/new.py` — <one-line responsibility>
- Modify: `path/to/existing.py` — <what changes>
- Test:   `tests/path/to/test_file.py` — <what it covers>

## Lite-eligible

<!--
For Lite slices, write exactly:

    `true`

For non-Lite slices, write the structured block:

    `false`

    **Disqualifier:** <one of: files>15 | cross-module | schema-migration | arch-unknown | hitl-cat3>
    **Reason:** <one sentence — what specifically triggers the disqualifier>
    **Split axis considered:** <one sentence — what split was rejected and why>

Default is `true` when borderline. Only set `false` with a named
disqualifier.
-->

## Implementation log

<!-- Leave blank. The `plan` skill appends the
       implementation plan here as a comment, and `ship`
     appends progress entries during execution.
     `ship-light` does not write here. -->

</issue-template>

Do NOT close or modify the parent PRD issue.

**After creating all issues, tell the user:**

> All slice issues created. For each issue, choose one path:
>
> - **Lite path** — `/stenswf:ship-light <issue>` for slices marked
>   `Lite-eligible: true` (single subsystem, crisp ACs, AFK).
>   Branches, TDDs, PRs, watches CI in one Sonnet session.
> - **Full path** — `/stenswf:plan <issue>` then `/stenswf:ship <issue>`
>   for HITL slices, `Lite-eligible: false`, or anything architecturally
>   uncertain.
>
> Start with issues that have no blockers.
