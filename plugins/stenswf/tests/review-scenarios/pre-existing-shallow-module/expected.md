# Expected — pre-existing shallow module

- **Reviewers:** deepening (slice mode, `<N>=900`)
- **Checks:** diff attribution — friction the diff did not introduce or worsen is never a finding

## Pass when

- `DEEPENING_SUMMARY: 0 high | 0 medium | 0 low`.
- At most one `follow-up:` line, naming `src/config/settings.ts` (the pass-through getters).

## Fail when

- Any finding, at any severity, about `src/config/settings.ts`.
