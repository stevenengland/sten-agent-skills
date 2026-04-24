---
name: prd-from-grill-me
description: Create a PRD through user interview, codebase exploration, and module design, then submit as an issue.
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).
The PRD document itself is a full-prose artifact (already excluded by
`brevity`'s Scope section).

---

Invoked when the user wants to create a PRD. Skip steps if unnecessary.

1. Ask the user for a long, detailed description of the problem and any
   solution ideas.

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
    upfront so slices stay AFK and Lite.

    For each, ask the user their preference (with your recommendation).
    Record the resolved decision in the PRD's `## Conventions` section.
    That section is copied verbatim into every slice by `prd-to-issues`.

    Typical prompts (use whichever apply): module/file naming, exported
    function naming, descriptor shape, test-file split, error surfacing,
    domain vocabulary.

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
   template). After the issue is created and its number `<N>` is known:

   ```bash
   git tag "prd-<N>-base" "$PRD_BASE"
   git push origin "prd-<N>-base"
   ```

   Do NOT apply any label. Mode is detected from the front-matter
   `type: PRD` marker.

   **Seed the PRD local tree.** Required for drift detection by
   `review` and `apply`:

   ```bash
   N=<issue-number>
   mkdir -p ".stenswf/$N"
   gh issue view "$N" --json body -q .body > ".stenswf/$N/concept.md"
   CONCEPT_SHA=$(sha256sum ".stenswf/$N/concept.md" | awk '{print $1}')
   cat > ".stenswf/$N/manifest.json" <<EOF
   {
     "issue": $N,
     "kind": "prd",
     "base_sha": "$PRD_BASE",
     "concept_sha256": "$CONCEPT_SHA",
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

   The tree is gitignored (see `bootstrap`).

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

   **After creating the issue, offer the chained handover:**

   > PRD created as issue #N.
   >
   > Continue directly into slicing now? Saves ~5–10K tokens vs. a fresh
   > run. (For more $ savings, run `prd-to-issues` separately on a smaller
   > model — see README routing table.)
   >   [y]es  /  [N]o, I'll review first
   >
   > Default: N

   If the user's response is `y`/`yes`/`proceed`/`go` (case-insensitive),
   immediately invoke `prd-to-issues` at **Step 3 (HITL triage)**,
   treating Steps 1–2 as done. Any other response → stop.

---

## Feedback

Log friction per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=prd-from-grill-me`.
