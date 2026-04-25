---
name: prd-to-issues
description: Break a PRD into independently-grabbable issues using tracer-bullet vertical slices.
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

### 5b. Pre-finalize reflection (before issues become durable)

Issues are the durable input to every later workflow stage; bad
slicing propagates everywhere. Pause and step back:

- Did any slice silently turn into a *horizontal layer* (DB-only,
  API-only, UI-only) instead of a tracer bullet through every layer?
- Did any "AFK" slice actually hide a HITL judgment call that the
  implementer would re-litigate?
- Are any `blocked_by` chains forming a critical path that should be
  collapsed into one slice, or split further?
- Did any slice exceed the Lite envelope without a recorded
  disqualifier?

If the answer changes the slice set, revise and re-quiz the user
before step 6.

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

Run the shared script:

```bash
bash plugins/stenswf/scripts/inherit-decisions.sh <prd-number> <slice-numbers...>
```

The script walks `.stenswf/<prd-number>/decisions.md`, copies active
entries as reference stubs into each slice's `decisions.md` (creating
the file with a seed header if absent), and preserves `Refs:` verbatim.
Strikethrough (superseded) entries are skipped. Silent on success.

Inherited stubs are frozen at slice-creation time — later PRD
supersessions do not retroactively update slice anchors. See
[../../references/decision-anchor-link.md](../../references/decision-anchor-link.md).

---

## Feedback

Log workflow friction per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=prd-to-issues`.
