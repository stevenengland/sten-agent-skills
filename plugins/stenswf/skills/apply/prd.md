# PRD-mode — cleanup PR from capstone findings

**Ceremony invariant (TDD-as-lens).** This mode MUST NOT (a)
instruct skipping tests for ACs annotated `(behavior)`, (b) remove
`tdd` from any SKILLS TO LOAD list, (c) accept `manual check` or
"rely on existing suite" as completion evidence for a `(behavior)`
AC, or (d) emit guidance that contradicts `tdd/SKILL.md`. Detection
of behavior change is the gate; loading `tdd` is the lens; whether
to write a test follows from the AC tag, not from this skill. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

## Step 0 — Strict gating (mirrors review/prd.md)

Refuse to run while any slice of this PRD is still open. The capstone
review already enforces this gate, but `apply` may be invoked directly
on an old PRD whose children have since drifted back to open
(reverted, reopened, or new follow-up slices linked to the same PRD):

```bash
OPEN=$(gh issue list --state open \
  --search "in:body \"Parent PRD\" \"#$ARGUMENTS\"" \
  --json number,title)

if [ "$(printf '%s' "$OPEN" | jq 'length')" -gt 0 ]; then
  echo "PRD-apply blocked: slices still open:" >&2
  printf '%s' "$OPEN" | jq -r '.[] | "  #\(.number) \(.title)"' >&2
  echo "Ship them first or close abandoned ones with: gh issue close <N> --reason \"not planned\"" >&2
  exit 1
fi
```

## Short-circuit: zero findings

Parse `<counts>` from the XML:

```bash
awk '/<counts>/,/<\/counts>/' .stenswf/$ARGUMENTS/review/prd-review.xml
```

If all zero, finalize without a branch or PR:

1. Post: `No cleanup needed — capstone review returned zero findings.`
2. Close the PRD issue (`gh issue close $ARGUMENTS`).
3. Archive:
   ```bash
   DATE=$(date +%Y-%m-%d)
   mkdir -p .stenswf/.archive
   mv ".stenswf/$ARGUMENTS" ".stenswf/.archive/$ARGUMENTS-$DATE"
   ```
4. Tell the user no cleanup PR was opened.

## Phase 1 — Extract and group findings

Per axis:

```bash
for axis in alignment scope architectural-coherence test-strategy ops-readiness; do
  awk "/<axis name=\"$axis\">/,/<\/axis>/" \
    .stenswf/$ARGUMENTS/review/prd-review.xml
done
```

Parse each `<finding>`: id, severity, axis, what, why, evidence.

**Coverage matrix.** `<coverage-matrix>` rows with
`status="not covered"` or `status="partially covered"` are first-class
findings even without matching `<finding>` elements. Treat as implicit
findings with ID `USn`, group under `alignment`. After implementation,
re-read PRD user stories/ACs and confirm coverage; if any remain
`not covered`, stop and report. Log `contract_violation`.

**Group by axis.** Each axis with ≥1 finding → one commit. Sub-commits
OK for disjoint areas within an axis.

Present the grouping (skipped in YOLO):

> I'll produce <N> themed commits:
> - alignment: F1, F2 (2 findings)
> - architectural-coherence: F5, F6, F7 (3 findings)
> - test-strategy: F9 (1 finding)
>
> Skipping: F3 (low severity, out of scope), F8 (already addressed).
> Proceed? (y/N)

## Phase 2 — Branch and implement

```bash
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git fetch origin "$DEFAULT"
git checkout -b "prd/$ARGUMENTS-cleanup" "origin/$DEFAULT"
BASE_SHA=$(git rev-parse HEAD)
```

For each approved axis group (severity order: critical → low):

1. Implement all findings. Load `tdd`, `clean-code`, `lint-escape`
   first. For every change touching a `(behavior)` AC, follow `tdd`
   RED-first; for `(structural)` ACs, run the existing suite and MUST
   NOT delete tests covering behavior. `lint-escape` as required.
2. Run tests. All must pass.
3. Commit:

   ```
   refactor(<axis-or-scope>): address <axis> findings from PRD #$ARGUMENTS

   <one paragraph summary>

   Addresses: F1, F2
   Refs: #$ARGUMENTS
   ```

   Types by axis: `test(...)`, `refactor(...)`, `fix(...)`,
   `chore(ops):`, `feat(ops):`.

4. Update `apply-state.json`. **Resume-safe write:** abort if the row
   was already `applied` or `skipped` (the resume contract from
   [SKILL.md](SKILL.md) forbids overwriting terminal states):

   ```bash
   ID="F1"
   SHA=$(git rev-parse HEAD)
   STATE=".stenswf/$ARGUMENTS/apply-state.json"
   CUR=$(jq -r --arg id "$ID" '.entries[$id].status // "missing"' "$STATE")
   case "$CUR" in
     applied|skipped)
       echo "refusing to overwrite $ID (status=$CUR); inspect $STATE manually" >&2
       bash plugins/stenswf/scripts/log-issue.sh contract_violation \
         "apply-state overwrite refused for $ID" "current=$CUR target=applied"
       exit 1
       ;;
     missing)
       echo "$ID not found in $STATE (init step skipped?)" >&2
       exit 1
       ;;
   esac
   jq --arg id "$ID" --arg sha "$SHA" \
     '.entries[$id] = {"status":"applied","commit_sha":$sha,"reason":null}' \
     "$STATE" > /tmp/as.json && mv /tmp/as.json "$STATE"
   ```

5. Update `BASE_SHA = HEAD_SHA`.

If any group cannot complete, post `FINDING_BLOCKER` on the PRD and
stop. Log `tool_failure`.

## Phase 3 — Ship the cleanup PR

Stage the committed decisions excerpt first per
[decisions-excerpt.md](decisions-excerpt.md).

Then run the shared PR+CI+merge procedure with `CI_MAX_CYCLES=3` and
`WAIT_FOR_MERGE=yes`:
[../../references/pr-ci-merge.md](../../references/pr-ci-merge.md).

With these substitutions:

- **Issue number:** `$ARGUMENTS` (PRD).
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
- **After PR opened, mirror `<prd-review>` XML onto the PR:**

  ```bash
  gh pr comment <pr-num> --body-file .stenswf/$ARGUMENTS/review/prd-review.xml
  ```

- **On merge:** archive the PRD tree, same as `ship` Phase 5. Post
  wrap-up comment listing themed commits and findings addressed. No
  labels.

## Idempotence

Re-running `apply` after a partial cleanup:

- `review` refreshes the `<prd-review>` — re-extract findings.
- `apply-state.json` already records `applied` / `skipped` — skip those.
- Branch may exist; rebase on current default and add commits for new
  findings. Do not amend prior cleanup commits.
