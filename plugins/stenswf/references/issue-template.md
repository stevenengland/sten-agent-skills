# Slice issue body template

Used by `prd-to-issues` at Step 6. Emits front-matter + body. Schema:
[front-matter-schema.md](front-matter-schema.md).

```markdown
<!-- stenswf:v1
type: slice — AFK
lite_eligible: true
conventions_source: prd#<PRD-N>
prd_ref: <PRD-N>
# bug_ref: <ORIGINAL-BUG-N>   # uncomment for bug-brief-derived slices
-->

## Parent PRD

#<prd-issue-number>

(For bug-brief-derived slices, the parent is the bug-brief issue
number; the original raw bug report is referenced in front-matter
as `bug_ref`.)

## What to build

Concise description of the vertical slice. End-to-end behavior, not
layer-by-layer implementation. Reference PRD sections rather than
duplicating content.

## Conventions (from PRD)

Copy the parent PRD's or bug-brief's `## Conventions` section verbatim
(contents only — do not repeat the heading). If the parent says
`None — slice-local decisions only.`, copy that single line.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## User stories addressed

- User story 3
- User story 7

## Files (hint)

Optional. Best-effort file list from Step 2 exploration. Omit section
if exploration produced nothing reliable.

- Create: `path/to/new.py` — <one-line responsibility>
- Modify: `path/to/existing.py` — <what changes>
- Test:   `tests/path/to/test_file.py` — <what it covers>

## Invariants preserved

Optional. **Required** when parent has `class: refactor` or
`class: bug-brief`. List behaviors that MUST stay unchanged (e.g.
"public API stable", "existing green tests stay green"). Lifted
verbatim from the parent's `## Invariants Preserved` section.
```

## Front-matter rules

- `type` — exactly one of: `slice — HITL` | `slice — AFK` | `slice — spike`
- `lite_eligible` — `true` (default when borderline) or `false`
- When `lite_eligible: false`, add:
  ```
  disqualifier: files>15   # or: cross-module | schema-migration | arch-unknown | hitl-cat3
  ```
- `conventions_source` — `prd#<N>` if inherited, `none` if slice-local only
- `prd_ref` — parent PRD issue number (int)
- `blocked_by` (optional) — space-separated issue numbers

## Blocked-by

Encode blockers in the front-matter, NOT as a body section:

```
blocked_by: 123 456
```

The old `## Blocked by` section is removed. Parsers read the
front-matter directly.
