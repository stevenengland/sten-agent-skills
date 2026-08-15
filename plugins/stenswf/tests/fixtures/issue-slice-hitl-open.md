<!-- Expected: type="slice — HITL"; lite_eligible="false";
     disqualifier="files>15" — a slice blocked by BOTH the envelope and
     HITL. The envelope blocker keeps the `disqualifier` slot; the HITL
     blocker is carried by `type`. Both must stay visible.
     → plan-light / ship-light Phase 0 route heavy on `files>15` BEFORE
     reaching the HITL gate, so the escape hatch must NOT run and must
     NOT write resolutions to this issue. With a `lite_override` added
     for the blast radius, HITL would become the sole blocker and the
     hatch would then be reachable.
     `## Open judgment calls` is the hatch's sole input. -->

<!-- stenswf:v1
type: slice — HITL
lite_eligible: false
conventions_source: prd#77
prd_ref: "77"
disqualifier: files>15
prd_base_sha: 89abcdef012345
-->

## Parent PRD

#77

## What to build

Replace the ad-hoc retry helpers scattered across the delivery layer with
a single policy object, and route every outbound call through it.

## Conventions (from PRD)

Follow PRD #77 §3 webhook vocabulary (`delivery`, `attempt`, `outcome`).

## Acceptance criteria

- [ ] (behavior) Every outbound call retries according to the shared policy.
- [ ] (structural) The ad-hoc helpers are removed.

## Open judgment calls

- **Retry backoff strategy for transient delivery failures** — the two
  existing helpers disagree (fixed vs. exponential) and no convention
  picks a winner.
- **Which failures count as permanent** — the current split is
  inconsistent across call sites and changes observable retry behavior.
