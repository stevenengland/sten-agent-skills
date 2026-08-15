<!-- Expected: type="slice — HITL"; lite_eligible="false";
     disqualifier="hitl-cat3" (= HITL is the ONLY blocker);
     hitl_resolved non-empty AND `## Resolved judgment calls` non-empty
     → both halves present, so the Phase-0 HITL gate (which runs LAST,
     after every other envelope check) logs user_override, sets
     HITL_CLEARED=true, and CONTINUES. Note HITL_CLEARED, not LITE.
     `## Resolved judgment calls` is spec-bearing: it participates in
     the source_signature triad+1. -->

<!-- stenswf:v1
type: slice — HITL
lite_eligible: false
conventions_source: prd#77
prd_ref: "77"
disqualifier: hitl-cat3
hitl_resolved: 2026-08-15 — 2 judgment calls resolved via hitl-escape-hatch
prd_base_sha: 89abcdef012345
-->

## Parent PRD

#77

## What to build

Retry outbound webhook deliveries that fail with a transient error,
surfacing the final outcome on the delivery record.

## Conventions (from PRD)

Follow PRD #77 §3 webhook vocabulary (`delivery`, `attempt`, `outcome`).

## Acceptance criteria

- [ ] (behavior) A transient delivery failure is retried and the
      delivery record persists the final outcome.
- [ ] (behavior) A permanent failure is not retried and is recorded as
      `failed`.
- [ ] (structural) Existing delivery tests stay green.

## Files (hint)

- Modify: `src/webhooks/delivery.py` — retry loop + outcome recording
- Test:   `tests/webhooks/test_delivery.py` — retry and give-up paths

## Resolved judgment calls

<!-- Written by references/hitl-escape-hatch.md. Spec-bearing: part of source_signature. -->

- **Retry backoff strategy for transient delivery failures** →
  exponential backoff with full jitter, capped at 5 attempts.
  Rejected: fixed interval — synchronises retries across all failing
  deliveries into a thundering herd against the same downstream host.
  Precedent: AWS Architecture Blog, "Exponential Backoff and Jitter" —
  full jitter minimises contention at equal completion time.
  Anchor: D1.
- **Which failures count as permanent** → 4xx other than 408/429 are
  permanent; everything else is transient.
  Rejected: retry every non-2xx — turns a caller's malformed-payload
  bug into sustained load with no possibility of success.
  Precedent: Stripe webhooks — retries are scoped to 5xx and timeouts,
  with 4xx surfaced to the endpoint owner instead.
  Anchor: D2.
