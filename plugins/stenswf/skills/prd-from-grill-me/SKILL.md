---
name: prd-from-grill-me
description: Create a PRD through user interview, codebase exploration, and module
  design, then submit as an issue.
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs the interview, codebase exploration narration, and module-design
dialogue. The PRD document itself is a full-prose artifact (already excluded
by `brevity`'s Scope section) — write it normally.

---

This skill will be invoked when the user wants to create a PRD. You may skip
steps if you don't consider them necessary.

1. Ask the user for a long, detailed description of the problem they want to
   solve and any potential ideas for solutions.

2. Explore the repo to verify their assertions and understand the current
   state of the codebase. **Delegate this to an Explore subagent** rather
   than reading files directly — the subagent returns a compact report
   (≤300 words) so the orchestrator trajectory stays light. Dispatch
   message:

   > Explore the codebase to verify these claims and map the current state
   > for a PRD on <topic>. Focus on: <the user's specific assertions> and
   > <the modules likely affected>. Return a report of ≤300 words covering
   > what exists, what's missing, and any risks. Thoroughness: medium.

   Escape hatch: if the returned report is insufficient, ask a targeted
   follow-up subagent rather than reading files in the parent session.

3. Interview me relentlessly about every aspect of the plan until we reach a
   shared understanding. Walk down each branch of the design tree and resolve
   dependencies between decisions one-by-one.

   - For each question, provide your recommended answer and reasoning.
   - If a question can be answered by exploring the codebase, dispatch a
     targeted Explore subagent (as in Step 2) instead of reading files
     directly.
   - Propose 2–3 different approaches with trade-offs.
   - Lead with your recommended option and explain why.
   - Go back and clarify when something doesn't make sense.

   When a recommendation touches a problem that well-known companies
   (e.g. Stripe, Spotify, GitHub, AWS, Shopify) have solved publicly, research
   how those industry leaders approach it and briefly weave the relevant
   patterns or practices into your recommendation. Cite the company and the
   specific practice so I can evaluate the reasoning. Do not force-fit
   references — only include them when genuinely relevant.

   Do not write any code in this phase.

4. Sketch out the major modules you will need to build or modify to complete
   the implementation. Actively look for opportunities to extract deep modules
   that can be tested in isolation.

   **Consult the `architecture` skill** for the deep-vs-shallow
   heuristic and for the criteria on when to extract an abstraction.

   A deep module (as opposed to a shallow module) is one which encapsulates a
   lot of functionality in a simple, testable interface which rarely changes.

   Check with the user that these modules match their expectations. Check with
   the user which modules they want tests written for.

4a. **Lock bikeshed decisions now.** Before writing the PRD, surface every
    decision that would otherwise be re-litigated inside individual slice
    issues (naming, shape, layout, test layout, error surfacing, action
    vocabularies for state machines). These are one-time calls; resolve
    them in the PRD so slices stay AFK and Lite.

    For each, ask the user their preference (with your recommendation),
    then record the resolved decision in the `## Conventions` section of
    the PRD (see template). This section is copied verbatim into every
    slice by `prd-to-issues`, so write it crisply and concretely.

    Typical prompts — use whichever apply to the PRD topic:
    - Module / file naming pattern for new helpers.
    - Exported function naming (`build_<op>_request` vs `<op>_request`).
    - Descriptor shape (frozen dataclass vs NamedTuple vs TypedDict; field set).
    - Test-file split (sibling vs nested; paired sync+async collapse).
    - Error surfacing (raise vs Result-style vs terminal-action).
    - Any domain-specific vocabulary (enum members, action types).

5. Once you have a complete understanding of the problem and solution, use the
   template below to write the PRD. The PRD should be submitted as an issue in
   the project's issue tracker. If a CLI tool is available (e.g. `gh`,
   `glab`), use it to create the issue; otherwise present the formatted issue
   body for manual creation.

   **Before creating the issue, record the PRD base SHA.** This is the
   commit the delivered PRD will be reviewed against by `review` in
   PRD-mode. Use the current `HEAD` of the default integration branch
   (typically `main`):

   ```bash
   git fetch origin
   PRD_BASE=$(git rev-parse origin/main)
   echo "PRD base SHA: $PRD_BASE"
   ```

   Embed `**PRD base SHA:** <PRD_BASE>` as a line in the PRD body (see
   template). After the issue is created and its number `<N>` is known,
   tag that commit so `review` can resolve it later:

   ```bash
   git tag "prd-<N>-base" "$PRD_BASE"
   git push origin "prd-<N>-base"
   ```

   After creating the issue, apply the `prd` lifecycle label using whichever
   issue-tracker CLI is available. Labels are
   created once per repo via the `bootstrap` skill.

   **After creating and labelling the issue, offer the chained handover:**

   Display this prompt verbatim:

   > PRD created as issue #N.
   >
   > Continue directly into slicing now? Saves ~5–10K tokens vs. a fresh
   > run. (For more $ savings, run `prd-to-issues` separately on a smaller
   > model — see README routing table.)
   >   [y]es  /  [N]o, I'll review first
   >
   > Default: N

   If the user's response is `y`, `yes`, `proceed`, or `go` (case-insensitive),
   immediately invoke the `prd-to-issues` procedure starting at its **Step 3
   (HITL triage)**, treating Steps 1–2 as already done (the PRD body and
   module exploration are still in your context). Any other response —
   including empty, ambiguous, or `N` — stop. Do not invoke `prd-to-issues`.

<prd-template>

**PRD base SHA:** <PRD_BASE>

## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the
format of:

1. As an <actor>, I want a <feature>, so that <benefit>

<user-story-example>
1. As a mobile bank customer, I want to see balance on my accounts, so that I
   can make better informed decisions about my spending
</user-story-example>

This list of user stories should be extremely extensive and cover all aspects
of the feature.

## Implementation Decisions

A list of implementation decisions that were made. This can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being
outdated very quickly.

## Conventions

Bikeshed decisions resolved upfront so individual slices do not re-litigate
them. `prd-to-issues` copies this section verbatim into every slice's body
as `## Conventions (from PRD)`. Plans and ship dispatches read it as hard
spec. Keep it concrete and terse — one bullet per decision.

Typical contents (include only what applies):

- **Naming.** Helper module `_<x>_helpers.py`; exported function
  `build_<op>`; descriptor class `<Op>Descriptor`.
- **Shape.** Frozen dataclass with fields `{method, path, json_body,
  query_params, headers}`.
- **Test layout.** Pure helpers in `tests/<module>/test_<x>_helpers.py`;
  dispatch tests (one sync + one async per method) stay in existing file.
- **Error surfacing.** Raise `<ExistingError>` from the helper; drivers do
  not translate.
- **Action vocabulary** (state machines only): `Poll`, `Sleep(delay)`,
  `Return(value)`, `Raise(error)`.

Omit subsections that do not apply. If no bikeshed decisions are needed,
write `None — slice-local decisions only.` and move on.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behavior, not
  implementation details)
- Which modules will be tested
- Prior art for the tests (i.e. similar types of tests in the codebase)

## Out of Scope

A description of the things that are out of scope for this PRD.

## Further Notes

Any further notes about the feature.

</prd-template>
