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

4-field identity stub. `ship-light` recomputes `source_signature` at
consume time — mismatch → plan treated as stale, ignored.

```bash
SIG=$( { cat /tmp/slice-$ARGUMENTS-what.md; \
         cat /tmp/slice-$ARGUMENTS-conv.md; \
         cat /tmp/slice-$ARGUMENTS-acs.md; \
       } | sha256sum | cut -d' ' -f1)

cat > ".stenswf/$ARGUMENTS/plan-light.json" <<EOF
{
  "issue": $ARGUMENTS,
  "kind": "slice-light",
  "plan_created_at": "$(date -u +%FT%TZ)",
  "source_signature": "$SIG"
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

No `manifest.json` beyond the 4-field stub. No `stable-prefix.md`. No
separate conventions/house-rules/design-summary files. No `--resume`.
Re-running overwrites in place.
