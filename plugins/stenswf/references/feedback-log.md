# stenswf feedback log

Every lifecycle skill logs workflow friction to a shared append-only
log. Readers (you, future improvement passes) grep it for patterns.

## Where

```
.stenswf/_feedback/<YYYY-MM-DD>.jsonl
```

Gitignored by the existing `.stenswf/*` rule (see `bootstrap`).

## Schema (one JSON object per line)

```json
{
  "ts": "2026-04-24T10:23:11Z",
  "skill": "ship-light",
  "phase": "ci-loop",
  "issue": 123,
  "category": "tool_failure",
  "summary": "CI cap reached after 2 cycles on flaky lint",
  "evidence": "/tmp/ci-fail-123-cycle2.log:42"
}
```

## Categories (fixed)

| Category | Meaning |
|---|---|
| `contract_violation` | Front-matter or body shape didn't match schema. |
| `ambiguous_instruction` | AC or convention allowed two plausible reads. |
| `missing_artifact` | Expected file (concept.md, conventions.md, …) absent. |
| `tool_failure` | External tool exit != 0 (gh, git, jq, CI). |
| `user_override` | User chose `(c)ontinue` on drift, or rejected rubberduck. |

## Write path

Via the canonical wrapper:

```bash
bash plugins/stenswf/scripts/log-issue.sh <category> "<summary>" [evidence]
```

Or with relative path from inside a skill that runs in the plugin:

```bash
bash "$STENSWF_ROOT/scripts/log-issue.sh" tool_failure "gh rate-limited" "$PWD/gh.log"
```

See [../scripts/log-issue.sh](../scripts/log-issue.sh).

## Boundary ping (user-facing)

At workflow-skill exit (`ship`, `ship-light`, `apply`), count entries
written in this run and emit one line to stdout:

```bash
N=$(wc -l < ".stenswf/_feedback/$(date -u +%F).jsonl" 2>/dev/null || echo 0)
SESSION_N=$((N - SESSION_START_N))
if [ "$SESSION_N" -gt 0 ]; then
  echo "stenswf: $SESSION_N workflow issues reported this session — see .stenswf/_feedback/"
fi
```

`SESSION_START_N` is captured at skill entry. No details in the ping —
just the count and the pointer.

## Who must log

The 8 workflow skills: `prd-from-grill-me`, `prd-to-issues`, `plan`,
`plan-light`, `ship`, `ship-light`, `review`, `apply`. Craft skills
(`brevity`, `tdd`, `clean-code`, `lint-escape`, `architecture`,
`bootstrap`) do not log — their friction surfaces in the caller.

## What qualifies as "notable"

- Front-matter missing or unparseable → `contract_violation`.
- Expected plan artifact absent → `missing_artifact`.
- `gh`/`git`/`jq` exits non-zero and blocks progress → `tool_failure`.
- User took the `(c)ontinue` branch on drift → `user_override`.
- Skill aborted with `ROUTE_HEAVY` → `ambiguous_instruction`.
- CI cap reached → `tool_failure`.

Routine "happy path" operations do not log. Logging on every dispatch
turns the log into noise and defeats its purpose.
