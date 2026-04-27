---
name: prd-from-grill-me
description: Create a PRD through user interview, codebase exploration, and module design, then submit as an issue.
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).
The PRD document itself is a full-prose artifact (already excluded by
`brevity`'s Scope section).

---

Invoked when the user wants to create a PRD. Skip steps if unnecessary.

**Ceremony invariant (TDD-as-lens).** This skill MUST NOT (a)
instruct skipping tests for ACs annotated `(behavior)`, (b) remove
`tdd` from any SKILLS TO LOAD list, (c) accept `manual check` or
"rely on existing suite" as completion evidence for a `(behavior)`
AC, or (d) emit guidance that contradicts `tdd/SKILL.md`. Detection
of behavior change is the gate; loading `tdd` is the lens; whether
to write a test follows from the AC tag, not from this skill. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

## Phase 0 — Issue intake (optional)

If `$ARGUMENTS` is a GitHub issue number, treat it as an existing
feature/refactor/integration/migration request to convert into a PRD.
This is the entry mode used when the user runs
`/stenswf:prd-from-grill-me <issue>` rather than a blank-page session.

```bash
if printf '%s' "${ARGUMENTS:-}" | grep -Eq '^[0-9]+$'; then
  ORIG="$ARGUMENTS"
  gh issue view "$ORIG" --json title,body,state \
    -q '"# " + .title + "\n\n" + .body' > /tmp/req-$ORIG.md

  # Refuse retriage / replanning of an already-shaped issue.
  if head -10 /tmp/req-$ORIG.md | grep -q '^<!-- stenswf:v1'; then
    echo "Issue #$ORIG already has stenswf:v1 front-matter. Use /stenswf:plan / /stenswf:plan-light / /stenswf:triage-issue as appropriate." >&2
    exit 1
  fi
else
  ORIG=""
fi
```

If `$ORIG` is set:

1. **Step-back classification** (per
   [../../references/reasoning-effects.md](../../references/reasoning-effects.md)).
   Read `/tmp/req-$ORIG.md`. Classify the request as one of:
   - `capability` — new user-facing feature.
   - `integration` — new system boundary or external service.
   - `migration` — behavior-preserving move with non-trivial risk.
   - `refactor` — structural change, behavior preserved (no new
     capability for users).

   If the body describes **broken behavior** rather than a desired
   change, abort: *"This looks like a bug report. Recommended:
   `/stenswf:triage-issue $ORIG`."*

2. Print a 5-line summary + the classification. Ask the user to
   confirm. On disagreement, re-classify and re-confirm.

3. Use `/tmp/req-$ORIG.md` as the Step-1 long description input —
   skip Step 1's open-ended question.

4. Bias subsequent template work toward the class:
   - `refactor` → make `## Invariants Preserved` and `## Risks of Not
     Doing This` first-class. `## User Stories` may be replaced by
     "Restoration / preservation" stories.
   - `migration` → emphasise sequenced rollout in `## Solution`.
   - `integration` → emphasise contracts in `## Implementation
     Decisions`.
   - `capability` → standard.

5. Record `class:` in the PRD front-matter (Step 5 already requires it
   per [../../references/prd-template.md](../../references/prd-template.md)).

If `$ORIG` is empty, behave as before (blank-page interview from Step 1).

## Phase 1 — Steps

1. Ask the user for a long, detailed description of the problem and any
   solution ideas. **Skip if Phase 0 already populated `/tmp/req-$ORIG.md`.**

2. Explore the repo via an Explore subagent (≤300 words, thoroughness: medium).
   Do NOT read files directly.

   > Explore the codebase to verify these claims and map the current
   > state for a PRD on <topic>. Focus on: <user's assertions> and
   > <affected modules>. Return a report ≤300 words: what exists,
   > what's missing, risks. Thoroughness: medium.

3. Interview relentlessly about every aspect of the plan. Walk each
   branch of the design tree. Resolve dependencies one-by-one.

   - Provide a recommended answer and reasoning for each question.
   - Delegate codebase questions to targeted Explore subagents.
   - Propose 2–3 approaches with trade-offs. Lead with recommendation.
   - Go back and clarify when something doesn't make sense.
   - Cite industry practice (Stripe, Spotify, GitHub, AWS, Shopify)
     only when genuinely relevant to a decision currently in play.

   No code in this phase.

4. Sketch modules to build/modify. Look for deep modules extractable in
   isolation. Consult the `architecture` skill.

   Check with the user that modules match their expectations. Check
   which modules they want tests written for.

4a. **Lock bikeshed decisions now.** Surface every decision that would
    otherwise be re-litigated inside slice issues (naming, shape,
    layout, test layout, error surfacing, vocabularies). Resolve them
    upfront so downstream issues stay AFK and Lite.

    For each, ask the user their preference (with your recommendation).
    Record the resolved decision in the PRD's `## Conventions` section.
    That section is copied verbatim into every slice by `prd-to-issues`.

    Typical prompts (use whichever apply): module/file naming, exported
    function naming, descriptor shape, test-file split, error surfacing,
    domain vocabulary.

4b. **Step back and reflect before writing the PRD.**

    First, classify: is this PRD primarily a *new capability*, an
    *integration*, a *migration*, or a *refactor*? The class shapes
    which sections of the template carry the load. **Phase 0** may have
    already locked this from an existing issue — reuse that
    classification unless the interview revealed it was wrong. Record
    in the PRD front-matter as `class:` (see
    [../../references/prd-template.md](../../references/prd-template.md)
    — the field is required).

    Then pause and step back: which decisions are still implicit and
    would otherwise leak as HITL ambiguity into every downstream issue?
    Which conventions did the interview surface but not lock? Are any
    "obvious" defaults actually contested in this codebase? Revise
    `## Conventions` and `## Implementation Decisions` before writing.

    For `class: refactor` PRDs: also fill `## Invariants Preserved`
    (required) and `## Risks of Not Doing This`. For `class: migration`,
    `## Invariants Preserved` is required (behavior preservation is the
    whole point).

    `## Out of Scope` MAY optionally list invariants-to-preserve as
    `(structural)` candidates that downstream slices should tag
    accordingly. Advisory only — `prd-to-issues` re-tags every AC
    against the heuristic ladder per
    [../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).
5. Write the PRD using the template at
   [../../references/prd-template.md](../../references/prd-template.md).
   Create as an issue (CLI when available; otherwise present formatted
   body for manual creation).

   **Record the PRD base SHA.** This is the commit the delivered PRD
   will be reviewed against. Use the current HEAD of the upstream
   integration branch — portable across branch names:

   ```bash
   git fetch --quiet
   # Resolve the upstream of the current HEAD if tracked; else repo default.
   PRD_BASE=$(git rev-parse --verify '@{upstream}' 2>/dev/null || {
     D=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)
     [ -n "$D" ] && git rev-parse "origin/$D"
   })
   [ -n "$PRD_BASE" ] || { echo "cannot resolve PRD base — set upstream or pass explicitly" >&2; exit 1; }
   echo "PRD base SHA: $PRD_BASE"
   ```

   Embed `prd_base_sha: $PRD_BASE` in the front-matter block (see
   template). The front-matter field is the sole anchor consumed by
   `review` and `apply`.

   Do NOT apply any label. Mode is detected from the front-matter
   `type: PRD` marker.

   **Seed the PRD local tree.** Required for drift detection by
   `review` and `apply`:

   ```bash
   N=<issue-number>
   mkdir -p ".stenswf/$N"
   gh issue view "$N" --json body -q .body > ".stenswf/$N/concept.md"
   CONCEPT_SHA=$(sha256sum ".stenswf/$N/concept.md" | awk '{print $1}')
   CLAUDE_SHA=$(git log -1 --format=%H -- CLAUDE.md AGENTS.md 2>/dev/null | head -1)
   cat > ".stenswf/$N/manifest.json" <<EOF
   {
     "issue": $N,
     "kind": "prd",
     "base_sha": "$PRD_BASE",
     "concept_sha256": "$CONCEPT_SHA",
     "claude_md_sha": "$CLAUDE_SHA",
     "plan_created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
     "slices": [],
     "review_step": {"status": "pending", "sha": null}
   }
   EOF

   # Bootstrap the decision anchor.
   cat > ".stenswf/$N/decisions.md" <<EOF
   # Decisions — #$N

   <!-- Seeded by prd-from-grill-me. Schema: plugins/stenswf/README.md#decision-anchor-contract -->
   EOF
   ```

   The tree is excluded per-clone via `.git/info/exclude` (see `bootstrap`).

   **If Phase 0 was driven by an existing issue (`$ORIG` set):** comment
   on the original and close it after the PRD issue exists — the original
   stays as the durable intake record, but its lifecycle ends here.

   ```bash
   if [ -n "${ORIG:-}" ]; then
     gh issue comment "$ORIG" --body \
"Triaged → PRD #$N. The request is preserved here as the intake record;
status updates will appear on the PRD and its slices."
     gh issue close "$ORIG" --reason completed
   fi
   ```

   **Seed anchor entries (LLM task).** Walk the PRD body and append one
   entry per qualifying item:

   - `## Conventions` item → category `decision`.
   - `## Implementation Decisions` item → category `arch`.

   Apply the grep-blame + surfaces test per
   [../../references/decision-anchor-link.md](../../references/decision-anchor-link.md).
   Skip routine defaults already documented. Typical count: 5–15.

   Use the canonical append snippet from the Decision Anchor Contract
   (see that file for the auto-incremented-ID awk). Adapt
   title/rationale/refs from each PRD item.

   **After creating the issue, display this prompt and STOP.**

   > PRD created as issue #N.
   >
   > Continue directly into slicing now? Saves ~5–10K tokens vs. a fresh
   > run. (For more $ savings, run `prd-to-issues` separately on a smaller
   > model — see README routing table.)
   >   [y]es  /  [N]o, I'll review first
   >
   > Default: N

   **HARD STOP.** Do not invoke `prd-to-issues`. Do not draft slices. Do
   not dispatch any subagent. Do not read any further files. End your
   turn now and wait for the user's literal next message.

   **On the next user message:**
   - If the message is `y`, `yes`, `proceed`, or `go` (case-insensitive,
     trimmed) → invoke `prd-to-issues` starting at its **Step 3 (HITL
     triage)**, treating Steps 1–2 as already done.
   - Any other message → end. Do not slice.

---

## Feedback

Log friction per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=prd-from-grill-me`.
