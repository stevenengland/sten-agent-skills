# ship — Phase 1 dispatch loop

**Ceremony invariant (TDD-as-lens).** This phase MUST NOT (a)
instruct skipping tests for ACs annotated `(behavior)`, (b) remove
`tdd` from any SKILLS TO LOAD list, (c) accept `manual check` or
"rely on existing suite" as completion evidence for a `(behavior)`
AC, or (d) emit guidance that contradicts `tdd/SKILL.md`. Detection
of behavior change is the gate; loading `tdd` is the lens; whether
to write a test follows from the AC tag, not from this skill. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

Walk pending tasks in order (`T10`, `T20`, …). `BASE_SHA` and the
current-task tracker are the orchestrator's state.

## 1a. Delegate to a subagent

Each dispatch pastes `stable-prefix.md` **verbatim** as the prompt head
(prompt caching hits on dispatches 2..N), then task-specific tail. The
tail carries the per-task BEHAVIOR FLAGS block — derived from the
manifest's `tasks[].acs[].behavior_change` mirror per
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).
The flags are per-task (NOT in `stable-prefix.md`) so the cached prefix
stays identical across all tasks; only the tail varies.

```
$(cat .stenswf/$ARGUMENTS/stable-prefix.md)

ISSUE: #$ARGUMENTS
TASK_ID: T<id>
TASK_FILE: .stenswf/$ARGUMENTS/tasks/T<id>.md

--- BEHAVIOR FLAGS ---
BEHAVIOR_CHANGE_ACS: <space-separated AC ids whose tag is (behavior)>
STRUCTURAL_ACS:      <space-separated AC ids whose tag is (structural)>
RULE: For each (behavior) AC, load tdd and follow RED-first.
      For each (structural) AC, skip RED; run existing tests;
      MUST NOT delete tests covering behavior.
RE-VALIDATE: Before writing any test, re-evaluate AC tags against
      the Done-when text and the files you have read. The current
      tag for each AC is derivable from the lists above
      (BEHAVIOR_CHANGE_ACS → `behavior`, STRUCTURAL_ACS →
      `structural`). If you disagree with the manifest, emit one
        BEHAVIOR_CHANGE_OVERRIDE: <ac> <old>→<new> <one-sentence reason>
      line per disagreement at the END of the success report (after
      `tests:`), where <old> and <new> are each `behavior` or
      `structural`. The orchestrator merges each override into the
      manifest. Omit entirely when no overrides fire.

FETCH YOUR TASK FRAGMENT (do this first):

  cat .stenswf/$ARGUMENTS/tasks/T<id>.md

Execute the extracted task block exactly as written. It is fully
self-contained: test code, paths, commands, Done-when, commit message.

At the end, commit with a `Refs: #$ARGUMENTS T<id>` trailer:

  git add <paths from Files>
  git commit -m "<commit attribute verbatim>" -m "Refs: #$ARGUMENTS T<id>"

REPORT FORMAT — silent on success, loud on failure.

On success (3 fixed lines + 0..N optional override lines, no other
output):

  TASK_REPORT T<id> DONE <sha>
  files: <space-separated list>
  tests: <N passed>
  BEHAVIOR_CHANGE_OVERRIDE: <ac> <old>→<new> <one-sentence reason>
  BEHAVIOR_CHANGE_OVERRIDE: <ac> <old>→<new> <one-sentence reason>

Emit one `BEHAVIOR_CHANGE_OVERRIDE` line per AC where re-evaluation
disagreed with the manifest's tag. Omit entirely when no overrides
fire — the 3 fixed lines remain the silent-success default.

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
- [ ] **Behavior-change override.** Scan the report tail for
  `BEHAVIOR_CHANGE_OVERRIDE: <ac> <old>→<new> <reason>` lines, where
  `<old>` and `<new>` are each `behavior` or `structural`. For each:
  verify `<old>` matches the manifest's current
  `tasks[].acs[].behavior_change` for `<ac>` (treat `behavior` as
  `true`, `structural` as `false`); on mismatch, log
  `contract_violation` and stop. Otherwise update the manifest's
  per-AC `behavior_change` to `<new>`, recompute the per-task
  `behavior_change` aggregate (`any(acs.behavior_change)`), and log
  `behavior_change_override` with evidence verbatim:
  `<ac> <old>→<new> <reason>` (the wire format is the canonical
  format — no translation).
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
