---
name: ship
description: Implement a slice issue by dispatching one subagent per local task fragment (TDD + clean code), run a refactor pass, file a PR, monitor CI to green, and archive the local plan on merge.
disable-model-invocation: true
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).
Subagents do NOT load `brevity`. A terse-reasoning rule is inlined in
`stable-prefix.md` instead.

---

Implement issue number $ARGUMENTS by dispatching subagents against the
local plan tree at `.stenswf/$ARGUMENTS/`. The local plan is the
**definitive specification**; issue body states the goal. On conflict,
local plan wins unless the issue body has drifted (see drift check).

If `.stenswf/$ARGUMENTS/` missing, stop and ask the user to run
`/stenswf:plan $ARGUMENTS` first. Log `missing_artifact`.

---

## Prerequisites

- [ ] Capture feedback-log baseline for the session boundary ping
  (see [../../references/feedback-log.md](../../references/feedback-log.md)):

  ```bash
  FB_LOG=".stenswf/_feedback/$(date -u +%F).jsonl"
  mkdir -p "$(dirname "$FB_LOG")"
  SESSION_START_N=$(wc -l < "$FB_LOG" 2>/dev/null || echo 0)
  export SESSION_START_N
  ```

- [ ] Detect the issue-tracker CLI (`gh`, `glab`, `tea`) and use it
  for every issue/PR command below.

- [ ] Confirm the local plan tree exists:

  ```bash
  D=.stenswf/$ARGUMENTS
  [ -s "$D/manifest.json" ]     || { echo "run /stenswf:plan $ARGUMENTS first"; exit 1; }
  [ -s "$D/stable-prefix.md" ]  || { echo "stable-prefix missing; re-run /stenswf:plan"; exit 1; }
  ```

- [ ] **Drift check** — full procedure at
  [../../references/drift-check.md](../../references/drift-check.md).
  On `(c)ontinue`, append a drift-accepted meta-entry to
  `decisions.md` and log `user_override`.

- [ ] Record `BASE_SHA`:

  ```bash
  BASE_SHA=$(git rev-parse HEAD)
  BRANCH=$(git branch --show-current)
  jq --arg b "$BRANCH" --arg s "$BASE_SHA" \
    '.branch=$b | .base_sha=$s' "$D/manifest.json" \
    > "$D/manifest.json.tmp" && mv "$D/manifest.json.tmp" "$D/manifest.json"
  ```

- [ ] **Resume detection** — find first `manifest.tasks[].status != "done"`.
  All done → Phase 2.

---

## Phase 1 — Task Execution (Orchestrator Loop)

Walk pending tasks in order (`T10`, `T20`, …).

### 1a. Delegate to a subagent

Each dispatch pastes `stable-prefix.md` **verbatim** as the prompt head
(prompt caching hits on dispatches 2..N), then task-specific tail:

```
$(cat .stenswf/$ARGUMENTS/stable-prefix.md)

ISSUE: #$ARGUMENTS
TASK_ID: T<id>
TASK_FILE: .stenswf/$ARGUMENTS/tasks/T<id>.md

FETCH YOUR TASK FRAGMENT (do this first):

  cat .stenswf/$ARGUMENTS/tasks/T<id>.md

Execute the extracted task block exactly as written. It is fully
self-contained: test code, paths, commands, Done-when, commit message.

At the end, commit with a `Refs: #$ARGUMENTS T<id>` trailer:

  git add <paths from Files>
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
above is the only way it should touch the plan.

### 1b. Verify the subagent report

- [ ] First line matches `TASK_REPORT T<id> DONE <sha>`.
- [ ] Commit was made:

  ```bash
  HEAD_SHA=$(git rev-parse HEAD)
  [ "$HEAD_SHA" != "$BASE_SHA" ] || { echo "FAIL — no commit"; }
  ```

- [ ] Reported SHA matches `HEAD_SHA`.
- [ ] On `BLOCKED` or no new commit: post `TASK_BLOCKER` and stop.
  Log `tool_failure`.
- [ ] `BASE_SHA = HEAD_SHA`.

### 1c. Update manifest

```bash
jq --arg id "T<id>" --arg sha "$HEAD_SHA" \
  '(.tasks[] | select(.id==$id)) |= (.status="done" | .sha=$sha)' \
  "$D/manifest.json" > "$D/manifest.json.tmp" \
  && mv "$D/manifest.json.tmp" "$D/manifest.json"
```

### Task Blocker Template

On `BLOCKED`: post as issue comment, set task status to `"blocked"` in
manifest, log `tool_failure`, stop:

```
TASK_BLOCKER
─────────────────────────────────────────────
Task:      T<id> <task name>
BASE_SHA:  <SHA before dispatch>
HEAD_SHA:  <SHA after subagent returned>
Committed: YES | NO
Error:     <paste from subagent's verbose TASK_REPORT>
Options:
  A) <concrete resolution — file, line, change>
  B) <alternative>
─────────────────────────────────────────────
```

If the user's `BLOCKED` override materially differs from the task's
`Done when`, append one `decision` entry to `decisions.md` (source `ship`,
refs include task id + paths). Routine BLOCKED-then-fix → no entry.

---

## Phase 2 — Refactor Pass (fresh session)

Runs in a **fresh session**, not the orchestrator parent. If your
harness cannot spawn one, `/clear` (or equivalent) and reload manually.

**Inputs:**

```bash
git diff $BASE_SHA..HEAD > /tmp/ship-$ARGUMENTS-refactor-diff.patch
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

Update `BASE_SHA`, mark manifest:

```bash
jq --arg sha "$(git rev-parse HEAD)" \
  '.refactor_pass.status="done" | .refactor_pass.sha=$sha' \
  .stenswf/$ARGUMENTS/manifest.json > /tmp/m.json \
  && mv /tmp/m.json .stenswf/$ARGUMENTS/manifest.json
```

---

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
    get_section "Acceptance criteria" /tmp/slice-$ARGUMENTS.md \
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

(See `get_section` in
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

---

## Phase 4 — PR, CI Loop, Merge Wait

Run the shared PR+CI+merge procedure with `CI_MAX_CYCLES=3` and
`WAIT_FOR_MERGE=yes`. Full recipe:
[../../references/pr-ci-merge.md](../../references/pr-ci-merge.md).

PR body must include:
- One-sentence summary.
- `Closes #$ARGUMENTS`.
- Summary of any `lint-escape` actions, with rationale.
- Any justified Review-Step absences.

---

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

Emit the feedback-log boundary ping
([../../references/feedback-log.md](../../references/feedback-log.md)):

```bash
FB_LOG=".stenswf/_feedback/$(date -u +%F).jsonl"
N=$(wc -l < "$FB_LOG" 2>/dev/null || echo 0)
SESSION_N=$((N - ${SESSION_START_N:-0}))
if [ "$SESSION_N" -gt 0 ]; then
  echo "stenswf: $SESSION_N workflow issues reported this session — see .stenswf/_feedback/"
fi
```

Tell the user the issue shipped and where the archive lives.

---

## Feedback

Log friction throughout via
[../../references/feedback-log.md](../../references/feedback-log.md).
Set `STENSWF_SKILL=ship` and `STENSWF_ISSUE=$ARGUMENTS` before calling
`scripts/log-issue.sh`.
