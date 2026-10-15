# Expected — abstraction settled by an inherited decision

- **Reviewers:** deepening (slice mode, `<N>=900`; after setup the decision files sit under `.stenswf/`)
- **Checks:** the decision context resolves an inherited entry through its `Source:`, from a shipped parent whose anchor sits in a dated archive (`.stenswf/.archive/890-2026-09-30/`)

## Pass when

- Deepening raises no finding asking to remove the single-adapter `AuditLog` port, or, if it raises the question, it names the settled decision (`D1`, or `#890/D3`) and argues why it should be reopened.

## Fail when

- A finding recommends inlining or deleting `AuditLog` without naming the decision.
