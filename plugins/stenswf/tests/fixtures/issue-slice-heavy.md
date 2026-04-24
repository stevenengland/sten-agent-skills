<!-- Expected: type="slice — HITL"; lite_eligible="false"; disqualifier
     present → ship-light aborts cleanly, plan+ship runs normally. -->

<!-- stenswf:v1
type: slice — HITL
lite_eligible: false
conventions_source: prd
prd_ref: "42"
disqualifier: "multi-subsystem + schema migration"
prd_base_sha: "0123456abcdef"
-->

## What to build

Introduce a second `users.auth_provider` column and migrate existing
oauth records. Touches the auth module, the migrations directory, and
the admin UI.

## Acceptance criteria

- [ ] New migration creates `auth_provider` column with default `local`.
- [ ] Existing `oauth_uid IS NOT NULL` rows backfill to `google`.
- [ ] Admin UI shows provider per user.
- [ ] Rollback script covered by a test.

## Conventions (from PRD)

Follow the convention table in PRD #42 §3. Provider enum values:
`local | google | github`. Column is non-null with a `local` default.

## Files (hint)

- `db/migrations/*`
- `src/auth/provider.ts`
- `src/admin/users.tsx`

## Blocked by

None.

## Parent PRD

#42
