# Slice-mode — per-slice change review

Review staged changes against issue number $ARGUMENTS.

**Hard constraint — plan-only.** Read-only against the codebase and
plan artifacts. The only files this mode may create or modify are
under `.stenswf/$ARGUMENTS/review/` and `/tmp/`. No `git add`, no
`git commit`, no `gh issue comment`, no edits to source/test files,
no edits to plan fragments outside `review/`. `decisions.md` is
read-only; undocumented decisions surface as findings.

## Step 0 — Synthesize conventions if missing (lite-path support)

If `.stenswf/$ARGUMENTS/conventions.md` is absent (common on the lite
path where `plan`/`plan-light` didn't run or was skipped), synthesize
`.stenswf/$ARGUMENTS/conventions.synth.md` from available sources
before the four-perspective pass. Log provenance.

```bash
D=".stenswf/$ARGUMENTS"
mkdir -p "$D"

if [ -s "$D/conventions.md" ]; then
  CONV_FILE="$D/conventions.md"
else
  # Always regenerate .synth from current PRD; prefer real file when present.
  PRD_REF=$(get_fm prd_ref /tmp/slice-$ARGUMENTS.md)
  SYNTH="$D/conventions.synth.md"

  {
    printf '<!-- synthesized by review/slice. Sources: '
    [ -n "$PRD_REF" ] && printf 'PRD#%s, ' "$PRD_REF"
    printf 'slice body -->\n\n'

    # 1) From issue body's `## Conventions (from PRD)` section.
    extract_section 'Conventions \(from PRD\)' /tmp/slice-$ARGUMENTS.md

    # 2) If PRD_REF is set and resolves, append current PRD `## Conventions`.
    if [ -n "$PRD_REF" ]; then
      gh issue view "$PRD_REF" --json body -q .body > /tmp/prd-$PRD_REF.md 2>/dev/null \
        && extract_section 'Conventions' /tmp/prd-$PRD_REF.md
    fi
  } > "$SYNTH"

  CONV_FILE="$SYNTH"
  bash plugins/stenswf/scripts/log-issue.sh missing_artifact \
    "synthesized conventions for lite-path review" \
    "$SYNTH" || true
fi
```

Downstream passes read `$CONV_FILE` — transparent to both real and
synthesized conventions.

## Step 1 — Change Review (inline four-perspective critique)

Inputs (read ranged, not full):

- Staged diff: `git diff --staged > /tmp/review-$ARGUMENTS-staged.patch`.
- Issue body: `/tmp/slice-$ARGUMENTS.md`.
- `$CONV_FILE` (real or synthesized).
- `.stenswf/$ARGUMENTS/acceptance-criteria.md` if present.
- `.stenswf/$ARGUMENTS/decisions.md` — active entries only
  (`grep -E '^### D[0-9]+ '`). Superseded (`### ~~D<n>~~`) ignored.
  Absence is a context note, not a finding.
- `.stenswf/$ARGUMENTS/lite-notes.md` if present (lite-path assumptions
  from `plan-light` / `ship-light`). Treated as **soft constraints**:
  a staged change that contradicts a listed assumption is Low/Info
  unless it also contradicts `decisions.md` or an AC (then normal
  severity rules apply). Absence is a context note.
- `.stenswf/$ARGUMENTS/file-structure.md` if present (architectural context).

### Define success

Write one sentence to `/tmp/review-$ARGUMENTS-findings.md`:

> This slice succeeds if [outcome, derived from ACs].

### Architect gate (rule-based)

```bash
NAMES=$(git diff --staged --name-only)
NEW_NAMES=$(git diff --staged --name-status | awk '$1=="A"{print $2}')
FILE_COUNT=$(printf '%s\n' "$NAMES" | grep -c . || true)
TOP_DIRS=$(printf '%s\n' "$NAMES" | awk -F/ 'NF>1{print $1}' | sort -u | wc -l)
DEP_HIT=$(echo "$NAMES" | grep -E '(^|/)(package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|go\.mod|go\.sum|requirements[^/]*\.txt|Pipfile(\.lock)?|pyproject\.toml|Cargo\.(toml|lock)|pom\.xml|build\.gradle(\.kts)?|Gemfile(\.lock)?|composer\.(json|lock)|mix\.exs|Podfile(\.lock)?)$' | head -1)
NEW_SRC=$(echo "$NEW_NAMES" | grep -E '^(src|lib|pkg|cmd|internal|app|apps|packages|services)/' | head -1)

if [ "$FILE_COUNT" -ge 3 ] && [ "$TOP_DIRS" -ge 2 ]; then
  ARCH_GATE=on
elif [ -n "$NEW_SRC" ] || [ -n "$DEP_HIT" ]; then
  ARCH_GATE=on
else
  ARCH_GATE=off
fi
echo "Architect gate: $ARCH_GATE"
```

### Four perspectives (axis-by-axis; do not collapse)

**Guard:** If a perspective has no significant findings, say so
explicitly. Do not invent issues.

**Perspective 1 — DevOps / SRE.** Deployment complexity, operability
(logging, observability, rollback, config), what breaks first in prod,
silent assumptions about external services.

**Perspective 2 — Peer Reviewer.** Logical contradictions, problem-vs-proxy,
E2E coverage of user-facing paths, edge cases, simpler approach ignored,
and **Plan / AC / decision deviation** — does staged diff match issue
body + `$CONV_FILE` + `acceptance-criteria.md` + active `decisions.md`?
Plan deviations tagged **High** by default. Decision-anchor contradictions:
`arch` → **High**, `decision` → **Medium** (→ **High** if `Refs:`
contains `AC#`). Superseded entries are not findings.

**Peer must produce an AC coverage matrix** — one row per AC, tagged
`covered | partially covered | not covered` with `file:line` citation.
`partially covered` auto-promotes to **High** or **Medium**.
`not covered` auto-promotes to **High**. If `acceptance-criteria.md`
absent or empty, skip the matrix (note absence as a context line).

**Perspective 3 — Security Engineer.** Realistic threat surface, new
trust boundaries, secrets, new dependencies. No enterprise checklist
padding.

**Perspective 4 — Software Architect.** *Only if `ARCH_GATE=on`.*
Structural fit, coupling, abstraction level, doc updates required.

If `ARCH_GATE=off`: one line — `Architect: skipped (diff below structural threshold).`

### Severity guide

- **Critical** — data loss, security breach, or crash on happy path.
- **High** — incorrect behavior, runtime bug, or plan deviation.
- **Medium** — maintainability, clarity, coverage gap with real cost.
- **Low** — nit, style.

## Slice-mode Output

Single numbered list of suggestions. Per item:

1. **What:** what should change.
2. **Why:** why it improves the code.
3. **Priority:** `high` | `medium` | `low` — each on its own line as
   `**Priority:** <level>` (schema check below depends on this).

Include the AC coverage matrix (if produced) as its own section above
the suggestions. Close with: `Summary: N high | M medium | K low`.

Write to `.stenswf/$ARGUMENTS/review/slice.md`:

```
# Review plan for issue <N>

## AC coverage matrix
<!-- omit entire section if acceptance-criteria.md was absent -->

## Suggestions
1. **What:** …
   **Why:** …
   **Priority:** high

Summary: N high | M medium | K low
```

### Schema validation (self-check)

```bash
OUT=".stenswf/$ARGUMENTS/review/slice.md"
grep -q '^## Suggestions' "$OUT" || { echo "schema: missing Suggestions"; exit 1; }
HIGH=$(grep -cE '\*\*Priority:\*\*[[:space:]]*high'    "$OUT" || true)
MED=$(grep -cE  '\*\*Priority:\*\*[[:space:]]*medium'  "$OUT" || true)
LOW=$(grep -cE  '\*\*Priority:\*\*[[:space:]]*low'     "$OUT" || true)
SUM=$(grep -oE 'Summary:[[:space:]]*[0-9]+[[:space:]]*high[[:space:]]*\|[[:space:]]*[0-9]+[[:space:]]*medium[[:space:]]*\|[[:space:]]*[0-9]+[[:space:]]*low' "$OUT")
[ -n "$SUM" ] || { echo "schema: missing Summary"; exit 1; }
SH=$(echo "$SUM" | grep -oE '[0-9]+[[:space:]]*high'   | grep -oE '[0-9]+')
SM=$(echo "$SUM" | grep -oE '[0-9]+[[:space:]]*medium' | grep -oE '[0-9]+')
SL=$(echo "$SUM" | grep -oE '[0-9]+[[:space:]]*low'    | grep -oE '[0-9]+')
[ "$HIGH" = "$SH" ] && [ "$MED" = "$SM" ] && [ "$LOW" = "$SL" ] \
  || { echo "schema: Summary counts mismatch (found H=$HIGH M=$MED L=$LOW vs summary H=$SH M=$SM L=$SL)"; exit 1; }
```

If `acceptance-criteria.md` was present, also require `## AC coverage matrix`.

Tell the user:

> Slice review written to `.stenswf/$ARGUMENTS/review/slice.md`. Run
> `/stenswf:apply $ARGUMENTS` to walk suggestions interactively.

Emit the feedback-log boundary ping.
