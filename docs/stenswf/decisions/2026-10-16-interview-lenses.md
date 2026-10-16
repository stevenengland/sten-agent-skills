# Decision: Interview lenses (2026-10-16)

Status: **adopted**.
Source: PRD #40, slice #41.
Refs: `plugins/stenswf/references/interview-lenses.md`,
`plugins/stenswf/skills/plan/SKILL.md`,
`plugins/stenswf/skills/prd-from-grill-me/SKILL.md`,
`plugins/stenswf/references/decision-weighting.md`,
`plugins/stenswf/tests/interview-lenses.test.sh`.

## Decision

**Root cause and fix.** The repository's ASK contract already required
researched alternatives and asked only heavy decisions, and `plan-light`
already resolved conventions and analogs before asking anything. Full `plan`
and `prd-from-grill-me` overrode that policy with unconditional interview
instructions: interview relentlessly, confirm interfaces and test priorities,
confirm modules, ask every bikeshed. The fix routes every substantive decision
through one research stage and decision-escalation's unchanged classifier, and
removes those instructions. Final approval stays a separate checkpoint.

**The research stage.** One shared reference with the interface "research
these unresolved decisions under these constraints":

- The caller drafts the questions. Design, Strategy and Precedent research
  them in parallel, at most once per run, each adding at most 3.
- The caller verifies every verdict against code, requirements, decisions and
  tests — starting from the citations and expanding narrowly — investigates
  disagreements, runs a pre-mortem, and re-verifies a replaced recommendation.
  Existing behavior never settles a `[business]` question.
- decision-escalation classifies. Easy decisions go to a vetoable
  `Decided without asking` digest; heavy ones are asked with each option's
  evidence and downsides. `Keep` / `Exempt this work` / `Supersede` is asked
  only when proceeding needs an exception.
- A changed premise reopens the conclusions that depended on it: narrow
  re-research, the same verification and classification, and re-approval if
  the approved design changed. The lens budget stays once per run.
- Resume pins only resolved decisions. Unattended runs PARK and halt; a PRD
  session parks on its intake issue — creating a plain `Intake: <topic>` issue
  when it has none — so a fresh run can resume and nothing is published around
  an open question.
- `decision-weighting` gains the business-logic question for every weighing
  skill.

## Consequences

- **More dispatches.** Up to three extra read-only dispatches per HITL `plan`
  or `prd-from-grill-me` run, one per abbreviated `plan` run, none when
  nothing is open — at most once per run, as with the deepening lens.
- **The topology is a hypothesis.** Three lenses were chosen because the user
  asked for lens subagents, and isolated contexts give each criterion a
  dedicated pass without loading the caller's context. Nothing shows they
  beat a strengthened Explore pass. Only `## When to run` and the lens blocks
  name lenses, so the producer can be swapped on evidence without touching
  verification, classification or the callers.
- **Same-model lenses.** The lenses are not independent authors. This is
  mitigated by verification beyond the citations, the caller's pre-mortem, and
  never counting consensus as a tiebreaker.
- **What the tests cannot show.** `tests/interview-lenses.test.sh` checks
  wiring only. It cannot show that fewer unnecessary questions reach the user,
  that a lens judges well, or that escalation behaves as before — an unchanged
  `decision-escalation.md` is not proof of that, and "the reference restates
  no easy/heavy rule" is a review-time check.
- **Resume re-dispatches open questions.** Verdicts are not persisted;
  resolved anchored decisions are pinned and parked ones are handled first.

## Rejected alternatives

- **Strengthen the existing Explore pass and let the caller apply the Design
  and Strategy criteria**, dispatching a specialist only where uncertainty
  remains. It attacks the policy gap as directly and avoids duplicated
  research and synthesis; there is no evidence it recommends worse. Not chosen
  because the user asked for lens subagents; kept as the comparison point for
  the topology hypothesis.
- **A dedicated critic subagent after the lenses.** Adds a sequential
  dispatch and latency to every run; the caller, which wrote no verdict, runs
  the pre-mortem.
- **Free-roaming lenses that write their own questions.** Noisier, with
  costly dedup.
- **Lens consensus as a tiebreaker.** Correlated errors from one model.
- **Verification limited to the cited evidence.** Cannot catch omitted
  context that defeats a recommendation.
- **Asking about every option that conflicts with a record.** Recreates the
  interviews this change removes.
- **Deferring an unattended PRD session's PARK until Step 5 creates the PRD
  issue.** PARK halts, so reaching Step 5 would bypass approval or publish a
  design built around open questions.
- **Treating easy decisions as final once the interview starts.** An answer
  can undercut the premise an earlier easy decision rested on.
- **A restated easy/heavy rule in the reference.** It drifted from
  decision-escalation by dropping its behavior-change and cross-module
  triggers.
- **A new `Exempts:` anchor field.** The existing `Supersedes:` and a new
  `arch` entry suffice.

## Carved invariants

- `decision-escalation.md` is unchanged and remains the only easy/heavy
  definition.
- No unilateral heavy decision.
- PARK halts, and nothing is published around a parked question.
- Final approval stays a separate checkpoint.
- `decision-weighting`'s `### Strategic over tactical` subsection is
  unchanged.
- `plan-light` is out of scope.
- `tdd` stays in every SKILLS TO LOAD list.
