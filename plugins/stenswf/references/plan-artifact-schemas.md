# plan — local-tree artifact schemas

Materialized under `.stenswf/$ARGUMENTS/` by `plan` Phase 2.

## Tree

```
.stenswf/$ARGUMENTS/
├── manifest.json
├── concept.md              # verbatim issue body at plan time (drift)
├── stable-prefix.md        # assembled dispatch prefix (cache-friendly)
├── conventions.md          # verbatim from slice body's Conventions section
├── decisions.md            # cross-skill decision anchor (see README)
├── house-rules.md
├── design-summary.md
├── acceptance-criteria.md
├── file-structure.md
├── review-step.md
└── tasks/
    ├── T10.md
    ├── T20.md
    └── T<last>.md          # documentation task (always last)
```

## manifest.json

```json
{
  "issue": $ARGUMENTS,
  "prd": <parent-prd-number>,
  "kind": "slice",
  "slice_type": "HITL|AFK|spike",
  "branch": null,
  "base_sha": null,
  "plan_created_at": "<ISO-8601>",
  "claude_md_sha": "<git log -1 --format=%H -- CLAUDE.md AGENTS.md>",
  "concept_sha256": "<sha256 of /tmp/slice-$ARGUMENTS.md>",
  "section_hashes": {
    "acceptance_criteria": "<sha256>",
    "conventions": "<sha256>",
    "what_to_build": "<sha256>"
  },
  "tasks": [
    {"id": "T10", "name": "<slice name>", "file": "tasks/T10.md",
     "commit_subject": "<type>(<scope>): <subject>",
     "status": "pending", "sha": null}
  ],
  "refactor_pass": {"status": "pending", "sha": null},
  "review_step":   {"status": "pending", "sha": null},
  "pr":            {"status": "pending", "url": null}
}
```

SHA computation: `sha256sum <file> | cut -d' ' -f1`. `branch` +
`base_sha` are filled by `ship` at dispatch time.

## concept.md

Full issue body copied verbatim at plan time. Used by drift detection
(`ship`, `review`, `apply` re-fetch and compare).

## stable-prefix.md

Pasted byte-identical at the start of every subagent dispatch so
prompt caching hits on dispatches 2..N. Assemble once at plan time,
never modify.

```
SKILLS TO LOAD: tdd, clean-code, lint-escape

HARD CONSTRAINTS (from CLAUDE.md — non-negotiable, verbatim, compressed):
<compressed hard-constraints block: untouchable files, forbidden
 suppressions, required tooling, enforced commands>

TEST COMMAND: <exact test command from orientation>
LINT COMMAND: <exact lint/check command from orientation>

HOUSE RULES (from the plan, read before every task):
<paste house-rules.md verbatim>

CONVENTIONS (from parent PRD — hard spec, follow verbatim):
<paste conventions.md verbatim>

REASONING STYLE: Keep internal reasoning terse. No pre-summaries, no
restating the task, no filler. Commit messages, PR bodies, and error
quotes remain verbatim.

CONTEXT HYGIENE: Do not re-read files you already read in this task. If
your harness supports `clear_tool_uses_20250919`, fire it with `keep: 3`
after each green test.

--- (stable prefix ends here; everything above is identical across tasks) ---
```

## conventions.md

Verbatim contents of the slice body's `## Conventions (from PRD)` section.
If it says `None — slice-local decisions only.`, write that single line.

## house-rules.md

```
- Follow `tdd`: one failing test, minimal code, next.
- Follow `clean-code`.
- Follow `conventions.md` verbatim — no alternative names/shapes/layouts. Escalate on conflict.
- DRY, YAGNI. No speculative abstractions. No error handling for impossible cases.
- Use the pre-written commit message at the end of each task verbatim.
- If a task conflicts with the codebase, pause and report — do not re-plan silently.
- One task at a time. No read-ahead.
```

## design-summary.md

3–5 short sentences: key components, interfaces, data/error flow.

## acceptance-criteria.md

Every AC from the issue, verbatim, one bullet each. Each maps to
exactly one task's `Done when` line.

## file-structure.md

```
- Create: `path/to/new_file.py` — <responsibility>
- Modify: `path/to/existing.py` — <what changes>
- Test:   `tests/path/to/test_file.py` — <what it covers>
```

## review-step.md

```
# Slice-level Review Step — #$ARGUMENTS (<one-line title>)

## Architectural Invariants
- [ ] **<Invariant name>.** <What the test asserts. Symbol paths only.>

## Recommended Regression Tests
- [ ] **<Scenario>.** <Setup, action, expected outcome.>

## Self-report Checklist
- [ ] `<lint command>` green.
- [ ] `<test command>` green.
- [ ] Invariants pass.
- [ ] Regression tests exist or absences justified in PR.
- [ ] No stale references to deleted symbols.
```

## decisions.md

Bootstrap with the canonical snippet from
[Decision Anchor Contract](../README.md#decision-anchor-contract).
Append one entry per Design Decision that passes grep-blame + surfaces
test, category `decision`|`arch`, source `plan`.

Inherited PRD stubs (from `prd-to-issues`) stay untouched.

Task bodies: see [plan-task-template.md](plan-task-template.md).
