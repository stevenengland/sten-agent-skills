---
name: ship
description: Implement an issue by dispatching one subagent per plan task (TDD + clean
  code), then run a refactor pass, file a PR, and monitor CI to green.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` sibling skill now, before the first response
in this session.** It governs every internal reasoning step, status update,
and tool-use narration across all phases. Self-check every message against
its rules before sending — do not drift into full prose on internal thinking.

The `brevity` skill already excludes commit messages, PR bodies,
`CI_BLOCKER` reports, subagent delegation messages, and the Phase 5 wrap-up
comment from its scope (see its Scope section). Write those in full prose.

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
- [ ] Fetch the issue and read both the plan comment and the implementation
  log table in the issue body (e.g. `gh issue view $ARGUMENTS`).
- [ ] Read `CLAUDE.md` OR `AGENTS.md` and note all hard constraints: untouchable files,
  forbidden suppressions, required tooling, enforced commands. These
  constraints are non-negotiable and supersede all other instructions. You
  will include them verbatim in every subagent delegation message.
- [ ] Confirm the test command and lint/check command from the plan's
  Assumptions section.
- [ ] Record `BASE_SHA`:
  ```bash
  BASE_SHA=$(git rev-parse HEAD)
  echo "BASE_SHA: $BASE_SHA"
  ```
- [ ] Check the implementation log table in the issue body. If any tasks are
  already marked ✅, skip them and resume from the first ⬜ pending task.
- [ ] Apply the `shipping` label to the issue. Keep the `planned` label in
  place so both states are visible. Labels are created once per repo via
  the `bootstrap` skill — assume they exist; if not, run `bootstrap` and
  retry.

---

## Phase 1 — Task Execution (Orchestrator Loop)

Walk the plan tasks in order. For each task:

### 1a. Delegate to a subagent

Dispatch the task to an implementer subagent. The delegation message must
be **fully self-contained** — the subagent has a fresh context window and
will not read the plan file. Construct the delegation message from these
parts (inline, not by reference):

```
TASK: <task name from plan>
ISSUE: #$ARGUMENTS
COMMIT_MSG: <pre-written commit message from the plan>

HARD CONSTRAINTS (from CLAUDE.md — non-negotiable):
<paste constraints verbatim>

TEST COMMAND: <exact test command from plan Assumptions>
LINT COMMAND: <exact lint/check command from plan Assumptions>

SKILLS TO LOAD: tdd, clean-code, conventional-commits, lint-escape

TASK BODY:
<paste the full Task N block from the plan verbatim, including all
 checkboxes, file paths, test code, commands, Done-when criterion,
 and commit message>

REPORT FORMAT (respond with this exact structure when done):
TASK_REPORT
─────────────────────────────────────────────
Task:        <task name>
Status:      DONE | BLOCKED
Commit SHA:  <output of `git rev-parse HEAD`>
Commands run:
  <list each command and its exit code>
Tests:
  <paste final test run output summary>
Files changed:
  <list files created or modified>
Scope confirmed: YES | NO — <note if anything was out of scope>
Blocker (if BLOCKED):
  <exact error or conflict, and suggested resolution>
─────────────────────────────────────────────
```

Never tell the subagent to "read the plan comment" or "see Task N in the
plan." All context must be in the delegation message.

### 1b. Verify the subagent report

After the subagent returns:

- [ ] Confirm `Status: DONE`.
- [ ] Verify commit was made:
  ```bash
  HEAD_SHA=$(git rev-parse HEAD)
  [ "$HEAD_SHA" != "$BASE_SHA" ] && echo "OK — committed" || echo "FAIL — no commit"
  ```
- [ ] If `Status: BLOCKED` or no new commit: do **not** proceed to the next
  task. Post a `TASK_BLOCKER` comment on the issue (see template below) and
  stop.
- [ ] Update `BASE_SHA = HEAD_SHA` for the next task.

### 1c. Update the implementation log

After each successful task, update the `## Implementation log` table in the
**issue body** (edit the issue, not a new comment):

```bash
# Example: mark Task 1 done with its SHA
gh issue edit $ARGUMENTS --body "$(gh issue view $ARGUMENTS --json body -q .body \
  | sed 's/| Task 1: .* | ⬜ pending | — |/| Task 1: <name> | ✅ done | '"$HEAD_SHA"' |/')"
```

Use whichever CLI is available. Keep all other rows unchanged. The table is
the single source of truth for progress — never track state in memory across
tasks.

### Task Blocker Template

If a subagent reports `BLOCKED`, post this as an issue comment and stop:

```
TASK_BLOCKER
─────────────────────────────────────────────
Task:      <task name>
BASE_SHA:  <SHA before dispatch>
HEAD_SHA:  <SHA after subagent returned>
Committed: YES | NO
Error:     <exact error from subagent report>
Options:
  A) <concrete resolution — specific file, line, change>
  B) <alternative approach>
─────────────────────────────────────────────
```

Do not proceed to Phase 2 until the blocker is resolved.

---

## Phase 2 — Refactor Pass

Run this phase in the **parent session** (not a subagent). The parent session
holds the full plan context needed to evaluate cross-task duplication and
naming consistency.

**Commit sequencing note.** Each Phase 1 task has already been committed by
its subagent using the pre-written commit message from the plan (this is what
the `HEAD_SHA != BASE_SHA` check in step 1b verifies). The refactor pass
produces **one additional commit** on top of those slice commits. Do not
squash or amend the subagents' slice commits — they must remain atomic and
demoable on their own.

Review every file touched across all tasks against:

- Hard constraints from `CLAUDE.md`.
- Coding guidelines inferred from the repo.
- `clean-code`, SOLID, DRY, KISS.

Perform a focused refactor pass:

- Eliminate duplication introduced during TDD steps.
- Clarify naming and structure where obviously beneficial.
- Do not introduce new scope beyond what the issue and plan describe.

Run the full lint/check command and test suite after the refactor. Apply the
`lint-escape` skill if needed. This is the last coding step.

Commit the refactor pass:

```bash
git add <changed paths>
git commit -m "refactor(<scope>): post-implementation refactor for #$ARGUMENTS"
```

Update `BASE_SHA` again after this commit.

---

## Phase 3 — Review Step

Work through the **Review Step** section of the plan (if present). Run this
in the parent session.

- **Architectural Invariants:** run the invariant test file. All must pass.
- **Recommended Regression Tests:** confirm each listed test exists, or note
  the justified absence in the PR body.
- **Self-report Checklist:** execute each item. Fix any failure before
  proceeding. Do not mark an item done without running the command.

Mark the Review Step row in the implementation log as ✅ done with the
current `HEAD_SHA`.

---

## Phase 4 — PR and CI Loop

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

Mark the PR / CI row in the implementation log as ✅ done with the PR URL.

### CI Loop (max 3 fix cycles)

After the PR is filed, monitor CI. For each failed run:

1. Read the failure output.
2. Identify the root cause (test failure, lint error, type error, hook
   failure).
3. Apply the appropriate fix: clean code change, or `lint-escape` protocol if
   a lint/type error.
4. Commit the fix (hooks must run). Push. Wait for CI.

**Cap: 3 fix cycles.** If CI is still failing after 3 cycles, stop and post:

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

---

## Phase 5 — Wrap-up

Once CI is green:

- Post a wrap-up comment on the issue:
  - Brief summary of the approach taken.
  - List plan tasks completed (by name and commit SHA, from the log table).
  - Any `lint-escape` actions taken (from subagent reports).
  - Any justified absences from the Review Step checklist.

- Remove the `shipping` label from the issue. The PR merge closes the issue
  via `Closes #$ARGUMENTS`; the `prd`/`slice`/`planned` labels remain as
  historical record.

- Do not close the issue — the PR merge closes it via
  `Closes #$ARGUMENTS`.
