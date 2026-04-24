---
name: plan-light
description: Lightweight planning for a well-scoped slice issue. Produces a
  single plan-light.md plus a 4-field plan-light.json identity card under
  `.stenswf/<issue>/` that `ship-light` can optionally consume. Makes
  educated guesses silently; escalates to heavy `plan` + `ship` only when
  genuinely blocked. Works with any model.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs dialogue and tool-use narration. The `plan-light.md`
artifact itself is full prose — `brevity`'s Scope section already
excludes issue-body-shaped artifacts.

---

Plan the implementation of slice issue number $ARGUMENTS.

## Audience

Unlike heavy `plan`, `plan-light` assumes the same model class will
ship. Do **not** over-document for a context-naive implementer — keep
notes compact. One markdown file, one JSON stub, no subtree.

This skill never interrupts the user. It either writes a plan and
returns `READY`, or it aborts to heavy `plan` + `ship` by returning
`ROUTE_HEAVY: <reason>`. No questions, no interviews.

The final line of output must be exactly one of:

```
READY
ROUTE_HEAVY: <one-sentence reason>
```

---

## Phase 0 — Preflight

Fetch the issue body and verify it is a slice:

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
wc -l /tmp/slice-$ARGUMENTS.md   # confirm; do not cat

TYPE=$(awk '/^## Type/,/^## /' /tmp/slice-$ARGUMENTS.md \
  | sed '$d' | tail -n +3 | head -1 | tr -d '[:space:]')
```

- `$TYPE == "PRD"` or missing → abort to the user:
  *"Not a slice issue — cannot plan-light. Use `/stenswf:prd-to-issues`
  to break the PRD down first."* Exit. Do not emit `ROUTE_HEAVY` (this
  is a misuse, not an envelope breach).
- `$TYPE` starts with `slice` → continue.

Extract the same envelope-check inputs that `ship-light` uses:

```bash
awk '/^## What to build/,/^## /'            /tmp/slice-$ARGUMENTS.md | sed '$d' > /tmp/slice-$ARGUMENTS-what.md
awk '/^## Conventions \(from PRD\)/,/^## /' /tmp/slice-$ARGUMENTS.md | sed '$d' > /tmp/slice-$ARGUMENTS-conv.md
awk '/^## Acceptance criteria/,/^## /'      /tmp/slice-$ARGUMENTS.md | sed '$d' > /tmp/slice-$ARGUMENTS-acs.md
awk '/^## Files \(hint\)/,/^## /'           /tmp/slice-$ARGUMENTS.md | sed '$d' > /tmp/slice-$ARGUMENTS-files.md
```

Run the Lite envelope check — same rules as `ship-light` Phase 0. If
**any** are true, emit `ROUTE_HEAVY` as your final line and exit:

- Body declares `Lite-eligible: false`. Echo the `Disqualifier:` tag if
  present: `ROUTE_HEAVY: lite-ineligible — <tag>`.
- Open `Blocked by #N` reference present.
- Scope plausibly exceeds the Lite envelope:
  - > 15 files likely changed.
  - Crosses more than one top-level module directory.
  - Schema migration implied.
  - Architectural decision not already resolved in
    `## Conventions (from PRD)`.

Exception: `## Type: slice — spike` ignores `arch-unknown` disqualifiers —
spike slices exist to resolve unknowns.

---

## Phase 1 — Quick orientation (conditional)

If `## Files (hint)` exists and lists ≤4 concrete paths, skip
orientation — the hint IS the orientation. Proceed to Phase 2.

Otherwise dispatch ONE `Explore` subagent (thoroughness: quick, ≤300
words):

> For issue #$ARGUMENTS, return a ≤300-word orientation:
>
> 1. Exact test command and test runner config path.
> 2. 1–2 structurally analogous files (symbol paths only, no file
>    contents) — one implementation, one test.
> 3. `CLAUDE.md` / `AGENTS.md` hard lines: untouchable files, forbidden
>    suppressions, required tooling.
> 4. Naming / module-layout conventions relevant to the affected area.
>
> Symbol paths only. Do not paste file contents.

---

## Phase 2 — Self-resolve decisions (silent)

Walk each AC. For every ambiguity encountered, apply this hierarchy:

1. Covered by `## Conventions (from PRD)` → use the convention silently.
2. Codebase analog exists (from the orientation or `Files (hint)`) →
   mirror the analog silently, record the decision in `## Assumptions`.
3. Two materially different paths, both plausible, **no codebase
   tiebreaker** → abort:
   `ROUTE_HEAVY: arch decision needed — <one sentence>`.
4. AC wording itself is ambiguous enough to mean two different
   behaviors → abort:
   `ROUTE_HEAVY: AC ambiguity — <quote the AC, propose the two reads>`.
5. A convention from the PRD conflicts with the existing codebase →
   abort:
   `ROUTE_HEAVY: convention conflicts with <path> — <one sentence>`.

No interview. No question-asking. Either resolve silently or escalate.

---

## Phase 3 — Write the artifact

Create the directory if needed:

```bash
mkdir -p ".stenswf/$ARGUMENTS"
```

### `.stenswf/$ARGUMENTS/plan-light.md`

Soft cap: ≤200 lines total. Hard cap: ≤6 tasks. If you need >6 tasks
the slice is too big for the lite path — emit
`ROUTE_HEAVY: scope >6 tasks — needs heavy plan`.

Template (full prose — `brevity` does NOT apply to the artifact):

```markdown
# Plan-Light — #$ARGUMENTS — <one-line title>

## Context

3–5 sentences: the behavioral goal, the key modules/files touched,
and the 1–3 conventions from `## Conventions (from PRD)` that
materially shape this slice. Pull analogous symbol paths inline
where useful.

## Tasks

- **T1. <short imperative name>**
  Files: `path/to/impl.py`, `tests/path/to/test_impl.py`
  Done when: <AC wording verbatim or a crisp criterion mapped to one AC>
  Commit: `<type>(<scope>): <imperative subject, ≤72 chars>`

- **T2. …**

(Tasks are vertical slices: each delivers observable behavior with a
failing test → minimal code → green. Hard cap 6.)

## Assumptions

- <load-bearing guess 1 — what was silently resolved, and why>
- <load-bearing guess 2>
- <load-bearing guess 3>

## Skipped (vs heavy plan)

- No stable-prefix, no per-task subagent dispatch, no manifest task
  tracking, no `--resume`.
- Issue body ACs remain authoritative — this plan is advisory
  implementation guidance only.
```

### `.stenswf/$ARGUMENTS/plan-light.json`

Compute `source_signature` from the three canonical sections:

```bash
SIG=$( { \
  cat /tmp/slice-$ARGUMENTS-what.md; \
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

No `manifest.json`, no `log.jsonl`, no `stable-prefix.md`, no
separate `conventions.md`/`house-rules.md`/`design-summary.md`/
`acceptance-criteria.md`/`file-structure.md`/`review-step.md`.

---

## Phase 4 — Self-check and final line

Three checks on `plan-light.md` before returning:

- [ ] **AC ↔ task coverage.** Every AC in the issue body maps to
      exactly one task's `Done when`. Missing coverage → fix inline.
- [ ] **No placeholders.** Grep for `TODO`, `FIXME`, `<...>` stubs
      that weren't replaced. Fix inline.
- [ ] **Task count ≤ 6.** If >6, emit
      `ROUTE_HEAVY: scope >6 tasks — needs heavy plan`.

Then tell the user in one paragraph:

> Plan written to `.stenswf/$ARGUMENTS/plan-light.md`. Run
> `/stenswf:ship-light $ARGUMENTS` to implement (it will auto-detect
> and consume this plan), or `/stenswf:slice-e2e $ARGUMENTS` to plan
> and ship in one shot with subagent context separation.

Print exactly one final line:

```
READY
```

(or `ROUTE_HEAVY: <reason>` if aborting).

---

## Out of scope (deliberate)

- No `manifest.json` beyond the 4-field stub.
- No `stable-prefix.md`, no per-task subagent dispatch planning.
- No separate conventions/house-rules/design-summary files.
- No `--resume`. Re-running `plan-light` overwrites in place.
- No interview phase. No question-asking. Either silent resolution or
  `ROUTE_HEAVY`.
- No industry-pattern research, no deep exploration loops.
