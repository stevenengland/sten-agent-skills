---
name: review
description: Review changes against an issue, slice, or PRD. Slice-mode runs an
  inline plan-only four-perspective critique and writes local findings. PRD-mode
  runs a 5-axis capstone review on the delivered diff and mirrors the capstone
  to the forthcoming cleanup PR.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs reasoning, axis-by-axis narration, and orchestration chatter.
The review artifacts (slice suggestions, PRD capstone XML) are full-prose
artifacts (already excluded by `brevity`'s Scope section).

---

You are in **plan-only mode**. Do not apply edits, create files outside
`.stenswf/<issue>/` or `/tmp/`, or run state-modifying git commands. Your
output is a structured review artifact on disk.

## Mode Detection

Mode is detected from the issue body's `## Type` marker (not from labels
— labels were removed from stenswf). Fetch and parse:

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
TYPE=$(awk '/^## Type/,/^## /' /tmp/slice-$ARGUMENTS.md \
  | sed '$d' | tail -n +3 | head -1 | tr -d '[:space:]')
```

- `$TYPE == "PRD"` → **PRD-mode** (capstone review).
- `$TYPE` starts with `slice` → **Slice-mode**.
- Unrecognised or missing → check local `.stenswf/$ARGUMENTS/manifest.json`
  (`.kind` field) as cache. Otherwise ask the user.

**Announce the detected mode** as your first line of output.

## Drift check (both modes)

Before reviewing, re-hash the current issue body and compare against
`.stenswf/$ARGUMENTS/manifest.json:concept_sha256` if it exists. On
mismatch, present the `(r)e-plan / (c)ontinue / (a)bort` menu (same
contract as `ship`). On the `r`e-plan branch, after the user accepts,
overwrite `concept.md` with the current body, recompute
`concept_sha256`, and append a `drift-replan` entry to `log.jsonl`.

## PRD-mode local-state backfill

PRD-mode assumes `.stenswf/$ARGUMENTS/{manifest.json,concept.md}` exist
(seeded by `prd-from-grill-me` at inception). For PRDs created before
the seeding step was added, backfill on first run if missing:

```bash
if [ "$TYPE" = "PRD" ] && [ ! -f ".stenswf/$ARGUMENTS/manifest.json" ]; then
  mkdir -p ".stenswf/$ARGUMENTS"
  cp "/tmp/slice-$ARGUMENTS.md" ".stenswf/$ARGUMENTS/concept.md"
  CONCEPT_SHA=$(sha256sum ".stenswf/$ARGUMENTS/concept.md" | awk '{print $1}')
  PRD_BASE=$(git rev-parse "prd-$ARGUMENTS-base" 2>/dev/null \
    || grep -oP 'PRD base SHA:\s*\K[0-9a-f]{7,40}' ".stenswf/$ARGUMENTS/concept.md")
  cat > ".stenswf/$ARGUMENTS/manifest.json" <<EOF
{
  "issue": $ARGUMENTS,
  "kind": "prd",
  "base_sha": "$PRD_BASE",
  "concept_sha256": "$CONCEPT_SHA",
  "plan_created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "slices": [],
  "review_step": {"status": "pending", "sha": null}
}
EOF
  printf '{"ts":"%s","event":"prd-manifest-backfilled"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> ".stenswf/$ARGUMENTS/log.jsonl"
fi
```

Announce when a backfill happened so the user knows drift detection is
seeded against the current body (not a prior snapshot).

---

# Slice-mode — per-slice change review

Review staged changes against issue number $ARGUMENTS.

**Hard constraint — plan-only.** Slice-mode review is read-only against
the codebase and the plan artifacts. Do NOT invoke the `plan-reviewer`
skill here: its contract rewrites plan files in-place and then
implements the revised plan, which is incompatible with this skill's
plan-only guarantee. The only files this mode may create or modify are
under `.stenswf/$ARGUMENTS/review/` and `/tmp/`. No `git add`, no
`git commit`, no `gh issue comment`, no edits to source or test files,
no edits to plan fragments under `.stenswf/$ARGUMENTS/` outside the
`review/` subdirectory. `decisions.md` is read-only; undocumented
decisions surface as findings in `review/slice.md` for `apply` to
override.

## Step 1 — Change Review (inline four-perspective critique)

Inputs (read, do not cat into context wholesale — use `awk` / ranged
reads):

- Staged diff: `git diff --staged > /tmp/review-$ARGUMENTS-staged.patch`.
- Issue body: `/tmp/slice-$ARGUMENTS.md` (fetched above).
- `.stenswf/$ARGUMENTS/conventions.md` if present.
- `.stenswf/$ARGUMENTS/acceptance-criteria.md` if present.
- `.stenswf/$ARGUMENTS/decisions.md` if present — active entries only
  (`grep -E '^### D[0-9]+ '`; strikethrough `### ~~D<n>~~` is
  superseded). Absence is a context note, not a finding.
  [Contract](../../README.md#decision-anchor-contract).
- `.stenswf/$ARGUMENTS/file-structure.md` if present (for architectural
  context only).

### Define success

Before the four passes, write one sentence to
`/tmp/review-$ARGUMENTS-findings.md`:

> This slice succeeds if [outcome, derived from ACs].

Use it as the evaluation frame for all four perspectives.

### Four perspectives (one at a time; do not collapse)

Work axis-by-axis. For each pass, append findings to
`/tmp/review-$ARGUMENTS-findings.md` tagged with the perspective. Stay in
scope per perspective — if you notice an issue belonging to another
perspective, jot `→ <Perspective>` and handle it in that pass.

**Perspective 1 — DevOps / SRE.** Deployment complexity, operability
(logging, observability, rollback, config), what breaks first in prod,
silent assumptions about external services, simpler operational shape.

**Perspective 2 — Peer Reviewer.** Logical contradictions, whether the
code solves the stated problem or a proxy, E2E coverage of critical
user-facing paths, unhandled edge cases (empty input, concurrent access,
failure mid-sequence), materially simpler approach ignored, and — most
important here — **Plan / AC / decision deviation**: does the staged
diff match the issue body + `conventions.md` + `acceptance-criteria.md`
+ active `decisions.md` entries? Tag plan deviations **High** by
default. Decision-anchor contradictions: `arch` → **High**,
`decision` → **Medium** (→ **High** if `Refs:` contains `AC#`).
Superseded entries are not findings. A contradiction is concrete: the
entry rejects Y, and the diff implements Y on a file listed in its
`Refs:`.

**Perspective 3 — Security Engineer.** Realistic threat surface for this
project, new trust boundaries or exposed interfaces, secrets and
credential handling, new dependencies' trust/patch surface. Do not apply
an enterprise checklist to a small project.

**Perspective 4 — Software Architect.** Structural fit, unnecessary
coupling, abstraction level, whether the design serves the project's
stated priorities, documentation updates (README/ADRs/API docs) required
by these changes, rewrite cost if the most likely next requirement
arrives.

### Severity guide

- **Critical** — data loss, security breach, or crash on the happy path.
- **High** — incorrect behaviour, likely runtime bug, or plan deviation.
- **Medium** — maintainability, clarity, or coverage gap with real cost.
- **Low** — nit, style, minor readability.

## Slice-mode Output

Produce a single, numbered list of suggestions from the four perspectives
above. For each item:

1. **What** — what should change.
2. **Why** — why it improves the code.
3. **Priority** — low / medium / high.

Close with a one-line summary: counts of high / medium / low priority.

**Write locally** — not as an issue comment:

```bash
mkdir -p ".stenswf/$ARGUMENTS/review"
cat > ".stenswf/$ARGUMENTS/review/slice.md" << 'EOF'
# Review plan for issue $ARGUMENTS

<numbered suggestions with What / Why / Priority>

Summary: N high | M medium | K low
EOF
```

Tell the user:

> Slice review written to `.stenswf/$ARGUMENTS/review/slice.md`. Run
> `/stenswf:apply $ARGUMENTS` to walk suggestions interactively.

---

# PRD-mode — 5-axis capstone review

PRD-mode reviews an entire delivered PRD: the union of all merged slices
since the PRD was recorded. Strategic review, not per-file code review.

## Step 0 — Strict gating

Refuse to run while any slice of this PRD is still open. Query via body
reference (not via labels):

```bash
gh issue list --state open \
  --search "in:body \"Parent PRD\" \"#$ARGUMENTS\"" \
  --json number,title
```

If any rows return, stop:

> PRD-review blocked: slices still open (#A, #B, #C…). Ship them first.

A slice that was abandoned without shipping should be closed manually
(`gh issue close <N> --reason "not planned"`) before re-running. There
is no `abandoned` label in the current stenswf.

## Step 1 — Resolve the PRD base

The PRD body contains:

```
**PRD base SHA:** <sha>
```

And a matching git tag `prd-<issue>-base`.

```bash
PRD_BASE=$(git rev-parse "prd-$ARGUMENTS-base" 2>/dev/null)
if [ -z "$PRD_BASE" ]; then
  PRD_BASE=$(gh issue view $ARGUMENTS --json body -q .body \
    | grep -oP 'PRD base SHA:\s*\K[0-9a-f]{7,40}')
fi
```

If neither source resolves, ask for the base SHA.

## Step 2 — Compute the delivered diff

```bash
mkdir -p ".stenswf/$ARGUMENTS/review"
git diff "$PRD_BASE..HEAD" --stat > "/tmp/prd-$ARGUMENTS-stat.txt"
git diff "$PRD_BASE..HEAD"       > "/tmp/prd-$ARGUMENTS-diff.patch"
wc -l "/tmp/prd-$ARGUMENTS-diff.patch"
```

**Soft warning.** If the diff touches > 50 files OR > 5000 added lines,
emit a warning but continue.

## Step 3 — Check for prior review (idempotent delta)

```bash
[ -s ".stenswf/$ARGUMENTS/review/prd-review.xml" ] && \
  PRIOR_SHA=$(grep -oP 'reviewed-at="\K[0-9a-f]+' \
    ".stenswf/$ARGUMENTS/review/prd-review.xml" | head -1)
```

If prior review at current `HEAD`: tell user *"PRD already reviewed at
this SHA. Nothing new to review."* and stop. Otherwise compute the delta
diff `<prior-sha>..HEAD` and review only the delta. Carry forward
unresolved prior findings.

## Step 4 — Five-axis review (axis-by-axis)

Do NOT read slice-level plans, implementation logs, or slice-level review
comments. The capstone reviews delivered code against the PRD's original
intent, not intermediate artifacts.

**Exception — decision anchors.** Axis 1 (Alignment) aggregates active
entries from all slice anchors (live or archived) and applies the same
contradiction → severity rule as Slice-mode Perspective 2
([contract](../../README.md#decision-anchor-contract)):

```bash
for S in $(gh issue list --state closed \
            --search "in:body \"Parent PRD\" \"#$ARGUMENTS\"" \
            --json number -q '.[].number'); do
  ANCHOR=".stenswf/$S/decisions.md"
  [ ! -s "$ANCHOR" ] && ANCHOR=$(ls -1 .stenswf/.archive/$S-*/decisions.md 2>/dev/null | head -1)
  [ -n "$ANCHOR" ] && [ -s "$ANCHOR" ] && grep -hE '^### D[0-9]+ ' "$ANCHOR"
done
```

Inputs: PRD body, `/tmp/prd-$ARGUMENTS-stat.txt`, the diff patch file
(read hunks via `awk` or ranged reads — never `cat` the full patch).

Work one axis at a time. Append findings to
`/tmp/review-$ARGUMENTS-findings.md`:

### Axis 1 — Alignment

Does the delivered code match what the PRD said? User stories / ACs not
reflected? Code that doesn't correspond to anything the PRD described?

### Axis 2 — Scope

Obvious scope-creep? Obvious scope-cuts?

### Axis 3 — Architectural coherence

Do the slices together form a coherent architecture? Duplicated
abstractions across slices, inconsistent boundaries, mixed paradigms,
dead code paths?

### Axis 4 — Test strategy

Does coverage match the PRD's risk surface? Critical user stories
without E2E coverage, integration gaps, drifted patterns?

### Axis 5 — Ops readiness

Logging, observability, rollback, config, failure modes.

### Hunk-level reads

```bash
awk '/^diff --git .*<path>/{p=1} p{print} /^diff --git/ && !/<path>/ && p{exit}' \
  /tmp/prd-$ARGUMENTS-diff.patch
```

Or ranged reads of files at HEAD. Never full files, never full patches.

## Step 5 — Output

Write the capstone to `.stenswf/$ARGUMENTS/review/prd-review.xml` using
the XML-anchored structure below. Finding IDs are globally unique (F1,
F2, F3…). Severity: `critical`, `high`, `medium`, `low`.

```xml
<prd-review for="#$ARGUMENTS" reviewed-at="<HEAD SHA>" base="<PRD_BASE>">

<summary>
One paragraph: what was delivered, overall judgment, top concern.
</summary>

<axis name="alignment">
<finding id="F1" severity="high">
<what>...</what>
<why>...</why>
<evidence>file.ts L42–L55; PRD user story #7</evidence>
</finding>
</axis>

<axis name="scope">...</axis>
<axis name="architectural-coherence">...</axis>
<axis name="test-strategy">...</axis>
<axis name="ops-readiness">...</axis>

<counts>
critical: 0 | high: 2 | medium: 3 | low: 4
</counts>

</prd-review>
```

### Mirror a human-readable summary to a PR comment (if any findings)

When `apply` opens the cleanup PR, it will post the `<prd-review>` content
as a PR comment (Q5a — local authoritative + PR mirror for team
visibility). `review` itself does not touch the PR — but this contract is
why the file is written in stable XML.

If **zero findings**, emit a minimal `<prd-review>` with just `<summary>`
and `<counts>` (all zeros), write it to disk, and tell the user:

> PRD #$ARGUMENTS reviewed. No findings. Run `/stenswf:apply $ARGUMENTS`
> to finalize (no cleanup PR will be opened).

No labels are applied anywhere.
