---
name: review
description: Review changes against an issue, slice, or PRD. Slice-mode uses plan-reviewer; PRD-mode runs a 5-axis capstone review on the full delivered diff.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs reasoning, status updates, axis-by-axis narration, and
orchestration chatter. The review-plan / PRD-review comment posted to the
issue is a full-prose artifact (already excluded by `brevity`'s Scope
section) — write it normally.

---

You are in **plan-only mode**. Do not apply edits, create files outside
`/tmp/`, or run state-modifying git commands. Your only output is a
structured review plan added to the target issue as a comment.

## Mode Detection

Inspect the labels of issue `$ARGUMENTS`:

```bash
gh issue view $ARGUMENTS --json labels -q '.labels[].name'
```

- Label includes `prd` (and not `slice`) → **PRD-mode** (capstone review).
- Label includes `slice` (or neither label is the `prd` label) →
  **Slice-mode** (default, per-slice review).

**Announce the detected mode** as your first line of output, e.g.:

> Detected PRD-mode for issue #$ARGUMENTS. Running 5-axis capstone review.

The rest of this skill branches on mode.

---

# Slice-mode — per-slice change review

Review staged changes against issue number $ARGUMENTS.

## Step 1 — Change Review

Invoke the `plan-reviewer` skill and follow its process to generate
a structured improvement plan based on the staged changes and the issue.

## Step 2 — Test Compaction

Invoke the `test-file-compaction` skill. Identify opportunities to
reduce test file size without losing coverage.

Express test-compaction opportunities as additional suggestions in the same
plan structure used in Step 1.

## Slice-mode Output

Produce a single, numbered list of suggestions that combines the results of
Step 1 and Step 2. For each item state:

1. **What** — what should change.
2. **Why** — why it improves the code.
3. **Priority** — low / medium / high.

Each suggestion should be concise. Refer to symbols and files by name instead
of quoting long code fragments.

Close with a one-line summary: how many suggestions are high, medium, and
low priority.

Add the completed improvement plan as a comment on the issue, clearly
labelled as the review plan for issue $ARGUMENTS.

---

# PRD-mode — 5-axis capstone review

PRD-mode reviews an entire delivered PRD: the union of all merged slices
since the PRD was recorded. It is a **strategic** review, not a per-file
code review — focus on whether the PRD was delivered coherently.

## Step 0 — Strict gating

Refuse to run while any slice of this PRD is still open. Query:

```bash
gh issue list --label slice --state open \
  --search "in:body \"Parent PRD\" \"#$ARGUMENTS\""
```

If any rows return, stop and tell the user:

> PRD-review blocked: slices still open (#A, #B, #C…). Ship or abandon
> them (apply the `abandoned` label) before re-running.

Also honor the `abandoned` label: abandoned slices are excluded from the
open check (`--state open` already excludes closed ones; ensure any
`abandoned`-labelled open issues are either closed or re-opened as slice
work — if they are open and labelled `abandoned`, treat as closed for this
gate and warn the user).

## Step 1 — Resolve the PRD base

The PRD body, written by `prd-from-grill-me`, contains a line:

```
**PRD base SHA:** <sha>
```

And a matching git tag `prd-<issue>-base` pointing to that SHA.

```bash
PRD_BASE=$(git rev-parse "prd-$ARGUMENTS-base" 2>/dev/null)
if [ -z "$PRD_BASE" ]; then
  # Fallback: parse from PRD body
  PRD_BASE=$(gh issue view $ARGUMENTS --json body -q .body \
    | grep -oP 'PRD base SHA:\s*\K[0-9a-f]{7,40}')
fi
echo "PRD_BASE: $PRD_BASE"
```

If neither source resolves, stop and ask the user for the base SHA.

## Step 2 — Compute the delivered diff

```bash
git diff "$PRD_BASE..HEAD" --stat > /tmp/prd-$ARGUMENTS-stat.txt
git diff "$PRD_BASE..HEAD"       > /tmp/prd-$ARGUMENTS-diff.patch
wc -l /tmp/prd-$ARGUMENTS-diff.patch
```

**Soft warning.** If the diff touches > 50 files OR > 5000 added lines,
emit:

> Warning: delivered diff is large (<N> files, <M> added lines). The
> capstone review will still run, but consider whether some themes could
> have been split into separate PRDs.

Continue regardless.

## Step 3 — Check for prior review (idempotent delta-review)

```bash
gh issue view $ARGUMENTS --json comments \
  -q '.comments[] | select(.body|contains("<prd-review for=")) | .body' \
  > /tmp/prd-$ARGUMENTS-prior.md
wc -l /tmp/prd-$ARGUMENTS-prior.md
```

If prior review exists and non-empty:

- Extract the SHA it reviewed against (look for `reviewed-at="<sha>"`
  attribute in the prior `<prd-review>` tag).
- If that SHA equals current `HEAD`, tell the user: *"PRD already reviewed
  at this SHA. Nothing new to review."* and stop.
- Otherwise compute the **delta diff** (`<prior-sha>..HEAD`) and review
  only the delta. Carry over prior-review findings that are still
  unresolved (not yet applied) so the user sees a cumulative view.

## Step 4 — Five-axis review (axis-by-axis, not file-by-file)

Do **not** read any slice-level plans, implementation logs, or slice-level
review comments. The capstone reviews the delivered code against the PRD's
original intent, not against intermediate artifacts.

Inputs: PRD body, `/tmp/prd-$ARGUMENTS-stat.txt`, and the diff patch file
(read hunks with `awk` or ranged reads — never `cat` the full patch).

Work one axis at a time. For each axis, append findings to
`/tmp/review-$ARGUMENTS-findings.md`:

### Axis 1 — Alignment

Does the delivered code match what the PRD said it would deliver? Look for
user stories or acceptance criteria that are not reflected in the diff,
and for code that doesn't correspond to anything the PRD described.

### Axis 2 — Scope

Did the implementation stay within scope? Flag obvious scope-creep
(features, refactors, or infrastructure not mentioned in the PRD). Flag
obvious scope-cuts (PRD requirements quietly dropped).

### Axis 3 — Architectural coherence

Do the slices together form a coherent architecture, or do they show
patches-on-patches? Look for: duplicated abstractions across slices,
inconsistent module boundaries, mixed paradigms, dead or orphaned code
paths.

### Axis 4 — Test strategy

Does the test coverage match the risk surface described in the PRD? Flag
critical user stories without E2E coverage, integration gaps between
slice boundaries, and test patterns that drifted across slices.

### Axis 5 — Ops readiness

Does the delivered system acknowledge the operational concerns the PRD
raised (or should have raised)? Logging, observability, rollback, config,
failure modes, degraded behavior.

### Hunk-level reads

When a finding needs code context, read only the relevant hunks:

```bash
awk '/^diff --git .*<path>/{p=1} p{print} /^diff --git/ && !/<path>/ && p{exit}' \
  /tmp/prd-$ARGUMENTS-diff.patch
```

Or read the file at HEAD with a line range around the change. Never load
full files or full patches.

## Step 5 — Output

Post a single comment on the PRD issue using this XML-anchored structure.
The anchors let future `apply` runs extract findings deterministically.

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
<finding id="F2" severity="medium">...</finding>
</axis>

<axis name="scope">
<finding id="F3" severity="low">...</finding>
</axis>

<axis name="architectural-coherence">
...
</axis>

<axis name="test-strategy">
...
</axis>

<axis name="ops-readiness">
...
</axis>

<counts>
critical: 0 | high: 2 | medium: 3 | low: 4
</counts>

</prd-review>
```

Finding IDs are globally unique across axes (F1, F2, F3…) so `apply` can
reference them without axis qualifier. Severity levels: `critical`,
`high`, `medium`, `low`.

If no findings in any axis, emit a minimal `<prd-review>` with just the
`<summary>` and `<counts>` (all zeros), and tell the user:

> PRD #$ARGUMENTS reviewed. No findings. Run `/stenswf:apply $ARGUMENTS`
> to finalize: it will detect the zero-findings review, apply the
> `applied` label, and close the PRD (no cleanup PR is opened).
