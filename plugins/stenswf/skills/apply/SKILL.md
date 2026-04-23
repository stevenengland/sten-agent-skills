---
name: apply
description: Apply a review plan — slice-mode (interactive per-suggestion) or PRD-mode (themed cleanup PR from <prd-review> findings).
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` sibling skill now, before the first response.**
It governs the interactive loop, YOLO-mode summaries, and reasoning. Commit
messages, PR bodies, and issue/PR comments are full-prose artifacts (already
excluded by `brevity`'s Scope section) — write them normally.

## Fetching the review plan (redirect-then-awk)

The review plan is a large prose comment. Do not `cat` it into context.
Redirect to a scratch file, then extract only the section you need:

```bash
gh issue view $ARGUMENTS --json comments \
  -q '.comments[] | select(.body|test("Review plan|improvement plan|<prd-review")) | .body' \
  > /tmp/review-$ARGUMENTS.md
wc -l /tmp/review-$ARGUMENTS.md   # confirm; do not cat
```

In slice-mode, read `/tmp/review-$ARGUMENTS.md` with ranged reads (e.g.
first 200 lines plus the numbered-suggestions body).

In PRD-mode, extract axis/finding blocks via `awk`:

```bash
awk '/<axis name="alignment">/,/<\/axis>/' /tmp/review-$ARGUMENTS.md
awk '/<axis name="scope">/,/<\/axis>/'     /tmp/review-$ARGUMENTS.md
# etc. for architectural-coherence, test-strategy, ops-readiness
awk '/<counts>/,/<\/counts>/'              /tmp/review-$ARGUMENTS.md
```

## Mode Detection

Inspect the labels of issue `$ARGUMENTS`:

```bash
gh issue view $ARGUMENTS --json labels -q '.labels[].name'
```

- Label includes `prd` (and not `slice`) → **PRD-mode** (cleanup PR).
- Otherwise → **Slice-mode** (default, interactive).

**Announce the detected mode** as your first line, e.g.:

> Detected PRD-mode for issue #$ARGUMENTS. Running themed cleanup flow.

If in PRD-mode, also verify the issue has a `<prd-review>` comment posted
by the `review` skill. If not, stop:

> No `<prd-review>` comment found on #$ARGUMENTS. Run `/stenswf:review
> $ARGUMENTS` first.

---

# Slice-mode

Work through the review plan for issue number $ARGUMENTS.

If no suitable plan comment is available on the issue (for example, a comment
containing a numbered list of suggestions with What / Why / Priority),
stop and ask the user to run the review skill first.

## YOLO Mode

If the user says **YOLO** at any point, switch to autonomous mode:

- Skip all interactive questions in Phase 1.
- Assess every suggestion yourself. Implement only those that provide
  meaningful value — skip trivial or unnecessary code improvements.
- Proceed directly to Phase 2 with your self-approved list.
- Before starting Phase 2, show a brief summary of what you chose to implement
  and what you skipped, using this format:

  Implementing:
  - #N: one-line reason
  - #M: one-line reason

  Skipped:
  - #K: one-line reason
  - #L: one-line reason

## Phase 1 — Evaluation

For each numbered suggestion in the plan:

1. Assess independently whether it is a good idea given the codebase context.
2. If you conclude it is worth doing, ask me explicitly:
   _"Suggestion #N: [one-line summary] — implement this?"_
3. Wait for my yes/no before moving to the next suggestion.
4. Track the approved list.

Do not implement anything during this phase.

_(Skipped entirely in YOLO mode.)_

## Phase 2 — Implementation

Implement all approved suggestions from Phase 1 (or the self-approved list
in YOLO mode) in a single pass.

When a suggestion involves code changes:

- Use TDD where appropriate: add or adjust tests first, then implement the
  minimal code to satisfy those tests.
- Apply your clean-code skill to keep the implementation simple, readable,
  and consistent with the existing codebase.

Keep changes focused on the scope of the approved suggestions.

## Phase 3 — Wrap-up (Slice-mode)

- Update the issue description and/or comments to reflect what was changed
  and why, referencing the suggestion numbers.
- Ask me to confirm the final review is complete.
- After confirmation: craft a **single conventional commit** that covers
  the entire issue — all changes from phase 1 through phase 3. The commit
  message must describe the overall feature, fix, or change delivered by
  the issue, not just the refactoring applied in this phase. Phase 3
  refinements are part of that delivery, not a separate scope.

  Conventional commit format (inlined — no separate skill load):

  ```
  <type>(<scope>): <imperative summary, lower case, no period, ≤72 chars>

  <body paragraph describing what & why, wrapped at ~72 chars. Omit if the
  summary is self-explanatory.>

  Refs: #$ARGUMENTS
  ```

  `type` is one of: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`,
  `chore`, `build`, `ci`, `style`, `revert`. `scope` is optional; use the
  top-level module or area touched. Breaking changes: add `!` after the
  type/scope and include a `BREAKING CHANGE:` paragraph in the body.

- Push the branch and close the issue.

---

# PRD-mode — cleanup PR from capstone findings

## Short-circuit: zero findings

Parse `<counts>` from the `<prd-review>`:

```bash
awk '/<counts>/,/<\/counts>/' /tmp/review-$ARGUMENTS.md
```

If all counts are zero, finalize the PRD lifecycle without a branch or PR:

1. Post a short comment on the PRD: `No cleanup needed — capstone review returned zero findings.`
2. Apply the `applied` label to the PRD issue (created once per repo via `bootstrap`).
3. Close the PRD issue.
4. Tell the user:

   > PRD #$ARGUMENTS had no findings. Applied `applied` label and closed the PRD. No cleanup PR was opened.

Do not create a branch, do not ship anything.

## Phase 1 — Extract and group findings

Extract findings from each axis (see "Fetching the review plan" above).
Parse each `<finding>` into: id, severity, axis, what, why, evidence.

**Group findings into themed commits by axis.** Each axis with at least
one finding becomes one commit. Within an axis, if findings touch
disjoint areas, you MAY split into sub-commits per area — but keep
theming obvious and avoid commit spam.

Present the grouping for user approval (or proceed in YOLO mode):

> I'll produce <N> themed commits:
> - alignment: F1, F2 (2 findings)
> - architectural-coherence: F5, F6, F7 (3 findings)
> - test-strategy: F9 (1 finding)
>
> Skipping: F3 (low severity, out of scope), F8 (already addressed).
> Proceed? (y/N)

Wait for confirmation unless YOLO.

## Phase 2 — Branch and implement

Create the cleanup branch from the PRD base's merge-target tip (typically
main or the PRD's integration branch):

```bash
git fetch origin
git checkout -b "prd/$ARGUMENTS-cleanup" origin/main
BASE_SHA=$(git rev-parse HEAD)
```

For each approved axis group, in order of severity (critical → high →
medium → low):

1. Implement all findings in the group. Use TDD where it fits. Apply the
   `clean-code` sibling skill. Apply `lint-escape` if strictly required.
2. Run tests. All must pass before moving on.
3. Commit with a themed conventional message:

   ```
   refactor(<axis-or-scope>): address <axis> findings from PRD #$ARGUMENTS

   <one paragraph summary of what changed across the axis findings>

   Addresses: F1, F2
   Refs: #$ARGUMENTS
   ```

   Use commit types appropriate to the axis: `test(...)` for test-strategy,
   `refactor(...)` for architectural-coherence, `fix(...)` for alignment
   where behavior was wrong, `chore(ops): ...` or `feat(ops): ...` for
   ops-readiness, etc.

4. Update `BASE_SHA = HEAD_SHA`.

If any group cannot be completed, stop and post a `FINDING_BLOCKER`
comment (same structure as `ship`'s `TASK_BLOCKER`) on the PRD issue.

## Phase 3 — Ship the cleanup PR (reuse ship Phase 4–5)

This phase **reuses the `ship` sibling skill's Phase 4 sub-procedure**
(PR, CI loop, merge wait) and Phase 5 (wrap-up). Do not re-implement that
logic here. Read `ship/SKILL.md` Phase 4 and Phase 5 and follow them
verbatim with these parameter substitutions:

- **Issue number:** `$ARGUMENTS` (the PRD).
- **Branch:** `prd/$ARGUMENTS-cleanup`.
- **PR title:** `PRD #$ARGUMENTS cleanup — capstone findings`.
- **PR body:**
  ```
  Addresses capstone findings from <link to <prd-review> comment>.

  Finding IDs addressed: F1, F2, F5, F6, F7, F9
  Finding IDs skipped (with reason):
    - F3: low severity, out of scope
    - F8: already addressed in slice #<N>

  Closes #$ARGUMENTS (capstone cleanup).
  ```
- **Label applied on merge:** `applied` (not `shipped`). The `applied`
  label is created once per repo via `bootstrap`.

After merge, post a wrap-up comment on the PRD issue listing the themed
commits and finding IDs addressed.

## Idempotence

If `apply` is re-run against the same PRD after a partial cleanup, the
`<prd-review>` will have been refreshed by `review` (delta-review).
Extract only the findings carried forward from the new review and repeat
this flow — the `prd/$ARGUMENTS-cleanup` branch may already exist; in
that case, rebase it on current main and add commits for the new
findings. Do not amend prior cleanup commits.
