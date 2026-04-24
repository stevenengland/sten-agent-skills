<!-- Expected: type="slice — AFK"; lite_eligible="true"; no disqualifier
     → ship-light preflight passes; plan-light optional. -->

<!-- stenswf:v1
type: slice — AFK
lite_eligible: true
conventions_source: prd
prd_ref: "42"
-->

## What to build

Add a `/healthz` HTTP endpoint returning `{"status":"ok"}` with status
200.

## Acceptance criteria

- [ ] `GET /healthz` returns 200 and JSON body `{"status":"ok"}`.
- [ ] Endpoint is registered in the main router.
- [ ] A handler unit test covers the happy path.

## Conventions (from PRD)

None — slice-local decisions only.

## Files (hint)

- `src/routes/healthz.ts`
- `src/routes/index.ts`
- `src/routes/__tests__/healthz.test.ts`

## Blocked by

None.

## Parent PRD

#42
