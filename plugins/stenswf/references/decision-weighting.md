# Decision weighting — prefer quality over development cost

Single source for **how a skill weighs competing technical options**. It
governs *which* option to pick, not *whether* a skill may pick alone — that
second question belongs to [decision-escalation.md](decision-escalation.md).

Loaded lazily by `architecture`, `plan`, `plan-light`, `grill-me`,
`prd-from-grill-me`, `prd-to-issues`, `triage-issue`, `tdd`, `apply`,
`clean-code`, and `slice-e2e` at their decision points.

---

## The rule

> When making a technical decision, give little weight to development cost
> (build effort and time-to-build). Prefer the option that best serves
> quality, simplicity, robustness, scalability, and long-term maintainability.
> Development cost is never a reason to pick a shallower or less robust design;
> use cost only to break ties between options that are otherwise equal on those
> axes. Do not gold-plate: spending disproportionate effort for negligible
> quality gain is itself poor judgment.

The anti-gold-plating clause is part of the rule, not a footnote: "ignore
development cost" is a mandate for the *right* design, not a licence for
disproportionate over-engineering. The deepest, simplest design that serves
the quality attributes wins — that is usually neither the cheapest-to-build
nor the most elaborate.

---

## What "cost" means here

"Cost" in this rule is **development cost only** — build effort and
time-to-build. It does **not** include:

- **Operational / runtime / infrastructure cost** — compute, latency,
  memory, hosting spend. These are *not* deprioritized; they remain
  legitimate inputs to **scalability** and **reliability**, which the rule
  tells you to prefer. `architecture`'s operational cost/benefit trade-offs
  stay intact.
- **Refactor cost** — the effort to improve existing structure is not framed
  as a cost to avoid. Deepening modules and removing duplication is the
  quality work the rule favours, not an expense to weigh against it.

So "little weight to cost" deprioritizes *how hard it is to build*, never
*how the thing behaves or scales once built*.

---

## Relationship to `decision-escalation`

Distinct, cross-linked concerns:

- **decision-weighting** (this file) — *which option?* How to weigh the
  factors once you are choosing.
- **[decision-escalation.md](decision-escalation.md)** — *may I decide alone,
  or must I ask?* Severity by reversibility + impact.

A corollary the escalation classifier states directly: **cost/effort is not a
severity factor.** A high-effort, robust solution is not "heavier" than a
cheap, shallow one — severity is reversibility + impact, not expense.
