---
name: prd-to-issues
description: Break a PRD into independently-grabbable issues using tracer-bullet vertical
  slices.
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs dialogue, exploration narration, and slice reasoning. Issue
bodies (titles, descriptions, acceptance criteria) are full-prose artifacts
(already excluded by `brevity`'s Scope section) — write them normally.

---

# PRD to Issues

Break a PRD into independently-grabbable issues using vertical slices
(tracer bullets).

## Process

### 1. Locate the PRD

**Fast-path:** if the PRD is already in your context from a chained
`prd-from-grill-me` run in this session, skip the fetch — note the issue
number and continue.

Otherwise, ask the user for the PRD issue number (or URL).

If the PRD is not already in your context window, fetch the issue content
(including comments) using the project's issue tracker CLI (e.g.
`gh issue view`, `glab issue view`). If no CLI is available, ask the user
to provide the PRD content.

### 2. Explore the codebase (optional, via subagent)

**Fast-path:** if module exploration on the same modules (named in the
PRD's Implementation Decisions) was already performed in this session,
skip — proceed to Step 3 using prior findings.

If you have not already explored the codebase in this session, **delegate
exploration to an Explore subagent** rather than reading files directly.
The subagent returns a ≤300-word report that stays compact in the
orchestrator trajectory.

First, extract the list of modules named in the PRD's **Implementation
Decisions** section — those are the only modules the subagent should
read. For each named module, the subagent reads **only the primary source
file + its most relevant test file**. Do not let the subagent wander the
repo.

Dispatch message:

> For each module listed below (from the PRD's Implementation Decisions),
> read ONLY its primary source file and the most directly associated test
> file. Do not read other files.
>
> Modules:
> - <module 1 name> — likely path: <path or "search by name">
> - <module 2 name> — likely path: <path or "search by name">
> - …
>
> Return a single report of ≤300 words total covering, per module: current
> shape in one sentence, integration points, and where a tracer-bullet
> slice would likely cut in. Thoroughness: quick.

Escape hatch: if the returned report leaves specific ambiguities, dispatch
a targeted follow-up subagent for just those files. Do not read the
codebase in the parent session.

### 3. HITL triage

Before drafting slices, list every decision that would normally trigger a
HITL slice. For each, classify:

- **Bikeshed** (naming, shape, layout, test layout, error surfacing,
  vocabulary) → should already live in the PRD's `## Conventions` section.
  If missing, stop and ask the user to add it before continuing. These do
  NOT warrant HITL slices.
- **Novel pattern** (new architectural idea, action vocabulary for a state
  machine, etc.) → two options:
  - Lock the shape in the PRD's `## Conventions` section, then treat the
    slice as AFK.
  - Introduce a **spike slice**: a tiny AFK+Lite slice that lands the
    types / vocabulary / one representative test — no consumers. Later
    slices consume the locked shape. Use this when the shape is hard to
    fully specify without touching code.
- **Genuine judgment call** (irreducible — the decision truly can only be
  made once implementation starts) → keep HITL, but write the escape hatch
  into the slice: state the fallback plan if the judgment call goes the
  "wrong" way.

Goal: zero HITL slices at the end of triage except irreducible judgment
calls. Present the triage table to the user for confirmation before
drafting slices.

### 4. Draft vertical slices (Lite-first)

Break the PRD into **tracer bullet** issues. Each issue is a thin vertical
slice that cuts through ALL integration layers end-to-end, NOT a horizontal
slice of one layer.

**Draft slices assuming each MUST fit the Lite envelope.** The `ship-light`
envelope is:

- ≤ 15 files changed (no distinction between src and test files)
- One top-level module directory. Intra-directory helpers are allowed and
  do not count as a second subsystem.
- No schema migration
- No architectural unknowns (resolved in PRD `## Conventions` or a spike
  slice)
- AFK-typed

A slice may exceed the envelope only if it is genuinely irreducible —
splitting would break the vertical-slice rule (no observable behavior) or
introduce a doc-only slice that ships nothing.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such
as an architectural decision or a design review. AFK slices can be
implemented and merged without human interaction. Prefer AFK over HITL
where possible — the Step 3 triage should have already eliminated most
HITL candidates.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer
  (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

### 5. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories from the PRD this addresses
- **Lite-eligible**: `true` / `false`. Default `true` when borderline —
  set `false` only when you can name a specific disqualifier (see below).
- **If `false`**: cite the disqualifier tag and the split axis you
  considered and rejected.

Disqualifier tags (pick exactly one for non-Lite slices):

- `files>15` — exceeds file cap
- `cross-module` — touches more than one top-level module directory
- `schema-migration` — includes a schema change
- `arch-unknown` — architectural decision not resolved in PRD
- `hitl-cat3` — genuine irreducible judgment call

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further? **For every non-Lite
  slice, is the rejected split axis convincing? If weak, split.**
- Are the correct slices marked as HITL and AFK?
- Are the `Lite-eligible` flags and disqualifier tags right?

> *Note: solo-dev assumption. On mid-batch failure, manually delete partial
> slice issues before re-running, or duplicates will be created.*

Iterate until the user approves the breakdown.

### 6. Create the issues

Use whichever issue-tracker CLI is available;
otherwise present the formatted issue body for manual creation. Mode and slice-type are encoded in the
issue body's `## Type` marker (see template).

Before creating issues, extract the PRD's `## Conventions` section into a
scratch file:

```bash
gh issue view <prd-number> --json body -q .body > /tmp/prd-<prd-number>.md
awk '/^## Conventions/,/^## /' /tmp/prd-<prd-number>.md | sed '$d' \
  > /tmp/prd-<prd-number>-conventions.md
wc -l /tmp/prd-<prd-number>-conventions.md   # confirm; do not cat
```

For each approved slice, create an issue in the project's issue tracker
using the body template below, inlining the Conventions file verbatim
where indicated.

Create issues in dependency order (blockers first) so you can reference real
issue numbers in the "Blocked by" field. Do NOT apply any labels — the
`## Type` marker in each body is authoritative for mode detection and
slice-type (`HITL`, `AFK`, or `spike`).

Do NOT modify the parent PRD issue either — there is no `sliced` label
to apply.

<issue-template>

## Type

<!--
Write exactly one of:
  slice — HITL
  slice — AFK
  slice — spike

This marker replaces the old `hitl`/`afk`/`spike`/`slice` labels.
Downstream skills (plan, ship, ship-light, review, apply) parse it via
`awk '/^## Type/,/^## /' | sed '$d' | tail -n +3 | head -1`.
-->

## Parent PRD

#<prd-issue-number>

## What to build

A concise description of this vertical slice. Describe the end-to-end
behavior, not layer-by-layer implementation. Reference specific sections of
the parent PRD rather than duplicating content.

## Conventions (from PRD)

<!--
Copy the PRD's `## Conventions` section verbatim here (contents only —
do not repeat the `## Conventions` heading from the PRD). Slices are
self-contained; downstream skills (plan, ship, ship-light) read this
section as hard spec without chasing back to the PRD.

If the PRD's Conventions section says `None — slice-local decisions
only.`, copy that line verbatim.
-->

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- Blocked by #<issue-number> (if any)

Or "None — can start immediately" if no blockers.

## User stories addressed

Reference by number from the parent PRD:

- User story 3
- User story 7

## Files (hint)

Optional bridge for `ship-light`. List the files this slice will likely
touch, with a one-line responsibility each. Best-effort only — drawn
from the Step 2 module exploration. Omit the section if exploration
produced nothing reliable.

- Create: `path/to/new.py` — <one-line responsibility>
- Modify: `path/to/existing.py` — <what changes>
- Test:   `tests/path/to/test_file.py` — <what it covers>

## Lite-eligible

<!--
For Lite slices, write exactly:

    `true`

For non-Lite slices, write the structured block:

    `false`

    **Disqualifier:** <one of: files>15 | cross-module | schema-migration | arch-unknown | hitl-cat3>
    **Reason:** <one sentence — what specifically triggers the disqualifier>
    **Split axis considered:** <one sentence — what split was rejected and why>

Default is `true` when borderline. Only set `false` with a named
disqualifier.
-->

</issue-template>

Do NOT close or modify the parent PRD issue.

### 7. Update the PRD manifest with slice numbers

If the PRD local tree exists (seeded by `prd-from-grill-me`), append
each created slice issue number to `manifest.json:slices[]`. This lets
PRD-mode `review` enumerate the expected slice set without re-querying
the issue tracker:

```bash
PRD=<prd-number>
if [ -f ".stenswf/$PRD/manifest.json" ]; then
  for SLICE in <list of created slice numbers>; do
    jq --argjson s "$SLICE" \
      '.slices = ((.slices // []) + [$s] | unique)' \
      ".stenswf/$PRD/manifest.json" > /tmp/prd-manifest.json \
      && mv /tmp/prd-manifest.json ".stenswf/$PRD/manifest.json"
  done
  printf '{"ts":"%s","event":"slices-registered","slices":[%s]}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "<comma-list>" \
    >> ".stenswf/$PRD/log.jsonl"
fi
```

If the PRD tree does not exist (PRD created before the seeding step was
added), skip silently — `review` will backfill on first PRD-mode run.

### 7b. Inherit decision stubs into each slice

For each created slice, seed `.stenswf/<SLICE>/decisions.md` with
reference stubs for the PRD's active anchor entries. Stubs are frozen
at slice-creation time and carry title + category + refs only — no
rationale. Rationale lives in the PRD source entry.

See the [Decision Anchor
Contract](../../README.md#decision-anchor-contract) for schema. The loop:

```bash
PRD=<prd-number>
PRD_ANCHOR=".stenswf/$PRD/decisions.md"
if [ -s "$PRD_ANCHOR" ]; then
  for SLICE in <list of created slice numbers>; do
    mkdir -p ".stenswf/$SLICE"
    DEST=".stenswf/$SLICE/decisions.md"
    [ -f "$DEST" ] && continue    # respect existing slice anchor
    {
      printf '# Decisions — #%s\n\n' "$SLICE"
      printf '<!-- Inherited stubs from PRD #%s. Schema: plugins/stenswf/README.md#decision-anchor-contract -->\n\n' "$PRD"
      # Emit one stub per ACTIVE PRD entry (header `### D<n> `, not
      # strikethrough `### ~~D<n>~~`). Bounded by the next `### ` or EOF.
      awk -v prd="$PRD" '
        function flush() {
          if (have && cat != "") {
            printf "### %s — %s (inherited from #%s)\n", bid, btitle, prd
            printf "- **Category:** %s\n", cat
            printf "- **Source:** #%s/%s\n", prd, bid
            if (refs != "") printf "- **Refs:** %s\n", refs
            printf "\n"
          }
          have=0; cat=""; refs=""; bid=""; btitle=""
        }
        /^### / {
          flush()
          if ($0 ~ /^### D[0-9]+ /) {
            match($0, /D[0-9]+/); bid=substr($0, RSTART, RLENGTH)
            btitle=$0; sub(/^### D[0-9]+ [—-] /, "", btitle)
            have=1
          }
          next
        }
        have {
          if ($0 ~ /^- \*\*Category:\*\*/) { cat=$0;  sub(/^- \*\*Category:\*\* */,"",cat) }
          if ($0 ~ /^- \*\*Refs:\*\*/)    { refs=$0; sub(/^- \*\*Refs:\*\* */,"",refs) }
        }
        END { flush() }
      ' "$PRD_ANCHOR"
    } > "$DEST"
  done
fi
```

If the PRD anchor is absent or empty, skip — `plan` will create a
fresh anchor on first slice work. Pre-existing slice anchors are
preserved (later runs of `prd-to-issues` are idempotent).

**After creating all issues, tell the user:**

> All slice issues created. For each issue, choose one path:
>
> - **Lite shortest** — `/stenswf:ship-light <issue>`
>   Issue body IS the spec. No local plan. Single session.
>   Best for: crisp ACs, ≤ ~5 files, established patterns,
>   `Lite-eligible: true`.
>
> - **Lite guided one-shot** — `/stenswf:slice-e2e <issue>`
>   Dispatches `plan-light` + `ship-light` as separate subagent
>   sessions for context separation. A light plan is saved to
>   `.stenswf/<issue>/plan-light.md`. Best for: borderline-lite slices
>   where a plan helps but heavy `plan` + `ship` is overkill.
>
> - **Full pipeline** — `/stenswf:plan <issue>` then
>   `/stenswf:ship <issue>`.
>   Full local plan tree, per-task subagent dispatch, prompt caching,
>   drift detection, archived state. Best for: HITL slices,
>   multi-subsystem, `Lite-eligible: false`, or architecturally
>   uncertain work.
>
> Start with issues that have no blockers.
