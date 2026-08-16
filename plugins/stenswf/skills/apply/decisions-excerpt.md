# Decisions excerpt (PRD-mode curation)

Curate the team-visible library of **major decisions** from
this PRD and stage it into the cleanup PR. Requires user confirmation
before persisting. See
[Decision Anchor Contract](../../README.md#decision-anchor-contract)
for the curation filter (active ∩ {arch, decision} ∩ has file-path Refs).

`arch` entries are the focus of the curation. `decision` entries are
valuable during the slice lifecycle but rarely justify a permanent
excerpt. Therefore mention them defensively if you think they might represent major decisions and await approval of what shall be persisted.

## Generate the candidate excerpt

Curation and the live-or-archived anchor lookup both live in
[../../scripts/publish-decisions.sh](../../scripts/publish-decisions.sh).
`render --excerpt` applies exactly the filter above; the same script
renders the unfiltered block that `ship` / `ship-light` publish to the
PR and issue.

```bash
mkdir -p docs/stenswf/decisions
EXCERPT="docs/stenswf/decisions/prd-$ARGUMENTS.md"
TITLE=$(gh issue view $ARGUMENTS --json title -q .title)
DATE=$(date -u +%Y-%m-%d)

# Closed slices of this PRD
SLICES=$(gh issue list --state closed \
  --search "in:body \"Parent PRD\" \"#$ARGUMENTS\"" \
  --json number -q '.[].number')

{
  printf '# Decisions — PRD #%s: %s\n\n' "$ARGUMENTS" "$TITLE"
  printf '*Curated from slice anchors on %s.*\n\n' "$DATE"

  # PRD's own anchor
  bash ../../scripts/publish-decisions.sh render --excerpt "$ARGUMENTS"

  # Per-slice anchors
  for S in $SLICES; do
    OUT=$(bash ../../scripts/publish-decisions.sh render --excerpt "$S")
    [ -n "$OUT" ] || continue
    printf '\n<!-- from slice #%s -->\n\n' "$S"
    printf '%s\n' "$OUT"
  done
} > "$EXCERPT"
```

Inherited stubs are dropped by the curated filter on their `inherited`
category — the PRD's own anchor is curated in its own right above, so
keeping the stubs would list every PRD decision twice.

## Confirm with the user

If the excerpt is non-empty, present it and ask for confirmation.
Skip the commit silently when no qualifying entries exist.

```markdown
The following major decisions were extracted for permanent
record in `docs/stenswf/decisions/prd-$ARGUMENTS.md`:

---
<contents of $EXCERPT>
---

Should these decisions be persisted into the repo?
- **(y)es** — commit as-is
- **(e)dit** — I'll adjust the excerpt, then re-confirm
- **(n)o** — discard, nothing will be committed

> Only major architectural calls belong here and carefully picked `decision`-category entries
```

On **(n)o**, remove the generated file and skip the commit:

```bash
rm -f "$EXCERPT"
```

On **(e)dit**, let the user modify `$EXCERPT` in the editor, then
re-present and re-confirm.

## Commit

On **(y)es** (or after a confirmed edit round):

```bash
if [ -s "$EXCERPT" ]; then
  git add "$EXCERPT"
  git commit -m "docs(stenswf): curated decisions for PRD #$ARGUMENTS"
else
  rm -f "$EXCERPT"
fi
```
