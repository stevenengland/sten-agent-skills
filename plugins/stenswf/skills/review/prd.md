# PRD-mode — 5-axis capstone review

**Ceremony invariant (TDD-as-lens).** This mode MUST NOT (a)
instruct skipping tests for ACs annotated `(behavior)`, (b) remove
`tdd` from any SKILLS TO LOAD list, (c) accept `manual check` or
"rely on existing suite" as completion evidence for a `(behavior)`
AC, or (d) emit guidance that contradicts `tdd/SKILL.md`. Detection
of behavior change is the gate; loading `tdd` is the lens; whether
to write a test follows from the AC tag, not from this skill. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

PRD-mode reviews an entire delivered PRD: the union of all merged
slices since the PRD was recorded. Strategic review, not per-file.

## Step 0 — Strict gating

Refuse to run while any slice of this PRD is still open:

```bash
gh issue list --state open \
  --search "in:body \"Parent PRD\" \"#$ARGUMENTS\"" \
  --json number,title
```

If any rows return, stop:

> PRD-review blocked: slices still open (#A, #B, …). Ship them first.

Abandoned slices should be manually closed
(`gh issue close <N> --reason "not planned"`).

## Step 1 — Resolve the PRD base

Resolved exclusively from the PRD issue front-matter `prd_base_sha`:

```bash
source plugins/stenswf/scripts/extractors.sh
PRD_BASE=$(get_fm prd_base_sha "/tmp/slice-$ARGUMENTS.md")
[ -n "$PRD_BASE" ] || { echo "PRD #$ARGUMENTS missing prd_base_sha in front-matter" >&2; exit 1; }
```

## Step 2 — Compute the delivered diff

```bash
mkdir -p ".stenswf/$ARGUMENTS/review"
git diff "$PRD_BASE..HEAD" --stat > "/tmp/prd-$ARGUMENTS-stat.txt"
git diff "$PRD_BASE..HEAD"       > "/tmp/prd-$ARGUMENTS-diff.patch"
wc -l "/tmp/prd-$ARGUMENTS-diff.patch"
```

**Soft warning** if diff > 50 files OR > 5000 added lines.

## Step 3 — Check for prior review (idempotent delta)

```bash
if [ -s ".stenswf/$ARGUMENTS/review/prd-review.xml" ]; then
  PRIOR_SHA=$(grep -oE 'reviewed-at="[0-9a-f]+' \
    ".stenswf/$ARGUMENTS/review/prd-review.xml" \
    | awk -F'"' '{print $2}' | head -1)
fi
```

If prior review at current HEAD: tell user and stop. Otherwise compute
delta diff `<prior-sha>..HEAD` and review only the delta. Carry forward
unresolved prior findings.

## Step 4 — Five-axis review (axis-by-axis)

Do NOT read slice-level plans, logs, or slice review comments. Capstone
reviews delivered code against PRD intent.

**Guard:** No findings on an axis → say so. Do not invent.

**Exception — decision anchors.** Axis 1 aggregates active entries
from all slice anchors (live or archived):

```bash
for S in $(gh issue list --state closed \
            --search "in:body \"Parent PRD\" \"#$ARGUMENTS\"" \
            --json number -q '.[].number'); do
  ANCHOR=".stenswf/$S/decisions.md"
  [ ! -s "$ANCHOR" ] && ANCHOR=$(ls -1 .stenswf/.archive/$S-*/decisions.md 2>/dev/null | head -1)
  [ -n "$ANCHOR" ] && [ -s "$ANCHOR" ] && grep -hE '^### D[0-9]+ ' "$ANCHOR"
done
```

Inputs: PRD body, `/tmp/prd-$ARGUMENTS-stat.txt`, diff patch (read
ranged). Never `cat` the full patch.

### Axis 1 — Alignment

Delivered code matches PRD intent? User stories / ACs not reflected?
Code with no PRD basis?

**User-story / AC coverage matrix.** Row per PRD user story / AC:
`covered | partially covered | not covered` with `file:line`.
`not covered` → **High**. `partially covered` → **Medium**. Skip matrix
if PRD has no enumerated stories/ACs.

### Axis 2 — Scope

Scope-creep or scope-cuts?

### Axis 3 — Architectural coherence

Slices form a coherent architecture? Duplicated abstractions, mixed
paradigms, dead code?

### Axis 4 — Test strategy

Coverage matches PRD risk surface? Critical stories without E2E? Gaps?
Implementation-coupled tests across the delivered slices (per
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md)
bad-test audit) — list as findings; behavior coverage MUST NOT drop.

### Axis 5 — Ops readiness

Logging, observability, rollback, config, failure modes.

### Hunk-level reads

```bash
awk '/^diff --git .*<path>/{p=1} p{print} /^diff --git/ && !/<path>/ && p{exit}' \
  /tmp/prd-$ARGUMENTS-diff.patch
```

Or ranged reads at HEAD. Never full files/patches.

## Step 5 — Output

Write `.stenswf/$ARGUMENTS/review/prd-review.xml`:

```xml
<prd-review for="#$ARGUMENTS" reviewed-at="<HEAD SHA>" base="<PRD_BASE>">
<summary>One paragraph: what was delivered, judgment, top concern.</summary>

<coverage-matrix>
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

<counts>critical: 0 | high: 2 | medium: 3 | low: 4</counts>
</prd-review>
```

### Schema validation (self-check)

Portable (no `xmllint` dependency):

```bash
OUT=".stenswf/$ARGUMENTS/review/prd-review.xml"
grep -q '<summary>' "$OUT" || { echo "schema: missing <summary>"; exit 1; }
grep -q '<counts>'  "$OUT" || { echo "schema: missing <counts>"; exit 1; }
# Balanced root tags (cheap structural check).
grep -c '<prd-review'  "$OUT" | grep -q '^1$' || { echo "schema: <prd-review> count != 1"; exit 1; }
grep -c '</prd-review>' "$OUT" | grep -q '^1$' || { echo "schema: </prd-review> count != 1"; exit 1; }
# Unique finding IDs.
DUPES=$(grep -oE 'id="F[0-9]+"' "$OUT" | sort | uniq -d)
[ -z "$DUPES" ] || { echo "schema: duplicate finding IDs: $DUPES"; exit 1; }
# Every finding has a valid severity.
BAD=$(grep -oE '<finding[^>]*>' "$OUT" | grep -vE 'severity="(critical|high|medium|low)"' || true)
[ -z "$BAD" ] || { echo "schema: finding without valid severity"; exit 1; }
# Optional XML well-formedness (if xmllint available).
command -v xmllint >/dev/null 2>&1 && xmllint --noout "$OUT" 2>/dev/null \
  || true   # do not fail when xmllint is not installed
```

### Zero findings path

Minimal `<prd-review>` with `<summary>` and `<counts>` (zeros only):

> PRD #$ARGUMENTS reviewed. No findings. Run `/stenswf:apply $ARGUMENTS`
> to finalize (no cleanup PR will be opened).

When `apply` opens the cleanup PR, it mirrors `<prd-review>` onto the
PR. `review` itself does not touch the PR.

No labels applied anywhere.

Emit the feedback-log boundary ping.
