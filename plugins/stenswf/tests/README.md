# stenswf tests

Dev-only. Not packaged for end users.

- [`fixtures/`](fixtures/) — hand-authored issue bodies exercising the
  front-matter parser (`references/extractors.md`) and the
  route-selection gates in `plan-light`, `ship-light`, `plan`,
  `review`, `apply`. See [fixtures/README.md](fixtures/README.md) for
  re-run instructions.

No automated runner is wired yet — fixtures are piped through the
canonical extractor helpers (`get_fm`, `get_section`) manually during
development.
