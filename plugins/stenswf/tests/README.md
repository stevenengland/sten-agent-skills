# stenswf tests

Dev-only. Not packaged for end users.

- [`pr-threads.test.sh`](pr-threads.test.sh) — behavior tests for the PR
  conversation loop's plumbing (`scripts/pr-threads.sh`).
- [`wayfinder.test.sh`](wayfinder.test.sh) — behavior tests for the
  wayfinder tracker plumbing (`scripts/wayfinder.sh`).
- [`fixtures/`](fixtures/) — hand-authored issue bodies exercising the
  front-matter parser (`references/extractors.md`) and the
  route-selection gates in `plan-light`, `ship-light`, `plan`,
  `review`, `apply`. See [fixtures/README.md](fixtures/README.md) for
  re-run instructions.

```bash
bash plugins/stenswf/tests/pr-threads.test.sh
bash plugins/stenswf/tests/wayfinder.test.sh
```

Both suites inject a fake `gh` on `PATH` rather than calling GitHub. The
fake keeps mutable state — threads, comments, assignees, issue bodies —
so a write is observable by a **later** read, which is the property the
loops actually depend on. A fake that only recorded what was sent would
pass while the real protocol failed to converge.

Fixtures have no runner: they are piped through the canonical extractor
helpers (`get_fm`, `extract_section`) manually during development.
