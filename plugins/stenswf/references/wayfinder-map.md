# wayfinder map — templates & tracker operations

Loaded by the `wayfinder` skill. Holds the map body template, the ticket
template, the local-tree seed, and every tracker operation (create, wire,
claim, frontier, resolve). Bodies here are **full prose** — `brevity` excludes
issue/map/comment bodies.

CLI examples use `gh`; substitute `glab` / `tea` on GitLab / Gitea as the rest
of stenswf does. Front-matter is parsed with `get_fm` from
[`../scripts/extractors.sh`](../scripts/extractors.sh) (see
[extractors.md](extractors.md)).

> **Canonical plumbing.** Claiming, the map-body append, resolution, and the
> handoff generator live in [`../scripts/wayfinder.sh`](../scripts/wayfinder.sh).
> Skills source that file — do not duplicate the function bodies here.

## Where the state lives

**The tracker is the map's only live state.** The map issue and its tickets are
canonical; everything else is derived.

- Each decision's full record is its ticket's **resolution comment**.
- The map body's *Decisions so far* is a human-readable **index**, and it is
  **rebuilt** from the **resolved** tickets by `sync_map_index` — never
  accumulated line by line. Resolved, not closed: a ticket becomes eligible
  for the index the moment its resolution comment lands, which is what lets
  the close stay last (see [Resolve a ticket](#resolve-a-ticket)).
- `.stenswf/<N>/decisions.md` is **generated once at handoff** from those
  comments (`generate_decisions`), not appended to as tickets resolve.
- `.stenswf/<N>/manifest.json` carries identity only.

This is deliberate, and it is what makes parallel sessions workable. Every
mirror kept live is a thing two sessions can disagree about and a thing a
crashed session can leave half-written; a derived artifact regenerated from the
tracker cannot go stale, because it does not exist between regenerations.

**Editing the map body is serialised.** An issue body is a whole-document
read-modify-write and the tracker offers no compare-and-set, so a session that
read the body before yours can land its stale copy after you wrote — and after
you verified. Verifying cannot catch that; only serialising can. Take the map
lock around **any** body edit:

```bash
with_map_lock <map> <command> [args...]   # acquire, run, release
```

That covers the prose sections too — graduating fog out of *Not yet specified*,
adding to *Out of scope*. `sync_map_index` takes the lock itself. Where a
clobber slips through anyway, the index self-heals on the next rebuild; the
hand-written prose sections do not, which is why the lock is not optional.

## Map body template

`type: wayfinder`. No label. `<N>` is assigned on `gh issue create` and written
back into the front-matter after creation.

```markdown
<!-- stenswf:v1
type: wayfinder
-->

## Destination

<what reaching the end of this map looks like — usually the clarity a PRD needs.
One or two lines; every session orients to it before choosing a ticket.>

## Notes

<domain; skills every session should consult; standing preferences for this effort>

## Decisions so far

<!-- the index — one line per closed ticket: enough to judge relevance, then zoom
the link for the detail the ticket's resolution comment holds. Rebuilt by
sync_map_index, never edited by hand -->

- [<closed ticket title>](link) — <one-line gist of the answer>

## Not yet specified

<!-- in-scope fog you can't ticket yet; graduates as the frontier advances -->

## Out of scope

<!-- work ruled beyond the destination; closed, never graduates -->
```

## Ticket body template

`type: wayfinder-ticket`. One question, sized to one agent session.

```markdown
<!-- stenswf:v1
type: wayfinder-ticket
ticket_type: grilling
map_ref: <N>
-->

Parent map: #<N>

## Question

<the decision or investigation this ticket resolves>
```

`ticket_type` is one of `research` | `prototype` | `grilling` | `task`.
`blocked_by:` is added in the second wiring pass, e.g. `blocked_by: 43 44`.

## Local-tree seed

`kind: "map"`, identity only. Run once when charting the map, after the map
issue exists.

```bash
N=<map-issue-number>
mkdir -p ".stenswf/$N/assets"
cat > ".stenswf/$N/manifest.json" <<EOF
{
  "issue": $N,
  "kind": "map",
  "base_sha": "$(git rev-parse HEAD)",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "decisions_anchor": ".stenswf/$N/decisions.md"
}
EOF
```

The seed deliberately omits three things the PRD seed carries:

- **No `concept.md` / `concept_sha256`.** Those exist for drift detection, which
  compares a plan against the issue body it was built from. A map body is
  *meant* to change — Decisions-so-far grows every time a ticket closes — so the
  hash could only ever read as drift. Nothing consumes it.
- **No `tickets` array.** The tracker knows which tickets belong to the map; see
  [Frontier query](#frontier-query). A second list would only be a thing to keep
  in sync.
- **No `decisions.md`.** It is generated at handoff — see
  [Handoff](#handoff--carry-the-maps-decisions-into-a-prd).

The `.stenswf/` tree is excluded per-clone via `.git/info/exclude` (see
`bootstrap`).

## Create a ticket

```bash
MAP=<map-number>
gh issue create \
  --title "<ticket title>" \
  --body-file /tmp/ticket-body.md   # from the ticket template above
```

The `Parent map: #<N>` body line and `map_ref:` front-matter are the ticket's
membership record — there is no local list to update.

## Wire blocking (second pass)

Ids exist only after creation, so wire `blocked_by:` after the blocked and
blocking tickets both exist. Edit the blocked ticket's body, adding a
`blocked_by:` line to its front-matter block:

```
<!-- stenswf:v1
type: wayfinder-ticket
ticket_type: grilling
map_ref: 41
blocked_by: 43 44
-->
```

```bash
gh issue edit <ticket> --body-file /tmp/ticket-body-wired.md
```

## Claim a ticket

Claim first, before any work — and check that the claim was **won**:

```bash
source ../../scripts/wayfinder.sh

SID=$(claim_ticket <ticket>) || {   # non-zero: someone else holds it
  echo "claim lost — taking the next frontier ticket"
  # pick the next frontier candidate and try again
}
```

`claim_ticket` assigns the ticket to `@me` (what a human sees) and then posts a
`<!-- stenswf-claim: <session-id> -->` comment; the **earliest claim comment
wins** and the loser withdraws its own claim automatically.

The comment is not ceremony — assignment alone cannot arbitrate. GitHub's
assignee field is a set with no compare-and-set, so two sessions can both
"succeed" at claiming; and when both are sessions of the *same* human they
authenticate identically, which makes the second `--add-assignee @me` a silent
no-op that reports success. The claim comment supplies the per-session token
that assignment cannot, and comment ids give every session the same total order
to break the tie with.

**Residual window.** Between reading the frontier and its claim comment
landing, another session may claim and start work. The loser detects this on its
very next read and yields, but the window is not zero — the tracker offers no
atomic primitive that would close it. Treat a claim as strong convention plus
fast collision detection, not as a lock.

## Frontier query

The frontier is the open, unblocked, unclaimed children. Find open children by
body reference (stenswf's parent-link convention, like `"Parent PRD"`), then
keep only true tickets that are unassigned and whose every `blocked_by` id is
closed.

```bash
source ../../scripts/extractors.sh
MAP=<map-number>

# Open candidates by body reference. Raise --limit past your ticket count
# (gh defaults to 30) or paginate — a truncated list can falsely read as an
# empty frontier.
gh issue list --state open --limit 200 \
  --search "in:body \"Parent map: #$MAP\"" \
  --json number,title,assignees,body > /tmp/candidates.json
```

The body search can false-positive (substring hits like `#12` inside `#123`,
or unrelated issues quoting the phrase), so **validate each candidate** before
trusting it:

1. **Is it a ticket of THIS map?** Fetch the body and confirm
   `type: wayfinder-ticket` **and** `map_ref` equals `$MAP`:
   ```bash
   gh issue view <cand> --json body -q .body > /tmp/c.md
   [ "$(get_fm type /tmp/c.md)" = "wayfinder-ticket" ] || continue
   [ "$(get_fm map_ref /tmp/c.md)" = "$MAP" ] || continue
   ```
2. **Unclaimed?** empty `assignees`.
3. **Unblocked?** every id in `blocked_by:` (via `get_fm blocked_by /tmp/c.md`)
   resolves to a closed issue — check each with
   `gh issue view <id> --json state -q .state` (`CLOSED` = satisfied).

A candidate passing all three is on the frontier.

## Resolve a ticket

Three writes — resolution comment, map index, **close last** — driven by one
call:

```bash
source ../../scripts/wayfinder.sh

resolve_ticket <map> <ticket> /tmp/resolution.md
```

**The close goes last, and that ordering is the durability guarantee.** Closing
first takes the ticket off the frontier while its decision may still be missing
from the map — the effort would then have no signal that anything is owed.
Closing last means a failure at any step leaves the ticket open, visible, and
retryable, and every earlier step checks for its own effect before repeating it,
so re-running after a failure is safe.

That ordering is why the index derives from tickets carrying a **resolution
block**, in any state, rather than from closed ones. A closed-only index would
skip the very ticket whose resolution triggered the rebuild — it is still open
at that point — and nothing rebuilds after the close, so each map's newest
decision would appear only when some *later* ticket resolved, and its last
decision never.

### Resolution comment

Full prose — the durable record of the answer; link any assets. It ends with a
**resolution block**, the one marker everything downstream reads:

```markdown
<the answer, in full prose — what was decided and what it rests on>

<!-- stenswf-resolved:v1
gist: <one line for the map index>
category: arch
title: <≤60 chars, imperative, no period>
rationale: <≤180 chars — why this, not the obvious alternative>
refs: <comma-separated paths/ids, ≤8 tokens>
-->
```

- `gist:` is required — it is the line `sync_map_index` puts on the map.
- The remaining fields are what make this an anchor entry.  `category` is
  `arch` for structural/boundary calls, `decision` otherwise; the fields and
  their caps follow the
  [Decision Anchor Contract](../README.md#decision-anchor-contract).

A **task** ticket resolved nothing to record as a decision, so it carries
`gist:` alone and contributes no anchor entry. It still needs the block: the
marker is how a retry knows the resolution comment was already posted, so a
task without one would re-post its comment on every retry.

## Handoff — carry the map's decisions into a PRD

When the way is clear, **generate the anchor** from the map's resolved tickets:

```bash
source ../../scripts/wayfinder.sh
generate_decisions <map#>          # writes .stenswf/<map#>/decisions.md
```

It walks the resolved tickets in resolution order, reads each resolution block,
and emits `D1..Dn` per the Decision Anchor Contract for every ticket that
recorded a `category` and a `rationale` — tasks are resolved but are not
entries. Re-running it rebuilds the file from scratch — it never appends, so a
regenerated anchor cannot drift from the tracker or double up its entries. The
file is assembled elsewhere and renamed into place, so an interrupted run
leaves the previous anchor rather than a truncated one, and a ticket list that
would have been truncated fails loudly instead of producing a short anchor.

That file is then the durable record of every decision the effort walked. A
single map may feed **several** PRDs, each taking only the subset it needs — so
carry decisions forward **selectively**, not by bulk-copying the whole anchor
into every PRD:

1. In the PRD's front-matter, record `map_ref: <map#>` — the provenance link. Any
   reviewer of the PRD or its slices can then hop to the map's anchor for the
   full "why", exactly as they hop to a PRD anchor from a slice.
2. When running `prd-from-grill-me`, **read** `.stenswf/<map#>/decisions.md` and
   let the decisions relevant to *this* PRD shape its `## Conventions` and
   `## Implementation Decisions`. `prd-from-grill-me`'s own anchor-seeding then
   records them as fresh, PRD-local `D<n>` entries — no id collisions, no
   duplication across sibling PRDs.

> Do **not** run `inherit-decisions.sh <map#> <prd#>`: it copies *all* active
> source entries preserving their ids, which both collides with the PRD's own
> seeded `D<n>` entries and floods every sibling PRD with the entire map. That
> script is for the empty-destination PRD→slice fan-out, not the map→PRD handoff.
