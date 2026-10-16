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

**Callers.** `plan` Phase 1 ([plan](../skills/plan/SKILL.md)). Each caller
names its depth; everything else lives here.

## When to run

Run once per caller run, after the caller's Explore orientation and before its
first question to the user.

| Caller and depth | Lenses dispatched |
|---|---|
| `plan`, full depth (HITL) | Design, Strategy, Precedent |

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
fails or returns nothing is not retried. Do not override the model.

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
