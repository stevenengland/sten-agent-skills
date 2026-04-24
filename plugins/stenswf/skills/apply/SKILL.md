---
name: apply
description: Apply a review — slice-mode (interactive per-suggestion) or PRD-mode
  (themed cleanup PR from local `<prd-review>` findings, mirrored onto the PR).
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs the interactive loop, YOLO-mode summaries, and reasoning.
Commit messages, PR bodies, and mirrored PR comments are full-prose
artifacts (already excluded by `brevity`'s Scope section).

---

## Mode Detection

Mode is detected from the issue body's `## Type` marker (not labels).

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
TYPE=$(awk '/^## Type/,/^## /' /tmp/slice-$ARGUMENTS.md \
  | sed '$d' | tail -n +3 | head -1 | tr -d '[:space:]')
```

- `$TYPE == "PRD"` → **PRD-mode**.
- `$TYPE` starts with `slice` → **Slice-mode**.
- Fallback: `.stenswf/$ARGUMENTS/manifest.json:.kind`.

**Announce the detected mode** as your first line of output.

## Prerequisites

- Confirm the review artifact exists on disk:

  - Slice-mode: `.stenswf/$ARGUMENTS/review/slice.md`.
  - PRD-mode: `.stenswf/$ARGUMENTS/review/prd-review.xml`.

  If missing, stop: `Run /stenswf:review $ARGUMENTS first.`

- Drift check (same contract as `ship`): if issue body hash differs
  from `manifest.json:concept_sha256`, present the re-plan / continue /
  abort menu.

- Initialise or load `.stenswf/$ARGUMENTS/apply-state.json`. Both modes
  share one schema; only the entry-ID prefix differs. Slice-mode uses
  `S<n>` (suggestion index from `review/slice.md`); PRD-mode uses `F<n>`
  (finding IDs from `review/prd-review.xml`).

  ```json
  {
    "mode": "slice",
    "entries": {
      "S1": {"status": "pending", "commit_sha": null, "reason": null},
      "S2": {"status": "pending", "commit_sha": null, "reason": null}
    }
  }
  ```

  `status` values: `pending | approved | applied | skipped`.
  `commit_sha` is set when a change lands; `reason` is set when skipped.
  Do NOT use the legacy `findings` key or bare `S<n>: applied:<sha>`
  shorthand — both are superseded.

  On init, set `mode` to the detected mode (`"slice"` or `"prd"`) and
  pre-populate `entries` by enumerating suggestion IDs from
  `review/slice.md` (slice-mode) or finding IDs from
  `review/prd-review.xml` (PRD-mode), each with
  `{"status":"pending","commit_sha":null,"reason":null}`. If the file
  already exists from a previous run, load it and resume — do not
  overwrite applied/skipped entries.

---

# Slice-mode

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

If an applied suggestion contradicts an active entry in
`.stenswf/$ARGUMENTS/decisions.md`, append a superseding entry (same
category, source `apply`) and strikethrough the old header \u2014
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

---

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

4. Update `apply-state.json` for each finding (unified schema —
   `entries.F<n>`, same shape as slice-mode):

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

**Before branching, stage the committed decisions excerpt.** PRD-mode
produces `docs/stenswf/decisions/prd-$ARGUMENTS.md` — the curated,
team-visible library of durable decisions from this PRD — and stages
it as part of the cleanup PR. Silent; no user prompt.

```bash
mkdir -p docs/stenswf/decisions
EXCERPT="docs/stenswf/decisions/prd-$ARGUMENTS.md"
TITLE=$(gh issue view $ARGUMENTS --json title -q .title)
DATE=$(date -u +%Y-%m-%d)

# Gather closed slices of this PRD
SLICES=$(gh issue list --state closed \
  --search "in:body \"Parent PRD\" \"#$ARGUMENTS\"" \
  --json number -q '.[].number')

# Extract ACTIVE arch/decision entries with at least one file-path Ref
# from one anchor. Active = header `### D<n> ` (strikethrough `~~`
# won't match). Entries are bounded by the next `### ` header or EOF.
curate_anchor() {
  awk '
    function flush() {
      if (have && (cat=="arch" || cat=="decision") && hasref) print block
      block=""; cat=""; hasref=0; have=0
    }
    /^### / {
      flush()
      if ($0 ~ /^### D[0-9]+ /) { block=$0 "\n"; have=1 }
      next
    }
    have {
      block = block $0 "\n"
      if ($0 ~ /^- \*\*Category:\*\* (arch|decision)/) {
        cat=$0; sub(/.*Category:\*\* */,"",cat)
      }
      if ($0 ~ /^- \*\*Refs:\*\*.*\//) hasref=1
    }
    END { flush() }
  ' "$1"
}

{
  printf '# Decisions — PRD #%s: %s\n\n' "$ARGUMENTS" "$TITLE"
  printf '*Curated from slice anchors on %s.*\n\n' "$DATE"

  # PRD's own anchor (live or archived)
  for SRC in ".stenswf/$ARGUMENTS/decisions.md" \
             $(ls -1 .stenswf/.archive/$ARGUMENTS-*/decisions.md 2>/dev/null); do
    [ -s "$SRC" ] && curate_anchor "$SRC"
  done

  # Per-slice anchors
  for S in $SLICES; do
    SRC=".stenswf/$S/decisions.md"
    [ -s "$SRC" ] || SRC=$(ls -1 .stenswf/.archive/$S-*/decisions.md 2>/dev/null | head -1)
    [ -n "$SRC" ] && [ -s "$SRC" ] || continue
    printf '\n<!-- from slice #%s -->\n\n' "$S"
    curate_anchor "$SRC"
  done
} > "$EXCERPT"
```

Curate-then-stage; the file is included in the cleanup PR so team
review sees durable decisions alongside the code. See [Decision Anchor
Contract](../../README.md#decision-anchor-contract) for the curation
filter (active ∩ {arch, decision} ∩ has file-path Refs).

Commit the excerpt as its own commit on top of the cleanup branch:

```bash
if [ -s "$EXCERPT" ]; then
  git add "$EXCERPT"
  git commit -m "docs(stenswf): curated decisions for PRD #$ARGUMENTS"
fi
```

If `$EXCERPT` ends up empty (no qualifying entries — unusual for a
PRD), skip the commit; remove the file so no zero-content artifact
leaks into the PR:

```bash
[ -s "$EXCERPT" ] || rm -f "$EXCERPT"
```

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
  comment (Q5a — local authoritative + PR mirror for team visibility):

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
