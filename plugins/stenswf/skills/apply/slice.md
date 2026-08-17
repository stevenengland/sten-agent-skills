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
  bash ../../scripts/log-issue.sh missing_artifact \
    "review/slice.md missing reviewed-at/diff-sha256 trailer" "$ART"
else
  CUR_SHA=$(git rev-parse HEAD)
  CUR_DIFF=$(git diff --staged | sha256sum | cut -d' ' -f1)
  if [ "$REVIEWED_DIFF" != "$CUR_DIFF" ]; then
    echo "review/slice.md is stale (reviewed at $REVIEWED_SHA / $REVIEWED_DIFF; current $CUR_SHA / $CUR_DIFF)" >&2
    echo "Re-run /stenswf:review $ARGUMENTS before applying." >&2
    bash ../../scripts/log-issue.sh contract_violation \
      "slice review artifact stale" "reviewed=$REVIEWED_DIFF current=$CUR_DIFF"
    exit 1
  fi
fi
```

## YOLO Mode

If the user says **YOLO**:

- Skip interactive questions.
- Run Phase 1 without its approval prompts — self-approve safe, non-rollback
  remedies and still persist every disposition. A rollback keeps its explicit
  approval (PARK when unattended).
- Show a brief summary:

  Implementing:
  - #N: one-line reason

  Skipped:
  - #K: one-line reason

## Phase 1 — Evaluation

For each numbered suggestion:

1. Validate independently per
   [../../references/review-finding-validation.md](../../references/review-finding-validation.md).
2. For a confirmed diagnosis with a safe remedy, show the evidence and ask:
   _"Suggestion #N: implement the proposed remedy?"_ — YOLO self-approves
   unless it is classified `Rollback: yes`, which always goes through the
   shared approval gate.
3. Persist the disposition in `apply-state.json` under `entries.S<n>`.
   **Resume-safe write:** never overwrite an entry already in
   `applied` or `skipped` state (the resume contract from
   [SKILL.md](SKILL.md)):

   ```bash
   ID="S$N"
   STATUS="approved"   # or "skipped" with a reason
   REASON=""           # verification/decline reason when skipped
   STATE=".stenswf/$ARGUMENTS/apply-state.json"
   CUR=$(jq -r --arg id "$ID" '.entries[$id].status // "missing"' "$STATE")
   case "$CUR" in
     applied|skipped)
       echo "refusing to overwrite $ID (status=$CUR); inspect $STATE manually" >&2
       bash ../../scripts/log-issue.sh contract_violation \
         "apply-state overwrite refused for $ID" "current=$CUR target=$STATUS"
       exit 1
       ;;
     missing)
       echo "$ID not found in $STATE (init step skipped?)" >&2
       exit 1
       ;;
   esac
   jq --arg id "$ID" --arg status "$STATUS" --arg reason "$REASON" \
     '.entries[$id] = {
       "status":$status,
       "commit_sha":null,
       "reason":(if $status == "skipped" then $reason else null end)
     }' \
     "$STATE" > /tmp/as.json && mv /tmp/as.json "$STATE"
   ```

   Use `status: "skipped"` with a `reason` for declined, rejected, or
   inconclusive suggestions.

Do not implement anything during this phase.

## Phase 2 — Implementation

Load `tdd`, `clean-code`, `lint-escape` before any edits.

Implement all approved suggestions in a single pass.

- For every change touching a `(behavior)` AC, follow `tdd` RED-first.
- For `(structural)` changes, run the existing suite and MUST NOT
  delete tests covering behavior.
- Apply `clean-code`.
- Keep changes focused.
- **Ponytail guard (anti-balloon).** Before applying a suggestion,
  check it does not grow into an unrequested abstraction — prefer the
  one-line / stdlib / native form per
  [../../references/ponytail-pass.md](../../references/ponytail-pass.md).
  Apply the suggestion's intent, not a heavier version of it.
- **Local-ID hygiene.** Never write `S<n>`/`AC<n>`/`F<n>`/`D<n>` codes into
  source, comments, test names, or commit subjects — describe the change in
  plain language. See
  [../../references/local-id-hygiene.md](../../references/local-id-hygiene.md).

If the review artifact contains an AC coverage matrix, any approved
`not covered` / `partially covered` row must be addressed. Re-check
the matrix after; if still uncovered, stop and report. Log
`contract_violation`.

If an applied suggestion contradicts an active entry in
`.stenswf/$ARGUMENTS/decisions.md`, overriding that recorded decision is a
**heavy decision** — ASK the user (alternatives + recommendation) when
available, PARK when unattended, per
[../../references/decision-escalation.md](../../references/decision-escalation.md).
On sign-off, append a superseding entry (same category, source `apply`) and
strikethrough the old header per
[../../references/decision-anchor-link.md](../../references/decision-anchor-link.md).

## Phase 3 — Wrap-up (Slice-mode)

- Add a brief issue comment reflecting what changed and why
  (referencing suggestion numbers). Comment, not issue-body edit: the
  body is hashed whole into `manifest.json:concept_sha256`, so editing
  it makes every later `ship` / `plan --resume` / `review` / `apply`
  raise a false drift prompt.
- Ask the user to confirm the final review is complete.
- After confirmation: craft a **single conventional commit** for the
  review-fix delivery (does NOT squash prior `ship`/`ship-light`
  commits — this is one additional commit on top):

  ```bash
  DEC=$(bash ../../scripts/publish-decisions.sh trailer "$ARGUMENTS")
  git commit -m "<type>(<scope>): <imperative summary, ≤72 chars>" \
             -m "$(printf 'Refs: #%s\n%s' "$ARGUMENTS" "$DEC")"
  ```

  `apply` slice-mode allowed types per
  [../../references/conventional-commits.md](../../references/conventional-commits.md):
  `feat|fix|refactor|perf|docs|test|chore|build|ci|style|revert`.

  Commit **after** the Phase 2 anchor writes, so this commit carries the
  superseding entry — the trailer names what it retired
  (`supersedes #$ARGUMENTS/D<n>`), while the commit that introduced the
  original keeps its own trailer. The log is a journal of what was believed
  when, not a current-state view; that is what the two upserts below are for.

- **Refresh the published decisions.** This mode is what strikes entries
  through (Phase 2 override), so a block published at PR-create time now
  contradicts the code that shipped. Re-render it — the upsert replaces
  the existing block in place and preserves everything around it:

  ```bash
  source ../../scripts/pr-threads.sh
  # No-arg resolve_pr = the current branch's PR, which is where slice-mode
  # already is. Never pass $ARGUMENTS: resolve_pr returns a numeric argument
  # verbatim, so it would silently address the PR whose number happens to
  # equal the issue number.
  PR=$(resolve_pr) || PR=""
  [ -n "$PR" ] && bash ../../scripts/publish-decisions.sh pr "$ARGUMENTS" "$PR"
  bash ../../scripts/publish-decisions.sh issue "$ARGUMENTS"
  ```

  Both upserts replace their existing block in place, so the superseded
  entry disappears from the PR body and the issue comment rather than
  standing next to its replacement. No PR (slice shipped without one) →
  the comment is the only surface.
- Push the branch and close the issue. No labels applied.

Emit the feedback-log boundary ping.
