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

## Step 0 — Freshness check

The review artifact carries a `<!-- reviewed-at: <SHA> diff-sha256:
<HASH> -->` trailer (see [../review/slice.md](../review/slice.md)
Output section). Refuse to apply against a working diff that no
longer matches the reviewed diff:

```bash
ART=".stenswf/$ARGUMENTS/review/slice.md"
REVIEWED_SHA=$(grep -oE 'reviewed-at: [0-9a-f]+' "$ART" | awk '{print $2}' | head -1)
REVIEWED_DIFF=$(grep -oE 'diff-sha256: [0-9a-f]+' "$ART" | awk '{print $2}' | head -1)

# Fall back to legacy reviews missing the trailer (one-time leniency).
if [ -z "$REVIEWED_SHA" ] || [ -z "$REVIEWED_DIFF" ]; then
  echo "warn: review artifact predates freshness stamp; proceeding without check" >&2
  bash plugins/stenswf/scripts/log-issue.sh missing_artifact \
    "review/slice.md missing reviewed-at/diff-sha256 trailer" "$ART"
else
  CUR_SHA=$(git rev-parse HEAD)
  CUR_DIFF=$(git diff --staged | sha256sum | cut -d' ' -f1)
  if [ "$REVIEWED_DIFF" != "$CUR_DIFF" ]; then
    echo "review/slice.md is stale (reviewed at $REVIEWED_SHA / $REVIEWED_DIFF; current $CUR_SHA / $CUR_DIFF)" >&2
    echo "Re-run /stenswf:review $ARGUMENTS before applying." >&2
    bash plugins/stenswf/scripts/log-issue.sh contract_violation \
      "slice review artifact stale" "reviewed=$REVIEWED_DIFF current=$CUR_DIFF"
    exit 1
  fi
fi
```

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
4. Track approvals in `apply-state.json` under `entries.S<n>`.
   **Resume-safe write:** never overwrite an entry already in
   `applied` or `skipped` state (the resume contract from
   [SKILL.md](SKILL.md)):

   ```bash
   ID="S$N"
   STATUS="approved"   # or "skipped" with a reason
   STATE=".stenswf/$ARGUMENTS/apply-state.json"
   CUR=$(jq -r --arg id "$ID" '.entries[$id].status // "missing"' "$STATE")
   case "$CUR" in
     applied|skipped)
       echo "refusing to overwrite $ID (status=$CUR); inspect $STATE manually" >&2
       bash plugins/stenswf/scripts/log-issue.sh contract_violation \
         "apply-state overwrite refused for $ID" "current=$CUR target=$STATUS"
       exit 1
       ;;
     missing)
       echo "$ID not found in $STATE (init step skipped?)" >&2
       exit 1
       ;;
   esac
   jq --arg id "$ID" --arg status "$STATUS" \
     '.entries[$id] = {"status":$status,"commit_sha":null,"reason":null}' \
     "$STATE" > /tmp/as.json && mv /tmp/as.json "$STATE"
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

  `apply` slice-mode allowed types per
  [../../references/conventional-commits.md](../../references/conventional-commits.md):
  `feat|fix|refactor|perf|docs|test|chore|build|ci|style|revert`.

- Push the branch and close the issue. No labels applied.

Emit the feedback-log boundary ping.
