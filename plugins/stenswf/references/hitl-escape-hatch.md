# HITL escape hatch — resolve the judgment calls, keep the lite path

A HITL slice is lite-shaped work with irreducible human judgment calls still
outstanding. When a human is present and HITL is the **only** thing left
blocking the lite path, those calls are answerable in one sitting.

This reference owns the protocol. The interview is
[decision-escalation.md](decision-escalation.md)'s ASK contract weighted by
[decision-weighting.md](decision-weighting.md), applied to each open call —
not restated here. Gate state and attestation validity belong to
`hitl_status` ([extractors.md](extractors.md)).

Loaded lazily by `plan-light` and `ship-light`.

---

## Precondition — HITL must be the sole remaining blocker

The caller MUST have evaluated every other Lite-envelope blocker
(`blocked_by`, scope, `schema-migration`, `arch-unknown`, blast radius and any
`lite_override` that waives it) and found them clear. The hatch runs **last**.

It resolves judgment calls. It does not make a one-way door reversible, shrink
a blast radius, or settle an architecture. If any other blocker is live, route
heavy without running the hatch — do not write resolutions to an issue that is
going heavy anyway.

Outcome is the caller's `HITL_STATE` moving to `cleared`. The hatch never
assigns `LITE` — that is the general envelope result and not the hatch's to
overwrite.

**Availability.** Requires an available run per
[decision-escalation.md](decision-escalation.md) § Availability —
`STENSWF_UNATTENDED` unset and not dispatched as an unattended subagent.
Unattended → the hatch does not run and the caller routes heavy. There is no
PARK: the gate fires at preflight, before any work exists to park.

---

## Input — the `## Open judgment calls` section

HITL slices carry their open calls in a required section, written by the
producer (`prd-to-issues` Step 3, `triage-issue` Phase 5.6):

```markdown
## Open judgment calls

- **<what must be decided, one sentence>** — <why it needs a human>
```

This section is the **sole** input. Do not reconstruct the list from AC
wording, parent sections, or inference — a reconstructed list can miss the
original blocker or conclude there were none, and then attest to that.

Missing or empty on a HITL slice → the producer broke its contract. Log
`contract_violation` and hand the caller
`ROUTE_HEAVY: HITL slice has no ## Open judgment calls — re-run prd-to-issues / triage-issue`.

---

## Resolve

Per entry, apply the ASK contract: the decision in one sentence, 2–3 researched
alternatives with trade-offs, industry-leader precedent named as company +
specific practice where one genuinely informs the fork, and a recommendation
led with. Weigh per [decision-weighting.md](decision-weighting.md) — build
effort is not a factor. Ask via `AskUserQuestion`, one call per question.

Write no code here; planning is the caller's job once the hatch returns.

---

## Commit — one atomic edit

Only after every entry is resolved. All of the following go up in a **single**
`gh issue edit --body-file` call, so the issue is never half-written:

1. **Replace** `## Open judgment calls` with `## Resolved judgment calls` —
   the open section does not survive; the issue always states exactly one of
   the two.

   ```markdown
   ## Resolved judgment calls

   <!-- Written by references/hitl-escape-hatch.md. Spec-bearing: part of source_signature. -->

   - **<decision, one sentence>** → <chosen option>.
     Rejected: <alternative> — <one-line why not>.
     Precedent: <Company> — <specific practice>.   <!-- omit if none applied -->
     Anchor: D<n>.
   ```

2. **Set the attestation** in the `<!-- stenswf:v1 -->` block, in the canonical
   form `hitl_status` enforces (see [extractors.md](extractors.md)):

   ```
   hitl_resolved: <YYYY-MM-DD> — <n> judgment call(s) resolved via hitl-escape-hatch
   ```

   `<n>` must equal the number of bullets written above.

Then append one `decision` anchor per call to `.stenswf/$ARGUMENTS/decisions.md`
(chosen **and** rejected) per [decision-anchor-link.md](decision-anchor-link.md),
category `arch` for genuinely architectural calls. `Source:` is the host skill —
provenance stays with the seam. Log `user_override` with the attestation.

Leave `type`, `lite_eligible`, and `disqualifier` **unrewritten**: they are
durable provenance, and a later heavy re-route must still see that this slice
was HITL.

---

## Bail-outs

Write **nothing** to the issue and hand the caller a `ROUTE_HEAVY: <reason>`
when:

- the entries number **more than 3**, or answering one changes the
  alternatives for another — coupled or numerous calls are a re-plan, not an
  escape hatch;
- the interview surfaces an architectural redesign, schema/data migration, or
  scope past the envelope;
- the user defers, declines, or asks for the heavy path.

Partial resolution is not a state — every call is answered and committed, or
nothing is.

---

## Downstream

- **`source_signature`** covers `## Resolved judgment calls`; it is spec.
  Absent on untouched slices, so pre-existing signatures are unchanged.
- **Re-runs** reuse a `cleared` slice silently — no re-confirmation. Edited
  resolutions change the signature, which already stales any dependent
  `plan-light` artifact.
- **`review`** sees ordinary active anchors — nothing parked, nothing blocking.
- **`slice-e2e`** stays unattended and routes heavy; resolve first with an
  attended `/stenswf:plan-light <N>`.
