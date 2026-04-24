# Feedback session plumbing

Shared boilerplate for lifecycle skills that log workflow friction and
emit a boundary ping on exit. See
[feedback-log.md](feedback-log.md) for the log schema.

## At session start (capture baseline)

```bash
FB_LOG=".stenswf/_feedback/$(date -u +%F).jsonl"
mkdir -p "$(dirname "$FB_LOG")"
SESSION_START_N=$(wc -l < "$FB_LOG" 2>/dev/null || echo 0)
export SESSION_START_N
```

## During the session (logging)

```bash
export STENSWF_SKILL=<skill-name>
export STENSWF_ISSUE=$ARGUMENTS
bash plugins/stenswf/scripts/log-issue.sh <category> "<summary>" [evidence]
```

Categories: `contract_violation`, `ambiguous_instruction`,
`missing_artifact`, `tool_failure`, `user_override`.

## At session exit (boundary ping)

```bash
FB_LOG=".stenswf/_feedback/$(date -u +%F).jsonl"
N=$(wc -l < "$FB_LOG" 2>/dev/null || echo 0)
SESSION_N=$((N - ${SESSION_START_N:-0}))
if [ "$SESSION_N" -gt 0 ]; then
  echo "stenswf: $SESSION_N workflow issues reported this session — see .stenswf/_feedback/"
fi
```
