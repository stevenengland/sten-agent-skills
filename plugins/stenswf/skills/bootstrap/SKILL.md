---
name: bootstrap
description: One-shot, human-invoked setup for repo-level artifacts the planning
  and shipping skills rely on. Adds `.stenswf/` to `.gitignore` and creates the
  local state root. Run once per repo.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs setup prompts, detection output, and status updates throughout
this one-shot flow.

---

# Bootstrap

**Human-invoked only.** Subagents and model-initiated flows must not call
this skill — it is intended to be run once per repository, by a human, before
the first use of `prd-from-grill-me`, `prd-to-issues`, `plan`, or `ship`. All
operations are idempotent and safe to re-run.

The workflow skills (`plan`, `ship`, `review`, `apply`) will still work
without running this skill — they create `.stenswf/` on demand. Running
this skill once upfront just avoids a surprised first-run.

---

## What this skill provisions

1. **`.stenswf/` in `.gitignore`** — the local state root used by `plan`,
   `ship`, `review`, and `apply` to store per-issue fragments, manifest,
   review findings, apply state, and append-only audit logs. Gitignored
   so per-developer state never leaks into team history.
2. **`.stenswf/` directory** with an empty `.archive/` subdir — created
   up front so skills never need to `mkdir -p` at dispatch time.
   Per-issue subtrees (`.stenswf/<issue>/`) are NOT created here — they
   are seeded by `prd-from-grill-me` at PRD inception and by `plan` at
   slice planning time. Bootstrap only owns the top-level root.
3. **No lifecycle labels.** Earlier versions of stenswf provisioned
   GitHub issue labels (`prd`, `slice`, `planned`, `shipping`, `shipped`,
   `applied`, etc.). These have been removed; the workflow no longer
   reads or writes labels. Mode detection and gating use issue-body
   markers and local state.

If your repo still carries the old labels from a previous stenswf
version, they do no harm — this skill neither creates nor deletes them.
You may delete them manually at your convenience.

---

## Steps

### 1. Add `.stenswf/` to `.gitignore`

```bash
if ! grep -qxF '.stenswf/' .gitignore 2>/dev/null; then
  printf '\n# stenswf local planning + execution state\n.stenswf/\n' >> .gitignore
  echo "added .stenswf/ to .gitignore"
else
  echo ".stenswf/ already in .gitignore"
fi
```

Commit the `.gitignore` change if the repo convention requires it — this
is the only team-visible artifact this skill touches.

### 2. Create the local state root

```bash
mkdir -p .stenswf/.archive
touch .stenswf/.archive/.keep
```

`.stenswf/` is gitignored, but creating it upfront lets `plan` write
into `.stenswf/<issue>/` on first use without a `mkdir -p` surprise.

### 3. Confirm

```bash
ls -la .stenswf/
grep '.stenswf/' .gitignore
```

Done. Tell the user:

> stenswf local state initialised. `.stenswf/` is gitignored; per-issue
> fragments will be created by `/stenswf:plan <issue>` on first use.
