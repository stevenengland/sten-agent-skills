---
name: wayfinder
description: Chart a too-big-for-one-session idea as a shared map of investigation tickets on the issue tracker, resolved one at a time until the way to a PRD is clear.
disable-model-invocation: true
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).
Map bodies, ticket bodies, and resolution comments are full-prose artifacts —
`brevity` does NOT apply to them, only to narration and the interview.

A loose idea has arrived — too big for a single `grill-me` / `prd-from-grill-me`
session, and wrapped in fog: the way from here to a writable **PRD** isn't
visible yet. Wayfinding is about finding that way, not charging at the
destination. This skill sits **before** `grill-me` and `prd-from-grill-me`: it
charts the fog as a **shared map** on the repo's issue tracker, works its
tickets one at a time until the route is clear, then hands the cleared
decisions to `prd-from-grill-me`.

The destination varies per effort, and naming it is the first act of charting —
it shapes every ticket. For stenswf it is usually *"enough clarity to write the
PRD(s)"*: the decision or spec that `prd-from-grill-me` needs and can't yet
extract in one interview. It might instead be a decision to lock before planning
starts, or a change made in place like a data-structure migration. The map is
domain-agnostic.

## Plan, don't do

Wayfinder is **planning** by default: each ticket resolves a decision, and the
map is done when the way is clear — nothing left to decide before someone writes
the PRD. The pull to just do the work is usually the signal you've reached the
edge of the map and it's time to hand off (see [Handoff](#handoff-to-prd-from-grill-me)).
Code is `ship`'s job downstream, never the map's — TDD-as-lens does not apply
here because wayfinder produces decisions, not behavior. An effort can override
this in its **Notes** — carrying execution into the map itself — but absent that,
produce decisions, not deliverables.

## Refer by name

Every map and ticket is an issue, so it has a **name** — its title. In
everything the human reads — narration, the map's Decisions-so-far — refer to it
by that name, never by a bare id, number, or slug. A wall of `#42, #43, #44` is
illegible; names read at a glance. The id and URL don't vanish — a name wraps its
link, and `blocked_by:` front-matter still stores bare numbers for machine
parsing — but in prose the number rides *inside* the name, never stands in for it.

## The Map

The map is a single issue on this repo's issue tracker, its front-matter marked
`type: wayfinder` — the canonical artifact. stenswf uses **no labels**; the
front-matter marker is how every lifecycle skill detects it. Its tickets are
child issues (`type: wayfinder-ticket`) linked by a `Parent map: #<map>` body
line and a `map_ref:` front-matter key.

The map is an **index**, not a store. It lists the decisions made and points at
the tickets that hold their detail; a decision lives in exactly one place — its
ticket — so the map never restates it, only gists it and links.

**The tracker is the map's only live state.** The map issue and its tickets are
canonical; each decision's full record is its ticket's resolution comment, and
the map body's *Decisions so far* indexes them. The local tree
`.stenswf/<map#>/` holds identity (`manifest.json`, `kind: "map"`) and assets —
nothing that mirrors the tracker. The **decision anchor** `decisions.md` is
**generated at handoff** from the resolved tickets, not maintained alongside them:
a derived artifact cannot go stale, and parallel sessions never write to it.
Body template, ticket template, local-tree seed, and every tracker operation
live in [../../references/wayfinder-map.md](../../references/wayfinder-map.md);
the operations that assume a concurrent writer live in
[../../scripts/wayfinder.sh](../../scripts/wayfinder.sh).

## Tickets

Each ticket is a **child issue** of the map; the tracker's issue id is its
identity. Its body is a single `## Question` — the decision or investigation it
resolves — sized to one agent session. Front-matter carries `type:
wayfinder-ticket`, `ticket_type:` (one of `research` / `prototype` / `grilling`
/ `task`), `map_ref:`, and — once wired — `blocked_by:`.

A session **claims** a ticket **first**, before any work, via `claim_ticket`:
it assigns the issue to the dev driving the map — an open, unassigned ticket is
unclaimed — and posts a claim comment carrying a per-session token. The
**earliest claim comment wins**, and a session that loses withdraws and takes
the next frontier ticket.

The token is what makes the claim mean something. Assignment is a set with no
compare-and-set, and two sessions of the same human assign identically, so a
loser could never detect the collision by reading assignees. Even so this is
detection, not exclusion: a narrow window remains between reading the frontier
and the claim landing (see
[../../references/wayfinder-map.md](../../references/wayfinder-map.md#claim-a-ticket)).

Blocking uses the stenswf **`blocked_by:` front-matter** convention (no labels,
no reliance on tracker-native dependency edges): a space-separated list of the
issue numbers that must close first. A ticket is **unblocked** when every ticket
in its `blocked_by` is closed; the **frontier** is the open, unblocked,
unclaimed children — the edge of the known. Because ids only exist after
creation, wire blocking in a **second pass**: create the tickets, then edit each
blocked ticket's front-matter to add `blocked_by:`.

The answer isn't part of the body — it's recorded on resolution (see [Work
through the map](#work-through-the-map)). Assets created while resolving a ticket
are linked from the issue, not pasted in.

## Ticket Types

Every ticket is either **HITL** — human in the loop, worked *with* a human who
speaks for themselves — or **AFK**, driven by the agent alone. A HITL ticket only
resolves through that live exchange; the agent never stands in for the human's
side of it (a grilling agent that answers its own questions has broken this).

- **Research** (AFK): Reading documentation, third-party APIs, or local
  knowledge. Dispatch an **Explore subagent**; save its report as a markdown
  asset under `.stenswf/<map#>/assets/` and link it from the ticket. Use when
  knowledge outside the working directory is required.
- **Prototype** (HITL): Raise the fidelity of the discussion by making a cheap,
  rough, concrete artifact to react to — an outline, a rough take, a stub, or a
  sketch (consult `architecture` for design shape when useful). stenswf has no
  dedicated prototyping skill; the artifact can be as light as a bullet list.
  Link it as an asset. Use when "how should it look / behave" is the key question.
- **Grilling** (HITL): Conversation via the `grill-me` skill, one question at a
  time. The default case.
- **Task** (HITL or AFK): Manual work that must happen before a *decision* can be
  made — nothing to decide, prototype, or research, but the discussion is blocked
  until it's done (signing up for a service so its API can be judged,
  provisioning access, moving data so its shape can be seen). This is the one
  type that *does* rather than decides — it earns its place by unblocking a
  decision, not by delivering the destination. The agent drives it alone where it
  can (AFK); otherwise it hands the human a precise checklist (HITL). Resolved
  when the work is done; the answer records what was done and any resulting facts
  (credentials location, new URLs, row counts) later tickets depend on.

**Run mode.** Wayfinder is HITL-first. When run unattended
(`STENSWF_UNATTENDED`), only AFK tickets (`research`, AFK `task`) may be
resolved; any HITL ticket is **parked** — leave it on the frontier and note the
skip. Never let an agent answer a grilling or prototype ticket on the human's
behalf.

## Fog of war

The map is _deliberately_ incomplete: don't chart what you can't yet see. Beyond
the live tickets lies the **fog of war** — the dim view of decisions you can tell
are coming but can't yet pin down, because they hang on questions still open.
Resolving a ticket clears the fog ahead of it, graduating whatever's now
specifiable into fresh tickets — one at a time, until the way is clear and no
tickets remain.

The map's **Not yet specified** section is where that dim view is written down.
It's the undiscovered frontier _toward_ the destination — everything here is in
scope, just not sharp enough to ticket.

**Fog or ticket?** The test is whether you can state the question precisely now —
_not_ whether you can answer it now.

- **Ticket when** the question is already sharp — even if it's blocked.
- **Not yet specified when** you can't yet phrase it that sharply. Don't
  pre-slice the fog: one patch may graduate into several tickets, or none, once
  the frontier reaches it.

**Not yet specified** excludes what's already decided (Decisions so far), what's
already a live ticket, and what's out of scope.

## Out of scope

The destination fixes the scope, so work beyond it is **out of scope** — it isn't
fog, and it doesn't belong in **Not yet specified**. It gets its own **Out of
scope** section on the map: work you've consciously ruled out of _this_ effort.

Out-of-scope work never graduates — the frontier stops at the destination — so it
returns only if the destination is redrawn, and then as a fresh effort. When a
ticket that already exists turns out to sit past the destination, **close it**
and leave one line in **Out of scope**: the gist plus why, linking the closed
ticket. It stays out of **Decisions so far**, which records the route actually
walked.

## Invocation

Two modes. Either way, **never resolve more than one ticket per session.**

### Chart the map

User invokes with a loose idea.

1. **Name the destination.** Run a `grill-me` session to pin down what this map
   is finding its way to — usually the clarity `prd-from-grill-me` needs. The
   destination fixes the scope, so it's settled first.
2. **Map the frontier.** Grill again, **breadth-first** this time: fan out across
   the whole space rather than deep on any one thread, surfacing the open
   decisions and the first steps takeable now. **If this surfaces no fog** — the
   way is already clear, small enough for one PRD session — you don't need a map.
   Stop and tell the user to run `prd-from-grill-me` directly.
3. **Create the map** (`type: wayfinder`) and seed its `.stenswf/<map#>/` tree
   per [../../references/wayfinder-map.md](../../references/wayfinder-map.md):
   Destination and Notes filled in, Decisions-so-far empty, the fog sketched into
   **Not yet specified**.
4. **Create the tickets you can specify now** as child issues — then wire
   `blocked_by:` in a **second pass** (issues need ids before they can reference
   each other). Everything you can't yet specify stays in the fog.
5. Stop — charting the map is one session's work; do not also resolve tickets.

### Work through the map

User invokes with a map (URL or number). A ticket is **optional** — without one,
you pick the next decision, not the user.

1. Load the **map** — the low-res view, not every ticket body.
2. Choose the ticket. If the user named one, use it. Otherwise take the first
   frontier ticket in order. **Claim it** with `claim_ticket` before any work —
   and if the claim is lost, move to the next frontier ticket rather than
   proceeding.
3. Resolve it — **zoom as needed**: fetch the full body of any related or closed
   ticket on demand; invoke the skills the `## Notes` block names. If in doubt,
   use `grill-me`.
4. Record the resolution with `resolve_ticket`: post the answer as a **resolution
   comment** (full prose, ending in the `stenswf-resolved:v1` block), **rebuild
   the map's Decisions-so-far** from the resolved tickets, and **close the ticket
   last** — so a failure anywhere leaves the ticket open and retryable rather
   than closed with its decision unrecorded. The decision-anchor entry is not
   written here; it is generated from this comment at handoff.
5. Add newly-surfaced tickets (create-then-wire); graduate any fog the answer has
   made specifiable, clearing each graduated patch from **Not yet specified**. If
   the answer reveals a ticket sits beyond the destination, **rule it out of
   scope** rather than resolving it. If the decision invalidates other parts of
   the map, update or delete those tickets.

The user may run unblocked tickets in parallel, so expect other sessions to be
editing the tracker concurrently. **Every edit to the map body goes through
`with_map_lock`** — including graduating fog and ruling work out of scope in
step 5. An issue body is a whole-document write with no compare-and-set, so two
unserialised sessions silently lose each other's edits; the lock is what stops
that, and rebuilding the decisions index rather than appending to it is what
makes a clobber that slips through recoverable.

## Handoff to prd-from-grill-me

When the frontier empties and the way is clear, the map is done. The destination
was *"ready to write the PRD(s)"* — so hand off, don't keep charting:

1. **Generate the decision anchor**: `generate_decisions <map#>` builds
   `.stenswf/<map#>/decisions.md` from the resolved tickets' resolution comments,
   in resolution order. This is the first handoff step because until now the
   anchor does not exist.
2. Tell the user the way is clear and recommend `/stenswf:prd-from-grill-me` — once
   per PRD-sized chunk if the destination spans several.
3. For each PRD, record `map_ref: <map#>` in its front-matter (the provenance
   link) and let the map's `.stenswf/<map#>/decisions.md` **inform** that PRD's
   `## Conventions` / `## Implementation Decisions` — carry forward only the
   subset each PRD needs. `prd-from-grill-me`'s own anchor-seeding then re-records
   them as fresh PRD-local entries. Do **not** bulk-copy the anchor with
   `inherit-decisions.sh` — see the reasoning in
   [../../references/wayfinder-map.md](../../references/wayfinder-map.md#handoff--carry-the-maps-decisions-into-a-prd).

The map issue stays open only until every PRD it feeds has been filed; then close
it with a comment linking the PRDs. It is the durable intake record for the
effort, the way the original issue is for `triage-issue`.

## Feedback

Log friction per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=wayfinder`.
