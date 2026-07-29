# Review finding validation

Treat every finding as a hypothesis, regardless of author.

1. Verify the diagnosis against the current code, requirements, active
   decisions, and tests. Reproduce behavior claims RED-first per
   [../skills/tdd/SKILL.md](../skills/tdd/SKILL.md).
2. Derive the smallest safe remedy yourself — the reviewer's remedy is not
   authoritative. Scope drift alone does not justify reverting collateral work
   that enables, preserves, or repairs required behavior.
3. Report: `Diagnosis: confirmed | rejected | inconclusive` ·
   `Evidence: <code/test/spec citations>` ·
   `Remedy: safe | unsafe | unknown — <minimum change, or none>` ·
   `Rollback: yes | no`.

Rejected or inconclusive → do not edit; record the evidence. Confirmed with no
safe remedy → block; never report it handled.

**Rollback** — intentionally reversing delivered behavior or a recorded
decision (ordinary code removal is not one) — is a **heavy decision**: ASK
with alternatives + recommendation, PARK when unattended, per
[decision-escalation.md](decision-escalation.md). YOLO and autonomous loops do
not supply that approval, and a parked PR thread stays unresolved and
unhandled.
