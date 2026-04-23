---
name: prd-from-grill-me
description: Create a PRD through user interview, codebase exploration, and module
  design, then submit as an issue.
---

This skill will be invoked when the user wants to create a PRD. You may skip
steps if you don't consider them necessary.

1. Ask the user for a long, detailed description of the problem they want to
   solve and any potential ideas for solutions.

2. Explore the repo to verify their assertions and understand the current
   state of the codebase.

3. Interview me relentlessly about every aspect of the plan until we reach a
   shared understanding. Walk down each branch of the design tree and resolve
   dependencies between decisions one-by-one.

   - For each question, provide your recommended answer and reasoning.
   - If a question can be answered by exploring the codebase, explore the
     codebase instead.
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

   A deep module (as opposed to a shallow module) is one which encapsulates a
   lot of functionality in a simple, testable interface which rarely changes.

   Check with the user that these modules match their expectations. Check with
   the user which modules they want tests written for.

5. Once you have a complete understanding of the problem and solution, use the
   template below to write the PRD. The PRD should be submitted as an issue in
   the project's issue tracker. If a CLI tool is available (e.g. `gh`,
   `glab`), use it to create the issue; otherwise present the formatted issue
   body for manual creation.

   After creating the issue, apply the `prd` lifecycle label using whichever
   issue-tracker CLI is available. Labels are
   created once per repo via the `bootstrap` skill.

   **After creating and labelling the issue, tell the user the issue number
   and suggest the next step:**

   > PRD created as issue #N. When ready, run the `prd-to-issues` skill with
   > this issue number to break it into independently-implementable vertical
   > slices.

<prd-template>

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
