# Conventional Commits — shared spec

Single source of truth for commit message format across `plan`, `ship`,
`ship-light`, `apply`, and `slice-e2e` (via `ship-light`). Prevents
drift in type list and trailer format.

## Format

```
<type>(<scope>): <imperative subject, lower-case, no period, ≤72 chars>

<optional body paragraph — omit when self-explanatory>

Refs: #<issue-number>
```

## Type list (canonical)

| Where used | Allowed types |
|---|---|
| `ship`, `ship-light`, `slice-e2e`-dispatched | `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `chore`, `build`, `ci` |
| `apply` (slice-mode review-fix) | All of the above plus `style`, `revert` |
| `apply` (PRD-mode cleanup) | `refactor`, `test`, `fix`, `chore(ops)`, `feat(ops)` (axis-driven) |

`style` and `revert` are only for `apply` because slice-implementation
phases never produce pure-style or pure-revert commits — those arise
from review feedback or rollback decisions, both downstream.

## Trailer rules

- **Always** use the colon-form `Refs: #N`. Bare `Refs #N` (no colon)
  breaks `git interpret-trailers` parsing.
- For `apply`-PRD commits, add `Addresses: F1, F2, …` above `Refs:`.
- For multi-issue references, separate with comma: `Refs: #123, #124`.

Example (ship-light, slice mode):

```
feat(auth): return 401 on missing token

Refs: #123
```

Example (apply, PRD-mode cleanup):

```
refactor(architectural-coherence): collapse duplicate retry helpers

Two slices introduced near-identical RetryWithBackoff helpers in
different modules. Consolidated under pkg/retry; updated 3 callers.

Addresses: F5, F7
Refs: #200
```

## Why no squashing

`ship-light` and `ship` produce one commit per AC (or per task) so
that bisect and review can attribute behavior changes to a specific
AC. Squashing on merge is allowed at the GitHub UI level if the team
prefers; the commit-per-AC discipline is for the working branch.

## Subject discipline

- Imperative mood ("add", not "added" / "adds").
- Lower-case first word.
- No trailing period.
- ≤72 chars (hard cap; tools wrap at 72).
- Scope is optional but encouraged. Drop it for cross-cutting commits
  rather than inventing a fake scope.
