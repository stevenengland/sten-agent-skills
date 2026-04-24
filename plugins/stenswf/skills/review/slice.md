# Slice-mode — per-slice change review

Review staged changes against issue number $ARGUMENTS.

**Hard constraint — plan-only.** Slice-mode review is read-only against
the codebase and the plan artifacts. Do NOT invoke `stenswr:plan-reviewer`
— it implements, which violates this skill's plan-only contract. The
only files this mode may create or modify are under
`.stenswf/$ARGUMENTS/review/` and `/tmp/`. No `git add`, no `git commit`,
no `gh issue comment`, no edits to source or test files, no edits to
plan fragments under `.stenswf/$ARGUMENTS/` outside the `review/`
subdirectory. `decisions.md` is read-only; undocumented decisions
surface as findings in `review/slice.md` for `apply` to override.

## Step 1 — Change Review (inline four-perspective critique)

Inputs (read, do not cat into context wholesale — use `awk` / ranged
reads):

- Staged diff: `git diff --staged > /tmp/review-$ARGUMENTS-staged.patch`.
- Issue body: `/tmp/slice-$ARGUMENTS.md` (fetched in SKILL.md mode detection).
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

### Architect gate (rule-based)

The Architect perspective only fires when the diff has real structural
signal. Compute once, before the perspectives:

```bash
# Files changed and their top-level directories
NAMES=$(git diff --staged --name-only)
NEW_NAMES=$(git diff --staged --name-status | awk '$1=="A"{print $2}')
FILE_COUNT=$(printf '%s\n' "$NAMES" | grep -c . || true)
TOP_DIRS=$(printf '%s\n' "$NAMES" | awk -F/ 'NF>1{print $1}' | sort -u | wc -l)

# Dependency manifests (any ecosystem)
DEP_HIT=$(echo "$NAMES" | grep -E '(^|/)(package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|go\.mod|go\.sum|requirements[^/]*\.txt|Pipfile(\.lock)?|pyproject\.toml|Cargo\.(toml|lock)|pom\.xml|build\.gradle(\.kts)?|Gemfile(\.lock)?|composer\.(json|lock)|mix\.exs|Podfile(\.lock)?)$' | head -1)

# New files under plausible source roots
NEW_SRC=$(echo "$NEW_NAMES" | grep -E '^(src|lib|pkg|cmd|internal|app|apps|packages|services)/' | head -1)

if [ "$FILE_COUNT" -ge 3 ] && [ "$TOP_DIRS" -ge 2 ]; then
  ARCH_GATE=on
elif [ -n "$NEW_SRC" ] || [ -n "$DEP_HIT" ]; then
  ARCH_GATE=on
else
  ARCH_GATE=off
fi
```

Announce: `Architect gate: $ARCH_GATE`.

### Four perspectives (one at a time; do not collapse)

Work axis-by-axis. For each pass, append findings to
`/tmp/review-$ARGUMENTS-findings.md` tagged with the perspective. Stay in
scope per perspective — if you notice an issue belonging to another
perspective, jot `→ <Perspective>` and handle it in that pass.

**Guard (applies to every perspective):** If you find nothing
significant in a perspective, say so clearly — do not invent issues to
appear thorough. An explicit "no findings" line is a valid result.

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

**Peer must produce an AC coverage matrix** — one row per AC in
`acceptance-criteria.md`, tagged `covered | partially covered | not
covered`:

- `covered` — cite `file:line` in the staged diff that implements it.
- `partially covered` — cite file:line, then name the gap. Auto-promotes
  to a finding at **High** or **Medium** depending on gap severity.
- `not covered` — auto-promotes to a finding at **High**.

If `acceptance-criteria.md` is absent or empty, skip the matrix and note
its absence as a context line (not a finding).

**Perspective 3 — Security Engineer.** Realistic threat surface for this
project, new trust boundaries or exposed interfaces, secrets and
credential handling, new dependencies' trust/patch surface. Do not apply
an enterprise checklist to a small project.

**Perspective 4 — Software Architect.** *Only run if `ARCH_GATE=on`.*
Structural fit, unnecessary coupling, abstraction level, whether the
design serves the project's stated priorities, documentation updates
(README/ADRs/API docs) required by these changes, rewrite cost if the
most likely next requirement arrives.

If `ARCH_GATE=off`, write one line to findings:
`Architect: skipped (diff below structural threshold).`

### Severity guide

- **Critical** — data loss, security breach, or crash on the happy path.
- **High** — incorrect behaviour, likely runtime bug, or plan deviation.
- **Medium** — maintainability, clarity, or coverage gap with real cost.
- **Low** — nit, style, minor readability.

## Slice-mode Output

Produce a single, numbered list of suggestions from the four perspectives
above. For each item:

1. **What:** what should change.
2. **Why:** why it improves the code.
3. **Priority:** `high` | `medium` | `low` (exact token, bolded key).

Each suggestion must emit `**Priority:** <level>` on its own line —
the schema check below depends on this literal form.

Include the AC coverage matrix (if produced) as its own section above
the suggestions. Close with a one-line summary: counts of high / medium
/ low priority.

**Write locally** — not as an issue comment:

The artifact structure (substitute `$ARGUMENTS` and fill sections
before writing — this is a skeleton, not a literal heredoc):

```
# Review plan for issue <N>

## AC coverage matrix
<one row per AC; covered / partially covered / not covered, with file:line>
<!-- omit the entire section if acceptance-criteria.md was absent -->

## Suggestions
1. **What:** …
   **Why:** …
   **Priority:** high

2. **What:** …
   **Why:** …
   **Priority:** medium

Summary: N high | M medium | K low
```

Write it with `mkdir -p .stenswf/$ARGUMENTS/review` then a standard
write of the filled-in content to `.stenswf/$ARGUMENTS/review/slice.md`.

### Schema validation (self-check)

Before announcing completion, validate the artifact:

```bash
OUT=".stenswf/$ARGUMENTS/review/slice.md"
grep -q '^## Suggestions' "$OUT" || { echo "schema: missing Suggestions section"; exit 1; }
HIGH=$(grep -cE '\*\*Priority:\*\*\s*high'    "$OUT" || true)
MED=$(grep -cE  '\*\*Priority:\*\*\s*medium'  "$OUT" || true)
LOW=$(grep -cE  '\*\*Priority:\*\*\s*low'     "$OUT" || true)
SUM=$(grep -oE 'Summary:\s*[0-9]+\s*high\s*\|\s*[0-9]+\s*medium\s*\|\s*[0-9]+\s*low' "$OUT")
[ -n "$SUM" ] || { echo "schema: missing Summary line"; exit 1; }
SH=$(echo "$SUM" | grep -oE '[0-9]+\s*high'   | grep -oE '[0-9]+')
SM=$(echo "$SUM" | grep -oE '[0-9]+\s*medium' | grep -oE '[0-9]+')
SL=$(echo "$SUM" | grep -oE '[0-9]+\s*low'    | grep -oE '[0-9]+')
[ "$HIGH" = "$SH" ] && [ "$MED" = "$SM" ] && [ "$LOW" = "$SL" ] \
  || { echo "schema: Summary counts mismatch (found H=$HIGH M=$MED L=$LOW vs summary H=$SH M=$SM L=$SL)"; exit 1; }
```

If `acceptance-criteria.md` was present, also require `## AC coverage matrix`.

Tell the user:

> Slice review written to `.stenswf/$ARGUMENTS/review/slice.md`. Run
> `/stenswf:apply $ARGUMENTS` to walk suggestions interactively.
