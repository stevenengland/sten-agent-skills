---
name: bootstrap
description: One-shot repo setup for stenswf planning/shipping — gitignores `.stenswf/` and creates the local state root.
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
   review findings, apply state, append-only audit logs, and the
   cross-skill decision anchor (`decisions.md`, lazily created by the
   first lifecycle skill that touches a given issue). Gitignored so
   per-developer state never leaks into team history — with one
   exception: the committed `.stenswf/README.md` (layout overview for a
   fresh clone), enabled via `!.stenswf/README.md`.
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
if ! grep -qxF '.stenswf/*' .gitignore 2>/dev/null && \
   ! grep -qxF '.stenswf/'  .gitignore 2>/dev/null; then
  printf '\n# stenswf local planning + execution state\n# (ignore contents, not the directory, so README exception works)\n.stenswf/*\n!.stenswf/README.md\n' >> .gitignore
  echo "added .stenswf/* (with README exception) to .gitignore"
else
  # Upgrade legacy `.stenswf/` to `.stenswf/*` so the re-include works
  # (git cannot re-include a file inside an excluded directory).
  if grep -qxF '.stenswf/' .gitignore 2>/dev/null; then
    sed -i.bak 's|^\.stenswf/$|.stenswf/*|' .gitignore && rm -f .gitignore.bak
    echo "upgraded .stenswf/ → .stenswf/* in .gitignore"
  fi
  if ! grep -qxF '!.stenswf/README.md' .gitignore 2>/dev/null; then
    printf '!.stenswf/README.md\n' >> .gitignore
    echo "added !.stenswf/README.md exception to .gitignore"
  else
    echo ".stenswf/* already in .gitignore"
  fi
fi
```

The `.stenswf/*` + `!.stenswf/README.md` pair lets us commit a single
layout overview so a fresh clone can discover `.stenswf/`'s purpose.
(Using `.stenswf/` alone would ignore the entire directory and git
cannot re-include files inside an excluded directory.)

Commit the `.gitignore` change if the repo convention requires it —
this is the only team-visible artifact this skill touches.

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
