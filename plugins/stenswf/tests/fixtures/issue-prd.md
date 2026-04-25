<!-- Expected: type="PRD" → review/apply dispatch to PRD-mode. -->

<!-- stenswf:v1
type: PRD
lite_eligible: false
conventions_source: self
prd_base_sha: abcdef0123456
-->

## Problem

Operators cannot tell whether the service is healthy from outside —
only from the internal dashboard.

## Goals

- Expose a public liveness signal.
- Expose per-provider auth health.

## User stories

1. As an SRE, I can `curl` a URL and see 200 when the service is up.
2. As an operator, I can see per-auth-provider health on a dashboard.

## Out of scope

- Deep-health checks (database roundtrip).
- Paging integration.

## Conventions

Route paths lower-case, hyphenated. JSON body `{"status":"ok"|"degraded"}`.

## Implementation decisions

Start with a flat `/healthz`; add `/readyz` only if needed.

## Acceptance criteria (PRD-level)

- [ ] `/healthz` returns 200 on happy path.
- [ ] Admin dashboard renders provider health rows.
