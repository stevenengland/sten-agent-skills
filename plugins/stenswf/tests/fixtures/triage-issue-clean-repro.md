<!-- Expected: triage-issue Phase 2 returns repro_status: confirmed.
     Phase 3 returns single-module root cause, ≤4 affected files,
     no judgment_calls. Phase 4 default outcome: C-1 (single slice).
     Phase 5 emits bug-brief + one slice with type: slice — AFK,
     lite_eligible: true, conventions_source: bug-brief#<N>. -->

# Pagination cursor returns duplicate items at page boundary

## Expected behavior

`GET /api/items?cursor=<c>&limit=20` returns the next 20 items
strictly after `<c>` with no duplicates across pages.

## Actual behavior

When two items share the same `created_at` timestamp at the page
boundary, the second page repeats one of them. Reproduces every time
on our staging dataset.

## Reproduction steps

1. Seed two items with the same `created_at` value (down to the
   millisecond).
2. `curl /api/items?limit=1` → returns item A, cursor C1.
3. `curl /api/items?cursor=C1&limit=1` → returns item A again
   (instead of item B).

## Environment

- Server: v2.4.1
- Runtime: Node 20.10
- DB: Postgres 15.3

## Logs

No errors. Query returned the duplicate row deterministically.

## Suspected area

Probably `src/api/pagination.ts` — the cursor comparison uses
`created_at >` rather than a stable tiebreaker like `(created_at, id)`.
