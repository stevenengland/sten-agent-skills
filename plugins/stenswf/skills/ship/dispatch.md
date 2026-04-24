# ship — Phase 1 dispatch loop

Walk pending tasks in order (`T10`, `T20`, …). `BASE_SHA` and the
current-task tracker are the orchestrator's state.

## 1a. Delegate to a subagent

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

## 1b. Verify the subagent report

- [ ] First line matches `TASK_REPORT T<id> DONE <sha>`.
- [ ] Commit was made:

  ```bash
  HEAD_SHA=$(git rev-parse HEAD)
  [ "$HEAD_SHA" != "$BASE_SHA" ] || { echo "FAIL — no commit"; }
  ```

- [ ] Reported SHA matches `HEAD_SHA`.
- [ ] On `BLOCKED` or no new commit: post `TASK_BLOCKER` (template
  below) and stop. Log `tool_failure`.
- [ ] `BASE_SHA = HEAD_SHA` (loop-tail bookkeeping; the original slice
  base is already persisted in `manifest.json:.base_sha` for Phase 2).

## 1c. Update manifest

```bash
jq --arg id "T<id>" --arg sha "$HEAD_SHA" \
  '(.tasks[] | select(.id==$id)) |= (.status="done" | .sha=$sha)' \
  "$D/manifest.json" > "$D/manifest.json.tmp" \
  && mv "$D/manifest.json.tmp" "$D/manifest.json"
```

## Task Blocker Template

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
`Done when`, append one `decision` entry to `decisions.md` (source
`ship`, refs include task id + paths). Routine BLOCKED-then-fix → no
entry.
