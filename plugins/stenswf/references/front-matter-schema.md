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
| `type` | `PRD` \| `bug-brief` \| `slice — HITL` \| `slice — AFK` \| `slice — spike` \| `wayfinder` \| `wayfinder-ticket` | Mode + slice-type marker. `bug-brief` is a narrow PRD-shaped artifact emitted by `triage-issue`. `wayfinder` (a shared map) and `wayfinder-ticket` (a map's child investigation issue) are emitted by `wayfinder`; they are planning artifacts, not `review`/`apply` targets. The slice-type marker (`HITL`/`AFK`/`spike`) governs plan **interview depth only** — NOT run reachability. Whether a skill may ask the user is the `STENSWF_UNATTENDED` run mode, per [decision-escalation.md](decision-escalation.md). |

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

## Required keys (wayfinder-ticket issues only)

| Key | Values | Notes |
|---|---|---|
| `ticket_type` | `research` \| `prototype` \| `grilling` \| `task` | Investigation kind. Governs which skill/flow resolves the ticket and whether it is HITL (`prototype`, `grilling`) or AFK-capable (`research`, `task`). Set by `wayfinder`. |
| `map_ref` | issue number (int) | Parent map. Also written as a `Parent map: #<N>` body line for the frontier query. |

## Optional keys

| Key | Values | Notes |
|---|---|---|
| `disqualifier` | `files>15` \| `cross-module` \| `schema-migration` \| `arch-unknown` \| `hitl-cat3` | Required when `lite_eligible: false`. Names the **envelope** blocker. `hitl-cat3` is the special case "no envelope blocker — HITL is the only one"; on a HITL slice that *also* breaks the envelope, emit the envelope blocker instead (the HITL blocker is already carried by `type`, and both must stay visible). |
| `lite_override` | free-text, non-empty | Slices only. Manual attestation that forces the lite path despite `lite_eligible: false`. Honored ONLY when `disqualifier` is `files>15` or `cross-module`; ignored for `schema-migration` / `arch-unknown`. Does **not** lift `hitl-cat3` — that is `hitl_resolved`'s job, and the two keys are independent (a HITL slice over the blast-radius envelope needs both). Consumers (`plan-light`, `ship-light`) log `user_override` with the reason as evidence. Not emitted by `prd-to-issues` / `triage-issue` — added manually post-triage. |
| `hitl_resolved` | free-text, non-empty (`<YYYY-MM-DD> — <n> judgment call(s) resolved via hitl-escape-hatch`) | Slices only. Attestation that the slice's judgment calls were resolved per [hitl-escape-hatch.md](hitl-escape-hatch.md). Clears **only** the HITL blocker, and only when a non-empty `## Resolved judgment calls` section is present too — the field alone opens nothing (`contract_violation`). Every other envelope blocker is evaluated first and independently. Written by the hatch itself, never by hand or by a producer. `type`, `lite_eligible`, and `disqualifier` stay unrewritten as durable provenance. Consumers log `user_override` with the attestation as evidence. |
| `blocked_by` | space-separated issue numbers | E.g. `123 456`. Absence = no blockers. |
| `bug_ref` | issue number (int) | Slices only. Original raw bug-report issue this slice descends from. Informational; not a routing gate. |
| `map_ref` | issue number (int) | On a **PRD/bug-brief**: the `wayfinder` map this artifact was born from (provenance). **Required** on `wayfinder-ticket` issues (see above); optional/informational elsewhere. |
| `affects_prd` | issue number (int) | Bug-brief only. Linked feature PRD (defect discovered against its scope). Informational. |
| `migration_mode` | `behavior-preserving` \| `contract-changing` | **Required** on slices whose parent has `class: migration`; absent everywhere else. Biases the behavior-change heuristic; see [behavior-change-signal.md](behavior-change-signal.md). |

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
