---
name: deliberate
description: Work a blocking tension out with a peer agent in another harness until it accepts a complete proposal, then record the outcome as a decision.
---

REASONING STYLE: terse internal reasoning, no pre-summaries, no filler.
Turn files, proposals, the result, and any sign-off request remain verbatim.

**Contract.** File layout, turn schemas, the acceptance scheme, the bounds and
the contradiction gate live in
[../../references/deliberation-loop.md](../../references/deliberation-loop.md).
Read it first — you are one half of a protocol and the other half runs somewhere
you cannot see.

**Weighting.** [../../references/decision-weighting.md](../../references/decision-weighting.md)
governs which option wins. **Escalation.** ASK / PARK are defined once, in
[../../references/decision-escalation.md](../../references/decision-escalation.md),
and reused here rather than reinvented.

**Finding validation.** [../../references/review-finding-validation.md](../../references/review-finding-validation.md)
applies to your own earlier turns, not only to B's.

---

You are **agent A** — the one that hit the wall. You own the tension, the
record, and the code. B owns the argument against you.

## Phase 0 — Open, and hand B the path

```bash
source ../../scripts/deliberation.sh
ISSUE=<the issue this session is working>
DIR=$(delib_new "$ISSUE")
```

Write `tension.md` per the contract. Two parts carry the whole deliberation:

- **`## Evidence` is what you verified, not what you believe.** B will check it,
  and an assumption presented as evidence costs a turn to unwind.
- **`## Candidate options` are real options.** A strawman beside your preference
  wastes B's research and teaches it to distrust your framing.

```bash
delib_turn_write "$DIR" 0 A tension.md
cat <<EOF
Start the peer in the other harness with:

  Read plugins/stenswf/skills/deliberate-peer/SKILL.md and follow it.
  Deliberation: $DIR
EOF
```

Hand over the **exact path**. B does not search for its work — that is what
makes it impossible for B to pick up the wrong deliberation.

## Phase 1 — Exchange

```bash
delib_wait "$DIR" "$TURN" "$PROP"   # turn <n> | proposal <n> | accepted <n> | rejected <n> | result | timeout
delib_round_guard "$DIR" || <fall back to ASK / PARK>
```

`$PROP` is the latest proposal version you know about — **including your own**.
Passing anything lower makes the wait return your own proposal immediately, and
you sit in a loop answering yourself while B waits.

Answer per the contract's turn schema. Your turn must **concede a named point,
contest one with evidence new to the exchange, or move your position** — none of
the three is a stall, and two consecutive stalls end the deliberation.

Concede quickly when B is right. The goal is the best solution, not the survival
of your opening position.

Turn files are immutable: `delib_turn_write` refuses to overwrite. If you got a
turn wrong, say so in the next one.

## Phase 2 — Propose until B accepts

When `## Open` is empty, write a **complete** proposal — one that actually
resolves what stopped you in Phase 0, not a direction of travel:

```bash
N=$(delib_propose "$DIR" proposal.md)
delib_wait "$DIR" "$TURN" "$N"           # => accepted <N> | rejected <N> | turn <n>
proposal_verify "$DIR" "$N"              # accepted | stale | pending
```

Pass **`$N`**, the version you just wrote — not `N-1`. The wait returns as soon
as it sees a proposal newer than the number you give it, so `N-1` returns your
own proposal instantly and you answer yourself in a loop while B waits.

If B rejects, `proposal-<N>.rejected-B.md` names the clauses that fail. Revise
into the **next version** — `delib_propose` handles the numbering, and the
rejected version stays readable beside it, which is what lets "B rejected clause
3" keep meaning something.

Do not edit an accepted proposal. `proposal_verify` recomputes the hash, so an
edit turns `accepted` into `stale` — correctly, because B accepted different
words. Write the next version instead.

## Phase 3 — The contradiction gate

```bash
delib_contradictions "$ISSUE" "$DIR/proposal-$N.md"
```

These are **candidates**. Judge which are real — a path match is not a
contradiction, and grep cannot tell the difference.

**A real contradiction means a human signs off, without exception.** Two agents
agreeing is not authority to overturn a call already on record; that record may
carry context neither of you has. Route it through the ASK contract — the
proposal is the recommendation, the entry it would retire is the named
alternative. Unattended → **PARK**. On approval, supersede per the canonical
snippet ([README](../../README.md#supersede-snippet-canonical)).

**`Scope impact: issue-rework` does not pass through this gate.** Record it,
hand it back to the host workflow for re-planning, and let the ordinary
`(r)/(c)/(a)` drift prompt handle the body change
([../../references/drift-check.md](../../references/drift-check.md)). Asking a
human to approve work that contradicts nothing on record is the friction this
mechanism exists to remove.

## Phase 4 — Record and resume

Write the result per the contract, including
`## Prior decisions and invariants examined` — record `(none found)` when the
gate came back clean, so the file shows the check ran rather than leaving a
reader to wonder. Publish it with:

```bash
delib_finish "$DIR" "$N" result.md
```

`delib_finish` is a state transition, not a file write: it refuses unless
proposal `$N` verifies as `accepted` and is the latest version, and it refuses
to replace an existing result. Writing `result.md` by hand bypasses all three
and can close a deliberation over a proposal B rejected.

Then **append the decision anchor** to `.stenswf/$ISSUE/decisions.md` using the
canonical bootstrap and append snippets, **always**. A wall that took two agents
an argument to clear is by definition something a `git blame` reader would ask
about. `Source:` is the host seam — the skill that hit the wall — never
`deliberate`; add `delib#<issue>-<id>` to `Refs:` alongside the paths.

Then **resume exactly where Phase 0 stopped.** The deliberation was an
interruption, not a new task.

## Out of scope (deliberate)

No diff review (that is `review`). No thread handling (that is `apply-loop`). B
never writes code, anchors, or commits — if you are asking B to make a change,
the roles are backwards.

## Feedback

Log friction per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=deliberate` and `STENSWF_ISSUE=$ISSUE`.
