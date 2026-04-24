---
name: ship-light
description: Implement a single well-scoped slice issue end-to-end in one session — branch, TDD, commit, PR, CI green.
disable-model-invocation: true
---

REASONING STYLE: terse internal reasoning, no pre-summaries, no filler.
Commit messages, PR bodies, error quotes, and the CI hand-off comment
remain verbatim.

Implement issue $ARGUMENTS end-to-end in this single session. No
subagents, no plan comment, no XML extraction. The issue body IS the spec.

## Phase 0 — Preflight gate

Capture feedback-session baseline per
[../../references/feedback-session.md](../../references/feedback-session.md).
Apply context-hygiene per
[../../references/context-hygiene.md](../../references/context-hygiene.md).

Fetch and read front-matter via
[../../references/extractors.md](../../references/extractors.md):

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
TYPE=$(get_fm type /tmp/slice-$ARGUMENTS.md)
LITE=$(get_fm lite_eligible /tmp/slice-$ARGUMENTS.md)
DISQ=$(get_fm disqualifier /tmp/slice-$ARGUMENTS.md)
BLOCKED=$(get_fm blocked_by /tmp/slice-$ARGUMENTS.md)
```

Abort to `/stenswf:plan` + `/stenswf:ship` (one-line reason to user,
nothing posted to issue) if any:

- Body lacks an `Acceptance criteria` section with ≥1 checkbox. Log `contract_violation`.
- `BLOCKED` non-empty.
- `LITE == "false"`. Echo the disqualifier: `aborting — $DISQ`.
  Exception: `TYPE == "slice — spike"` ignores `arch-unknown`.
- Scope plausibly exceeds the Lite envelope (> 15 files, multi-module,
  schema migration, unresolved arch decision).

When in doubt, proceed — the Phase 3 rubberduck will catch drift.

## Phase 0.5 — Plan-light detection (optional)

If `plan-light` has been run, its pair of artifacts is on disk. Detect
and (if current) consume as advisory:

```bash
PLAN_MD=".stenswf/$ARGUMENTS/plan-light.md"
PLAN_JSON=".stenswf/$ARGUMENTS/plan-light.json"

if [ -s "$PLAN_MD" ] && [ -s "$PLAN_JSON" ]; then
  CUR_SIG=$( { \
    extract_section 'What to build'            /tmp/slice-$ARGUMENTS.md; \
    extract_section 'Conventions \(from PRD\)' /tmp/slice-$ARGUMENTS.md; \
    extract_section 'Acceptance criteria'      /tmp/slice-$ARGUMENTS.md; \
  } | sha256sum | cut -d' ' -f1)
  PLAN_SIG=$(jq -r .source_signature "$PLAN_JSON")

  if [ "$CUR_SIG" = "$PLAN_SIG" ]; then
    echo "plan-light current; using as advisory guidance"
  else
    echo "plan-light stale; ignoring, proceeding from issue body"
  fi
fi
```

**Precedence.** Issue body ACs are authoritative for "done."
`plan-light.md` is advisory only. If they disagree, issue body wins.

## Phase 1 — Setup

- Read `CLAUDE.md` (or `AGENTS.md`) once. **Honour throughout.**
- Extract the slice's `## Conventions (from PRD)`:

  ```bash
  extract_section 'Conventions \(from PRD\)' /tmp/slice-$ARGUMENTS.md \
    > /tmp/slice-$ARGUMENTS-conventions.md
  wc -l /tmp/slice-$ARGUMENTS-conventions.md
  ```

  If content is `None — slice-local decisions only.`, no cross-cutting
  conventions — proceed normally.
- Load exactly: `tdd`, `clean-code`, `lint-escape`.
- Branch off default (portable across branch names):

  ```bash
  BASE_SHA=$(git rev-parse HEAD)
  DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
  git fetch origin "$DEFAULT"
  SLUG=$(gh issue view $ARGUMENTS --json title -q .title \
    | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | cut -c1-40)
  git checkout -b "impl/$ARGUMENTS-$SLUG" "origin/$DEFAULT"
  ```

## Phase 2 — TDD per acceptance criterion

For each AC in order: failing test → minimal code → green → refactor
(`clean-code`) → commit. One commit per behavioral change. Names,
shapes, layouts match `## Conventions (from PRD)` verbatim — on conflict,
stop and hand off to `/stenswf:plan` + `/stenswf:ship`. Log
`contract_violation` if the conflict was discovered late.

Conventional Commits:

```bash
git commit -m "<type>(<scope>): <imperative subject>" -m "Refs #$ARGUMENTS"
```

`type`: `feat|fix|refactor|perf|docs|test|chore|build|ci`. Subject
lower-case, no period, ≤72 chars. Apply `lint-escape` if blocked. No squash.

**Ambiguity handling (silent-or-escalate).** Two materially different
implementations, no codebase tiebreaker → stop, emit
`ROUTE_HEAVY: <reason>` as FINAL line. Log `ambiguous_instruction`.
Minor implementation choices (naming within conventions, local
helpers, test shape) are educated guesses — record in PR body's
`## Notable assumptions` and proceed.

`## Notable assumptions` is NOT the decision anchor — the anchor
captures rejected alternatives.

## Phase 3 — Pre-push rubberduck

Same session, no subagent. Orthogonal to `clean-code`:

- **AC → test mapping.** Each AC has a test proving it. Missing → add.
- **Convention drift.** Grep diff for new symbols; confirm every new
  module path, function name, class name, and field set matches
  `## Conventions (from PRD)` verbatim. Drift → fix or hand off.
- **Scope drift.** `git diff $BASE_SHA..HEAD` — anything not required
  by an AC → delete or justify in one sentence.
- **Untested error path.** Grep diff for new/changed
  `raise|throw|return Err|return nil|panic(`. Untested → add a test.
- **Leftover smell.** Grep diff for
  `TODO|FIXME|print(|console\.log|debugger` and commented-out blocks.

If anything was fixed, re-run tests+lint, then:
`git commit -am "refactor(<scope>): self-critique pass" -m "Refs #$ARGUMENTS"`.

If the rubberduck rejected a concrete alternative, append one
`decision` entry (source `ship-light`) to
`.stenswf/$ARGUMENTS/decisions.md` per
[../../references/decision-anchor-link.md](../../references/decision-anchor-link.md).

Non-decision "minor guesses" go in both the PR body's
`## Notable assumptions` AND `lite-notes.md`'s
`## Assumptions (ship-light)` section (create the file with an empty
`## Assumptions (plan-light)` heading if plan-light was not run):

```bash
LN=".stenswf/$ARGUMENTS/lite-notes.md"
if [ ! -f "$LN" ]; then
  mkdir -p "$(dirname "$LN")"
  printf '# Lite Notes — #%s\n\n## Assumptions (plan-light)\n\n## Assumptions (ship-light)\n' \
    "$ARGUMENTS" > "$LN"
fi
# append each guess as "- <one-sentence assumption>" under the ship-light section
```

## Phase 4 — Push and PR

Final test + lint must pass (or `lint-escape`-justified). Then run the
shared PR+CI procedure with `CI_MAX_CYCLES=2` and `WAIT_FOR_MERGE=no`:
[../../references/pr-ci-merge.md](../../references/pr-ci-merge.md).

PR body template: [pr-body.md](pr-body.md). Verbatim, no brevity compression.

## Phase 5 — CI (via shared procedure)

`gh pr checks --watch`. Green → done. Red → up to 2 fix cycles per
[pr-ci-merge.md](../../references/pr-ci-merge.md). On cap reached,
post `CI_BLOCKER (ship-light cap reached)` and log `tool_failure`.

`ship-light` does NOT wait for merge — user handles async.

## Out of scope (deliberate)

No plan comment, `<task>` blocks, XML/awk extraction. No subagent
dispatch (except optional Cycle-2 `/clear`). No review-step, invariant
gate, or multi-axis review — use `/stenswf:review $ARGUMENTS`
separately. No labels. No implementation-log table. No worktrees.

If the slice grows past the preflight envelope mid-flight: stop, hand
off to `/stenswf:plan` + `/stenswf:ship`. Do not silently re-plan.
Log `ambiguous_instruction`.

## Envelope form (when dispatched by `slice-e2e`)

Final line must be exactly one of:

```
MERGED <pr-url>
CI_BLOCKER <pr-url>
ROUTE_HEAVY: <one-sentence reason>
```

---

## Feedback

Log friction throughout per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=ship-light` and `STENSWF_ISSUE=$ARGUMENTS`.
