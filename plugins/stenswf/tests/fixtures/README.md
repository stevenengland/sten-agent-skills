# Test fixtures — manual verification

These fixtures are small, hand-authored issue bodies that exercise the
front-matter parser (`scripts/extractors.sh`, documented in
`references/extractors.md`) and the route-selection gates in
`plan-light`, `ship-light`, `plan`, `review`, `apply`.

## How to re-run manually

No automated runner — these are pasted into a scratch issue or piped
into `get_fm` / `extract_section` during development:

```bash
source plugins/stenswf/scripts/extractors.sh

F=plugins/stenswf/tests/fixtures/issue-slice-heavy.md
get_fm type               "$F"
get_fm lite_eligible      "$F"
get_fm disqualifier       "$F"
extract_section 'What to build' "$F"
```

Expected results are noted in each fixture's header comment. When a
parser change lands, walk through each fixture by hand and confirm the
expectations still hold.

## Fixtures

| File | Expected route |
|---|---|
| `issue-slice-heavy.md`   | `plan` + `ship` (lite_eligible=false, disqualifier set) |
| `issue-slice-lite.md`    | `ship-light` eligible (lite_eligible=true) |
| `issue-slice-override.md`          | `ship-light` eligible via `lite_override` (disqualifier=files>15, override honored, `user_override` logged) |
| `issue-slice-override-rejected.md` | `plan` + `ship` — `lite_override` IGNORED for disqualifier=schema-migration; ROUTE_HEAVY fires |
| `issue-prd.md`           | PRD-mode (type=PRD) |
| `triage-issue-clean-repro.md` | `triage-issue` Phase-4 default → C-1 (single slice). Bug-brief + one AFK lite slice. |
| `triage-issue-ambiguous.md`   | `triage-issue` Phase-4 only offers R-info (needs-info). No derived artifacts. |
