# Local-ID hygiene — shared rule

`AC<n>` (acceptance criteria), `F<n>` (review findings), and `D<n>`
(decision-anchor entries) are **local positional identifiers** scoped to the
`.stenswf/` working state. They are recomputed per run and mean nothing to a
reader who does not have that local state in front of them.

**They MUST NOT appear in:**

- produced source code,
- code comments,
- test names / test descriptions,
- commit **subject** lines.

Describe the behavior, finding, or decision in plain language instead — e.g.
`feat(auth): return 401 on missing token`, not `feat(auth): implement AC12`;
`// reject empty cursors`, not `// AC12`.

**They MAY appear (resolvable in context, or purely local):**

- commit **trailers** — `Refs: #N`, `Addresses: F1, F2` (the `apply`-PRD
  review XML is mirrored onto the PR, so finding codes resolve there),
- PR bodies and issue / PR comments,
- the committed decisions excerpt headers (`### D<n>` in
  `docs/decisions/prd-N.md`),
- any file under `.stenswf/`.

The distinction is durability + resolvability: a git history reader years
later cannot resolve `AC12` in a source file, but `Addresses: F1` in a trailer
sits next to the mirrored review on the PR.
