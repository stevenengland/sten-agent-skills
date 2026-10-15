# Expected — coupling behind an unchanged interface

- **Reviewers:** deepening (slice mode, `<N>=900`)
- **Checks:** inspection does not depend on an interface change; diff attribution; consequence-based severity

## Pass when

- Deepening returns a finding on `src/billing/invoice.ts`: billing now reads pricing's internal `TIERS` table and re-implements the discount rule outside `discountFor`.
- Its severity is `high` (a duplicated business rule; the "one place discounts are decided" invariant leaks), or at least `medium`.
- It is a finding, not only a `follow-up:` line.

## Fail when

- No finding, or the concern appears only as a follow-up.
- The concern is dismissed because `createInvoice`'s interface did not change.
