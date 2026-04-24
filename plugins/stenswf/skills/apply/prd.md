# PRD-mode — cleanup PR from capstone findings

## Short-circuit: zero findings

Parse `<counts>` from the XML:

```bash
awk '/<counts>/,/<\/counts>/' .stenswf/$ARGUMENTS/review/prd-review.xml
```

If all counts are zero, finalize without a branch or PR:

1. Post a short comment on the PRD: `No cleanup needed — capstone review returned zero findings.`
2. Close the PRD issue (`gh issue close $ARGUMENTS`).
3. Archive the local tree:
   ```bash
   DATE=$(date +%Y-%m-%d)
   mkdir -p .stenswf/.archive
   mv ".stenswf/$ARGUMENTS" ".stenswf/.archive/$ARGUMENTS-$DATE"
   ```
4. Tell the user no cleanup PR was opened.

## Phase 1 — Extract and group findings

Extract findings per axis:

```bash
for axis in alignment scope architectural-coherence test-strategy ops-readiness; do
  awk "/<axis name=\"$axis\">/,/<\/axis>/" \
    .stenswf/$ARGUMENTS/review/prd-review.xml
done
```

Parse each `<finding>`: id, severity, axis, what, why, evidence.

**Coverage matrix (if present).** If `<prd-review>` contains
`<coverage-matrix>`, every row with `status="not covered"` or
`status="partially covered"` is a first-class finding to address,
even if no matching `<finding>` was emitted by review. Treat these
rows as implicit findings with ID `USn` (from `row id="..."`) and
group them under the `alignment` axis in the plan below. After
implementation (Phase 2), re-read the PRD body's user stories / ACs
and confirm each previously-uncovered row now has code addressing it;
if any remain `not covered`, stop and report.

**Group by axis.** Each axis with ≥1 finding → one commit. Within an
axis, sub-commits OK for disjoint areas; keep theming obvious.

Present the grouping (YOLO skips the question):

> I'll produce <N> themed commits:
> - alignment: F1, F2 (2 findings)
> - architectural-coherence: F5, F6, F7 (3 findings)
> - test-strategy: F9 (1 finding)
>
> Skipping: F3 (low severity, out of scope), F8 (already addressed).
> Proceed? (y/N)

Wait unless YOLO.

## Phase 2 — Branch and implement

```bash
git fetch origin
git checkout -b "prd/$ARGUMENTS-cleanup" origin/main
BASE_SHA=$(git rev-parse HEAD)
```

For each approved axis group (severity order: critical → low):

1. Implement all findings in the group. TDD where it fits. `clean-code`,
   `lint-escape` as required.
2. Run tests. All must pass.
3. Commit with a themed conventional message:

   ```
   refactor(<axis-or-scope>): address <axis> findings from PRD #$ARGUMENTS

   <one paragraph summary>

   Addresses: F1, F2
   Refs: #$ARGUMENTS
   ```

   Types by axis: `test(...)` for test-strategy, `refactor(...)` for
   architectural-coherence, `fix(...)` for alignment bugs, `chore(ops):`
   or `feat(ops):` for ops-readiness.

4. Update `apply-state.json` for each finding (`entries.F<n>`):

   ```bash
   jq --arg id "F1" --arg sha "$(git rev-parse HEAD)" \
     '.entries[$id] = {"status":"applied","commit_sha":$sha,"reason":null}' \
     .stenswf/$ARGUMENTS/apply-state.json > /tmp/as.json \
     && mv /tmp/as.json .stenswf/$ARGUMENTS/apply-state.json
   ```

5. Update `BASE_SHA = HEAD_SHA`.

If any group cannot complete, post a `FINDING_BLOCKER` comment on the
PRD and stop.

## Phase 3 — Ship the cleanup PR

**Before opening the PR, stage the committed decisions excerpt.**
Execute the full curation procedure in
[`decisions-excerpt.md`](decisions-excerpt.md) now. It produces and
stages (or removes, if empty) `docs/stenswf/decisions/prd-$ARGUMENTS.md`
on the current `prd/$ARGUMENTS-cleanup` branch.

Now reuse the `ship` skill's Phase 4 sub-procedure (PR, CI loop, merge
wait) and Phase 5 (wrap-up + archive) with these substitutions:

- **Issue number:** `$ARGUMENTS` (the PRD).
- **Branch:** `prd/$ARGUMENTS-cleanup`.
- **PR title:** `PRD #$ARGUMENTS cleanup — capstone findings`.
- **PR body:**
  ```
  Addresses capstone findings from the local `<prd-review>`.
  Includes the curated decisions excerpt at
  `docs/stenswf/decisions/prd-$ARGUMENTS.md` (committed as
  `docs(stenswf): curated decisions for PRD #$ARGUMENTS`).

  Finding IDs addressed: F1, F2, F5, F6, F7, F9
  Finding IDs skipped (with reason):
    - F3: low severity, out of scope
    - F8: already addressed in slice #<N>

  Closes #$ARGUMENTS (capstone cleanup).
  ```
- **After PR is opened, mirror the `<prd-review>` XML onto the PR** as a
  comment (local authoritative + PR mirror for team visibility):

  ```bash
  gh pr comment <pr-num> --body-file .stenswf/$ARGUMENTS/review/prd-review.xml
  ```

- **On merge**: archive the PRD tree, same as `ship` Phase 5:

  ```bash
  DATE=$(date +%Y-%m-%d)
  mv ".stenswf/$ARGUMENTS" ".stenswf/.archive/$ARGUMENTS-$DATE"
  ```

  Post wrap-up comment on the PRD issue listing themed commits and
  finding IDs addressed. No labels applied.

## Idempotence

Re-running `apply` after a partial cleanup:

- `review` refreshes the `<prd-review>` (delta review) — re-extract
  findings.
- `apply-state.json` already records which findings are `applied` /
  `skipped` — skip those.
- The `prd/$ARGUMENTS-cleanup` branch may already exist; rebase on
  current main and add commits for new findings. Do not amend prior
  cleanup commits.
