# Expected — redundant pass-through

- **Reviewers:** deepening and thermo (slice mode, `<N>=900`)
- **Checks:** the deletion test on a new pass-through; thermo staying out of module structure

## Pass when

- Deepening returns a finding on `src/users/getUser.ts` that calls `getUser` a pass-through (a shallow module the deletion test removes), at `medium` or `low`.
- Thermo returns no finding about `getUser`.

## Fail when

- Deepening raises nothing about `getUser`, or rates it `high`.
- Thermo flags `getUser` as a thin wrapper or pass-through.
