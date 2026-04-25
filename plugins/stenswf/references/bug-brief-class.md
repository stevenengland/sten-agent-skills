# bug-brief class — addendum to PRD template

A **bug-brief** is a narrow PRD-shaped artifact emitted by
`/stenswf:triage-issue` when an accepted bug needs ceremony. It uses
[prd-template.md](prd-template.md) with two markers:

```
type: bug-brief
class: bug-brief
```

This file documents the section-by-section overrides. Everything not
listed here behaves as in the base PRD template.

## Required body sections

| Section | Notes |
|---|---|
| `## Problem Statement` | One-paragraph summary of the broken behavior, lifted from the original bug report (paraphrased — keep the reporter's wording verbatim only when essential). |
| `## Root Cause` | Output of `triage-issue` Phase 3. ≤3 sentences. Cites file:line for the origin and the symptom. |
| `## Implementation Decisions` | Fix-shape summary from triage. Modules to modify. No file paths or code. |
| `## Invariants Preserved` | **Required.** Behaviors that MUST stay unchanged (e.g. public API stable, persisted state shape unchanged, existing green tests stay green). |
| `## Conventions` | New rules introduced by this fix to prevent recurrence. May be exactly `None — slice-local decisions only.` |
| `## Out of Scope` | Adjacent defects observed but explicitly deferred. Prevents slice scope-creep. |
| `## Testing Decisions` | Regression test placement, coverage strategy. |

## N/A sections (omit)

- `## Solution` — the slice IS the solution.
- `## User Stories` — replaced by the implicit "restore expected behavior" story.
- `## Risks of Not Doing This` — implicit (a real bug already filed).

## Front-matter shape

```
<!-- stenswf:v1
type: bug-brief
class: bug-brief
prd_base_sha: <BASE>
# affects_prd: <N>      # optional, see below
-->
```

### `affects_prd`

Optional. Set when the bug was discovered against an open feature
PRD's scope. Informational only — does **not** gate `review` or
`apply` in v1. Future versions may surface it in PRD-mode capstone
review reports as "bugs filed against this PRD."

**bug-brief never gets a `prd_ref`.** It is a top-level artifact, not
a child of a feature PRD.

## Lifecycle

1. `/stenswf:triage-issue <bug-N>` creates the bug-brief and a single
   child slice. Default fan-out is 1; multi-slice fan-out is gated
   (see `triage-issue` Phase 5).
2. The child slice references the bug-brief via `prd_ref:`,
   `conventions_source: bug-brief#<N>`, and `bug_ref: <bug-N>`.
3. `/stenswf:plan-light <slice>` (or `plan` if heavy) treats the
   bug-brief as the PRD for purposes of conventions extraction.
4. `/stenswf:review <bug-brief-N>` and `/stenswf:apply <bug-brief-N>`
   run **slice-mode-on-children**, not capstone. See
   [mode-detection.md](mode-detection.md).

## Local state

`triage-issue` seeds `.stenswf/<bug-brief-N>/` identically to a PRD:

- `manifest.json` with `"kind": "bug-brief"` and `"slices": []` (filled
  on slice creation).
- `concept.md` (the bug-brief body, captured for drift detection).
- `decisions.md` seeded with the root-cause as entry D1 (category
  `arch`) plus any introduced conventions as `decision`-category
  entries.

The base SHA convention mirrors PRD: `prd_base_sha` in front-matter,
no remote tag.

## Why bug-brief is not just `type: PRD`

- PRD-mode `review` is a 5-axis architectural capstone — overkill for
  a single defect fix.
- PRD-mode gating ("refuses while any slice is open") still applies,
  but the *output* is slice-mode-on-children, not capstone synthesis.
- Keeping the type distinct preserves PRD-mode capstone semantics for
  feature deliveries (its original purpose) without diluting it with
  every accepted bug.
