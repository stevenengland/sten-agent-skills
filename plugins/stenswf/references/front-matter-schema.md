# stenswf front-matter schema (v1)

Every PRD and slice issue body opens with a machine-readable HTML-comment
block. Invisible in the GitHub UI, parsed by every lifecycle skill.

## Syntax

```
<!-- stenswf:v1
type: slice — AFK
lite_eligible: true
conventions_source: prd#123
prd_ref: 123
-->
```

Rules:

- First line: literal `<!-- stenswf:v1` (space-sensitive; used for
  version detection).
- Last line: literal `-->` on its own line.
- Body: one `key: value` per line, YAML-compatible single-line values.
- Block MUST appear as the first non-blank content of the issue body.

## Required keys (all issues)

| Key | Values | Notes |
|---|---|---|
| `type` | `PRD` \| `bug-brief` \| `slice — HITL` \| `slice — AFK` \| `slice — spike` | Mode + slice-type marker. `bug-brief` is a narrow PRD-shaped artifact emitted by `triage-issue`. |

## Required keys (PRD + bug-brief issues)

| Key | Values | Notes |
|---|---|---|
| `class` | `capability` \| `integration` \| `migration` \| `refactor` \| `bug-brief` | Shapes which template sections carry the load. `bug-brief` is reserved for `triage-issue` output. |
| `prd_base_sha` | 7-40 hex chars | Set by `prd-from-grill-me` / `triage-issue`. |

## Required keys (slice issues only)

| Key | Values | Notes |
|---|---|---|
| `lite_eligible` | `true` \| `false` | Gate for `ship-light` / `plan-light`. |
| `conventions_source` | `prd#<N>` \| `bug-brief#<N>` \| `none` | Where slice conventions come from. `none` = slice-local only. |
| `prd_ref` | issue number (int) | Parent PRD or bug-brief. Used by `review/slice` to synthesize lite-path conventions. |

## Optional keys

| Key | Values | Notes |
|---|---|---|
| `disqualifier` | `files>15` \| `cross-module` \| `schema-migration` \| `arch-unknown` \| `hitl-cat3` | Required when `lite_eligible: false`. |
| `blocked_by` | space-separated issue numbers | E.g. `123 456`. Absence = no blockers. |
| `bug_ref` | issue number (int) | Slices only. Original raw bug-report issue this slice descends from. Informational; not a routing gate. |
| `affects_prd` | issue number (int) | Bug-brief only. Linked feature PRD (defect discovered against its scope). Informational. |

## Extraction (canonical)

See [extractors.md](extractors.md) for the parser snippet. One-liner for
a single key:

```bash
sed -n '/^<!-- stenswf:v1/,/^-->/p' "$BODY" \
  | sed -n 's/^'"$KEY"':[[:space:]]*\(.*\)$/\1/p' \
  | head -1
```

## Version compatibility

Only `<!-- stenswf:v1` is recognised. Bodies with a different opening
tag (`<!-- stenswf:v2`, etc.) are rejected by parsers — they must be
upgraded or the reader must use the matching stenswf plugin version.

Bodies with no stenswf front-matter block at all are rejected with a
helpful message directing the user to re-run `prd-from-grill-me` or
`prd-to-issues`.
