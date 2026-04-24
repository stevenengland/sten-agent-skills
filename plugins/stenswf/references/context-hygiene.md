# Context hygiene

Practices for keeping orchestrator + subagent context lean across long
lifecycle sessions. Sourced from
[../research/perplexity_token_efficiency.md] and
[../research/notebooklm_token_efficiency.md] (out-of-repo research
bundle).

## 1. Clear stale tool results between phases

If your harness supports `clear_tool_uses_20250919`, fire it with
`keep: 3` between phases and between tasks inside `ship`'s Phase 1
dispatch loop. This is the single highest-leverage context reduction
(up to ~67% per event). If unsupported, note it once in the run's
first BLOCKER / exit report; do not retry per turn.

## 2. Trim large tool results on read

- `git diff` / patches: `wc -l` first. If > ~500 lines, read ranged
  slices (`sed -n 'A,Bp'`) or split by path.
- `gh issue view`: already scoped via `--json body`. Do not `view` twice;
  persist to `/tmp/slice-$ARGUMENTS.md` and re-read.
- File reads for context: prefer `head`/`tail`/ranged reads over full file.

## 3. Pre-subtask compaction

Before dispatching a sub-task or entering a fresh phase, prune the
current conversation of:

- Successful diagnostic greps (the answer is in the next tool's input).
- Resolved error traces.
- Superseded plan drafts.

## 4. Persisted-artifact compression

`decisions.md`, `house-rules.md`, `design-summary.md` grow unbounded
across issue lifetimes. When any single file crosses ~300 lines:

- Superseded decision entries (`### ~~D<n>~~`) can be moved to an
  archive block at the bottom of the file — header and `Supersedes:`
  references must still resolve.
- `house-rules.md` / `design-summary.md` rewrite in terser prose when
  the slice archives.

Not automated; apply during review or apply phases when the file is
already open.

## 5. Prompt caching (ship only)

`ship`'s Phase 1 dispatch pastes `stable-prefix.md` verbatim. Caching
hits on dispatches 2..N only if the prefix is byte-identical — never
inject per-task content above the prefix boundary.
