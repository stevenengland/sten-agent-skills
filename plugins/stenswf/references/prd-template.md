# PRD body template

Used by `prd-from-grill-me` at Step 5. Substitute `<PRD_BASE>` with the
actual SHA. Issue number `<N>` is assigned on `gh issue create` and
written back into the front-matter block after creation.

```markdown
<!-- stenswf:v1
type: PRD
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
```

## Post-create step

After `gh issue create` returns the issue number `<N>`:

```bash
git tag "prd-<N>-base" "<PRD_BASE>"
git push origin "prd-<N>-base"
```

The tag is the durable anchor for `review` in PRD-mode. The
`prd_base_sha` front-matter field is the redundant pointer.
