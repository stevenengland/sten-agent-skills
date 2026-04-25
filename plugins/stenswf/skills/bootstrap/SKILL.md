---
name: bootstrap
description: One-shot repo setup for stenswf planning/shipping.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs setup prompts, detection output, and status updates throughout
this one-shot flow.

---

# Bootstrap

**Human-invoked only.** Subagents and model-initiated flows must not call
this skill — it is intended to be run once **per clone**, by a human, before
the first use of `prd-from-grill-me`, `prd-to-issues`, `plan`, or `ship`.
The exclusion rule it installs lives in `.git/info/exclude` (not committed),
so every developer must run it after cloning. All operations are idempotent
and safe to re-run.

The workflow skills (`plan`, `ship`, `review`, `apply`) will still work
without running this skill — they create `.stenswf/` on demand. Running
this skill once upfront just avoids a surprised first-run.

---

## What this skill provisions

1. **`.stenswf/` excluded via `.git/info/exclude`** — the local state
   root used by `plan`, `ship`, `review`, and `apply` to store per-issue
   fragments, manifest, review findings, apply state, append-only audit
   logs, and the cross-skill decision anchor (`decisions.md`, lazily
   created by the first lifecycle skill that touches a given issue).
   The exclusion rule is written to `.git/info/exclude` (per-clone, not
   tracked), **not** to `.gitignore`. Nothing under `.stenswf/` is ever
   committed. Each developer must run `/stenswf:bootstrap` once after
   cloning to install the exclusion rule.
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

### 1. Exclude `.stenswf/` via `.git/info/exclude`

```bash
EXCLUDE=.git/info/exclude
if [ ! -f "$EXCLUDE" ] || [ ! -w "$EXCLUDE" ]; then
  echo "stenswf: $EXCLUDE not found or not writable — skipping ignore step"
  echo "        (run inside a standard git repo to enable; continuing)"
else
  if grep -qxF '.stenswf/' "$EXCLUDE"; then
    echo "stenswf: .stenswf/ already excluded in $EXCLUDE"
  else
    printf '\n# stenswf local planning + execution state (per-clone; not committed)\n.stenswf/\n' >> "$EXCLUDE"
    echo "stenswf: added .stenswf/ to $EXCLUDE"
  fi
fi
```

`.git/info/exclude` is git's per-clone ignore file. It is created
automatically by `git init`, lives outside the working tree, and is
**not** committed — so the exclusion rule never leaks into team
history. Each developer who clones the repo must run this skill once
to install their own copy of the rule. If the file is missing (linked
worktrees, submodules, non-git dirs), this step soft-fails and
bootstrap continues.

### 2. Create the local state root

```bash
mkdir -p .stenswf/.archive
touch .stenswf/.archive/.keep
```

`.stenswf/` is excluded per-clone via `.git/info/exclude`, but creating
it upfront lets `plan` write into `.stenswf/<issue>/` on first use
without a `mkdir -p` surprise.

### 3. Confirm

```bash
ls -la .stenswf/
grep -F '.stenswf/' .git/info/exclude 2>/dev/null || echo "(exclude step skipped)"
```

Done. Tell the user:

> stenswf local state initialised. `.stenswf/` is excluded **per-clone**
> via `.git/info/exclude` (not committed to `.gitignore`). Each developer
> must run `/stenswf:bootstrap` once after cloning. Per-issue fragments
> will be created by `/stenswf:plan <issue>` on first use.
