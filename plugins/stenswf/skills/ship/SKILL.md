---
name: ship
description: Implement an issue by dispatching one subagent per plan task (TDD + clean
  code), then run a refactor pass, file a PR, and monitor CI to green.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response
in this session.** It governs the orchestrator parent session: internal
reasoning, tool-use narration, status updates between phases. Self-check
every message against its rules before sending.

The `brevity` skill excludes commit messages, PR bodies, `CI_BLOCKER`
reports, subagent delegation messages, the plan-extraction blocks below,
and the Phase 5 wrap-up comment (see `brevity` Scope). Write those in full
prose.

Subagents do NOT load `brevity` (saves one concurrent skill per
SkillsBench 2–3 sweet spot). A one-line terse-reasoning rule is inlined
into every dispatch message instead.

## Fetching the plan (redirect-then-awk)

This skill reads the large plan comment written by `plan`. Never `cat` the
whole comment — its contents would flood the orchestrator trajectory.

Always use this pattern, in the orchestrator and in every fresh session
spawned from this skill:

```bash
# 1. Redirect full plan comment to a scratch file. Empty stdout; content
#    on disk only.
gh issue view $ARGUMENTS --json comments \
  -q '.comments[] | select(.body|contains("Implementation plan for issue")) | .body' \
  > /tmp/plan-$ARGUMENTS.md
wc -l /tmp/plan-$ARGUMENTS.md   # confirm file wrote; do NOT cat it

# 2. Extract the plan-index (task list + CLAUDE SHA + permalink):
gh issue view $ARGUMENTS --json comments \
  -q '.comments[] | select(.body|contains("Implementation plan-index for issue")) | .body' \
  > /tmp/plan-index-$ARGUMENTS.md

# 3. Extract only what you need, by tag, for the current phase:
awk '/<house-rules>/,/<\/house-rules>/'             /tmp/plan-$ARGUMENTS.md
awk '/<assumptions>/,/<\/assumptions>/'             /tmp/plan-$ARGUMENTS.md
awk '/<file-structure>/,/<\/file-structure>/'       /tmp/plan-$ARGUMENTS.md
awk '/<acceptance-criteria>/,/<\/acceptance-criteria>/'  /tmp/plan-$ARGUMENTS.md
awk '/<review-step>/,/<\/review-step>/'             /tmp/plan-$ARGUMENTS.md
awk '/<task id="T10">/,/<\/task>/'                  /tmp/plan-$ARGUMENTS.md
```

Only the extracted text enters context. The redirect stdout is empty.

---

Implement issue number $ARGUMENTS by dispatching subagents that follow the
implementation plan attached to the issue as a comment.

The implementation plan comment is the **definitive specification**. The issue
description states the goal; the plan governs. Where they conflict, the plan
wins.

If no suitable implementation plan comment is available, stop and ask the
user to run the `plan` planning skill first.

---

## Prerequisites (complete before dispatching any subagent)

- [ ] Detect the issue-tracker CLI available in this repo (`gh`, `glab`,
  `tea`, etc.) and use it for every issue/label/PR command in this skill.
  Translate the example `gh` syntax below to the detected tool.
- [ ] Fetch plan + plan-index via the redirect-then-awk block above.
  Confirm both files non-empty.
- [ ] Extract the plan task list from the plan-index for progress tracking.
- [ ] Extract `<assumptions>` and read once. Record the exact TEST command
  and LINT command from assumptions.
- [ ] Extract `<house-rules>` and read once. This is the stable prefix you
  will paste into every subagent dispatch message (see Phase 1a).
- [ ] Read `CLAUDE.md` OR `AGENTS.md` and extract all hard constraints:
  untouchable files, forbidden suppressions, required tooling, enforced
  commands. Compress filler per `brevity` Rules while keeping verbatim
  anything quoted (commands, file paths, error patterns). The compressed
  block is what you paste as `HARD CONSTRAINTS` in every dispatch.
- [ ] Record `BASE_SHA`:
  ```bash
  BASE_SHA=$(git rev-parse HEAD)
  echo "BASE_SHA: $BASE_SHA"
  ```
- [ ] Check the implementation log table in the issue body. If any tasks
  are already marked ✅, skip them and resume from the first ⬜ pending
  task. The log uses task IDs (`T10`, `T20` …) as row keys.
- [ ] Apply the `shipping` label to the issue. Keep the `planned` label in
  place so both states are visible. Labels are created once per repo via
  the `bootstrap` skill — assume they exist; if not, run `bootstrap` and
  retry.

---

## Phase 1 — Task Execution (Orchestrator Loop)

Walk the tasks in order (T10, T20, T30 … from the plan-index). For each
task:

### 1a. Delegate to a subagent

Dispatch the task to an implementer subagent. The dispatch message is
**stable-prefix-first** so prompt caching hits on dispatches 2..N. Every
dispatch in this `ship` run reuses the same prefix (SKILLS → HARD
CONSTRAINTS → TEST/LINT → HOUSE RULES). Only the tail varies.

Construct the dispatch message exactly in this order:

```
SKILLS TO LOAD: tdd, clean-code, lint-escape

HARD CONSTRAINTS (from CLAUDE.md — non-negotiable, verbatim):
<paste the compressed HARD CONSTRAINTS block from Prerequisites>

TEST COMMAND: <exact test command from <assumptions>>
LINT COMMAND: <exact lint/check command from <assumptions>>

HOUSE RULES (from the plan, read before every task):
<paste the <house-rules> block extracted in Prerequisites>

REASONING STYLE: Keep internal reasoning terse. No pre-summaries, no
restating the task, no filler. Commit messages, PR bodies, and error quotes
remain verbatim.

CONTEXT HYGIENE: Do not re-read files you already read in this task. If
your harness supports `clear_tool_uses_20250919`, fire it with `keep: 3`
after each green test in this slice.

--- (stable prefix ends here; everything above is identical across tasks) ---

ISSUE: #$ARGUMENTS
TASK_ID: T<id>

FETCH YOUR TASK BLOCK (do this first, before any other action):

  gh issue view $ARGUMENTS --json comments \
    -q '.comments[] | select(.body|contains("Implementation plan for issue")) | .body' \
    > /tmp/plan-$ARGUMENTS.md
  wc -l /tmp/plan-$ARGUMENTS.md   # confirm; do not cat
  awk '/<task id="T<id>">/,/<\/task>/' /tmp/plan-$ARGUMENTS.md

Execute the extracted task block exactly as written. It is fully
self-contained: test code, file paths, commands, Done-when criterion, and
the commit message (from the task's `commit="…"` attribute).

At the end, commit with a `Refs: #$ARGUMENTS T<id>` trailer:

  git add <paths from the task's Files section>
  git commit -m "<commit attribute verbatim>" -m "Refs: #$ARGUMENTS T<id>"

REPORT FORMAT — silent on success, loud on failure.

On success (exactly 3 lines, no extra output):

  TASK_REPORT T<id> DONE <sha>
  files: <space-separated list>
  tests: <N passed>

On failure (BLOCKED) use the verbose form:

  TASK_REPORT T<id> BLOCKED
  ─────────────────────────────────────────────
  Task:         T<id> <task name>
  Commands run: <list each with exit code>
  Tests:        <final test run output summary>
  Error:        <exact error message or conflict>
  Suggested resolution:
    A) <concrete fix>
    B) <alternative>
  ─────────────────────────────────────────────
```

Never tell the subagent to "read the plan" in prose. The explicit extract
command above is the only way it should touch the plan.

### 1b. Verify the subagent report

After the subagent returns:

- [ ] Parse the first line. If it matches `TASK_REPORT T<id> DONE <sha>`,
  continue. Anything else (including `BLOCKED`) → stop.
- [ ] Verify commit was made:
  ```bash
  HEAD_SHA=$(git rev-parse HEAD)
  [ "$HEAD_SHA" != "$BASE_SHA" ] && echo "OK — committed" || echo "FAIL — no commit"
  ```
- [ ] Verify the reported SHA matches `HEAD_SHA`.
- [ ] If `BLOCKED` or no new commit: do **not** proceed to the next task.
  Post a `TASK_BLOCKER` comment on the issue (template below) and stop.
- [ ] Update `BASE_SHA = HEAD_SHA` for the next task.

### 1c. Update the implementation log

After each successful task, update the `## Implementation log` table in
the **issue body** (edit the issue, not a new comment). Match rows by task
ID, not by position:

```bash
# Example: mark T20 done with its SHA
gh issue edit $ARGUMENTS --body "$(gh issue view $ARGUMENTS --json body -q .body \
  | sed 's/| T20: .* | ⬜ pending | — |/| T20: <name> | ✅ done | '"$HEAD_SHA"' |/')"
```

The table is the single source of truth for progress — never track state
in memory across tasks.

### Task Blocker Template

If a subagent reports `BLOCKED`, post this as an issue comment and stop:

```
TASK_BLOCKER
─────────────────────────────────────────────
Task:      T<id> <task name>
BASE_SHA:  <SHA before dispatch>
HEAD_SHA:  <SHA after subagent returned>
Committed: YES | NO
Error:     <paste from subagent's verbose TASK_REPORT>
Options:
  A) <concrete resolution — specific file, line, change>
  B) <alternative approach>
─────────────────────────────────────────────
```

Do not proceed to Phase 2 until the blocker is resolved.

---

## Phase 2 — Refactor Pass (fresh session)

This phase runs in a **fresh session**, not the orchestrator parent. The
orchestrator's trajectory is now heavy with N subagent dispatches and
reports; a fresh session starts clean and reads only what the refactor
actually needs. Anthropic's multi-agent context-engineering guidance:
*"detailed search context remains within sub-agents while the lead agent
synthesizes results."*

**Fresh-session escape hatch.** If your harness cannot spawn a fresh
session from within a skill (e.g., a plain Claude Code chat), run `/clear`
(or the harness equivalent) at this point, then reload the inputs listed
below manually before continuing. Do not silently continue in the
orchestrator context — that defeats the whole phase.

**Inputs for the fresh session (redirect-then-awk):**

```bash
git diff $BASE_SHA..HEAD > /tmp/ship-$ARGUMENTS-refactor-diff.patch
wc -l /tmp/ship-$ARGUMENTS-refactor-diff.patch

gh issue view $ARGUMENTS --json comments \
  -q '.comments[] | select(.body|contains("Implementation plan for issue")) | .body' \
  > /tmp/plan-$ARGUMENTS.md
awk '/<file-structure>/,/<\/file-structure>/'       /tmp/plan-$ARGUMENTS.md
awk '/<acceptance-criteria>/,/<\/acceptance-criteria>/'  /tmp/plan-$ARGUMENTS.md
```

The session reads: hard constraints from CLAUDE.md, the diff, the
`<file-structure>`, the `<acceptance-criteria>`. Nothing else.

**Commit sequencing note.** Each Phase 1 task was committed by its subagent
using the pre-written commit message from the plan (verified by the
`HEAD_SHA != BASE_SHA` check). The refactor pass produces **one additional
commit** on top of those slice commits. Do not squash or amend the
subagents' slice commits — they must remain atomic and demoable on their
own.

Review every file touched across all tasks (from the diff) against:

- Hard constraints from `CLAUDE.md`.
- Coding guidelines inferred from the repo.
- `clean-code`, SOLID, DRY, KISS.

Perform a focused refactor pass:

- Eliminate duplication introduced during TDD steps.
- Clarify naming and structure where obviously beneficial.
- Do not introduce new scope beyond what the issue and plan describe.

Run the full lint/check command and test suite after the refactor. Apply
the `lint-escape` skill if needed. This is the last coding step.

Commit the refactor pass (use imperative mood, conventional format):

```bash
git add <changed paths>
git commit -m "refactor(<scope>): post-implementation refactor for #$ARGUMENTS"
```

Update `BASE_SHA` again after this commit. Return to the orchestrator.

---

## Phase 3 — Review Step

Work through the `<review-step>` section of the plan. Extract it in the
orchestrator parent session:

```bash
awk '/<review-step>/,/<\/review-step>/' /tmp/plan-$ARGUMENTS.md
```

- **Architectural Invariants:** run the invariant test file. All must pass.
- **Recommended Regression Tests:** confirm each listed test exists, or
  note the justified absence in the PR body.
- **Self-report Checklist:** execute each item. Fix any failure before
  proceeding. Do not mark an item done without running the command.

Mark the Review Step row in the implementation log as ✅ done with the
current `HEAD_SHA`.

---

## Phase 4 — PR, CI Loop, and Merge Wait

This phase is a **reusable sub-procedure**. The `apply` skill's PRD
cleanup flow invokes it with a different branch and PR body. When called
from `apply`, the parameters below are substituted by that caller.

### File the PR

- Stage all remaining changes.
- Commit any remaining staged files (hooks must run and pass).
- Push the branch.
- Open a PR against the default branch. PR body must include:
  - One-sentence summary of what this delivers.
  - Link to the issue (`Closes #$ARGUMENTS`).
  - Summary of any `lint-escape` actions taken, with rationale (copy from
    subagent reports).
  - Any justified absences from the Review Step checklist.

Mark the `PR / CI` row in the implementation log as ✅ done with the PR URL.

### CI Loop (max 3 fix cycles, each in a fresh session)

After the PR is filed, monitor CI. Each fix cycle runs in a **fresh
session** reading only the failing job log + `git diff BASE_SHA..HEAD`.
The orchestrator parent spawns the cycle, waits for its result, then
decides whether to run another cycle or proceed.

**Fresh-session escape hatch.** If your harness cannot spawn fresh
sessions, run `/clear` (or equivalent) at the start of each cycle and
reload the two inputs below manually. Do not continue fixing in the
orchestrator context \u2014 the accumulated dispatch/report trajectory will
poison CI diagnosis.

Per cycle:

1. Orchestrator fetches failing job log:
   ```bash
   gh run view --log-failed > /tmp/ci-fail-$ARGUMENTS-cycle$N.log
   ```
2. Spawn fresh session with: `/tmp/ci-fail-$ARGUMENTS-cycle$N.log`,
   `git diff $BASE_SHA..HEAD`, CLAUDE.md hard constraints.
3. Fresh session identifies root cause (test failure, lint, type, hook),
   applies the appropriate fix (clean-code change, or `lint-escape`
   protocol), commits (hooks run), pushes, returns commit SHA to
   orchestrator.
4. Orchestrator waits for CI, updates `BASE_SHA = HEAD_SHA`.

**Cap: 3 fix cycles.** If CI is still failing after 3 cycles, orchestrator
stops and posts:

```
CI_BLOCKER
─────────────────────────────────────────────
Cycle:     3 of 3 exhausted
Failing:   <job name and step>
Error:     <exact error output>
Cycles tried:
  Cycle 1: <approach and outcome>
  Cycle 2: <approach and outcome>
  Cycle 3: <approach and outcome>
Options for resolution (choose one):
  A) <concrete fix — specific file, line, change>
  B) <config or environment change required>
─────────────────────────────────────────────
```

Post as both a PR comment and an issue comment. Do not push further commits.

### Merge Wait

Once CI is green, wait for merge. Do not apply the `shipped` label yet —
its semantics are "PR merged to main."

```bash
while true; do
  state=$(gh pr view <pr-number> --json state -q .state)
  [ "$state" = "MERGED" ] && break
  [ "$state" = "CLOSED" ] && { echo "PR closed without merge"; exit 1; }
  sleep 30
done
```

(On platforms without live-watching capability, poll via a loop in a
terminal session, or prompt the user to confirm the merge.)

Once merged:

- Apply the `shipped` label to the issue.
- Remove the `shipping` label.

---

## Phase 5 — Wrap-up

Once the PR has merged and `shipped` is applied:

- Post a wrap-up comment on the issue:
  - Brief summary of the approach taken.
  - List plan tasks completed (by T-ID and commit SHA, from the log table).
  - Any `lint-escape` actions taken (from subagent reports).
  - Any justified absences from the Review Step checklist.

- The PR merge has already closed the issue via `Closes #$ARGUMENTS`; the
  `prd`/`slice`/`planned`/`shipped` labels remain as historical record.

- If this issue is the last open slice under a parent PRD (query:
  `gh issue list --label slice --state open --search "parent-prd:#<PRD>"`
  returns empty), tell the user:

  > All slices of PRD #<PRD> are shipped or abandoned. Run `/stenswf:review
  > <PRD>` to run the PRD-scoped capstone review.
