# Conventional Commits — shared spec

Single source of truth for commit message format across `plan`, `ship`,
`ship-light`, `apply`, and `slice-e2e` (via `ship-light`). Prevents
drift in type list and trailer format.

## Format

```
<type>(<scope>): <imperative subject, lower-case, no period, ≤72 chars>

<optional body paragraph — omit when self-explanatory>

Refs: #<issue-number>
Decision: #<issue>/D<n> [<category>] <title>
Rationale: <why, folded to one trailer value>
Touches: <files the decision implicates>
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
- The decision trailers go in the **same paragraph** as `Refs:`, never in
  a paragraph of their own. Git only parses the last paragraph, so a blank
  line between them demotes `Refs:` to body text.

## Decision trailers

`.stenswf/` is gitignored, so the decision anchor dies with the working
copy. Every commit carries the decisions that were not yet recorded on this
branch — which makes the branch history the repo-durable record, readable
with `git log --grep='^Decision:'` long after the branch is deleted. The
canonical form, at every commit site:

```bash
DEC=$(bash ../../scripts/publish-decisions.sh trailer "$ARGUMENTS")
git commit -m "<type>(<scope>): <subject>" \
           -m "$(printf 'Refs: #%s\n%s' "$ARGUMENTS" "$DEC")"
```

`$(...)` strips the trailing newline, so an empty `$DEC` — no anchor, or
nothing new since the last commit — leaves a bare `Refs: #N` and the commit
is unchanged. Never hand-write these trailers; the script owns the ids, the
supersession wording, and the resolution of inherited stubs.

The log is an **append-only journal, not a current state view**: a decision
superseded later keeps the trailer on the commit that was made on its basis,
and the superseding entry names what it retired. For current state, read the
PR body block or the issue comment. See
[decision-anchor-link.md](decision-anchor-link.md).

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
- No local `AC/F/D` codes in the subject — describe the change in plain
  language. Trailers may carry `Addresses: F…`. See
  [local-id-hygiene.md](local-id-hygiene.md).
