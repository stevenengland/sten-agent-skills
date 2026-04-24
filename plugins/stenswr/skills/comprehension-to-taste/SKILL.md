---
name: comprehension-to-taste
description: Research a codebase, then interview the user through three scoped quizzes (scope, blast radius, architecture) to extract and persist the repository's "taste" — a layered profile of conventions, invariants, and design decisions that downstream skills and agents can load on demand. Use when onboarding to an unfamiliar repo, before a non-trivial refactor, when the user says "get a taste of this repo", "understand this codebase", or "write down what this project is about".
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs codebase-research narration, interview questions, and tool-use
status. The final `TASTE.md` artifact is a full-prose document (already
excluded by `brevity`'s Scope section) — write it normally.

---

## When to use

- Onboarding an agent (or human) to an unfamiliar repository.
- Before a non-trivial refactor, when assumptions must be made explicit.
- When the user wants a persisted "taste" document to guide future work.
- When downstream skills (e.g. `architecture`, `plan`, `review`) need a
  grounded profile of conventions rather than re-deriving them each run.

## Do not use when

- The task is confined to a single file or trivial change.
- A current, trusted `TASTE.md` (or equivalent) already exists — load it
  instead of regenerating.
- The user wants a marketing description or a README — this skill
  deliberately rejects marketing prose.

---

## Core Principle

"Taste" is **not** style preference. It is the set of decisions — explicit
and implicit — that a reasonable maintainer would defend under pressure.
The goal of this skill is to surface those decisions, pressure-test them
with the user, and persist the survivors as a layered artifact.

Every question in the interview must come with a **recommended answer
grounded in the research phase** — never a blank prompt. The user's job is
to confirm, correct, or refine.

---

## Phase 1 — Codebase Research

**Delegate to an `Explore` subagent.** Do not read files directly in the
orchestrator session. Dispatch:

> Produce a research report (≤600 words) on this repository to seed a
> taste-extraction interview. Cover:
>
> 1. **Purpose** — what this software actually does, in full sentences.
>    No marketing, no half-sentences. What does it explicitly *not* do
>    (scope boundaries visible in code/docs)? Who is the consumer and
>    what do they get from it?
> 2. **Dependencies** — runtime, build, test, and external service
>    dependencies. Flag any that look load-bearing or unusual.
> 3. **Fragile parts** — modules with high churn, missing tests, TODOs,
>    long functions, or comments like "don't touch", "hack", "temporary".
> 4. **Assumptions** — implicit contracts visible in code (e.g. "timezone
>    is always UTC", "IDs are UUIDv4", "single-tenant"). List them even
>    if nowhere documented.
> 5. **Architecture signals** — layering, module boundaries, DI style,
>    error-handling discipline, testing strategy, naming conventions.
>    Note anything that looks like an established pattern and anything
>    that looks like AI-generated noise (see red flags below).
> 6. **Docs/ADRs** — list any `docs/`, `ADR-*`, `DECISIONS.md`,
>    `ARCHITECTURE.md`, or similar. Quote decision headings verbatim;
>    do not summarize away rationale.
>
> Thoroughness: medium. Use `head`/`grep`/`find`; never dump full files.
> Ignore `node_modules`, `dist`, lock files, `.git`.

### AI-noise red flags (for the subagent and the orchestrator)

- Overly defensive error handling for impossible states.
- Docstrings/comments that restate the obvious.
- Abstractions with one implementation and one caller.
- Unused "future-proof" parameters, hooks, or interfaces.
- Naming that drifts across a module (e.g. `getUser`, `fetch_user_data`,
  `UserLoader.load()` all in one layer).
- Tests that assert on implementation detail rather than behaviour.

Record the subagent's report verbatim in session notes. If it is
insufficient, dispatch a targeted follow-up subagent rather than reading
files in the parent session.

---

## Phase 2 — The Three Quizzes

Ask **one question at a time**. For each question: state your recommended
answer grounded in Phase 1 findings, cite the evidence (file path, doc,
pattern), then ask the user to confirm, correct, or refine.

If a question can be better answered by exploring further, dispatch another
`Explore` subagent instead of guessing or asking the user to recall.

### Quiz A — Scope check

A1. **What does this software do?** One to three full sentences. No
    marketing, no half-sentences. Grounded in entry points, README,
    top-level modules.

A2. **What does it explicitly not do?** Out-of-scope items visible in
    code, docs, or deliberate omissions. Flag anything the user may be
    tempted to add that contradicts existing scope.

A3. **What does it do for the consumer?** Identify the consumer (end
    user, other service, library caller, operator). State the value they
    extract. If multiple consumer types exist, list each separately.

### Quiz B — Blast-radius quiz

B1. **What are the dependencies?** Runtime, build, test, external
    services. Group by criticality. Flag any single points of failure.

B2. **What breaks if core module X fails?** For each load-bearing module
    identified in Phase 1, name the downstream consumers and the user-
    visible failure mode.

B3. **What are the fragile parts?** Modules flagged in Phase 1 —
    confirm or correct. Ask: is this fragility deliberate (deferred work)
    or accidental (unnoticed decay)?

B4. **What assumptions is this built on?** Present the implicit
    contracts found in Phase 1. For each, ask: is this a load-bearing
    assumption, a convenience, or obsolete?

### Quiz C — Architecture quiz

C1. **What decisions were made, and why?** For each architectural
    signal found in Phase 1:

    - If ADRs/docs exist: quote the decision and ask the user to confirm
      it is still in force.
    - If no docs exist: identify the **pattern** (e.g. Hexagonal, CQRS,
      Feature-Sliced Design, Repository pattern, event sourcing) and
      propose 2–3 grounded explanations from industry practice (cite
      the company/source when relevant — e.g. "Shopify uses this shape
      for modular monoliths"). Ask the user which matches their intent.

C2. **What seems like AI noise?** Present the red-flag findings from
    Phase 1. Before surfacing them to the user, run a **devil's-advocate
    pass**: dispatch a second `Explore` subagent with this prompt:

    > Play devil's advocate. For each flagged item below, argue the
    > strongest case that it is *intentional* (defensive for a real
    > failure mode, required by a framework contract, load-bearing for
    > a consumer, or a deliberate ergonomic choice). Cite code evidence.
    > Return a table: `item | flag reason | counter-argument | verdict
    > (likely noise / likely intentional / unclear)`. ≤400 words.
    > Thoroughness: quick.

    Then present to the user only the items still marked `likely noise`
    or `unclear`, with both the original flag and the counter-argument.
    For each, recommend: keep, refactor, or delete. Defer to the user
    on anything marked `unclear`.

C3. **Which patterns should stay? Which shouldn't?** From the surviving
    set, ask the user to rank keep-at-all-costs vs open-to-change.

---

## Phase 3 — Persist the Taste

Produce a **layered** artifact. Two layers, clearly separated:

1. **Surface layer** — what the code looks and feels like. Naming,
   file layout, test style, commit style, error-message tone, public
   API shape. Read in <2 minutes.

2. **Deep technical layer** — architectural decisions, invariants,
   load-bearing assumptions, blast-radius notes, fragile parts,
   deliberate out-of-scope items. Cite files and ADRs.

Ask the user where to write the artifact. Recommended default:

- **`TASTE.md`** at repo root, plus a one-line reference in
  `AGENTS.md` / `CLAUDE.md` / `copilot-instructions.md` so downstream
  agents discover it.

Alternatives:

- `.github/instructions/taste.instructions.md` with `description:` set
  and **no** `applyTo` pattern — agent loads it on demand, avoiding
  per-file context burn.
- `docs/TASTE.md` if the repo already uses `docs/` for ADRs.

### Record the baseline SHA

Before writing the artifact, pin the commit this taste profile was
derived from so future runs can refresh incrementally:

```bash
git fetch origin
TASTE_BASE=$(git rev-parse HEAD)
echo "Taste base SHA: $TASTE_BASE"
```

Embed `**Taste base SHA:** <TASTE_BASE>` in the artifact header (see
template). On subsequent runs, the skill should:

1. Read the recorded SHA from the existing `TASTE.md`.
2. Run `git diff --name-only <TASTE_BASE>..HEAD` to list changed paths.
3. Scope the Phase 1 `Explore` subagent to those paths only.
4. Re-interview only the quiz branches whose evidence intersects the
   changed paths. Leave untouched sections of `TASTE.md` alone.
5. Update the `Taste base SHA` on successful refresh.

If no prior `TASTE.md` exists, run the full skill.

### Template

```markdown
# TASTE — <repo name>

*Generated by `comprehension-to-taste` on <date>.*
*Taste base SHA: `<TASTE_BASE>`*
*Revisit when architecture shifts or the fragile-parts list changes.*

## Surface

### What it does (and does not)
- Does: …
- Does not: …
- Consumer(s) and value delivered: …

### Conventions
- Naming: …
- File layout: …
- Test style: …
- Error-handling tone: …
- Public API shape: …

## Deep

### Architectural decisions
| Decision | Rationale | Evidence | Status |
|---|---|---|---|
| … | … | `path/to/file` or ADR-### | in force / under review |

### Load-bearing assumptions
- …

### Blast radius
- Module `X` → downstream `[A, B]` → failure mode: …

### Fragile parts
- `path/to/module` — reason, deliberate? (yes/no), mitigation.

### Patterns: keep / change
- Keep at all costs: …
- Open to change: …
- Confirmed AI noise (candidates for deletion): …

## Out of scope for this repo
- …
```

---

## Exit criteria

- Phase 1 report captured.
- Every question in Quizzes A/B/C answered (or explicitly deferred).
- `TASTE.md` (or chosen equivalent) written and committed on a branch
  the user named. Do not push without confirmation.
- Reference added to the repo's agent instructions file so future
  sessions discover the taste profile.

## Anti-patterns

- Asking open-ended questions without a grounded recommendation.
- Reading files in the orchestrator instead of delegating to `Explore`.
- Writing a `TASTE.md` that reads like a README or marketing page.
- Flattening the surface/deep distinction into one mixed section.
- Treating "AI noise" calls as final without user confirmation.
