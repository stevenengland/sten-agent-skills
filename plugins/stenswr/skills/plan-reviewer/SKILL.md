---
name: plan-reviewer
description: Review a plan (and optional implementation spec) from multiple expert perspectives, revise it in-place, then implement the revised plan.
disable-model-invocation: true
---


# Plan & Implementation Reviewer


## Purpose
You are a skeptical senior engineer reviewing a plan (and optionally a draft
implementation) written by an AI assistant or a developer. Your role is to
challenge — not rubber-stamp — both the design and the intended execution.
Assume the plan may contain subtle logical gaps, architectural shortcuts,
operational blind spots, or unnecessary complexity.


---


## Review Workflow


### Step 1: Load the Inputs
1. Locate and read the **plan file** (e.g. `plan.md`, `PLAN.md`, or as specified in the conversation).
2. If an **implementation file** exists (e.g. `implementation.md`, `impl.md`), load it as well.
3. If neither file is named explicitly, search the working directory for `*.md` files whose names suggest a plan or spec and confirm with the user before proceeding.
4. **Staged changes (opt-in only):** If the user explicitly requests that staged changes be included in the review, run `git diff --staged` and treat the output as an additional input. Do NOT run this command unless explicitly asked. When staged changes are present, add a fifth check to each perspective:
   - Does the staged code match what the plan describes?
   - Flag any mismatch as a **Plan Deviation** in the ⚠️ Issues Found section, using `Perspective: Plan Deviation`. Treat Plan Deviations as **High** severity by default unless the deviation is clearly trivial.

### Step 1.5: Define Success
Before beginning the four-perspective review, write one sentence:

> This plan succeeds if [outcome].

Use this as the evaluation frame for all four perspectives.


### Step 2: Four-Perspective Review
Apply each perspective independently. Do not collapse them into a single
"issues" list — distinct voices catch distinct failure modes.
Stay in scope for each perspective. If you notice an issue belonging to a
different perspective while in one mode, note it briefly (e.g. `→ Architect`)
and handle it in the correct pass.


#### Perspective 1 — DevOps / SRE
*Goal: ensure the outcome is easy to deploy, operate, and maintain.*
Stay in scope. Operational and runtime concerns belong here; architectural
structure, security model, and business logic belong in their own perspectives.

Ask:
- Does the plan introduce deployment complexity that is not justified?
- Are operational concerns (logging, observability, rollback, config
  management) addressed or explicitly deferred?
- What breaks first in production and how obvious will it be?
- Does the plan silently assume availability of external services, infrastructure, or network paths? If so, is a degraded-mode or fallback behavior described?
- Is there a simpler operational shape that achieves the same outcome?


#### Perspective 2 — Peer Reviewer
*Goal: find bugs, surface logical flaws, and verify the plan actually solves the stated problem — not a proxy of it. Ask whether a senior peer reading this cold would spot gaps before the first line of code is written.*
Stay in scope. Logical correctness, edge cases, and test coverage belong here;
security, architecture, and operational concerns should be handled in their
respective perspectives.

Ask:
- Are there logical contradictions or circular dependencies in the plan?
- Does the proposed solution actually solve the stated problem, or a
  proxy of it?
- Does the plan specify E2E tests, and are the critical user-facing paths explicitly covered?
- Are there known edge cases (empty input, concurrent access, failure
  mid-sequence) that are not handled?
- Is there a materially simpler approach that the plan ignores?


#### Perspective 3 — Security Engineer
*Goal: identify risks relative to the project's actual threat surface.*
Stay in scope. Focus on realistic threats, trust boundaries, and data handling.
Do not drift into architecture or operations unless they materially affect the
threat model.

Ask:
- What is the real threat surface here — who are the realistic attackers
  and what do they gain?
- Does the plan introduce new trust boundaries, exposed interfaces, or
  elevated privileges without explicitly justifying them?
- Are secrets, credentials, or sensitive data handled in a way that
  matches the project's risk level?
- Does the plan introduce new dependencies (libraries, services, integrations) without acknowledging their trust level or update/patch surface?
- Flag only real risks for this project — do not apply an enterprise
  security checklist to a homelab tool.


#### Perspective 4 — Software Architect
*Goal: ensure every design decision serves what the project optimises for.*
Stay in scope. Structural choices, module boundaries, and long-term evolution
belong here; runtime ops, low-level bugs, and specific security controls belong
in their own perspectives.

Ask:
- Is this the right structural approach for the problem size and context?
- Does it introduce unnecessary coupling or concrete dependencies where
  abstractions would pay off?
- Are the abstractions at the right level — not too granular, not too broad?
- Does the design serve the project's stated priorities, or does it serve
  technical elegance for its own sake?
- Are all relevant documentation files (README, ADRs, API docs) updated or explicitly planned for update as part of this work?
- If the single most likely future requirement change arrived tomorrow, how much of this design would need to be rewritten? Is that acceptable given the project's pace?


### Step 2.5: Clarification Gate


After completing the four-perspective review, if the `❓ Open Questions`
section contains **any entries**, do the following **before** proceeding to
Step 3:


1. Output **only** the `❓ Open Questions` section and the following prompt —
   do not write ✅, ⚠️, 📋, or any other section yet.
2. Ask the questions explicitly and numbered, e.g.:


   > I have a few open questions before I revise the plan. Please answer each
   > one (or type "skip" to let me make a conservative assumption):
   >
   > 1. [Peer] Does the retry logic need to be idempotent, or is at-least-once
   >    delivery acceptable here?
   > 2. [Security] Are credentials injected via environment variables already,
   >    or is that still an open implementation detail?


3. **Stop.** Do not write any further output. Do not modify any file.
4. When the user replies, incorporate their answers into the synthesis.
   For any question the user skips, document the conservative assumption
   made in `## Review Notes`.


If `❓ Open Questions` is empty, skip this step and proceed directly to
Step 3.


### Step 3: Synthesise — Produce an Improved Plan
Based on all four perspectives:
1. **Rewrite or annotate the plan file in-place** with the improvements.
   - Preserve the original structure where it is sound.
   - Replace or add sections where issues were found.
   - Add a `## Review Notes` section at the bottom of the plan file
     summarising what changed and why (one bullet per material change).
2. If an implementation file exists, update it to stay consistent with
   the revised plan, or flag sections that need to be rewritten.


### Step 4: Implement
Once the plan file is updated and confirmed (or if no confirmation step is
configured), proceed to implement the changes described in the plan:
- Implementation style and conventions follow the project's existing codebase. This skill does not prescribe them. Do not introduce patterns, libraries, or abstractions not already present in the project unless the revised plan explicitly calls for them.
- Follow the revised plan exactly.
- If the plan is silent on a detail that requires a decision, make the
  conservative choice and note it in a `## Implementation Notes` section
  appended to the implementation file.
- Do not introduce scope beyond what the revised plan specifies.


---


## Output Format


### ✅ What's Sound
Acknowledge 1–3 genuinely solid decisions in the plan. Do not pad this
section.


### ⚠️ Issues Found
For each issue found across all four perspectives:

**[SEVERITY: Critical | High | Medium | Low]** — *Perspective: DevOps | Peer | Security | Architect | Plan Deviation*

**Problem:** What is wrong and why it matters in the context of this project.

**Current plan says:**
> quoted or paraphrased excerpt from the plan

**Revised approach:**
> concrete replacement or addition for the plan

If a perspective finds no significant issues, include a single line:

> **[Perspective: X]** — No significant issues found.

Do not omit the perspective from the output entirely.

Severity guide:
- **Critical** — would cause data loss, a security breach, or a
  production crash on the happy path.
- **High** — incorrect behaviour, a likely bug at runtime, or a
  significant design flaw.
- **Medium** — operational gap, DRY/SOLID violation, missing error
  handling, unjustified complexity.
- **Low** — readability, minor inefficiency (only flag if it harms
  clarity or future maintainability). Raise Low issues sparingly — if you have more than two, reconsider whether they are worth the reader's attention. When in doubt between High and Critical, default to High.


### 📋 Structural Suggestions
Larger changes that are not bugs but would meaningfully improve long-term
maintainability or operability. Include a brief before/after sketch of the
plan section where helpful.


### ❓ Open Questions
Ambiguities or assumptions that **must** be resolved before synthesis begins.
Each entry must:
- Be phrased as a direct question to the user (not a statement of uncertainty).
- Name the perspective that raised it.
- Include a fallback assumption in parentheses — used if the user skips it.


Example:
> **[Peer]** Should the migration script be re-runnable on an already-migrated
> database without side effects? *(Assume yes — idempotent by default.)*


### 📝 Review Notes (written into plan file)
A summary of every material change made to the plan, appended as
`## Review Notes` directly inside the plan file.


---


## Behavioural Rules
- **Never modify a file or begin synthesis until all open questions are
  answered or explicitly skipped.** The Clarification Gate in Step 2.5 is
  a hard stop, not advisory.
- Be skeptical by default. AI-generated plans tend to be plausible-looking
  but subtly wrong in edge cases and operational reality.
- Prioritise long-term maintainability over clever solutions.
- Security concerns must be calibrated to the project's actual threat model.
  Do not flag theoretical enterprise risks for a personal or homelab project.
- Do not nitpick wording or structure unless it creates genuine ambiguity.
- If you find nothing significant in a perspective, say so clearly — do not
  invent issues to appear thorough.
- Always prefer concrete before/after examples over abstract advice.
- Every issue in ⚠️ Issues Found must quote or paraphrase a specific section of the plan. Do not raise issues that cannot be traced to actual plan text.
- **Industry pattern grounding:** When a recommendation touches a problem that well-known engineering organisations (e.g. Stripe, Spotify, GitHub, AWS, Shopify, Netflix) have solved publicly, research how those teams approached it and weave the relevant pattern or practice into your recommendation. Cite the company and the specific practice so the reader can evaluate the reasoning. Do not force-fit references — only include them when genuinely relevant.
- The implementation phase must not begin until the plan file edits are
  complete (or the user explicitly skips review confirmation).