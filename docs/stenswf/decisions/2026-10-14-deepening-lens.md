# Decision: Deepening lens (2026-10-14)

Status: **adopted**.
Source: PRD #37, slice #38.
Refs: `plugins/stenswf/skills/codebase-design/SKILL.md`,
`plugins/stenswf/references/deepening-subagent.md`,
`plugins/stenswf/references/thermo-subagent.md`,
`plugins/stenswf/skills/review/slice.md`,
`plugins/stenswf/skills/review/prd.md`,
`plugins/stenswf/skills/review-loop/SKILL.md`,
`plugins/stenswf/skills/improve-codebase-architecture/SKILL.md`,
`plugins/stenswf/tests/review-scenarios/`.

## Decision

`codebase-design` is applied as a **lens**, mirroring
[TDD-as-lens](2026-04-26-tdd-as-lens.md):

- **Trigger.** Slice review dispatches the deepening subagent whenever the
  diff (staged, or `review-loop`'s commit range) changes a file outside docs, data files and test paths
  (`DEEPEN_HIT`). It looks for no declarations: when in doubt the subagent
  inspects, and the subagent decides what is a finding. The Architect gate is
  unchanged. PRD review has no trigger: Axis 3 runs the pass every time.
- **Lens.** A read-only subagent loads `codebase-design`, reads the modules
  the diff touches and their callers whether or not an interface changed, and
  reads the full decision context (every active entry, inherited entries
  through their `Source:`, archived slice entries in PRD mode, ADRs).
- **Finding.** Severity follows demonstrated consequence — a duplicated
  business rule, a leaked invariant, change that propagates through callers,
  an obscured contract — not upstream's recommendation strength. Confidence
  only decides whether to publish; speculative redesigns stay with
  `/stenswf:improve-codebase-architecture`, the only place that grills. Only
  problems the diff introduced or worsened are findings; older friction is an
  uncounted follow-up line.
- **Ownership.** Deepening owns module structure; thermo keeps code-level
  quality. The thermo skill itself hands module structure to
  `codebase-design`, so the two never give opposite advice.
- **Cost.** Each review dispatches thermo and deepening once; `review-loop`
  runs them only on its first pass, over the whole PR.
- **Rules as questions.** The deletion test and the adapter count are
  evidence, not verdicts; recommendations name the invariants they must keep;
  old tests go only once interface tests cover what they checked.
- **Single home.** `codebase-design` is the only place deep-module theory
  lives; `tdd`, `plan`, `plan-light`, `prd-from-grill-me` and `architecture`
  link it.
- **One meaning for "seam".** stenswf's former name for the hosting workflow
  skill is now "host skill"; reflection points are "checkpoints". The
  deliberation filter still reads the old label, so a deliberation open
  across an upgrade still blocks `review-loop` from converging.
- **Judgment checks.** `tests/review-scenarios/` holds six sample diffs with
  expected verdicts, run whenever the reviewer instructions change.

## Consequences

- **More review work.** A diff that touches production code costs a second
  specialist dispatch, and the caller must dedup Architect, thermo and
  deepening findings before it can count them.
- **Later commits get no specialist pass.** `review-loop` runs thermo and
  deepening only on its first pass. A structural or code-quality regression
  introduced by a later fix-up commit is seen only by the five perspectives,
  never by either specialist. This is accepted: later deltas are fix-ups, and
  re-running both on every pass would multiply the cost of every loop.
- **Judgment is checked by hand.** The bash suites check that the contract is
  wired up; whether the reviewers judge well is known only from running
  `tests/review-scenarios/`, which is not a pass/fail gate.

## Rejected alternatives

- **Fold the deepening pass into the thermo subagent.** One reviewer would
  save a dispatch, but module structure and code-level quality are separate
  judgments; the owner chose a separate reviewer with a clear split over one
  prompt carrying both. Their differing vocabulary was not the reason.
- **A column-0 declaration gate (`IFACE_HIT`).** Missed methods, removals,
  multi-line signature changes and most languages, and silently skipped the
  pass when unsure.
- **Map upstream strength to severity.** Confidence in a recommendation is
  not the cost of leaving the code as it is.
- **Cap findings at low unless an interface changed.** Under-ranked coupling
  added behind an unchanged interface.
- **Rename the deliberation field with a hard cut.** Would hide a
  deliberation opened before an upgrade from `review-loop`'s convergence
  guard.

## Carved invariants

- Review output schemas (`## Suggestions` / `Summary:`, `<finding>`) are
  unchanged; deepening findings fold into them like thermo's, and follow-up
  lines stay outside the counts.
- `tdd` stays in every SKILLS TO LOAD list; the TDD ceremony invariant is
  untouched.
- Thermo runs on every review (on the first pass in `review-loop`).
- Review never interviews the user.
- `review-loop` never converges while a deliberation is open.
