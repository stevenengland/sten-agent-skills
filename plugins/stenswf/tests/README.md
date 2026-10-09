# stenswf tests

Dev-only. Not packaged for end users.

- [`pr-threads.test.sh`](pr-threads.test.sh) — behavior tests for the PR
  conversation loop's plumbing (`scripts/pr-threads.sh`).
- [`wayfinder.test.sh`](wayfinder.test.sh) — behavior tests for the
  wayfinder tracker plumbing (`scripts/wayfinder.sh`).
- [`inherit-decisions.test.sh`](inherit-decisions.test.sh) — behavior tests
  for copying active PRD decision stubs into slices
  (`scripts/inherit-decisions.sh`).
- [`publish-decisions.test.sh`](publish-decisions.test.sh) — behavior tests for
  rendering decision anchors to the PR body and issue comment
  (`scripts/publish-decisions.sh`). Targets three silent failures:
  inherited stubs publishing as dangling `#<PRD>/D<n>` pointers with no
  rationale, a non-idempotent upsert growing a second `## Decisions` block on
  every `apply-loop` pass, and superseded entries leaking into a surface that
  then contradicts the shipped code. Also covers the commit-trailer tier
  against a real throwaway git repo — re-emission (a ten-commit slice
  repeating D1 ten times) and under-emission (a sibling issue's `D1`
  suppressing this one's, silently) — plus wiring checks that the publishing
  skills call the script, that every commit site records, and that
  `review-loop` does neither.
- [`deliberation.test.sh`](deliberation.test.sh) — behavior tests for the peer
  deliberation protocol (`scripts/deliberation.sh`): moves are immutable and
  taken in order, whose move it is, every way a deliberation ends (`agreed`,
  `parked`, `escalated`, `cancelled`), a round cap that counts every move,
  role-aware waits that never wake on their own move, a stale acceptance, the
  PR-loop shared-checkout gate, the installed-skill bootstrap, and a
  contradiction gate that matches literally, reaches root-level names, and drops
  nothing silently — plus the skills' wiring to all of it.

  **Not covered — by design:** the research, the argument, the convergence, and
  the contradiction judgement. No shell assertion distinguishes a restatement
  from an argument, which is also why the two-stall rule is documented as the
  agents' judgement rather than claimed as enforcement.
- [`issue-comments.test.sh`](issue-comments.test.sh) — behavior tests for
  `get_comments` (`scripts/extractors.sh`): every comment prints, compact and
  in order — none filtered, since any comment may carry a design marker — and
  nothing prints when there are none. Plus wiring checks that every content
  read of an issue calls it, that no hashed body file (`concept.md`, drift
  check) receives comments, and that the conflict rule the header names exists
  in `references/decision-escalation.md`.
- [`apply-verification.test.sh`](apply-verification.test.sh) — wiring checks
  that `apply`/`apply-loop` load `references/review-finding-validation.md`
  and that its links resolve.
- [`hitl-escape-hatch.test.sh`](hitl-escape-hatch.test.sh) — behavior tests
  for the HITL escape hatch's silent-failure modes: `source_signature`
  drifting apart across its three computation sites, the Phase-0 gate missing
  a dash variant of `type:`, a half-attestation opening the gate, and the gate
  overwriting `LITE` instead of setting `HITL_CLEARED`. Plus wiring checks.

  **Covered:** the Phase-0 gate predicate (extracted from each `SKILL.md` and
  executed), signature parity and backward-compatibility, front-matter and
  section contracts, producer wiring.
  **Not covered — prose only:** the attended interview itself, unattended
  routing, the atomic `gh issue edit` write-back, and the hatch's bail-outs.
  These need a real issue and a `gh` fake; the suite does not assert them, so
  do not read a green run as evidence that they work.
- [`show-me.test.sh`](show-me.test.sh) — shared scripts for show-me /
  visual-pr: `ensure-stenswf-dir.sh` (local state ignored before the first
  write, also without bootstrap and in worktrees) and `open-html.sh` (opener
  chosen by platform; path printed, exit 0 when nothing opens).
- [`visual-pr.test.sh`](visual-pr.test.sh) —
  `skills/visual-pr/scripts/pr-body.sh` (compose with byte-exact evidence,
  in-place refresh with the saved body published, legacy migration, refusal
  on malformed markers, idempotence, coexistence with `## Decisions`), the
  `workflow-issue.sh` guard, and all show-me / visual-pr wiring.
- [`fixtures/`](fixtures/) — hand-authored issue bodies exercising the
  front-matter parser (`references/extractors.md`) and the
  route-selection gates in `plan-light`, `ship-light`, `plan`,
  `review`, `apply`. See [fixtures/README.md](fixtures/README.md) for
  re-run instructions.

```bash
bash plugins/stenswf/tests/pr-threads.test.sh
bash plugins/stenswf/tests/wayfinder.test.sh
bash plugins/stenswf/tests/inherit-decisions.test.sh
bash plugins/stenswf/tests/apply-verification.test.sh
bash plugins/stenswf/tests/hitl-escape-hatch.test.sh
bash plugins/stenswf/tests/publish-decisions.test.sh
bash plugins/stenswf/tests/show-me.test.sh
bash plugins/stenswf/tests/visual-pr.test.sh
```

The GitHub-facing suites inject a fake `gh` on `PATH` rather than calling
GitHub. The fake keeps mutable state — threads, comments, assignees, issue
bodies — so a write is observable by a **later** read, which is the property
the loops actually depend on. A fake that only recorded what was sent would
pass while the real protocol failed to converge.

Fixtures are piped through the canonical extractor helpers (`get_fm`,
`extract_section`) manually during development. `hitl-escape-hatch.test.sh`
is the exception that also drives them from a runner.

Where a skill's logic lives in a bash block inside its `SKILL.md` rather than
in `scripts/`, the test **extracts that block and executes it** instead of
restating the predicate. A restated predicate keeps passing while the skill it
guards regresses — that failure was observed and fixed during this suite's
development, so prefer extraction whenever the block is the thing under test.
