<!-- Expected: type="slice — HITL"; lite_eligible="false";
     disqualifier="schema-migration"; lite_override non-empty
     → override IGNORED (non-overridable disqualifier);
     plan-light / ship-light Phase 0 emit ROUTE_HEAVY. -->

<!-- stenswf:v1
type: slice — HITL
lite_eligible: false
conventions_source: prd
prd_ref: "42"
disqualifier: schema-migration
lite_override: trust me, it's quick
prd_base_sha: 0123456abcdef
-->

## What to build

Add a non-null `users.tenant_id` column with a backfill from
`organizations.id`. Requires migration.

## Acceptance criteria

- [ ] Migration adds `tenant_id` column, non-null, with backfill.
- [ ] Rollback script tested.
- [ ] All `users.*` queries scoped by `tenant_id` going forward.

## Conventions (from PRD)

Follow PRD #42 §4 multi-tenancy convention.

## Files (hint)

- `db/migrations/*`
- `src/users/*`

## Blocked by

None.

## Parent PRD

#42
