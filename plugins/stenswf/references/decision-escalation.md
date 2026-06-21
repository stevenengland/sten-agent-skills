# Decision escalation — consult on heavy, decide on easy

Single source for **when a skill must consult the user before deciding** and
**how it consults**. The governing rule: a skill never decides a *heavy*
question on its own. It reasons about alternatives, presents them with a
recommendation, and asks — or, when no answer is obtainable, parks the work
rather than guessing.

This reference is **additive**. It adds an ask/park layer on top of the
classifiers stenswf already has; it never overrides them. The ponytail
safe/contentious split, the behavior-change "default true" ladder, the
`plan-light` resolution tiers, and `clean-code` / `tdd` all keep their
meaning — their outputs **feed** this layer (a contentious cut, a `behavior`
re-tag that is a genuine fork, a "two materially different paths" tie are all
*heavy decisions* routed through the machinery below).

Loaded lazily by `plan`, `plan-light`, `ship` (orchestrator + dispatch),
`ship-light`, and `apply`; referenced by `review` and `tdd` for definitions.
`slice-e2e` does not run the classifier itself; it sets the run mode (below)
and relays the `PARKED` envelope.

---

## Severity — the one-way / two-way door classifier

Every decision is **easy** or **heavy**. Borrowed from the reversible /
irreversible ("two-way door" / "one-way door") framing.

**Easy** — BOTH hold:

- **Reversible** — undoing it later is a cheap code change. No data migration,
  no published artifact, no external contract already shipped.
- **A tiebreaker exists** — a `conventions.md` line, an active `decisions.md`
  anchor, or a clear codebase analog picks the answer.

Easy decisions are made autonomously. Record a `decision` anchor **only if the
choice rejected a concrete alternative** (per
[decision-anchor-link.md](decision-anchor-link.md)); otherwise just proceed.
Minor mechanical choices (naming within conventions, a local helper, test
shape) are easy and need no record.

**Heavy** — ANY of:

- **Irreversible** — one-way door: schema/data migration, a released API or
  CLI surface, a persisted shape, a new dependency, anything a later change
  cannot cheaply walk back.
- **No tiebreaker** — two materially different paths and neither conventions
  nor the codebase picks a winner.
- **Changes a public contract or observable behavior** in a way not already
  pinned by an AC or a recorded decision.
- **Architectural / cross-module** — touches a chosen pattern or spans module
  boundaries.

**Default to heavy on any uncertainty.** (Mirrors the behavior-change ladder's
"default true" and ponytail's "default contentious".)

---

## Outcomes

| Decision | Run available | Run unavailable |
|---|---|---|
| **Easy** | decide + record-if-alt-rejected | decide + record-if-alt-rejected |
| **Heavy** | **ASK** | **PARK** |

> **Zero autonomous heavy decisions, ever.** A skill never picks between two
> heavy alternatives on its own. If it cannot ask, it parks.

`ROUTE_HEAVY` is **not** an outcome of this classifier. ASK fires **before**
`ROUTE_HEAVY`: a single fork the user can resolve in one answer is an ASK, and
the lite path continues with the answer. `ROUTE_HEAVY` is reserved for a
genuine full re-plan — multiple coupled decisions, an architectural redesign,
or scope past the lite envelope. Eligibility gates that already emit
`ROUTE_HEAVY` (lite-ineligible, blocked, scope > envelope, > 6 tasks) are
unchanged.

---

## Availability — the single switch

A run is **available** (may prompt the user) unless it is **unattended**. A run
is unattended when EITHER:

- the environment variable **`STENSWF_UNATTENDED`** is set and non-empty — a
  direct run the user launched intending to walk away (check with
  `[ -n "$STENSWF_UNATTENDED" ]`); or
- the skill was **dispatched as a subagent** whose prompt says it is unattended
  (it cannot prompt the user regardless — see below).

There is no second dial and no slice-TYPE involvement: the slice `type`
(`HITL` / `AFK` / `spike`) governs plan **interview depth**, not reachability.
The issue id stays in `$ARGUMENTS` as before; availability is read from the
environment, not parsed out of the arguments.

- **Direct top-level invocation**, env var unset → available.
- **`STENSWF_UNATTENDED` set** → unavailable.
- **`slice-e2e`** runs its dispatched skills unattended (it is the unattended
  batch entry; otherwise a heavy fork would block the batch). It signals this in
  the **dispatch prompt** — a `Task`, not an exported env var — so that prose
  instruction ("you are unattended; you cannot prompt; PARK heavy decisions") is
  the authoritative signal for the subagent.

The harness cannot detect whether a human walked away from an *available* run; a
heavy ASK in that case blocks until answered (Ctrl-C to park manually). Setting
`STENSWF_UNATTENDED` before the run is the way to opt out up front.

### Subagents bubble up

A subagent (a dispatched `Task`) can never prompt the user. On a heavy
decision it does **not** decide and does **not** park on its own — it emits a
`DECISION_NEEDED` envelope as its result and stops. The orchestrator (the
top-level session) then ASKs (available) or PARKs (unattended) and
re-dispatches with the answer. So a subagent under an available orchestrator is
*reachable*; the subagent boundary is not an unavailability boundary.

---

## The ASK contract

Every ASK — without exception — presents:

1. **The decision** in one sentence.
2. **2–3 researched alternatives.** Research is proportional to severity:
   always check conventions + the codebase; reach for industry practice only
   when it distinguishes options in play. Each alternative carries a one-line
   trade-off.
3. **A recommendation** — lead with it, with its rationale.
4. **The rejected-alternative rationale** when the answer is taken.

Use the harness question facility (e.g. `AskUserQuestion`) where available.
After the answer, record a `decision` anchor per
[decision-anchor-link.md](decision-anchor-link.md) capturing the chosen path
**and** the rejected alternative. Never ask a bare "what should I do?" — a
recommendation is mandatory.

---

## PARK — heavy decision, no answer obtainable

PARK halts the slice cleanly without guessing. It writes the tension where a
human will see it and leaves a resumable marker; it creates **no new artifact
file**.

1. **Tension → the tracker.** Write the full `DECISION_NEEDED` block
   (decision, alternatives, recommendation) to the **PR body** if a PR exists,
   else as an **issue comment**.
2. **Pending note → `decisions.md`.** Append a pending `decision` anchor
   (status `parked`) naming the decision and pointing at the tracker location,
   per [decision-anchor-link.md](decision-anchor-link.md).
3. **Halt and exit** with `PARKED: <one-sentence decision>` as the final
   envelope line. Do not apply anything that depended on the parked decision.

**Resume.** Re-invoking the skill (available) detects the pending `parked`
anchor, ASKs (alternatives + recommendation are already recorded), records the
answer as a resolved `decision`, clears the `parked` status, and continues.

**Review.** `review` treats an unresolved `parked` anchor as **High /
blocking** — a parked decision means the work is not done.

---

## The `DECISION_NEEDED` envelope (wire format)

Emitted by a subagent to its orchestrator, and reused as the PARK tension
block — minus the `TASK_REPORT T<id>` report header that `ship/dispatch.md`
wraps around it when a subagent emits it:

```
DECISION_NEEDED
─────────────────────────────────────────────
Decision:       <one sentence>
Reversible:     yes | no
Alternatives:
  A) <option> — <one-line trade-off>
  B) <option> — <one-line trade-off>
Recommendation: <A|B> — <one-line rationale>
─────────────────────────────────────────────
```

`DECISION_NEEDED` is distinct from a `BLOCKED` / `TASK_BLOCKER` report:
`BLOCKED` is a failure (a command errored, a conflict the subagent could not
execute); `DECISION_NEEDED` is a healthy stop at a heavy fork.

---

## Recording — summary

| Situation | Record |
|---|---|
| Easy, rejected an alternative | `decision` anchor (host seam's source) |
| Easy, no alternative | nothing |
| Heavy, answered via ASK | `decision` anchor (chosen + rejected) |
| Heavy, parked | pending `decision` anchor (`status: parked`) + tracker block |

Provenance stays with the host seam (`plan` / `plan-light` / `ship` /
`ship-light` / `apply`); there is no `decision-escalation` source. See
[decision-anchor-link.md](decision-anchor-link.md).
