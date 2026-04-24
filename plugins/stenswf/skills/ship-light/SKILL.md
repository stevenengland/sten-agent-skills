---
name: ship-light
description: Implement a single, well-scoped slice issue end-to-end in one
  session — branch, TDD, commit, PR, CI green. Lighter alternative to the
  `plan` + `ship` pair for crisp single-slice work.
disable-model-invocation: true
---

REASONING STYLE: terse internal reasoning, no pre-summaries, no filler.
Commit messages, PR bodies, error quotes, and the CI hand-off comment
remain verbatim.

Implement issue $ARGUMENTS end-to-end in this single session. No
subagents, no plan comment, no XML extraction. The issue body IS the spec.

## Phase 0 — Preflight gate

`gh issue view $ARGUMENTS` (or `glab`/`tea`). Abort to `/stenswf:plan` +
`/stenswf:ship` (one-line reason to user, nothing posted to issue) if any:

- Body lacks an `Acceptance criteria` section with ≥1 checkbox.
- Open `Blocked by #N` exists.
- Body declares `Lite-eligible: false`. If a structured disqualifier
  block is present (`Disqualifier: <tag>`), echo the tag in the one-line
  abort reason (e.g. `aborting — files>15`). Exception: if the body's
  `## Type` marker says `slice — spike`, ignore a
  `Disqualifier: arch-unknown` — spike slices exist to resolve unknowns.
- Scope plausibly exceeds the Lite envelope and the issue body did not
  already declare it non-Lite:
  - **> 15 files** changed (no distinction between src/test).
  - Crosses **more than one top-level module directory** (intra-directory
    helpers are fine).
  - Includes a schema migration.
  - Introduces an architectural decision not already resolved in
    `## Conventions (from PRD)`.
  Read `What to build`, `Files (hint)`, and `## Conventions (from PRD)`
  before judging. When in doubt, proceed — the `apply` skill's
  per-suggestion loop and `ship-light` Phase 3 rubberduck will catch
  drift.

## Phase 1 — Setup

- Read `CLAUDE.md` (or `AGENTS.md`) once. **Honour CLAUDE.md throughout.**
- Extract the slice's `## Conventions (from PRD)` section and read once.
  Treat as hard spec alongside Acceptance criteria — do not invent
  alternative names, shapes, or layouts:

  ```bash
  gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
  awk '/^## Conventions \(from PRD\)/,/^## /' /tmp/slice-$ARGUMENTS.md \
    | sed '$d' > /tmp/slice-$ARGUMENTS-conventions.md
  wc -l /tmp/slice-$ARGUMENTS-conventions.md
  ```

  If the extracted content is `None — slice-local decisions only.`, there
  are no cross-cutting conventions — proceed normally.
- Load exactly: `tdd`, `clean-code`, `lint-escape`. No others.
- Branch off default:

  ```bash
  BASE_SHA=$(git rev-parse HEAD)
  DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
  git fetch origin "$DEFAULT"
  SLUG=$(gh issue view $ARGUMENTS --json title -q .title \
    | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | cut -c1-40)
  git checkout -b "impl/$ARGUMENTS-$SLUG" "origin/$DEFAULT"
  ```

## Phase 2 — TDD per acceptance criterion

For each AC in order, follow the `tdd` skill: failing test → minimal
code → green → refactor (apply `clean-code`) → commit. One commit per
behavioural change. Names, shapes, and layouts used here must match
`## Conventions (from PRD)` verbatim — if a convention conflicts with
the codebase, stop and hand off to `/stenswf:plan`+`/stenswf:ship` rather
than improvising. Conventional Commits, `Refs #$ARGUMENTS` footer:

```bash
git commit -m "<type>(<scope>): <imperative subject>" -m "Refs #$ARGUMENTS"
```

`type`: `feat|fix|refactor|perf|docs|test|chore|build|ci`. Subject
lower-case, no period, ≤72 chars. Apply `lint-escape` if a lint/type
error blocks progress. Do not squash.

## Phase 3 — Pre-push rubberduck

Same session, no subagent. Orthogonal to `clean-code` — only catches
what that skill does not:

- **AC → test mapping.** For each AC in the body, name the test proving
  it. Missing → add one.
- **Convention drift.** Grep the diff for symbols introduced by this
  slice; confirm every new module path, function name, class name, and
  field set matches `## Conventions (from PRD)` verbatim. Any drift →
  fix or hand off.
- **Scope drift.** Read `git diff $BASE_SHA..HEAD`. Anything not required
  by an AC → delete or justify in one sentence.
- **Untested error path.** Grep diff for new/changed
  `raise|throw|return Err|return nil|panic(`. Untested path → add a test.
- **Leftover smell.** Grep diff for
  `TODO|FIXME|print(|console\.log|debugger` and commented-out blocks.
  Clean up.

If anything was fixed: re-run full tests + lint, then
`git commit -am "refactor(<scope>): self-critique pass" -m "Refs #$ARGUMENTS"`.

## Phase 4 — Push and PR

Final test + lint must pass (or `lint-escape`-justified). Then:

```bash
git push -u origin "$(git branch --show-current)"
gh pr create --base "$DEFAULT" \
  --title "<type>(<scope>): <subject> (#$ARGUMENTS)" \
  --body-file <(cat <<EOF
Closes #$ARGUMENTS

## Summary
- <bullet 1: what changed>
- <bullet 2: how it was tested>
- <bullet 3: notable trade-off, or "none">

## Tests added (red → green)
- \`<test name 1>\`
- \`<test name 2>\`
EOF
)
```

PR body is verbatim — no brevity compression.

## Phase 5 — CI loop (hard cap: 2 cycles)

`gh pr checks --watch`. Green → done, exit silently, no label changes.

Red → fix loop. **Never `cat` a CI log.** Full job logs (5–50K tokens
typical) must not enter context — always redirect to a scratch file,
then extract only the slice you need with `tail`/`grep`.

**Cycle 1 (same session):**

```bash
gh run view --log-failed > /tmp/ci-fail-$ARGUMENTS-1.log
wc -l /tmp/ci-fail-$ARGUMENTS-1.log   # confirm wrote; do NOT cat

# Diagnosis extracts only — pick the one(s) that fit the failure:
tail -200                                              /tmp/ci-fail-$ARGUMENTS-1.log
grep -nE 'FAIL|Error|^E |Traceback|##\[error\]|panic:' /tmp/ci-fail-$ARGUMENTS-1.log | tail -60
grep -nB2 -A8 '<failing test name>'                    /tmp/ci-fail-$ARGUMENTS-1.log
```

Diagnose from the extracted slice. Fix (`clean-code` for logic,
`lint-escape` for unresolvable lint/type), re-run locally, commit, push,
re-watch.

**Cycle 2 (fresh context):** spawn fresh session if possible, else
`/clear`. Reload only:

- `/tmp/ci-fail-$ARGUMENTS-2.log` — fetched the same way; read via
  `tail`/`grep` extracts, never `cat`.
- `git diff $BASE_SHA..HEAD`.
- CLAUDE.md hard lines (extracted, not full file).

One more attempt. Push.

Still red → STOP. No third cycle. Build the `Error excerpt` block from
the same `grep`/`tail` extract (≤10 lines). Post PR comment verbatim
and exit:

```
CI_BLOCKER (ship-light cap reached)
─────────────────────────────────────────────
Cycles: 2 of 2 exhausted.
Failing job: <name and step>
Error excerpt:
  <last ~10 lines from the grep/tail extract — never the full log>
Cycle 1 attempt: <one sentence>
Cycle 2 attempt: <one sentence>
Suggested next steps:
  A) <concrete fix — file, line, change>
  B) Re-open with `/stenswf:plan` then `/stenswf:ship`.
─────────────────────────────────────────────
```

## Out of scope (deliberate)

No plan comment, `<task>` blocks, XML/awk extraction. No subagent
dispatch (except optional Cycle-2 `/clear`). No review-step, invariant
gate, or multi-axis review — use `/stenswf:review $ARGUMENTS`
separately. No `shipping`/`shipped` labels. No implementation-log
table. No worktrees.

If the slice grows past the preflight envelope mid-flight (exceeds 15
files, crosses into a second top-level module directory, surfaces a
schema migration, or reveals an architectural unknown not covered by
`## Conventions (from PRD)`): stop, hand off to `/stenswf:plan` +
`/stenswf:ship`. Do not silently re-plan.
