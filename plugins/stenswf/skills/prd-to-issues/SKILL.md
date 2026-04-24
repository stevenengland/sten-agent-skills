---
name: prd-to-issues
description: Break a PRD into independently-grabbable issues using tracer-bullet vertical
  slices.
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).

# PRD to Issues

Break a PRD into independently-grabbable issues using vertical slices
(tracer bullets).

## Process

### 1. Locate the PRD

**Fast-path:** if chained from `prd-from-grill-me`, skip fetch — note the
issue number and continue.

Otherwise, ask the user for the PRD issue number. Fetch via
`gh issue view` (or `glab`/`tea`). If no CLI, ask the user for content.

### 2. Explore the codebase (optional, via subagent)

**Fast-path:** if module exploration already happened this session, skip.

Otherwise dispatch an Explore subagent on ONLY the modules named in
the PRD's **Implementation Decisions** — primary source + most-relevant
test file per module. ≤300-word report. No wandering.

### 3. HITL triage

List every decision that would trigger a HITL slice. Classify each:

- **Bikeshed** (naming, shape, layout, error surfacing, vocabulary) →
  belongs in PRD `## Conventions`. If absent, warn and log
  `missing_artifact`; continue only if the PRD truly has no
  cross-cutting conventions (emit `conventions_source: none`).
- **Novel pattern** → either lock in PRD `## Conventions`, or introduce
  a spike slice (tiny AFK+Lite, lands types/vocabulary, no consumers).
- **Genuine judgment call** (irreducible) → keep HITL. Write an escape
  hatch into the slice.

Goal: zero HITL slices except irreducible judgment calls. Present the
triage table to the user for confirmation.

### 4. Draft vertical slices (Lite-first)

Each issue is a thin **tracer bullet** cutting through all layers
end-to-end. Default to the Lite envelope:

- ≤ 15 files changed (src + test combined)
- One top-level module directory
- No schema migration
- No unresolved architectural unknowns
- AFK-typed

Exceed only if genuinely irreducible.

Slice types: `HITL` | `AFK` | `spike`. Prefer AFK.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer.
- Completed slice is demoable or verifiable on its own.
- Prefer many thin slices over few thick ones.
</vertical-slice-rules>

### 5. Quiz the user

Present as numbered list. For each slice show: Title, Type (HITL/AFK/spike),
Blocked by, User stories covered, Lite-eligible (true/false + disqualifier
tag if false). Disqualifier tags: `files>15 | cross-module |
schema-migration | arch-unknown | hitl-cat3`.

Ask: granularity right? dependencies right? correct HITL/AFK? Lite
flags and disqualifiers correct? Iterate until approved.

> *Solo-dev assumption. On mid-batch failure, delete partial slice
> issues manually before re-running, or duplicates appear.*

### 6. Create the issues

Extract the PRD's `## Conventions` section via
[../../references/extractors.md](../../references/extractors.md):

```bash
gh issue view <prd-number> --json body -q .body > /tmp/prd-<prd-number>.md
extract_section 'Conventions' /tmp/prd-<prd-number>.md \
  > /tmp/prd-<prd-number>-conventions.md
wc -l /tmp/prd-<prd-number>-conventions.md
```

For each approved slice, create an issue using the template at
[../../references/issue-template.md](../../references/issue-template.md).
Inline the Conventions file where indicated.

Create in dependency order (blockers first) so real issue numbers can
be referenced in `blocked_by` front-matter.

No labels. No modifications to the parent PRD issue.

Slice front-matter shape (canonical — emit exactly this block at the
top of every slice body):

```
<!-- stenswf:v1
type: slice — AFK            # or: slice — HITL | slice — spike
lite_eligible: true          # or false with a disqualifier line
conventions_source: prd#<PRD-N>   # or "none" for slice-local only
prd_ref: <PRD-N>
# disqualifier: files>15     # required when lite_eligible: false
# blocked_by: 123 456        # optional, space-separated
-->
```

### 7. Update the PRD manifest with slice numbers

If `.stenswf/<prd-number>/manifest.json` exists:

```bash
PRD=<prd-number>
if [ -f ".stenswf/$PRD/manifest.json" ]; then
  for SLICE in <list>; do
    jq --argjson s "$SLICE" \
      '.slices = ((.slices // []) + [$s] | unique)' \
      ".stenswf/$PRD/manifest.json" > /tmp/prd-manifest.json \
      && mv /tmp/prd-manifest.json ".stenswf/$PRD/manifest.json"
  done
fi
```

### 7b. Seed inherited PRD decision stubs into each slice

For each created slice, copy active PRD anchor entries as reference
stubs per the
[Decision Anchor Contract](../README.md#decision-anchor-contract)
(inherited stubs carry no rationale; readers hop to
`.stenswf/<PRD>/decisions.md#D<n>` for the `why`):

```bash
PRD_SRC=".stenswf/<prd-number>/decisions.md"
[ -s "$PRD_SRC" ] || exit 0

for N in <slice-numbers>; do
  D=".stenswf/$N"
  mkdir -p "$D"
  if [ ! -f "$D/decisions.md" ]; then
    cat > "$D/decisions.md" <<EOF
# Decisions — #$N

<!-- Seeded by prd-to-issues from #<prd-number>. Schema: ../../plugins/stenswf/README.md#decision-anchor-contract -->

EOF
  fi

  # Active entries only (strikethrough ~~...~~ excluded by this pattern).
  awk '
    /^### D[0-9]+ / { inblock=1; buf=$0 ORS; next }
    inblock && /^### / { print buf; print "---\n"; inblock=0 }
    inblock { buf=buf $0 ORS; next }
    END { if (inblock) { print buf } }
  ' "$PRD_SRC" | awk -v P="<prd-number>" '
    /^### D[0-9]+ / {
      hdr=$0
      sub(/^### /, "", hdr)
      id=hdr; sub(/ .*/, "", id)
      title=hdr; sub(/^[^ ]+ — /, "", title)
      printf "### %s — %s (inherited from #%s)\n\n", id, title, P
      printf "- **Category:** inherited\n"
      printf "- **Source:** #%s/%s\n", P, id
      next
    }
    /^- \*\*Refs:\*\*/ { print; next }
    /^### / { printf "\n" }
  ' >> "$D/decisions.md"
done
```

Silent on success. Slice anchors now contain reference stubs for every
active PRD decision at slice-creation time.

---

## Feedback

Log workflow friction via
[../../references/feedback-log.md](../../references/feedback-log.md).
Set `STENSWF_SKILL=prd-to-issues` before calling
`scripts/log-issue.sh`.
