# stenswf tests

Dev-only. Not packaged for end users.

- [`pr-threads.test.sh`](pr-threads.test.sh) — behavior tests for the PR
  conversation loop's plumbing (`scripts/pr-threads.sh`).
- [`wayfinder.test.sh`](wayfinder.test.sh) — behavior tests for the
  wayfinder tracker plumbing (`scripts/wayfinder.sh`).
- [`inherit-decisions.test.sh`](inherit-decisions.test.sh) — behavior tests
  for copying active PRD decision stubs into slices
  (`scripts/inherit-decisions.sh`).
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
