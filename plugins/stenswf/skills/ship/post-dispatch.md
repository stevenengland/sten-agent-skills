# ship — Phases 2–5 (post-dispatch)

Runs after Phase 1 reports `all done`. All phases read
`manifest.json` as the source of truth for `base_sha`, task SHAs, and
PR state.

## Phase 2 — Refactor Pass (fresh session)

Runs in a **fresh session**, not the orchestrator parent. If your
harness cannot spawn one, `/clear` (or equivalent) and reload manually.

**Inputs:**

```bash
# Phase 1b mutates the orchestrator's BASE_SHA per task; the original
# slice base lives in the manifest. Always read it back here.
BASE_SHA=$(jq -r .base_sha .stenswf/$ARGUMENTS/manifest.json)
git diff "$BASE_SHA..HEAD" > /tmp/ship-$ARGUMENTS-refactor-diff.patch
wc -l /tmp/ship-$ARGUMENTS-refactor-diff.patch   # if huge, read ranged slices
cat .stenswf/$ARGUMENTS/file-structure.md
cat .stenswf/$ARGUMENTS/acceptance-criteria.md
```

Read those plus `CLAUDE.md` hard lines. Nothing else.

**Commit sequencing.** Slice commits stay atomic. Refactor pass is one
additional commit on top. Do not squash or amend.

Review every touched file against:

- `CLAUDE.md` hard constraints.
- Repo coding guidelines.
- `clean-code`, SOLID, DRY, KISS.

Focused refactor: eliminate TDD-introduced duplication, clarify naming
where beneficial. No new scope.

Run lint + tests. Apply `lint-escape` if needed.

```bash
git add <changed paths>
git commit -m "refactor(<scope>): post-implementation refactor for #$ARGUMENTS"
```

Mark manifest:

```bash
jq --arg sha "$(git rev-parse HEAD)" \
  '.refactor_pass.status="done" | .refactor_pass.sha=$sha' \
  .stenswf/$ARGUMENTS/manifest.json > /tmp/m.json \
  && mv /tmp/m.json .stenswf/$ARGUMENTS/manifest.json
```

## Phase 3 — Review Step

If `.stenswf/$ARGUMENTS/review-step.md` is missing (entry path was
`plan-light → ship` rather than heavy `plan`), synthesise a minimal
one from the issue body's `Acceptance criteria` section and any
`plan-light.json` hints on disk:

```bash
RS=".stenswf/$ARGUMENTS/review-step.md"
if [ ! -s "$RS" ]; then
  gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
  {
    echo "<!-- synthesized by ship (plan-light pivot) -->"
    echo "# Review Step (synthesized)"
    echo
    echo "## Architectural Invariants"
    echo "_None declared (lite path). Rely on existing test suite._"
    echo
    echo "## Recommended Regression Tests"
    extract_section 'Acceptance criteria' /tmp/slice-$ARGUMENTS.md \
      | sed -n 's/^- \[.\] /- /p'
    echo
    echo "## Self-report Checklist"
    echo "- [ ] All AC boxes mapped to a test or manual check."
    echo "- [ ] No new invariants introduced without a test."
  } > "$RS"
  bash plugins/stenswf/scripts/log-issue.sh missing_artifact \
    "review-step.md synthesised on plan-light pivot" "$RS"
fi
```

(See `extract_section` in
[../../references/extractors.md](../../references/extractors.md).)

Then work through `$RS`:

- **Architectural Invariants:** run the invariant test file. All pass.
- **Recommended Regression Tests:** confirm each exists, or note
  justified absence in PR body.
- **Self-report Checklist:** execute each item.

```bash
jq --arg sha "$(git rev-parse HEAD)" \
  '.review_step.status="done" | .review_step.sha=$sha' \
  .stenswf/$ARGUMENTS/manifest.json > /tmp/m.json \
  && mv /tmp/m.json .stenswf/$ARGUMENTS/manifest.json
```

## Phase 4 — PR, CI Loop, Merge Wait

Run the shared PR+CI+merge procedure with `CI_MAX_CYCLES=3` and
`WAIT_FOR_MERGE=yes`. Full recipe:
[../../references/pr-ci-merge.md](../../references/pr-ci-merge.md).

PR body must include:
- One-sentence summary.
- `Closes #$ARGUMENTS`.
- Summary of any `lint-escape` actions, with rationale.
- Any justified Review-Step absences.

## Phase 5 — Wrap-up + archive

Post a single wrap-up comment on the issue:

- Brief summary of approach.
- Task list by T-ID and commit SHA (from manifest).
- Any `lint-escape` actions taken.
- Any justified review-step absences.

Archive the local plan tree:

```bash
DATE=$(date +%Y-%m-%d)
mkdir -p .stenswf/.archive
mv ".stenswf/$ARGUMENTS" ".stenswf/.archive/$ARGUMENTS-$DATE"
```

If this was the last open slice of a parent PRD:

```bash
PARENT=$(jq -r .prd ".stenswf/.archive/$ARGUMENTS-$DATE/manifest.json")
OPEN=$(gh issue list --state open \
  --search "in:body \"Parent PRD\" \"#$PARENT\"" --json number -q 'length')
if [ "$OPEN" = "0" ]; then
  echo "All slices of PRD #$PARENT shipped. Run /stenswf:review $PARENT."
fi
```

Emit the feedback boundary ping per
[../../references/feedback-session.md](../../references/feedback-session.md).

Tell the user the issue shipped and where the archive lives.
