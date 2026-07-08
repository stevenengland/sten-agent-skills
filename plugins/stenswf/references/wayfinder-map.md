# wayfinder map — templates & tracker operations

Loaded by the `wayfinder` skill. Holds the map body template, the ticket
template, the local-tree seed, and every tracker operation (create, wire,
claim, frontier, resolve). Bodies here are **full prose** — `brevity` excludes
issue/map/comment bodies.

CLI examples use `gh`; substitute `glab` / `tea` on GitLab / Gitea as the rest
of stenswf does. Front-matter is parsed with `get_fm` from
[`../scripts/extractors.sh`](../scripts/extractors.sh) (see
[extractors.md](extractors.md)).

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
the link for the detail the ticket holds. The machine-readable twin lives in
.stenswf/<N>/decisions.md -->

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

Mirror the PRD seed, `kind: "map"`. Run once when charting the map, after the
map issue exists.

```bash
N=<map-issue-number>
mkdir -p ".stenswf/$N/assets"
gh issue view "$N" --json body -q .body > ".stenswf/$N/concept.md"
CONCEPT_SHA=$(sha256sum ".stenswf/$N/concept.md" | awk '{print $1}')
BASE_SHA=$(git rev-parse HEAD)
cat > ".stenswf/$N/manifest.json" <<EOF
{
  "issue": $N,
  "kind": "map",
  "base_sha": "$BASE_SHA",
  "concept_sha256": "$CONCEPT_SHA",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tickets": [],
  "decisions_anchor": ".stenswf/$N/decisions.md"
}
EOF

# Bootstrap the decision anchor (its Decisions-so-far twin).
cat > ".stenswf/$N/decisions.md" <<EOF
# Decisions — #$N

<!-- Seeded by wayfinder. Schema/recipes: plugins/stenswf/README.md#decision-anchor-contract -->
EOF
```

The `.stenswf/` tree is excluded per-clone via `.git/info/exclude` (see
`bootstrap`).

## Create a ticket

```bash
MAP=<map-number>
gh issue create \
  --title "<ticket title>" \
  --body-file /tmp/ticket-body.md   # from the ticket template above
```

Record each new ticket number in `manifest.json`'s `tickets` array.

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

The assignee _is_ the claim — do it first, before any work.

```bash
gh issue edit <ticket> --add-assignee @me
```

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

Four writes, in order:

```bash
MAP=<map-number>
TICKET=<ticket-number>

# 1. Post the answer as a resolution comment (full prose; link any assets).
gh issue comment "$TICKET" --body-file /tmp/resolution.md

# 2. Close the ticket.
gh issue close "$TICKET"
```

3. **Append a one-line gist** to the map body's `## Decisions so far`:

   ```markdown
   - [<ticket title>](<ticket url>) — <one-line gist of the answer>
   ```

4. **Append a decision-anchor entry** to `.stenswf/$MAP/decisions.md` using the
   canonical auto-incrementing snippet (set `ARGUMENTS=$MAP`) from the
   [Decision Anchor Contract](../README.md#decision-anchor-contract). Category
   `arch` for structural/boundary calls, `decision` otherwise. This is the
   durable record that carries forward to the PRD(s) at handoff.

## Handoff — carry the map's decisions into a PRD

When the way is clear, the map's `.stenswf/<map#>/decisions.md` is the durable
record of every decision the effort walked. A single map may feed **several**
PRDs, each taking only the subset it needs — so carry decisions forward
**selectively**, not by bulk-copying the whole anchor into every PRD:

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
