# Slice issue body template

Used by `prd-to-issues` at Step 6. Emits front-matter + body. Schema:
[front-matter-schema.md](front-matter-schema.md).

The issue **title** is not part of this body template — the
`<PRD-N>/<ordinal>: <title>` convention and sub-issue linkage live in
`prd-to-issues` Step 6.

```markdown
<!-- stenswf:v1
type: slice — AFK
lite_eligible: true
conventions_source: prd#<PRD-N>
prd_ref: <PRD-N>
# bug_ref: <ORIGINAL-BUG-N>   # uncomment for bug-brief-derived slices
# migration_mode: behavior-preserving   # REQUIRED on slices whose parent has class: migration; values: behavior-preserving | contract-changing
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

Every checkbox MUST carry a tag as its first parenthesised token:
either `(behavior)` or `(structural)`. Untagged ACs are a hard error
and will be rejected by `plan`, `plan-light`, `ship`, and
`ship-light`. See
[behavior-change-signal.md](behavior-change-signal.md).

- [ ] (behavior) Criterion 1 — observable outcome
- [ ] (behavior) Criterion 2 — observable outcome
- [ ] (structural) Criterion 3 — rename / move / reformat only

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

## Judgment-call sections (HITL slices only)

A HITL slice carries exactly one of these, appended **last** so no
extractor above it is perturbed.

**`## Open judgment calls` — required on every `slice — HITL`.** Emitted
by `prd-to-issues` (Step 3) and `triage-issue` (Phase 5.6). One entry
per irreducible call that made the slice HITL:

```markdown
## Open judgment calls

- **<what must be decided, one sentence>** — <why it needs a human>
```

It is the sole input to [hitl-escape-hatch.md](hitl-escape-hatch.md);
the hatch does not reconstruct the list from AC wording. Omit it and the
slice is stranded on the heavy path.

**`## Resolved judgment calls`** replaces it, atomically, once the hatch
runs. Never written by a producer. It is **spec-bearing** — it
participates in the `source_signature` that `plan-light` writes and
`ship-light` recomputes. Shape and write-back rules live in that
reference.

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
- `hitl_resolved` — never emitted here. Added later by
  [hitl-escape-hatch.md](hitl-escape-hatch.md) when a HITL slice's
  judgment calls are resolved. Clears only the HITL blocker, only
  alongside a non-empty `## Resolved judgment calls` section, and
  without rewriting `type` / `lite_eligible` / `disqualifier`.

## Blocked-by

Encode blockers in the front-matter, NOT as a body section:

```
blocked_by: 123 456
```

The old `## Blocked by` section is removed. Parsers read the
front-matter directly.
