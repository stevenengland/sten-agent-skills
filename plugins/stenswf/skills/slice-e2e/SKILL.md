---
name: slice-e2e
description: One-shot lite pipeline dispatching `plan-light` then `ship-light` in separate subagent sessions for context separation.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first response.**
It governs orchestrator narration. Subagent dispatch prompts are full
prose.

---

This skill is a **facade**. All actual work happens in two dispatched
subagents. The orchestrator parses one-line envelopes and passes
control through. Zero judgment calls — run on the cheapest available
model.

Pipeline for slice issue $ARGUMENTS:

1. Dispatch subagent → `plan-light` → writes artifact, returns envelope.
2. On `READY`: dispatch subagent → `ship-light` → implements, opens PR,
   watches CI, returns terminal state.
3. On `ROUTE_HEAVY` from either phase: surface reason, recommend heavy
   `plan` + `ship`, exit.

---

## Phase 0 — Preflight

**Ceremony invariant (TDD-as-lens).** This skill MUST NOT (a)
instruct skipping tests for ACs annotated `(behavior)`, (b) remove
`tdd` from any SKILLS TO LOAD list (it appears in every dispatched
subagent's SKILLS list), (c) accept `manual check` or "rely on
existing suite" as completion evidence for a `(behavior)` AC, or
(d) emit guidance that contradicts `tdd/SKILL.md`. Detection of
behavior change is the gate; loading `tdd` is the lens; whether to
write a test follows from the AC tag, not from this skill. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

Confirm the target is a slice issue:

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
TYPE=$(awk '/^## Type/,/^## /' /tmp/slice-$ARGUMENTS.md \
  | sed '$d' | tail -n +3 | head -1 | tr -d '[:space:]')
```

- `$TYPE` starts with `slice` → continue.
- Anything else → tell the user:
  *"Not a slice issue. `slice-e2e` only handles slices. Use
  `/stenswf:prd-to-issues` first if this is a PRD."* Exit.

---

## Phase 1 — Dispatch `plan-light` subagent

Message template (paste verbatim):

```
SKILLS TO LOAD: plan-light, brevity

Run the plan-light skill for issue #$ARGUMENTS.

Your FINAL line of output must be exactly one of:
  READY
  ROUTE_HEAVY: <one-sentence reason>

Do not ask the user anything. Either write the plan and return READY,
or abort with ROUTE_HEAVY.
```

Capture the subagent's final non-empty line:

```bash
# Parse the last non-empty line of the subagent's output
FINAL=$(printf '%s\n' "$SUBAGENT_OUTPUT" | awk 'NF' | tail -1)
```

Branch on the envelope:

- **`READY`** → continue to Phase 2.
- **`ROUTE_HEAVY: <reason>`** → print to the user:

  > `plan-light` aborted: <reason>
  >
  > This slice needs the full pipeline. Run:
  >
  >     /stenswf:plan $ARGUMENTS
  >     /stenswf:ship $ARGUMENTS

  Exit. Do not post anything on the issue.
- **Anything else** (malformed output, subagent harness failure) →
  print the last ~10 lines of subagent output verbatim to the user
  and exit.

Sanity-check the artifact on disk before dispatching Phase 2:

```bash
[ -s ".stenswf/$ARGUMENTS/plan-light.md" ]   || { echo "plan-light.md missing"; exit 1; }
[ -s ".stenswf/$ARGUMENTS/plan-light.json" ] || { echo "plan-light.json missing"; exit 1; }
```

---

## Phase 2 — Dispatch `ship-light` subagent

`tdd` is a non-removable member of every dispatched SKILLS TO LOAD
list. AC tags from the issue body (`(behavior)` / `(structural)`) are
the gate; the subagent re-validates per
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

Message template (paste verbatim):

```
SKILLS TO LOAD: ship-light, tdd, clean-code, lint-escape, brevity

Run the ship-light skill for issue #$ARGUMENTS.

A plan-light artifact is on disk at .stenswf/$ARGUMENTS/plan-light.md
(with identity stub plan-light.json, including `behavior_change_acs`).
Consume it as advisory implementation guidance per ship-light's
Phase 0.5 detection block. Issue body acceptance criteria remain
authoritative for "done." Re-validate every AC tag against the
heuristic ladder; untagged ACs are a hard contract_violation.

Your FINAL line of output must be exactly one of:
  PR_OPENED <pr-url>
  CI_BLOCKER <pr-url>
  ROUTE_HEAVY: <one-sentence reason>

Do not ask the user anything. Either ship or abort.
```

Parse the final line the same way. Then **validate the URL token** via
host CLI round-trip (contract boundary — producers populate, consumer
verifies):

```bash
KEYWORD=$(printf '%s' "$FINAL" | awk '{print $1}')
ARG=$(printf '%s' "$FINAL" | cut -d' ' -f2-)
case "$KEYWORD" in
  PR_OPENED|CI_BLOCKER)
    RESOLVED=$(gh pr view "$ARG" --json url -q .url 2>/dev/null) || {
      echo "Malformed envelope: $ARG is not a PR URL"; exit 1; }
    [ "$RESOLVED" = "$ARG" ] || {
      echo "Malformed envelope: PR URL mismatch ($RESOLVED vs $ARG)"; exit 1; }
    ;;
esac
```

Branch:

- **`PR_OPENED <pr-url>`** → print:

  > Shipped (PR open, awaiting merge): <pr-url>

  Exit silently.
- **`CI_BLOCKER <pr-url>`** → print:

  > CI blocked after ship-light's cycle cap: <pr-url>
  >
  > The PR has a `CI_BLOCKER` comment with diagnosis and next-step
  > suggestions. Review there.

  Exit.
- **`ROUTE_HEAVY: <reason>`** → print:

  > `ship-light` aborted mid-flight: <reason>
  >
  > Partial commits are on the branch. Continue with:
  >
  >     /stenswf:plan $ARGUMENTS
  >     /stenswf:ship $ARGUMENTS

  Exit.
- **Malformed output** → print the last ~10 lines verbatim and exit.

---

## Out of scope (deliberate)

- No retry logic. If a subagent fails, surface and exit.
- No parallel multi-slice (`slice-e2e 123 124 …`) — single issue only
  in v0.5.
- No caching across runs. Re-invoking re-dispatches both phases.
- No issue comments. The only side effects are what `plan-light` and
  `ship-light` themselves perform (local artifacts, branch, PR, PR
  comments).
- No judgment calls. If you find yourself reasoning about anything
  other than "which envelope did I receive," you are doing it wrong —
  that work belongs inside one of the dispatched subagents.
