# Deliberation loop (shared contract)

The contract for `deliberate` (agent **A**, who hit the wall) and
`deliberate-peer` (agent **B**, the challenging peer). The two run in
**separate harnesses** — Claude Code, Codex, anything with a shell and a
checkout — and share exactly one thing: a directory of files.

> **Canonical plumbing.** The functions live in
> [`../scripts/deliberation.sh`](../scripts/deliberation.sh). Skills source that
> file — do not duplicate the bodies here or in any skill.

## What this is for

A heavy decision otherwise has two outcomes
([decision-escalation.md](decision-escalation.md)): **ASK** a human, or **PARK**
when no human is reachable. Both hand the problem to someone with less context
than the agent that stopped.

Deliberation is the third: A states the tension with its evidence and options; B
studies the code, docs, history and issues, then argues for the best solution —
one of A's or its own. They exchange turns until B accepts a complete proposal
of A's.

**The governing invariant is "no *unilateral* heavy decisions", not "no
autonomous" ones.** A countersigned peer agreement is a legitimate resolution:
two agents that argued to a written, verifiable agreement have done more than a
single agent guessing, and more than a human answering a question they have less
context for. What still requires a human is **contradicting the record** — see
[The contradiction gate](#the-contradiction-gate).

## State

```
.stenswf/<issue>/deliberations/<id>/
├── tension.md                  A, turn 0
├── 01-B.md
├── 02-A.md
├── proposal-1.md               A's complete proposal
├── proposal-1.rejected-B.md    B's verdict: the clauses that fail
├── proposal-2.md               A's revision
├── proposal-2.accepted-B       B's verdict: the hash B computed
└── result.md                   closes the deliberation
```

**A creates the directory and hands B the exact path.** There is no discovery,
no search, and no environment variable — each of those turns "which
deliberation is this?" into a question that can be answered wrongly, and the id
in the path is what lets one issue hit two walls without the second overwriting
the first.

**Turn and proposal files are immutable.** `delib_turn_write` and
`delib_propose` refuse to clobber. A transcript you can rewrite is not evidence,
and "B rejected clause 3" has to keep pointing at readable text after clause 3
is replaced.

**`result.md` is the only thing that ends a deliberation.** Not a proposal — a
proposal awaits a verdict, so the exchange is still live. Ending it at the
proposal is exactly what makes a rejection impossible.

It is written by `delib_finish`, never by hand: closing is a state transition,
and each way it can go wrong is silent. A result over an unaccepted proposal
records a decision the peer never agreed to; over a superseded version, the one
B rejected; a second result quietly replaces the first. `delib_finish` refuses
all three.

**Once a proposal exists, it — not the turn parity — says whose move it is.**
Parity only orders the free-form exchange. An unjudged proposal is B's move; a
verdict of *either* kind returns control to A, to revise after a rejection or to
run the gate and finalize after an acceptance. Letting parity answer over a
proposal puts the wrong agent on both ends of the handover, and both sides wait.

## The exchange

**Turn 0 — `tension.md`,** written by A:

```markdown
# Tension — #<issue>

- **Issue:** #<issue>
- **Host seam:** <the skill that hit the wall>
- **Blocked at:** <what A was doing when it stopped>

## What blocks
<the fork, and why neither branch is obviously right>

## Evidence
<what A verified — paths, symbols, SHAs, test output. Not what it assumes.>

## Open questions
- Q1 — <question>

## Candidate options
### O1 — <title>   (Pro / Con)
### O2 — <title>   (Pro / Con)

## A's lean
<O#> — <why>

## Open
Q1, O1-vs-O2
```

**Turns 1..n — `NN-<role>.md`,** alternating:

```markdown
# Turn <n> — <A|B>

## Read
<what this turn studied, with identifiers: paths, symbols, SHAs, issue numbers>

## Concede
<points accepted, by id — or `(none)`>

## Contest
<points rejected, each with the evidence that rejects it — or `(none)`>

## Position
<where this side now stands>

## Open
<ids still unresolved — or `(none)`>
```

`## Read` is what makes "study it thoroughly" checkable. A turn that cites
nothing studied nothing, and the other side should say so.

A turn that concedes nothing, contests nothing new, and moves nothing is a
**stall**. Two consecutive stalls end the deliberation. **This is a judgement
the agents make, not something the script detects** — no assertion can tell a
restatement from an argument, so do not read a green test run as enforcement.

## Proposal and acceptance

When the ledger is empty, A writes a **complete proposal** —
`delib_propose` versions it:

```markdown
# Proposal <n> — #<issue>

- **Solves:** <the tension, one sentence>
- **Category:** arch | decision

## Solution
<complete enough to implement — it must actually resolve what stopped A>

## Rejected
<the alternatives, and why each loses>

## Consequences
<what this forces elsewhere>

## Refs
<every file path the decision implicates, comma-separated>

## Scope impact
none | issue-rework: <what the issue must become>
```

B then does exactly one of two things:

- **Accept** — `delib_accept <dir> <n>` records the hash **B** computed over
  the proposal text. A's acceptance is its authorship; there is no counterpart
  file for A and nothing for A to sign.
- **Reject** — `delib_reject <dir> <n> <file>` records the clauses that fail and
  why. A revises into `proposal-<n+1>.md`; the rejected version stays readable
  beside it. The artifact matters: a rejection written only as prose in a turn
  leaves the proposal awaiting a verdict as far as the protocol can see, so
  control never returns to A and both sides wait.

When A waits after proposing, it passes **its own version number**. `delib_wait`
returns on a proposal *newer* than the number given, so passing `n-1` returns
A's own proposal at once and A answers itself in a loop while B waits.

`proposal_verify <dir> <n>` prints `accepted` | `stale` | `pending` and
**recomputes the proposal's hash every time**. `stale` is the case worth having:
the proposal was accepted and has since changed, so the acceptance no longer
covers what the file says. Comparing two stored signatures would call that
`accepted` forever — which is not a countersignature, only a decoration.

## Bounds

| Bound | Default | Enforced by |
|---|---|---|
| Round cap | `DELIB_MAX_ROUNDS` 6 | `delib_round_guard` — non-zero exit past the cap |
| Peer absent | `DELIB_PEER_TIMEOUT` 1800s | `delib_wait` returns `timeout` |
| Two consecutive stalls | — | **the agents' judgement, not the script** |

All three land in the same place: the **existing** ASK when a human is
reachable, PARK when unattended. The transcript becomes the alternatives block,
so a deliberation that fails to converge costs a delay and loses no research.

## Priority — the system over the issue

B loads [decision-weighting.md](decision-weighting.md), which governs *which*
option wins. This contract adds what that file does not cover: **serving the
system beats serving the issue as written.** If the sound solution points
somewhere the issue did not intend, that is a finding — declare it as
`Scope impact: issue-rework`.

Both agents apply
[review-finding-validation.md](review-finding-validation.md): every claim is a
hypothesis regardless of author, including your own from the last turn. Two
agents that defer to each other converge fast and badly.

## The contradiction gate

Before recording, A runs `delib_contradictions`, which searches every tier that
already holds a decision for the proposal's `Refs:` paths: local and archived
anchors (naming the **entry** whose own `Refs:` carries the path, not every
header in the file), `docs/stenswf/decisions/`, `Touches:` commit trailers, and
the house rules.

**Paths are matched literally, never as patterns.** A real path routinely
contains regex metacharacters — `app/[id]/page.tsx`, `pages/(group)/x.ts`,
`lib/a+b.ts` — and matching one as a regex silently finds nothing. That is the
worst failure this feature has: a miss here walks a genuine contradiction past a
*mandatory* human sign-off, and reports success while doing it. The git tier
pays for this by searching whole commit messages rather than just `Touches:`
trailers, since a literal pattern cannot also carry the `^Touches:` anchor.
Over-reporting costs A one judgement call; under-reporting costs the gate.

**The script supplies candidates; A judges which are real.** Whether one
decision contradicts another is a question about meaning that a path match
cannot answer — the same division of labour `review` already uses. Because the
search errs toward extra candidates, expect to dismiss some.

A real contradiction requires **human sign-off**, via the ordinary ASK contract:
the proposal is the recommendation, the entry it would retire is the named
alternative. On approval, supersede per the
[canonical snippet](../README.md#supersede-snippet-canonical), category matching
the superseded entry. Unattended → **PARK**.

**Only a contradiction triggers this gate.** `Scope impact: issue-rework` does
*not*: reworking an issue is the host workflow's ordinary business — record it,
hand it back for re-planning, and let the existing `(r)/(c)/(a)` drift prompt do
its job when the body changes. Gating it here would put a human in front of a
decision that no recorded call disagrees with, which is the thing this whole
mechanism exists to avoid.

## Result and recording

A writes the result with `delib_finish "$DIR" "$N" result.md` — the accepted
proposal plus what the gate found:

```markdown
# Result — #<issue>

- **Proposal:** <n> (accepted-B <hash>)
- **Turns:** <n>

## Decision
<the accepted solution>

## Prior decisions and invariants examined
<what delib_contradictions surfaced and what A judged of each — `(none found)`
 is a valid entry, and saying so is the point: it records that the check ran>

## Contradictions
none | <entry> — signed off by <who>, <when>

## Scope impact
none | issue-rework: <handed back to the host workflow>
```

Then **A appends a decision anchor before resuming** — always. A deliberation is
by definition a call someone doing `git blame` would ask about, so the
qualification tests are already satisfied; there is no case where two agents
argued a wall to a written agreement and the result is not worth recording.

- `Source:` is the **host seam** — the skill that hit the wall — never
  `deliberate`, per [decision-anchor-link.md](decision-anchor-link.md).
- `Refs:` carries `delib#<issue>-<id>` alongside the file paths.

From there the existing tiers carry it: commit trailers at the next commit, the
published PR-body and issue-comment block, the curated excerpt at PRD close. No
new tier.

**A is the sole writer** of code, anchors and commits. **B writes turn files and
acceptance files, nothing else.**

## What B needs

A checkout, a shell, and this repository. **Transport is offline; research is
not.** B is asked to study open issues and history — `git log` and `git blame`
work from any clone, but reading issues needs `gh` or a browser. Where B has
neither, it says so in its `## Read` section rather than quietly skipping that
source, because A weighs B's argument by what it actually examined.

Where the harness cannot load a plugin skill, A's bootstrap line carries
everything B needs:

```
Read plugins/stenswf/skills/deliberate-peer/SKILL.md and follow it.
Deliberation: .stenswf/42/deliberations/7f3a1c/
```
