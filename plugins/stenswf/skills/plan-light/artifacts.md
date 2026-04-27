# plan-light — artifact templates

Templates for the three files `plan-light` writes to
`.stenswf/$ARGUMENTS/`. SKILL.md decides *when*; this file decides *what*.

## 1. `plan-light.md`

Soft cap: ≤200 lines. Hard cap: ≤6 tasks. If >6 tasks, abort with
`ROUTE_HEAVY: scope >6 tasks — needs heavy plan`.

```markdown
# Plan-Light — #$ARGUMENTS — <one-line title>

## Context
3–5 sentences: behavioral goal, modules touched, 1–3 materially-shaping
conventions. Analogous symbol paths inline where useful.

## Tasks
- **T1. <short imperative name>**
  Files: `path/to/impl.py`, `tests/path/to/test_impl.py`
  Done when: <AC wording verbatim or crisp mapped criterion>
  Commit: `<type>(<scope>): <imperative subject, ≤72 chars>`

- **T2. …**

(Tasks are vertical slices. Hard cap 6.)

## Assumptions
- <load-bearing guess 1 — what was silently resolved, why>
- <load-bearing guess 2>

## Skipped (vs heavy plan)
- No stable-prefix, no per-task subagent dispatch, no manifest task
  tracking, no `--resume`.
- Issue body ACs remain authoritative.
```

## 2. `plan-light.json`

5-field identity stub. `ship-light` recomputes `source_signature` at
consume time — mismatch → plan treated as stale, ignored.
`behavior_change_acs` mirrors AC tags from the issue body (per
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md))
as a JSON array of AC ids whose tag is `(behavior)`. The list is
computed from `extract_acs` (per
[../../references/extractors.md](../../references/extractors.md));
never hand-authored.

**Kind values.** `"slice-light"` is the intentional vocabulary for
lite plan-ahead artifacts (distinct from heavy `manifest.json`'s
`"slice"`). When `ship-light` runs directly without a prior
`plan-light`, it seeds an `anchor.json` with `kind: "slice-shipped"`
using this same shape — see
[../ship-light/SKILL.md](../ship-light/SKILL.md) Phase 4.

```bash
SIG=$( { cat /tmp/slice-$ARGUMENTS-what.md; \
         cat /tmp/slice-$ARGUMENTS-conv.md; \
         cat /tmp/slice-$ARGUMENTS-acs.md; \
       } | sha256sum | cut -d' ' -f1)

# extract_acs hard-errors itself on untagged ACs; BEHAVIOR_ACS is the
# space-separated id list it produces.
ACS_JSON=$(printf '%s' "${BEHAVIOR_ACS}" \
  | tr ' ' '\n' | awk 'NF{printf "%s\"%s\"", (n++?",":""), $0} END{print ""}')

cat > ".stenswf/$ARGUMENTS/plan-light.json" <<EOF
{
  "issue": $ARGUMENTS,
  "kind": "slice-light",
  "plan_created_at": "$(date -u +%FT%TZ)",
  "source_signature": "$SIG",
  "behavior_change_acs": [${ACS_JSON}]
}
EOF
```

## 3. `lite-notes.md` (handoff to review)

Mirrors `plan-light.md`'s `## Assumptions` block. `ship-light` appends
its own assumptions later. Slice review reads it as soft constraints.

```bash
cat > ".stenswf/$ARGUMENTS/lite-notes.md" <<EOF
# Lite Notes — #$ARGUMENTS

<!-- Read by review/slice.md as soft constraints. Not decisions. -->

## Assumptions (plan-light)
<!-- one bullet per load-bearing guess resolved silently in Phase 2 -->

## Assumptions (ship-light)
<!-- appended by ship-light on exit; empty until then -->
EOF
```

Populate `## Assumptions (plan-light)` with the same bullets written
to `plan-light.md`'s `## Assumptions` section.

## Out of scope (deliberate)

No `manifest.json` beyond the 5-field stub. No `stable-prefix.md`. No
separate conventions/house-rules/design-summary files. No `--resume`.
Re-running overwrites in place.
