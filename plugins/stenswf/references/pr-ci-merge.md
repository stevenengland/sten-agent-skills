# PR + CI loop + merge wait (shared sub-procedure)

Reused by `ship` Phase 4, `ship-light` Phase 4-5, and `apply` PRD-mode
Phase 3.

## Parameters

| Var | `ship` | `ship-light` | `apply` PRD-mode |
|---|---|---|---|
| `CI_MAX_CYCLES` | 3 | 2 | 3 |
| `WAIT_FOR_MERGE` | yes | no | yes |
| `PR_TITLE` | from task | `<type>(<scope>): <subject> (#$ARGUMENTS)` | `PRD #$ARGUMENTS cleanup — capstone findings` |
| `PR_BODY` | see caller | see caller | see caller |

## Push and open PR

```bash
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git push -u origin "$(git branch --show-current)"
gh pr create --base "$DEFAULT" --title "$PR_TITLE" --body-file "$PR_BODY_FILE"
```

Record the PR URL in manifest when a manifest exists:

```bash
PR_URL=$(gh pr view --json url -q .url)
jq --arg u "$PR_URL" '.pr.status="open" | .pr.url=$u' \
  "$D/manifest.json" > /tmp/m.json && mv /tmp/m.json "$D/manifest.json"
```

## CI loop

Monitor `gh pr checks --watch`. On red, run up to `$CI_MAX_CYCLES`
cycles. Each cycle:

1. Fetch failing log to a scratch file — **never `cat` CI logs**:

   ```bash
   gh run view --log-failed > /tmp/ci-fail-$ARGUMENTS-cycle$N.log
   wc -l /tmp/ci-fail-$ARGUMENTS-cycle$N.log
   ```

2. Diagnose via `tail`/`grep` extracts only:

   ```bash
   tail -200 /tmp/ci-fail-$ARGUMENTS-cycle$N.log
   grep -nE 'FAIL|Error|^E |Traceback|##\[error\]|panic:' \
     /tmp/ci-fail-$ARGUMENTS-cycle$N.log | tail -60
   ```

3. Fix (apply `clean-code` / `lint-escape` as needed), commit, push,
   re-watch.

Cycle 2+ runs in a fresh session where possible — reload only the log,
`git diff $BASE_SHA..HEAD`, and `CLAUDE.md` hard lines.

## CI cap reached

Post a `CI_BLOCKER` comment on the PR and stop. Schema:

```
CI_BLOCKER (<skill-name> cap reached)
─────────────────────────────────────────────
Cycles: N of N exhausted.
Failing job: <name and step>
Error excerpt:
  <last ~10 lines from grep/tail extract>
Cycles tried:
  Cycle 1: <approach and outcome>
  ...
Suggested next steps:
  A) <concrete fix>
  B) <alternative>
─────────────────────────────────────────────
```

Log to feedback (`scripts/log-issue.sh tool_failure "ci cap reached" <pr-url>`)
before exit.

## Merge wait (`WAIT_FOR_MERGE=yes` only)

```bash
while true; do
  state=$(gh pr view --json state -q .state)
  [ "$state" = "MERGED" ] && break
  [ "$state" = "CLOSED" ] && { echo "PR closed without merge"; exit 1; }
  sleep 30
done
jq '.pr.status="merged"' "$D/manifest.json" > /tmp/m.json \
  && mv /tmp/m.json "$D/manifest.json"
```

For `ship-light` (`WAIT_FOR_MERGE=no`), stop after CI green. No
merge-wait — user handles merge asynchronously.

## Envelope (when dispatched as a subagent)

Final line must be exactly one of:

```
MERGED <pr-url>
CI_BLOCKER <pr-url>
ROUTE_HEAVY: <one-sentence reason>
```
