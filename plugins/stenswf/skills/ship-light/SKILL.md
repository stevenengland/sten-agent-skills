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

**Ceremony invariant (TDD-as-lens).** This skill MUST NOT (a)
instruct skipping tests for ACs annotated `(behavior)`, (b) remove
`tdd` from any SKILLS TO LOAD list, (c) accept `manual check` or
"rely on existing suite" as completion evidence for a `(behavior)`
AC, or (d) emit guidance that contradicts `tdd/SKILL.md`. Detection
of behavior change is the gate; loading `tdd` is the lens; whether
to write a test follows from the AC tag, not from this skill. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

Capture feedback-session baseline per
[../../references/feedback-session.md](../../references/feedback-session.md).
Apply context-hygiene per
[../../references/context-hygiene.md](../../references/context-hygiene.md).

Fetch and read front-matter via
[../../references/extractors.md](../../references/extractors.md)
(canonical source: `plugins/stenswf/scripts/extractors.sh`):

```bash
source plugins/stenswf/scripts/extractors.sh
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
TYPE=$(get_fm type /tmp/slice-$ARGUMENTS.md)
LITE=$(get_fm lite_eligible /tmp/slice-$ARGUMENTS.md)
DISQ=$(get_fm disqualifier /tmp/slice-$ARGUMENTS.md)
OVERRIDE=$(get_fm lite_override /tmp/slice-$ARGUMENTS.md)
BLOCKED=$(get_fm blocked_by /tmp/slice-$ARGUMENTS.md)
```

Abort to `/stenswf:plan` + `/stenswf:ship` (one-line reason to user,
nothing posted to issue) if any:

- Body lacks an `Acceptance criteria` section with ≥1 checkbox. Log `contract_violation`.
- `BLOCKED` non-empty.
- `TYPE == "slice — HITL"`. HITL slices are structurally unfit for the
  lite path; reroute regardless of `lite_eligible` or `lite_override`.
  Echo: `aborting — HITL slice not eligible for lite path`.
- `LITE == "false"`. Echo the disqualifier: `aborting — $DISQ`.
  Exception: `TYPE == "slice — spike"` ignores `arch-unknown`.
  Exception: `lite_override` is non-empty AND `DISQ` is `files>15` or
  `cross-module` — honor the override and continue. Log `user_override`
  with the reason as evidence:
  ```bash
  if [ "$LITE" = "false" ] && [ -n "$OVERRIDE" ]; then
    case "$DISQ" in
      files\>15|cross-module)
        bash plugins/stenswf/scripts/log-issue.sh user_override \
          "lite_override honored on #$ARGUMENTS ($DISQ)" "$OVERRIDE"
        LITE=true
        ;;
    esac
  fi
  ```
  `lite_override` is NOT honored for `schema-migration`, `arch-unknown`,
  or `hitl-cat3` — these signal work the lite path is structurally
  unfit to handle.
- Scope plausibly exceeds the Lite envelope (> 15 files, multi-module,
  schema migration, unresolved arch decision). When `lite_override`
  was honored above, the blast-radius sub-clauses (>15 files,
  multi-module) are waived for this run; schema-migration and
  unresolved arch decision remain disqualifying.

When in doubt, proceed — the Phase 3 rubberduck will catch drift.

## Phase 0.5 — Plan-light detection (optional)

`lite_override` (Phase 0) waives **blast-radius** disqualifiers only;
behavior-change detection and `tdd`-loading are unaffected by the
override. Honoring the override does NOT skip AC-tag re-validation.

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
    # Capture the planner's behavior tag list for cross-check in Phase 2.
    PLAN_BEHAVIOR_ACS=$(jq -r '.behavior_change_acs[]?' "$PLAN_JSON" \
      | tr '\n' ' ' | sed 's/ *$//')
  else
    echo "plan-light stale; ignoring, proceeding from issue body"
    PLAN_BEHAVIOR_ACS=""
  fi
else
  PLAN_BEHAVIOR_ACS=""
fi
```

**Precedence.** Issue body ACs are authoritative for "done."
`plan-light.md` is advisory only. If they disagree, issue body wins.
`PLAN_BEHAVIOR_ACS` (when set) is consumed by Phase 2 as a
planner-vs-shipper cross-check — divergence from the live issue body
fires `behavior_change_override`.

## Phase 1 — Setup

- Read `CLAUDE.md` (or `AGENTS.md`) once. **Honour throughout.**
- Extract the slice's `## Conventions (from PRD)`. When the slice
  front-matter sets `conventions_source: none`, skip the extraction
  and leave the conventions file empty:

  ```bash
  CONV_SRC=$(get_fm conventions_source /tmp/slice-$ARGUMENTS.md)
  if [ "$CONV_SRC" = "none" ]; then
    : > /tmp/slice-$ARGUMENTS-conventions.md
  else
    extract_section 'Conventions \(from PRD\)' /tmp/slice-$ARGUMENTS.md \
      > /tmp/slice-$ARGUMENTS-conventions.md
  fi
  wc -l /tmp/slice-$ARGUMENTS-conventions.md
  ```

  If content is `None — slice-local decisions only.`, no cross-cutting
  conventions — proceed normally.
- Load exactly: `tdd`, `clean-code`, `lint-escape`.
- Branch off default (portable across branch names):

  ```bash
  set -euo pipefail
  ORIG_HEAD=$(git rev-parse HEAD)              # pre-checkout HEAD (informational)
  DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
  [ -n "$DEFAULT" ] || { echo "ROUTE_HEAVY: could not resolve default branch"; exit 1; }
  git fetch origin "$DEFAULT"
  SLUG=$(gh issue view $ARGUMENTS --json title -q .title \
    | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | cut -c1-40)
  BR="impl/$ARGUMENTS-$SLUG"
  git checkout -b "$BR" "origin/$DEFAULT" || {
    echo "ROUTE_HEAVY: branch creation failed (likely stale $BR from prior run; delete it or check it out manually, then re-run)"
    exit 1
  }
  BASE_SHA=$(git rev-parse HEAD)               # branch base — used for scope-drift diff in Phase 3
  ```

## Phase 1 exit gate — HARD INVARIANT

Before any Phase 2 work (no test, no code, no commit) the following
MUST hold:

```bash
CUR=$(git branch --show-current)
AHEAD=$(git rev-list HEAD ^"origin/$DEFAULT" --count)
[ "$CUR" = "impl/$ARGUMENTS-$SLUG" ] && [ "$AHEAD" = "0" ] || {
  echo "ROUTE_HEAVY: phase 1 gate failed (on=$CUR, ahead=$AHEAD); recover manually if commits are local-only:"
  echo "  git branch impl/$ARGUMENTS-$SLUG && git reset --hard origin/$DEFAULT && git checkout impl/$ARGUMENTS-$SLUG"
  exit 1
}
```

Do NOT "fix" a violation by retroactively branching off a dirty HEAD.
Abort and route heavy.

## Phase 2 — TDD per acceptance criterion

**AC-tag re-validation.** Use `extract_acs` from
[../../references/extractors.md](../../references/extractors.md) to
parse `/tmp/slice-$ARGUMENTS.md` into `AC<n>\t<tag>\t<text>`
records. The extractor itself hard-errors and logs
`contract_violation` on any untagged AC — abort with
`ROUTE_HEAVY: untagged AC — re-run prd-to-issues / triage-issue`
in that case. Re-evaluate every parsed tag against the heuristic
ladder in
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).
Disagreement with the issue body → re-tag silently for this run
and log `behavior_change_override` with `<ac> <old>→<new>
<reason>` as evidence.

**Planner-vs-shipper cross-check (when plan-light is current).** If
`PLAN_BEHAVIOR_ACS` was populated in Phase 0.5, compare it
set-equal against the live `BEHAVIOR_ACS` from `extract_acs`. Any
AC present in one set and absent from the other fires a
`behavior_change_override` log entry with `<ac> <old>→<new>
plan-light vs issue body divergence` as evidence. Live `BEHAVIOR_ACS`
wins (ship is authoritative). When `plan-light` was not current or
absent, this cross-check is skipped.

Per-AC gate based on the tag:

- **`(behavior)` AC** — failing test → minimal code → green →
  refactor (`clean-code`) → commit. RED-first is mandatory.
- **`(structural)` AC** — skip RED. Run the existing suite; it MUST
  stay green. MUST NOT delete tests covering behavior. Commit.

For each AC in order, follow the gate above. Names, shapes, layouts
match `## Conventions (from PRD)` verbatim — on conflict, stop and
hand off to `/stenswf:plan` + `/stenswf:ship`. Log
`contract_violation` if the conflict was discovered late.

Conventional Commits (full spec at
[../../references/conventional-commits.md](../../references/conventional-commits.md)):

```bash
git commit -m "<type>(<scope>): <imperative subject>" -m "Refs: #$ARGUMENTS"
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

- **AC → test mapping.** Each `(behavior)` AC has a test proving it.
  Missing → add. Each `(structural)` AC has the existing suite still
  green; MUST NOT have deleted any test covering behavior.
- **Convention drift.** Grep diff for new symbols; confirm every new
  module path, function name, class name, and field set matches
  `## Conventions (from PRD)` verbatim. Drift → fix or hand off.
- **Scope drift.** `git diff $BASE_SHA..HEAD` — anything not required
  by an AC → delete or justify in one sentence.
- **Untested behavior change (irrefutable backstop).** Diff-grep for
  new/changed exported symbols, signatures, error exits
  (`raise|throw|return Err|return nil|panic(`), public endpoints,
  CLI flags, config keys, persisted shapes. Any uncovered → fail
  rubberduck. This check overrides the per-AC gate: a `(structural)`
  AC tag does NOT exempt new exported behavior from coverage. Per
  [../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).
- **Bad-test audit (refactor-time diagnostic).** For any test that
  broke during the rubberduck refactor, classify as **legitimate**
  (refactor changed observable behavior) or
  **implementation-coupled** (mocked an internal collaborator,
  asserted on private state, queried internal storage instead of
  the public interface, or re-implemented production logic in
  fixture form). Implementation-coupled: rewrite to the public
  interface or delete with one-line justification appended to
  `lite-notes.md`'s `## Assumptions (ship-light)` section. **No
  green-by-deletion of a behavior test** — behavior coverage MUST
  NOT drop.
- **Leftover smell.** Grep diff for
  `TODO|FIXME|print(|console\.log|debugger` and commented-out blocks.

If anything was fixed, re-run tests+lint, then:
`git commit -am "refactor(<scope>): self-critique pass" -m "Refs: #$ARGUMENTS"`.

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

Final test + lint must pass (or `lint-escape`-justified).

**Drift anchor for direct path.** When `ship-light` was invoked
directly (no prior `plan-light` run), seed a minimal anchor so later
`/stenswf:review` and `/stenswf:apply` have a drift baseline. Reuses
the `plan-light.json` shape with `kind: "slice-shipped"`. Skip if a
`plan-light.json` is already present (the lite plan-ahead path):

```bash
ANCHOR=".stenswf/$ARGUMENTS/anchor.json"
PLAN_JSON=".stenswf/$ARGUMENTS/plan-light.json"
if [ ! -s "$PLAN_JSON" ] && [ ! -s "$ANCHOR" ]; then
  mkdir -p ".stenswf/$ARGUMENTS"
  SIG=$( { \
    extract_section 'What to build'            /tmp/slice-$ARGUMENTS.md; \
    extract_section 'Conventions \(from PRD\)' /tmp/slice-$ARGUMENTS.md; \
    extract_section 'Acceptance criteria'      /tmp/slice-$ARGUMENTS.md; \
  } | sha256sum | cut -d' ' -f1)
  cat > "$ANCHOR" <<EOF
{
  "issue": $ARGUMENTS,
  "kind": "slice-shipped",
  "plan_created_at": "$(date -u +%FT%TZ)",
  "source_signature": "$SIG",
  "behavior_change_acs": []
}
EOF
fi
```

Then run the shared PR+CI procedure with `CI_MAX_CYCLES=2` and
`WAIT_FOR_MERGE=no`:
[../../references/pr-ci-merge.md](../../references/pr-ci-merge.md).

PR body template: [pr-body.md](pr-body.md). Verbatim, no brevity compression.

## Phase 5 — CI (via shared procedure)

`gh pr checks --watch`. Green → done. Red → up to 2 fix cycles per
[pr-ci-merge.md](../../references/pr-ci-merge.md). On cap reached,
post `CI_BLOCKER (ship-light cap reached)` and log `tool_failure`.

`ship-light` does NOT wait for merge — user handles async.

## Out of scope (deliberate)

No plan comment, `<task>` blocks, XML/awk extraction. No subagent
dispatch (except optional Cycle-2 `/clear`). No content-review step or
multi-axis review (use `/stenswf:review $ARGUMENTS` separately). No
labels. No implementation-log table. No worktrees.

(Phase 1 exit gate is a workflow invariant, not a review gate — it
guards branch identity, not code quality.)

If the slice grows past the preflight envelope mid-flight: stop, hand
off to `/stenswf:plan` + `/stenswf:ship`. Do not silently re-plan.
Log `ambiguous_instruction`.

## Envelope form (when dispatched by `slice-e2e`)

Final line must be exactly one of:

```
PR_OPENED <pr-url>
CI_BLOCKER <pr-url>
ROUTE_HEAVY: <one-sentence reason>
```

`PR_OPENED` (not `MERGED`) — `ship-light` runs with `WAIT_FOR_MERGE=no`,
so "merged" would be a lie. `<pr-url>` is the canonical `$PR_URL`
captured and validated by [pr-ci-merge.md](../../references/pr-ci-merge.md);
never improvise a URL from `git`/`gh` stderr.

---

## Feedback

Log friction throughout per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=ship-light` and `STENSWF_ISSUE=$ARGUMENTS`.
