---
name: ship
description: Implement a slice issue by dispatching one subagent per local task
  fragment (TDD + clean code), run a refactor pass, file a PR, monitor CI to green,
  archive the local plan on merge.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs the orchestrator parent session: internal reasoning, tool-use
narration, status updates between phases.

The `brevity` skill excludes commit messages, PR bodies, `CI_BLOCKER`
reports, subagent delegation messages, and the Phase 5 wrap-up comment —
write those in full prose.

Subagents do NOT load `brevity`. A one-line terse-reasoning rule is
inlined into `stable-prefix.md` instead.

---

Implement issue number $ARGUMENTS by dispatching subagents that follow
the local plan tree at `.stenswf/$ARGUMENTS/`. The local plan is the
**definitive specification** for implementation; the issue body states
the goal. Where they conflict, the local plan wins — unless the issue
body has drifted since plan time (see Prerequisites drift check).

If `.stenswf/$ARGUMENTS/` does not exist, stop and ask the user to run
`/stenswf:plan $ARGUMENTS` first.

---

## Prerequisites (complete before dispatching any subagent)

- [ ] Detect the issue-tracker CLI (`gh`, `glab`, `tea`, …) and use it
  for every issue/PR command below. Translate `gh` syntax accordingly.

- [ ] Confirm the local plan tree exists and looks healthy:

  ```bash
  D=.stenswf/$ARGUMENTS
  [ -s "$D/manifest.json" ] || { echo "run /stenswf:plan $ARGUMENTS first"; exit 1; }
  [ -s "$D/stable-prefix.md" ] || { echo "stable-prefix missing; re-run /stenswf:plan"; exit 1; }
  ```

- [ ] **Drift check** — re-fetch the current issue body and compare
  hashes. Issue bodies can be edited by teammates between `plan` and
  `ship`; silent divergence is the #1 cause of pipeline breakage.

  ```bash
  gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS-now.md
  NOW_SHA=$(sha256sum /tmp/slice-$ARGUMENTS-now.md | cut -d' ' -f1)
  PLAN_SHA=$(jq -r .concept_sha256 "$D/manifest.json")

  # Also check CLAUDE.md drift
  CLAUDE_NOW=$(git log -1 --format=%H -- CLAUDE.md AGENTS.md 2>/dev/null | head -1)
  CLAUDE_PLAN=$(jq -r .claude_md_sha "$D/manifest.json")
  ```

  If `NOW_SHA != PLAN_SHA` OR `CLAUDE_NOW != CLAUDE_PLAN`:

  1. Identify which sections changed by recomputing per-section hashes
     on `/tmp/slice-$ARGUMENTS-now.md` (`acceptance_criteria`,
     `conventions`, `what_to_build`) and comparing against
     `manifest.json:section_hashes`.
  2. Show the user:

     ```
     ⚠  Issue #$ARGUMENTS body has changed since plan was written.
        Changed sections: <comma-separated list>
        [diff of changed sections shown inline via `diff` of concept.md vs /tmp/slice-$ARGUMENTS-now.md,
         capped at ~30 lines]

        (r) re-plan       — run /stenswf:plan $ARGUMENTS --resume
                             (keeps done tasks, regenerates the rest)
        (c) continue      — proceed with stale plan
        (a) abort
     ```

  3. Wait for user input. `r` → stop and tell user to run `plan --resume`;
     `c` → proceed (log `"event":"drift-accepted"` to `log.jsonl`);
     `a` → stop.

- [ ] Record `BASE_SHA` and persist to manifest:

  ```bash
  BASE_SHA=$(git rev-parse HEAD)
  BRANCH=$(git branch --show-current)
  jq --arg b "$BRANCH" --arg s "$BASE_SHA" \
    '.branch=$b | .base_sha=$s' "$D/manifest.json" \
    > "$D/manifest.json.tmp" && mv "$D/manifest.json.tmp" "$D/manifest.json"
  ```

- [ ] **Resume detection** — read `manifest.tasks[]` and find the first
  task with `status != "done"`. Skip completed tasks. If all tasks are
  `done`, proceed to Phase 2 (Refactor).

- [ ] Append a dispatch-start event to the audit log:

  ```bash
  printf '{"ts":"%s","event":"ship-start","base_sha":"%s"}\n' \
    "$(date -u +%FT%TZ)" "$BASE_SHA" >> "$D/log.jsonl"
  ```

---

## Phase 1 — Task Execution (Orchestrator Loop)

Walk pending tasks in order (T10, T20, T30 …) as listed in
`manifest.tasks[]`.

### 1a. Delegate to a subagent

Each dispatch pastes `stable-prefix.md` **verbatim** as the prompt head,
then a short task-specific tail. The prefix is identical across all
dispatches in this run — prompt caching hits on dispatches 2..N.

Dispatch message structure:

```
$(cat .stenswf/$ARGUMENTS/stable-prefix.md)

ISSUE: #$ARGUMENTS
TASK_ID: T<id>
TASK_FILE: .stenswf/$ARGUMENTS/tasks/T<id>.md

FETCH YOUR TASK FRAGMENT (do this first, before any other action):

  cat .stenswf/$ARGUMENTS/tasks/T<id>.md

Execute the extracted task block exactly as written. It is fully
self-contained: test code, file paths, commands, Done-when criterion,
and the commit message (from the task's `commit="…"` attribute).

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

Never tell the subagent to "read the plan" in prose. The explicit `cat`
command above is the only way it should touch the plan.

### 1b. Verify the subagent report

- [ ] Parse the first line. Must match `TASK_REPORT T<id> DONE <sha>`.
      Anything else (including `BLOCKED`) → stop.
- [ ] Verify a commit was made:

  ```bash
  HEAD_SHA=$(git rev-parse HEAD)
  [ "$HEAD_SHA" != "$BASE_SHA" ] && echo "OK — committed" || echo "FAIL — no commit"
  ```

- [ ] Verify the reported SHA matches `HEAD_SHA`.
- [ ] If `BLOCKED` or no new commit: do NOT proceed. Post a
      `TASK_BLOCKER` comment on the issue (template below) and stop.
- [ ] Update `BASE_SHA = HEAD_SHA` for the next task.

### 1c. Update manifest + audit log

Update the materialised state in `manifest.json` (O(1) read for resume)
and append to the audit trail (never read in hot path):

```bash
D=.stenswf/$ARGUMENTS

# Update manifest: set task status/sha
jq --arg id "T<id>" --arg sha "$HEAD_SHA" \
  '(.tasks[] | select(.id==$id)) |= (.status="done" | .sha=$sha)' \
  "$D/manifest.json" > "$D/manifest.json.tmp" \
  && mv "$D/manifest.json.tmp" "$D/manifest.json"

# Append to audit log
printf '{"ts":"%s","event":"report","task":"T<id>","status":"done","head_sha":"%s"}\n' \
  "$(date -u +%FT%TZ)" "$HEAD_SHA" >> "$D/log.jsonl"
```

The manifest is the single source of truth for resume; the log is
append-only forensic data.

### Task Blocker Template

If a subagent reports `BLOCKED`, post this as an issue comment, append a
blocked-event to `log.jsonl`, set the task's `status` in manifest to
`"blocked"`, and stop:

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

This phase runs in a **fresh session**, not the orchestrator parent.

**Fresh-session escape hatch.** If your harness cannot spawn a fresh
session, run `/clear` (or the harness equivalent), then reload the
inputs below manually.

**Inputs for the fresh session:**

```bash
git diff $BASE_SHA..HEAD > /tmp/ship-$ARGUMENTS-refactor-diff.patch
cat .stenswf/$ARGUMENTS/file-structure.md
cat .stenswf/$ARGUMENTS/acceptance-criteria.md
```

Read those plus `CLAUDE.md` hard lines. Nothing else.

**Commit sequencing note.** Slice commits from Phase 1 stay atomic. The
refactor pass produces one additional commit on top. Do not squash or
amend the slice commits.

Review every file touched across all tasks (from the diff) against:

- Hard constraints from `CLAUDE.md`.
- Coding guidelines inferred from the repo.
- `clean-code`, SOLID, DRY, KISS.

Focused refactor:

- Eliminate TDD-introduced duplication.
- Clarify naming where obviously beneficial.
- Do NOT introduce new scope beyond the issue.

Run lint + tests after the refactor. Apply `lint-escape` if needed.
This is the last coding step.

Commit:

```bash
git add <changed paths>
git commit -m "refactor(<scope>): post-implementation refactor for #$ARGUMENTS"
```

Update `BASE_SHA`. Mark manifest:

```bash
jq --arg sha "$(git rev-parse HEAD)" \
  '.refactor_pass.status="done" | .refactor_pass.sha=$sha' \
  .stenswf/$ARGUMENTS/manifest.json > /tmp/m.json \
  && mv /tmp/m.json .stenswf/$ARGUMENTS/manifest.json
```

Return to the orchestrator.

---

## Phase 3 — Review Step

Work through `.stenswf/$ARGUMENTS/review-step.md` in the orchestrator:

- **Architectural Invariants:** run the invariant test file. All pass.
- **Recommended Regression Tests:** confirm each listed test exists, or
  note the justified absence in the PR body.
- **Self-report Checklist:** execute each item. Fix any failure.

Mark manifest:

```bash
jq --arg sha "$(git rev-parse HEAD)" \
  '.review_step.status="done" | .review_step.sha=$sha' \
  .stenswf/$ARGUMENTS/manifest.json > /tmp/m.json \
  && mv /tmp/m.json .stenswf/$ARGUMENTS/manifest.json
```

---

## Phase 4 — PR, CI Loop, and Merge Wait

This phase is a **reusable sub-procedure**. `apply` (PRD-mode) invokes
it with a different branch and PR body.

### File the PR

- Stage and commit any remaining changes (hooks must pass).
- Push the branch.
- Open a PR against the default branch. PR body must include:
  - One-sentence summary.
  - `Closes #$ARGUMENTS`.
  - Summary of any `lint-escape` actions taken, with rationale.
  - Any justified absences from the Review Step checklist.

Update manifest with PR URL:

```bash
PR_URL=$(gh pr view --json url -q .url)
jq --arg u "$PR_URL" '.pr.status="open" | .pr.url=$u' \
  .stenswf/$ARGUMENTS/manifest.json > /tmp/m.json \
  && mv /tmp/m.json .stenswf/$ARGUMENTS/manifest.json
```

### CI Loop (max 3 fix cycles, each in a fresh session)

Monitor CI. Each fix cycle runs in a **fresh session** reading only:

- `/tmp/ci-fail-$ARGUMENTS-cycle$N.log` (never `cat` CI logs — always
  `tail`/`grep` extract)
- `git diff $BASE_SHA..HEAD`
- `CLAUDE.md` hard lines

Per cycle:

1. Orchestrator fetches failing job log:
   ```bash
   gh run view --log-failed > /tmp/ci-fail-$ARGUMENTS-cycle$N.log
   wc -l /tmp/ci-fail-$ARGUMENTS-cycle$N.log   # confirm; do NOT cat
   ```
2. Spawn fresh session; diagnose via `tail`/`grep` extracts only:
   ```bash
   tail -200 /tmp/ci-fail-$ARGUMENTS-cycle$N.log
   grep -nE 'FAIL|Error|^E |Traceback|##\[error\]|panic:' \
     /tmp/ci-fail-$ARGUMENTS-cycle$N.log | tail -60
   ```
3. Fix, commit (hooks run), push, return commit SHA.
4. Orchestrator waits for CI, updates `BASE_SHA`.

**Cap: 3 fix cycles.** If still failing, post on PR + issue:

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
Options:
  A) <concrete fix>
  B) <config or environment change>
─────────────────────────────────────────────
```

Stop.

### Merge Wait

```bash
while true; do
  state=$(gh pr view --json state -q .state)
  [ "$state" = "MERGED" ] && break
  [ "$state" = "CLOSED" ] && { echo "PR closed without merge"; exit 1; }
  sleep 30
done
```

Update manifest:

```bash
jq '.pr.status="merged"' .stenswf/$ARGUMENTS/manifest.json \
  > /tmp/m.json && mv /tmp/m.json .stenswf/$ARGUMENTS/manifest.json
```

No labels. The PR merge closes the issue via `Closes #$ARGUMENTS`.

---

## Phase 5 — Wrap-up + archive

Post a single wrap-up comment on the issue:

- Brief summary of the approach.
- Task list by T-ID and commit SHA (from manifest).
- Any `lint-escape` actions taken.
- Any justified review-step absences.

**Archive the local plan tree** (cold storage — keeps forensic `log.jsonl`
+ manifest without polluting the active workspace):

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

Tell the user the issue shipped and where the archive lives.
