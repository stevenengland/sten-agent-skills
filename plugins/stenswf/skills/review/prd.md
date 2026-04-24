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

**Guard (applies to every axis):** If an axis has no findings, say so
clearly — do not invent issues to appear thorough. An explicit "no
findings" line is a valid result.

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

**User-story / AC coverage matrix.** If the PRD body enumerates user
stories or acceptance criteria, produce one row per item tagged
`covered | partially covered | not covered`, each with at least one
`file:line` citation for `covered` / `partially covered`. `not covered`
and `partially covered` auto-promote to findings (High / Medium
respectively). If the PRD has no enumerated stories or ACs, skip the
matrix and note its absence.

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

<coverage-matrix>
  <!-- one row per PRD user story / AC; omit entire element if PRD had none -->
  <row id="US1" status="covered" evidence="src/foo.ts:42"/>
  <row id="US2" status="partially covered" evidence="src/bar.ts:10" gap="error path missing"/>
  <row id="US3" status="not covered"/>
</coverage-matrix>

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

### Schema validation (self-check)

Before announcing completion, validate the artifact:

```bash
OUT=".stenswf/$ARGUMENTS/review/prd-review.xml"
xmllint --noout "$OUT" 2>/dev/null || { echo "schema: malformed XML"; exit 1; }
grep -q '<summary>' "$OUT" || { echo "schema: missing <summary>"; exit 1; }
grep -q '<counts>'  "$OUT" || { echo "schema: missing <counts>"; exit 1; }
# Finding IDs must be unique
DUPES=$(grep -oE 'id="F[0-9]+"' "$OUT" | sort | uniq -d)
[ -z "$DUPES" ] || { echo "schema: duplicate finding IDs: $DUPES"; exit 1; }
# All findings carry a severity
grep -oE '<finding[^>]*>' "$OUT" | grep -vE 'severity="(critical|high|medium|low)"' \
  && { echo "schema: finding without valid severity"; exit 1; } || true
```

### Mirror a human-readable summary to a PR comment (if any findings)

When `apply` opens the cleanup PR, it will post the `<prd-review>` content
as a PR comment (local authoritative + PR mirror for team visibility).
`review` itself does not touch the PR — but this contract is why the
file is written in stable XML.

If **zero findings**, emit a minimal `<prd-review>` with just `<summary>`
and `<counts>` (all zeros), write it to disk, and tell the user:

> PRD #$ARGUMENTS reviewed. No findings. Run `/stenswf:apply $ARGUMENTS`
> to finalize (no cleanup PR will be opened).

No labels are applied anywhere.
