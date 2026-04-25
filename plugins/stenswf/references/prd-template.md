# PRD body template

Used by `prd-from-grill-me` at Step 5. Substitute `<PRD_BASE>` with the
actual SHA. Issue number `<N>` is assigned on `gh issue create` and
written back into the front-matter block after creation.

```markdown
<!-- stenswf:v1
type: PRD
class: capability
prd_base_sha: <PRD_BASE>
-->

## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

Numbered list. Each in the format:

1. As an <actor>, I want a <feature>, so that <benefit>

Cover all aspects of the feature extensively.

## Implementation Decisions

- Modules to build/modify
- Interfaces being modified
- Technical clarifications
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets — they go stale fast.

## Conventions

Bikeshed decisions resolved upfront so individual slices do not
re-litigate them. `prd-to-issues` copies this section verbatim into
every slice's body as `## Conventions (from PRD)`. Plans and ship
dispatches read it as hard spec.

- One bullet per decision. Concrete and terse.
- If nothing qualifies, write exactly:
  `None — slice-local decisions only.`

## Out of Scope

Explicitly list what this PRD does NOT cover. Prevents slice scope-creep.

## Testing Decisions

Test strategy at PRD scope (integration boundaries, happy-path
coverage targets). Not test case enumeration.

## Invariants Preserved (refactor / bug-brief only)

Optional. Required when `class: refactor` or `class: bug-brief`.
List behaviors that MUST stay unchanged (e.g. "public API stable",
"all green tests stay green", "persisted state shape unchanged").

## Risks of Not Doing This (refactor only)

Optional. For `class: refactor` PRDs that lack user-stories, document
what continues to break / drift if this work is deferred.
```

## Class shapes which sections carry the load

| Class | Required | N/A or de-emphasised |
|---|---|---|
| `capability`  | Problem, Solution, User Stories, Implementation Decisions, Conventions, Out of Scope, Testing Decisions | Invariants Preserved, Risks of Not Doing This |
| `integration` | Problem, Solution, Implementation Decisions, Conventions, Out of Scope, Testing Decisions | (User Stories optional) |
| `migration`   | Problem, Implementation Decisions, Invariants Preserved, Conventions, Out of Scope, Testing Decisions | (Solution may be a sequenced rollout) |
| `refactor`    | Problem, Implementation Decisions, Invariants Preserved, Risks of Not Doing This, Conventions, Out of Scope, Testing Decisions | User Stories (replaced by Invariants) |
| `bug-brief`   | Problem (= report summary), Root Cause, Implementation Decisions, Invariants Preserved, Conventions, Out of Scope, Testing Decisions | User Stories, Solution (the slice IS the solution) |

For `class: bug-brief`, see also
[bug-brief-class.md](bug-brief-class.md) for the section-by-section
spec, the `## Root Cause` block, and `affects_prd` semantics.

## Post-create step

The `prd_base_sha` front-matter field is the durable anchor for
`review` and `apply` in PRD-mode (and bug-brief-mode). No remote tag is
created.
