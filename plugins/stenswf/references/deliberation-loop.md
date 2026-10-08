# Deliberation loop (shared contract)

The contract for `deliberate` (agent **A**, who hit the wall) and
`deliberate-peer` (agent **B**, the challenging peer). The two run in
**separate harnesses** — Claude Code, Codex, anything with a shell — and share
exactly one thing: a directory of files. This file is the authority; the skills
are procedure and do not restate it.

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
one of A's or its own. They exchange moves until B accepts a complete proposal
of A's, or the deliberation ends without one and falls back to ASK / PARK.

**The governing invariant is "no *unilateral* heavy decisions", not "no
autonomous" ones.** Two agents that argued to a written, verifiable agreement
have done more than a single agent guessing, and more than a human answering a
question they have less context for. What still requires a human is
**contradicting the record** — see [The contradiction gate](#the-contradiction-gate).

## State — one directory of numbered moves

```
.stenswf/<issue>/deliberations/<id>/
├── 00-A-tension.md
├── 01-B-turn.md
├── 02-A-proposal.md
├── 03-B-reject.md       the clauses that fail
├── 04-A-turn.md         A may discuss a rejection instead of revising
├── 05-B-turn.md
├── 06-A-proposal.md
├── 07-B-accept.md       the hash B's side computed over 06
└── 08-A-agreed.md       the result; ends the deliberation
```

Every move is one file, `NN-<role>-<kind>.md`, and **the highest `NN` is the
whole state.** There is no second record that could drift from the files:
`delib_status` derives everything from the latest move, and `delib_move` is the
only writer.

- **A creates the directory and hands B the exact path** (`delib_new`, then
  `delib_bootstrap`). No discovery, no search, no environment variable — each
  turns "which deliberation is this?" into a question that can be answered
  wrongly. The id lets one issue hit two walls; a colliding id is retried,
  never reused.
- **Moves are immutable.** `delib_move` never overwrites, and it reserves each
  number atomically, so two sides moving at once cannot both take it. A
  transcript you can rewrite is not evidence, and "B rejected clause 3" has to
  keep pointing at readable text after clause 3 is replaced. Got a move wrong?
  Say so in the next one.
- **Whose move it is follows from who moved last** — the other side. One rule,
  for turns, proposals and verdicts alike; there is no parity and no special
  case for proposals.

## Moves

| kind | who | allowed when |
|---|---|---|
| `tension` | A | move 00, once — `delib_new` writes it |
| `turn` | A or B | their move, and they are not owed a verdict |
| `proposal` | A | A's move |
| `accept` | B | the latest move is a proposal; records the hash computed over it |
| `reject` | B | the latest move is a proposal; names the clauses that fail |
| `agreed` | A | the latest move is an `accept` that still verifies |
| `parked` | A | any time |
| `escalated` | A | any time |
| `cancelled` | A or B | any time |

`delib_move <dir> <A|B> <kind> [file]` refuses anything else: exit 1 when the
move is not allowed, 2 on bad arguments, **3 when the round cap is spent**.

`delib_status <dir>` prints exactly one of `open A` | `open B` | `capped` |
`ended <agreed|parked|escalated|cancelled>` | `none`.

`delib_wait <dir> <role>` blocks until it is *that role's* move or the
deliberation ends, then prints the status and the latest move's file — e.g.
`open A 03-B-reject.md` — or `timeout`. A is also woken by `capped`, because only
A can close a capped deliberation. The wait is role-aware, so there is no cursor
to pass and no way to wake on your own move or sleep through the peer's.

## The exchange

**`00-A-tension.md`:**

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

`## Evidence` is what A verified, not what it believes — B will check it. The
`## Candidate options` are real options; a strawman beside A's preference wastes
B's research.

**Turns:**

```markdown
# Turn <NN> — <A|B>

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
**stall**. Two consecutive stalls end the deliberation (see
[Bounds and endings](#bounds-and-endings)). **This is a judgement the agents
make, not something the script detects** — no assertion can tell a restatement
from an argument.

## Proposal and verdicts

When `## Open` is empty, A's move is a **complete proposal** — one that actually
resolves what stopped A, not a direction of travel:

```markdown
# Proposal — #<issue>

- **Solves:** <the tension, one sentence>
- **Category:** arch | decision

## Solution
<complete enough to implement>

## Rejected
<the alternatives, and why each loses>

## Consequences
<what this forces elsewhere>

## Refs
<every file path the decision implicates, comma-separated>

## Scope impact
none | issue-rework: <what the issue must become>
```

B owes it exactly one verdict:

- **Accept** — `delib_move <dir> B accept`. The function records the proposal's
  file and the hash it computed over it. A's acceptance is its authorship; there
  is nothing for A to sign.
- **Reject** — `delib_move <dir> B reject <file>`, naming **which clauses** fail
  and the evidence. A then revises (a new `proposal`) or argues (a `turn`); the
  rejected text stays readable either way.

**Acceptance is verified by recomputing the hash, never by comparing stored
values.** `proposal_verify <dir>` prints `accepted` | `stale` | `pending`.
`stale` is the case worth having: the proposal changed after B accepted it, so
the acceptance no longer covers what the file says, and `agreed` is refused.
The hash forgives CRLF, trailing whitespace and blank-line runs; any rewording
changes it. Do not edit a proposal — propose again.

## Bounds and endings

| Bound | Default | Enforced by |
|---|---|---|
| Round cap | `DELIB_MAX_ROUNDS` 6 | `delib_move` — exit 3 once `2 × cap` moves follow the tension |
| Peer absent | `DELIB_PEER_TIMEOUT` 1800s | `delib_wait` returns `timeout` |
| Peer never arrives (PR loop) | `DELIB_HANDSHAKE_TIMEOUT` 600s | A's first `delib_wait` |
| Two consecutive stalls | — | **the agents' judgement, not the script** |

**Every move counts toward the cap** — turns, proposals and verdicts alike. Past
it, a verdict B already owes is still allowed, and so is the `agreed` an
acceptance makes possible; nothing else is. A wakes on `capped` and must close.

**Every deliberation ends in exactly one terminal move:**

| Outcome | Written by | When | Then |
|---|---|---|---|
| `agreed` | A | B accepted, the gate cleared | record the anchor, resume |
| `escalated` | A | cap, stalls, B absent, or a contradiction — and a human is reachable | the existing **ASK**, the transcript as its alternatives block |
| `parked` | A | the same, unattended | the existing **PARK** |
| `cancelled` | A or B | the other side never arrived or went away, or the question disappeared | ASK / PARK if the question still stands |

Nothing ends a deliberation except one of these, and nothing follows one. A
deliberation that fails to converge costs a delay and loses no research.

## Priority — the system over the issue

B loads [decision-weighting.md](decision-weighting.md), which governs *which*
option wins. This contract adds: **serving the system beats serving the issue as
written.** If the sound solution points somewhere the issue did not intend, that
is a finding — declare it as `Scope impact: issue-rework`.

Both agents apply
[review-finding-validation.md](review-finding-validation.md): every claim is a
hypothesis regardless of author, including your own from the last move. Two
agents that defer to each other converge fast and badly.

## The contradiction gate

After B accepts and before `agreed`, A runs
`delib_contradictions <issue> <proposal-file>`. It searches every tier that
already holds a decision for the proposal's `## Refs`:

- **anchor** — active entries in local and archived `decisions.md` whose own
  body carries the path (the *entry*, not every header in the file);
- **committed** — `docs/stenswf/decisions/`;
- **git** — commit messages, whole, so a squash cannot hide a `Touches:` trailer;
- **house** — `CLAUDE.md`, `AGENTS.md`, `conventions.md`, **always** listed.

A miss here walks a genuine contradiction past a *mandatory* human sign-off and
reports success while doing it, so the search errs toward extra candidates:

- **Paths match literally, never as patterns** — `app/[id]/page.tsx` is a path.
- **Refs are normalised as agents write them** — list bullets, backticks,
  quotes, a leading `./`, and a trailing `:12` or `#L4-L9` are stripped. Every
  remaining token is searched, including root-level names like `Dockerfile`.
- **Nothing is dropped silently.** Every matching entry is printed; past
  `DELIB_GIT_HITS` (20) commits, the git tier prints an explicit "N more" line
  with the command that lists them.

**The script supplies candidates; A judges which are real.** Whether one
decision contradicts another is a question about meaning.

A real contradiction requires **human sign-off** via the ordinary ASK contract:
the proposal is the recommendation, the entry it would retire is the named
alternative. Approved → `agreed`, then supersede per the
[canonical snippet](../README.md#supersede-snippet-canonical). Declined → revise
or `escalated`. Unattended → `parked`.

**Only a contradiction triggers this gate.** `Scope impact: issue-rework` does
not: reworking an issue is the host workflow's business — record it, hand it
back for re-planning, and let the existing `(r)/(c)/(a)` drift prompt handle the
body change.

## Result and recording

A's `agreed` move is the result:

```markdown
# Result — #<issue>

- **Proposal:** <NN> (accepted in <NN>)

## Decision
<the accepted solution>

## Prior decisions and invariants examined
<what delib_contradictions surfaced and what A judged of each — `(none found)`
 is a valid entry, and saying so records that the check ran>

## Contradictions
none | <entry> — signed off by <who>, <when>

## Scope impact
none | issue-rework: <handed back to the host workflow>
```

Then **A appends a decision anchor before resuming — always.** A wall two agents
argued to an agreement is by definition something a `git blame` reader would
ask about.

- `Source:` is the **host seam**, never `deliberate`, per
  [decision-anchor-link.md](decision-anchor-link.md).
- `Refs:` carries `delib#<issue>-<id>` alongside the file paths.

From there the existing tiers carry it. No new tier.

## Who writes what

**A** writes its moves, the code, the anchor and the commits. **B writes its
moves — turns, verdicts, and `cancelled` — and nothing else:** no source edits,
no git, no anchors, no issue or PR edits. One writer of everything outside the
directory is what makes two harnesses safe against one repository.

## What B needs

A shell, a checkout that **contains A's directory**, and the plugin.
`delib_bootstrap` prints both ways to start B: the installed skill
(`/stenswf:deliberate-peer <absolute dir>`), and, for a harness without the
plugin, the resolved path of the installed skill file to read instead.

**Transport is files; research is not.** `git log` and `git blame` work from any
clone, but reading issues needs `gh` or a browser. Where B cannot reach a
source, it says so in `## Read` rather than skipping it, because A weighs B's
argument by what it actually examined.

## PR-loop mode — `apply-loop` as A, `review-loop` as B

The one automatic entry: `apply-loop` opens a deliberation on a re-raised thread
or a heavy fix (see [pr-conversation-loop.md](pr-conversation-loop.md)), and the
reviewer argues as B.

**It requires both loops to share one checkout.** The PR-loop contract does not
otherwise assume a shared tree, and these files are local, so a reviewer in
another checkout would neither see the deliberation nor know to hold its
approval. Hence:

- **Opt-in:** the user sets `STENSWF_DELIB_SHARED_CHECKOUT=1`.
- **Validation:** `delib_pr_peer_ready <issue>` also requires
  `.stenswf/<issue>/loop-state.reviewer.json` in this tree — the reviewer's own
  cache, so its presence shows the reviewer writes here. Either check failing
  means **no deliberation**: the decision goes straight to ASK / PARK.
- **Handshake:** A's first wait uses `DELIB_HANDSHAKE_TIMEOUT`. No reviewer move
  by then → `cancelled`, then ASK / PARK.
- **Wake-up:** the reviewer waits on the PR, which is quiet while A argues, so A
  replies on the thread with a `<!-- stenswf-delib: <id> -->` marker. That wakes
  `wait_for_change` and leaves the deliberation visible on the PR. It is a
  signal, not transport — the moves stay in files.
- **Host seam filter:** the reviewer takes only deliberations whose tension
  names `apply-loop` as the host seam, so it never answers one opened for
  another peer.

The remaining risk is a stale reviewer cache left in this checkout by an earlier
run while the reviewer now runs elsewhere. The handshake bounds it: that
deliberation is cancelled after `DELIB_HANDSHAKE_TIMEOUT`, and the thread stays
`disputed`, which no reviewer converges over.
