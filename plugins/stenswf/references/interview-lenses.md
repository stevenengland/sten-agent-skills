# Interview lenses — research-first interview contract

Research every open decision before the user sees a question. Read-only lens
subagents answer the drafted questions in parallel, the caller verifies their
verdicts, and only the questions that remain heavy reach the user.

**Interface.** The caller hands this stage its unresolved decisions and their
constraints — the subject (`#<N>`, or a one-line topic before a PRD issue
exists), the orientation report, the drafted questions, the pinned decisions,
and the depth — and gets back verified research per question: facts,
applicable precedents, alternatives, and uncertainty.

**Responsibilities.**

1. **Research** establishes facts, precedents, alternatives and uncertainty —
   this file.
2. **Weighing** evaluates the alternatives against architecture and business
   rules — [decision-weighting.md](decision-weighting.md).
3. **Authority** — who may decide — belongs to
   [decision-escalation.md](decision-escalation.md), the only definition of
   easy and heavy. This file never restates it.
4. The **caller** owns approval, recording and resume.

**Topology.** The research result is the contract; the three lenses are its
current producer. Only `## When to run` and the lens blocks name lenses, so a
different producer would change only those. Whether lenses beat a strengthened
Explore pass is a recorded hypothesis, not an invariant.

**Callers.** `plan` Phase 1 ([plan](../skills/plan/SKILL.md)) and
`prd-from-grill-me` Step 2a
([prd-from-grill-me](../skills/prd-from-grill-me/SKILL.md)). Each caller names
its depth; everything else lives here.

## When to run

Run once per caller run, after the caller's Explore orientation and before its
first question to the user.

| Caller and depth | Lenses dispatched |
|---|---|
| Any caller, no open question after drafting | none — no dispatch |
| `plan`, abbreviated depth (AFK, spike) | Precedent only |
| `plan`, full depth (HITL) | Design, Strategy, Precedent |
| `prd-from-grill-me` | Design, Strategy, Precedent |

On a resumed run (`plan --resume`, or a parked run re-invoked), pin only the
resolved entries in `.stenswf/<N>/decisions.md` — active (not struck through)
and without `Status: parked`. Each parked entry is an unanswered question:
draft it as a question and handle it first. Lens verdicts are never persisted.

## 1. Draft the questions

Write one question per substantive open decision, numbered `Q1`, `Q2`, … —
including interface changes, the behaviors to test and their priority, module
boundaries, and bikesheds.

Pin only resolved, applicable decisions, and leave them out of the questions:

- the issue's acceptance criteria and its `## Conventions (from PRD)` /
  `## Conventions`;
- `## Resolved judgment calls`;
- active entries in `.stenswf/<N>/decisions.md`;
- decisions an inline brief records.

Pinned items still go to every lens as `<PINNED>` context — a lens must respect
them and flag any option that contradicts one.

Tag a question `[business]` (as `Q4 [business] …`) when it asks for required
behavior or a business rule that the issue, the PRD or a recorded decision does
not state. Existing behavior is evidence of what the product does, not
authority for what the change should do.

## 2. Dispatch the lenses

Dispatch the lenses for the run's depth in parallel, in one message, as
read-only subagents. Each lens is dispatched at most once per run; a lens that
fails or returns nothing is not retried — its questions stay open (§3). Do not override the model.

Each dispatch message is three parts pasted verbatim in order — the lens block,
the shared context block, the return format — with the `<…>` slots
substituted.

### Shared context block

```
SUBJECT: <SUBJECT>

ORIENTATION (from the caller's Explore pass):
<ORIENTATION>

QUESTIONS (answer every one; a [business] question asks what the change
should do — existing behavior is evidence, never the answer):
<QUESTIONS>

PINNED (resolved — do not reopen; flag any option that contradicts one):
<PINNED>
```

### Design lens

```
SKILLS TO LOAD: codebase-design, clean-code, brevity

Read-only Design lens for <SUBJECT>. You MUST NOT edit any file or run
state-modifying git/gh commands. Read ranged file context; never cat whole
files needlessly.

Answer each question through module design and code clarity: deep modules
behind small interfaces, where the seam belongs, the deletion test, the
adapter-count question, testability through the public interface, and names
that say what a thing is. Prefer the option that hides the most complexity
behind the smallest interface.
```

### Strategy lens

```
SKILLS TO LOAD: architecture, brevity

Read-only Strategy lens for <SUBJECT>. You MUST NOT edit any file or run
state-modifying git/gh commands. Read ranged file context; never cat whole
files needlessly.

Answer each question through architecture and strategic programming:
ownership and boundaries, reversibility (one-way vs. two-way doors), the
long-term cost of change, and whether the option leaves the design better for
the next change. Weigh options per decision-weighting (linked from
`architecture`): quality, simplicity, robustness, scalability and
maintainability over build cost. Cite a winning practice from a well-known
company when one genuinely informs the choice. You own `also_solves`: name
existing problems in the codebase the recommended option would also fix.
```

### Precedent lens

```
SKILLS TO LOAD: brevity

Read-only Precedent lens for <SUBJECT>. You MUST NOT edit any file or run
state-modifying git/gh commands. Read ranged file context; never cat whole
files needlessly.

Answer each question from what this repository has already decided or
built. Search these sources and cite what you find:

- conventions and decision anchors: `.stenswf/*/conventions.md`,
  `.stenswf/*/decisions.md`, `CLAUDE.md` / `AGENTS.md`;
- recorded decisions and docs: `docs/` (decision records), READMEs,
  reference files;
- git history: `git log --grep='^Decision:'`, `git log -S '<symbol>'`,
  `git log --follow -- <path>`, `git blame -L <range> <path>`;
- issues: `gh issue list --state all --search '<nouns> in:title,body'` for
  open work and earlier rejections;
- codebase analogs, callers, and the public contracts an option would touch.

A convention, an anchor or an analog that settles a question is its
tiebreaker — check that it applies here, not only that it exists. Name any
recorded decision or invariant an option contradicts, qualified by issue
(for example #40/D7).
```

### Return format

```
Return one verdict per question, in question order, with nothing between
verdicts. Give 2–3 lettered options; every option carries its own evidence,
downsides and contradictions:

  Q<n> <lens> — recommend: <letter>
    A) <option> — evidence: <path:line, sha7, #issue> — downsides: <…> — contradicts: #<issue>/D<n> | invariant: <source> | none
    B) <option> — evidence: <…> — downsides: <…> — contradicts: <…>
    also_solves: <existing problem the recommendation also fixes, or none>   tiebreaker: convention | anchor | analog | none (<evidence>)   reversible: yes | no
    uncertain: <what you could not establish, or none>

Precedent — an analog or existing behavior — is never the tiebreaker for a
[business] question.

You may add at most 3 questions the caller missed, numbered Q+1, Q+2, Q+3,
each followed by its own verdict. Add one only if its answer would change
the plan.

End with exactly one line:
  LENS_SUMMARY: <lens> answered=<n> added=<n> tiebreakers=<n> contradictions=<n>
```

## 3. Verify the verdicts

Treat every verdict as a hypothesis, the way
[review-finding-validation.md](review-finding-validation.md) treats review
findings: check it against the current code, requirements, active decisions and
tests, and mark it `confirmed`, `rejected` or `inconclusive`.

- Start from the cited evidence. Expand narrowly only where needed: to check
  that a precedent applies here (its callers, its constraints, later
  decisions), to look for counterevidence that would defeat the
  recommendation, or to resolve a disagreement between lenses. Do not
  re-explore the codebase.
- Drop `rejected` verdicts. Uncertainty you cannot resolve stays
  `inconclusive`, and an inconclusive tiebreaker counts as `none`.
- Never drop a drafted question. One left with no `confirmed` or
  `inconclusive` verdict — every verdict rejected, or its lens failed —
  stays open: research it narrowly yourself, as §6 allows (never a second
  lens dispatch), and hand it to §4 with whatever uncertainty remains.
- When lenses recommend different options, investigate. If a verified,
  applicable tiebreaker decides the question, the lenses only weighted
  different priorities and the question is settled. Only a conflict
  investigation cannot resolve leaves the question without a tiebreaker.
- A `[business]` question has no precedent tiebreaker: only the issue, the PRD
  or a recorded decision can settle it.
- Drop a lens-added question whose answer would not change the plan; keep the
  rest as ordinary questions.

Run a **pre-mortem** on each surviving recommendation — you wrote none of the
verdicts, so you are the critic. Assume it failed a year from now and ask why:
complete every option's `downsides`, check what else a proper solution would
fix (`also_solves`), and apply the business-logic question from
[decision-weighting.md](decision-weighting.md). If the pre-mortem favours
another option, re-verify that option — its evidence, tiebreaker,
reversibility and contradictions — before it becomes the recommendation.

## 4. Classify and ask

Hand each verified question to
[decision-escalation.md](decision-escalation.md)'s classifier. It alone defines
easy and heavy; this file restates no rule. Hand it the verified tiebreaker and
its evidence, the reversibility, the contradictions, the remaining uncertainty,
and whether the choice changes observable behavior not pinned by an AC or
crosses modules. Lens consensus is never a tiebreaker — the lenses are one
model, so their agreement is weak evidence.

- **Easy** → decide it, log it with its source lens as provenance, and list it
  in the digest (§5).
- **Heavy** → ask it with `AskUserQuestion`, per decision-escalation's ASK
  contract. Put the recommended option first, labelled `(Recommended)`; each
  option's description carries that option's own evidence and downsides; name
  the heavy trigger the classifier found.
- **Contradictions.** A conflicting alternative that is not chosen is
  rejected without asking; record its conflict as the rejected-alternative
  reason. Ask `Keep` / `Exempt this work` / `Supersede` only when proceeding
  with the recommended or the chosen option requires an exception to, or a
  supersession of, a recorded decision or invariant:
  - `Keep` — the record holds; choose another option.
  - `Exempt this work` — record a new `arch` anchor that cites the invariant's
    source and scopes the exemption to this work.
  - `Supersede` — record a new anchor with `Supersedes:` and strike the old ID
    through, per [decision-anchor-link.md](decision-anchor-link.md).

  The anchor schema gains no new field.
- **Caller-owned.** Final approval, recording and resume stay with the caller;
  an unattended run parks the approval (see `## Unattended runs`).

## 5. Decided without asking

Before the caller's approval checkpoint, show every easy decision under the
heading `Decided without asking`, one line each:

    - Q<n> <decision> — tiebreaker: <kind> (<evidence>) — via <lens>

A vetoed line becomes a heavy question and is asked per §4. The digest is not
the approval — the caller's approval checkpoint still follows it.

## 6. Changed premises

The lens budget (at most once per run) is separate from ongoing decision
handling. When an answer, a veto or new evidence changes a premise, reopen
every conclusion that depended on it — easy decisions already in the digest
included. Research new or affected questions narrowly — targeted reads or a
targeted Explore, never a second lens dispatch — then verify them per §3 and
classify them per §4. Refresh the digest; if the design the user already
approved changed, ask for approval again. Decisions that surface late, after an
approval checkpoint, go through the same rule.

## Unattended runs

When no user can answer (`STENSWF_UNATTENDED` set, or a dispatch prompt that
says so, per [decision-escalation.md](decision-escalation.md)
`## Availability`), read availability once, at the caller's intake, and apply
it to every user checkpoint — not only to heavy questions. Availability never
changes who decides: what needs the user in an attended run still needs the
user.

- A **heavy question** PARKs per decision-escalation's PARK contract; its
  `DECISION_NEEDED` block carries the verified research.
- A **checkpoint the user owns** — a confirmation the caller asks for, the
  final approval — parks the same way: the pending item is the decision, the
  caller's proposal the recommendation.
- **Easy decisions** are still decided. The `Decided without asking` digest
  goes into the parked block and the caller's decision log instead of to a
  user.

Park everything pending at that point together and halt before any work that
depends on it. Each caller names its park target and its resume steps.
