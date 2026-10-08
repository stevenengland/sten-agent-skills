---
name: deliberate
description: Work a blocking tension out with a peer agent in another harness until it accepts a complete proposal, then record the outcome as a decision.
---

REASONING STYLE: terse internal reasoning, no pre-summaries, no filler.
Moves — tension, turns, proposals, the result — and any sign-off request remain verbatim.

**Contract.** Layout, move rules, schemas, bounds, outcomes and the
contradiction gate live in
[../../references/deliberation-loop.md](../../references/deliberation-loop.md).
Read it first — you are one half of a protocol and the other half runs somewhere
you cannot see.

**Weighting.** [../../references/decision-weighting.md](../../references/decision-weighting.md)
governs which option wins. **Escalation.** ASK / PARK are defined once, in
[../../references/decision-escalation.md](../../references/decision-escalation.md).
**Finding validation.** [../../references/review-finding-validation.md](../../references/review-finding-validation.md)
applies to your own earlier moves, not only to B's.

---

You are **agent A** — the one that hit the wall. You own the tension, the
record, and the code. B owns the argument against you.

## Phase 0 — Open, and hand B the path

Write `tension.md` per the contract's schema, then:

```bash
source ../../scripts/deliberation.sh
ISSUE=<the issue this session is working>
DIR=$(delib_new "$ISSUE" tension.md) || exit 1
delib_bootstrap "$DIR"        # print this for the user to start B with
```

## Phase 1 — Exchange until B accepts

Loop:

```bash
delib_wait "$DIR" A    # open A <move> | capped <move> | ended <outcome> <move> | timeout
```

Read the status word first — `capped …-reject.md` is a cap, not a rejection to
revise — then the move it names, and answer it:

| Woken by | Your move |
|---|---|
| `open A …-turn.md` | `delib_move "$DIR" A turn turn.md` — or, once `## Open` is empty, `delib_move "$DIR" A proposal proposal.md` |
| `open A …-reject.md` | revise: `delib_move "$DIR" A proposal proposal.md` — or argue: `… A turn turn.md` |
| `open A …-accept.md` | Phase 2 |
| `capped`, `timeout`, or two consecutive stalls | Phase 3 |
| `ended cancelled …` | B withdrew — Phase 3's fallback, without a move |

Every turn must **concede a named point, contest one with evidence new to the
exchange, or move your position.** Concede quickly when B is right; the goal is
the best solution, not the survival of your opening position.

A proposal must be **complete** — it resolves what stopped you in Phase 0. Never
edit one once written: propose again.

`delib_move` exits 3 once the round cap is spent — go to Phase 3.

## Phase 2 — The contradiction gate, then agree

```bash
delib_contradictions "$ISSUE" "$DIR/<NN>-A-proposal.md"   # the proposal B accepted
```

Judge each candidate — a path match is not a contradiction. **A real
contradiction means a human signs off, without exception**: route it through
ASK, the proposal as recommendation and the entry it would retire as the named
alternative. Approved → continue. Declined → revise (`proposal`) or Phase 3.
Unattended → Phase 3, `parked`.

`Scope impact: issue-rework` **does not pass through this gate** — record it
and hand it back to the host workflow
([../../references/drift-check.md](../../references/drift-check.md)).

Write the result per the contract — including
`## Prior decisions and invariants examined`, `(none found)` when clean — and:

```bash
delib_move "$DIR" A agreed result.md    # refused unless B's acceptance still verifies
```

Then **append the decision anchor** to `.stenswf/$ISSUE/decisions.md` with the
canonical bootstrap and append snippets, **always**. `Source:` is the host seam,
never `deliberate`; add `delib#<issue>-<id>` to `Refs:`.

Then **resume exactly where Phase 0 stopped.** The deliberation was an
interruption, not a new task.

## Phase 3 — End without agreement

```bash
delib_move "$DIR" A escalated why.md   # a human is reachable
delib_move "$DIR" A parked why.md      # unattended
delib_move "$DIR" A cancelled why.md   # B never arrived, or the question went away
```

`why.md` names the bound that ended it and both positions. Then run the
**existing** ASK or PARK from decision-escalation.md, with the transcript as the
alternatives block.

## Out of scope (deliberate)

No diff review (that is `review`). No thread handling (that is `apply-loop`). B
never writes code, anchors, or commits — if you are asking B to make a change,
the roles are backwards.

## Feedback

Log friction per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=deliberate` and `STENSWF_ISSUE=$ISSUE`.
