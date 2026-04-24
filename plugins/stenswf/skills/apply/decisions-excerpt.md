# Decisions excerpt (PRD-mode curation)

Curate the team-visible library of durable decisions from this PRD and
stage it into the cleanup PR. Silent; no user prompt. See
[Decision Anchor Contract](../../README.md#decision-anchor-contract)
for the curation filter (active ∩ {arch, decision} ∩ has file-path Refs).

```bash
mkdir -p docs/stenswf/decisions
EXCERPT="docs/stenswf/decisions/prd-$ARGUMENTS.md"
TITLE=$(gh issue view $ARGUMENTS --json title -q .title)
DATE=$(date -u +%Y-%m-%d)

# Closed slices of this PRD
SLICES=$(gh issue list --state closed \
  --search "in:body \"Parent PRD\" \"#$ARGUMENTS\"" \
  --json number -q '.[].number')

# Extract ACTIVE arch/decision entries with at least one file-path Ref
# from one anchor. Active = header `### D<n> ` (strikethrough won't match).
# Entries bounded by next `### ` or EOF.
curate_anchor() {
  awk '
    function flush() {
      if (have && (category=="arch" || category=="decision") && hasref) print block
      block=""; category=""; hasref=0; have=0
    }
    /^### / {
      flush()
      if ($0 ~ /^### D[0-9]+ /) { block=$0 "\n"; have=1 }
      next
    }
    have {
      block = block $0 "\n"
      if ($0 ~ /^- \*\*Category:\*\* (arch|decision)/) {
        category=$0; sub(/.*Category:\*\* */,"",category)
      }
      if ($0 ~ /^- \*\*Refs:\*\*.*\//) hasref=1
    }
    END { flush() }
  ' "$1"
}

{
  printf '# Decisions — PRD #%s: %s\n\n' "$ARGUMENTS" "$TITLE"
  printf '*Curated from slice anchors on %s.*\n\n' "$DATE"

  # PRD's own anchor (live or archived)
  for SRC in ".stenswf/$ARGUMENTS/decisions.md" \
             $(ls -1 .stenswf/.archive/$ARGUMENTS-*/decisions.md 2>/dev/null); do
    [ -s "$SRC" ] && curate_anchor "$SRC"
  done

  # Per-slice anchors
  for S in $SLICES; do
    SRC=".stenswf/$S/decisions.md"
    [ -s "$SRC" ] || SRC=$(ls -1 .stenswf/.archive/$S-*/decisions.md 2>/dev/null | head -1)
    [ -n "$SRC" ] && [ -s "$SRC" ] || continue
    printf '\n<!-- from slice #%s -->\n\n' "$S"
    curate_anchor "$SRC"
  done
} > "$EXCERPT"
```

Commit as its own commit on the cleanup branch:

```bash
if [ -s "$EXCERPT" ]; then
  git add "$EXCERPT"
  git commit -m "docs(stenswf): curated decisions for PRD #$ARGUMENTS"
else
  # No qualifying entries (unusual) — remove empty file.
  rm -f "$EXCERPT"
fi
```
