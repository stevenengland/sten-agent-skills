# Slice-mode — interactive per-suggestion apply

**Ceremony invariant (TDD-as-lens).** This mode MUST NOT (a)
instruct skipping tests for ACs annotated `(behavior)`, (b) remove
`tdd` from any SKILLS TO LOAD list, (c) accept `manual check` or
"rely on existing suite" as completion evidence for a `(behavior)`
AC, or (d) emit guidance that contradicts `tdd/SKILL.md`. Detection
of behavior change is the gate; loading `tdd` is the lens; whether
to write a test follows from the AC tag, not from this skill. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

Work through `.stenswf/$ARGUMENTS/review/slice.md`.

## YOLO Mode

If the user says **YOLO**:

- Skip interactive questions.
- Self-assess every suggestion. Implement only those with meaningful value.
- Proceed directly to Phase 2.
- Show a brief summary:

  Implementing:
  - #N: one-line reason

  Skipped:
  - #K: one-line reason

## Phase 1 — Evaluation

For each numbered suggestion:

1. Assess independently whether it is a good idea.
2. If worth doing, ask:
   _"Suggestion #N: [one-line summary] — implement this?"_
3. Wait for yes/no.
4. Track approvals in `apply-state.json` under `entries.S<n>`:

   ```bash
   jq --arg id "S$N" --arg status "approved" \
     '.entries[$id] = {"status":$status,"commit_sha":null,"reason":null}' \
     .stenswf/$ARGUMENTS/apply-state.json > /tmp/as.json \
     && mv /tmp/as.json .stenswf/$ARGUMENTS/apply-state.json
   ```

   Use `status: "skipped"` with a `reason` for declined suggestions.

Do not implement anything during this phase.

_(Skipped entirely in YOLO mode.)_

## Phase 2 — Implementation

Load `tdd`, `clean-code`, `lint-escape` before any edits.

Implement all approved suggestions in a single pass.

- For every change touching a `(behavior)` AC, follow `tdd` RED-first.
- For `(structural)` changes, run the existing suite and MUST NOT
  delete tests covering behavior.
- Apply `clean-code`.
- Keep changes focused.

If the review artifact contains an AC coverage matrix, any approved
`not covered` / `partially covered` row must be addressed. Re-check
the matrix after; if still uncovered, stop and report. Log
`contract_violation`.

If an applied suggestion contradicts an active entry in
`.stenswf/$ARGUMENTS/decisions.md`, append a superseding entry (same
category, source `apply`) and strikethrough the old header per
[../../references/decision-anchor-link.md](../../references/decision-anchor-link.md).

## Phase 3 — Wrap-up (Slice-mode)

- Update the issue description / add a brief comment reflecting what
  changed and why (referencing suggestion numbers).
- Ask the user to confirm the final review is complete.
- After confirmation: craft a **single conventional commit** for the
  review-fix delivery (does NOT squash prior `ship`/`ship-light`
  commits — this is one additional commit on top):

  ```
  <type>(<scope>): <imperative summary, lower case, no period, ≤72 chars>

  <body paragraph — omit if self-explanatory>

  Refs: #$ARGUMENTS
  ```

  `type`: `feat|fix|refactor|perf|docs|test|chore|build|ci|style|revert`.

- Push the branch and close the issue. No labels applied.

Emit the feedback-log boundary ping.
