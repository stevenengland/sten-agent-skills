# Slice-mode — interactive per-suggestion apply

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
2. If worth doing, ask explicitly:
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

Implement all approved suggestions in a single pass.

- Use TDD where appropriate.
- Apply `clean-code`.
- Keep changes focused.

If the review artifact contains an AC coverage matrix, any
`not covered` / `partially covered` row whose promoted finding is
approved must be addressed in this phase. Re-check the matrix after
implementation; if a previously `not covered` AC is still not covered
by the new diff, stop and report.

If an applied suggestion contradicts an active entry in
`.stenswf/$ARGUMENTS/decisions.md`, append a superseding entry (same
category, source `apply`) and strikethrough the old header —
[contract](../../README.md#decision-anchor-contract). Otherwise no
anchor write is needed.

## Phase 3 — Wrap-up (Slice-mode)

- Update the issue description / add a brief comment reflecting what
  changed and why (referencing suggestion numbers).
- Ask the user to confirm the final review is complete.
- After confirmation: craft a **single conventional commit** covering
  the entire issue's phase-1-through-3 delivery:

  ```
  <type>(<scope>): <imperative summary, lower case, no period, ≤72 chars>

  <body paragraph — omit if self-explanatory>

  Refs: #$ARGUMENTS
  ```

  `type`: `feat|fix|refactor|perf|docs|test|chore|build|ci|style|revert`.

- Push the branch and close the issue. No labels applied.
