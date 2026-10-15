# Decisions — #890

<!-- Seeded by prd-from-grill-me. Schema: plugins/stenswf/README.md#decision-anchor-contract -->

### D3 — Keep the AuditLog port with a single adapter for now

- **Category:** arch
- **Source:** prd-from-grill-me
- **Rationale:** Compliance requires a per-tenant audit sink next quarter (WORM storage for regulated tenants); the port lands now so callers never change again.
- **Refs:** src/audit/auditLog.ts
