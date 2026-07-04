---
name: grill-me
description: Interview the user relentlessly about a plan or design until every branch of the decision tree is resolved ("grill me").
---

## Token Efficiency

**Load and apply the `brevity` skill now, before the first question.**
Keep interview questions, reasoning, and recommendations tight. Self-check
every message against its rules before sending.

---

Interview me relentlessly about every aspect of the plan until we reach a
shared understanding. Walk down each branch of the design tree and resolve
dependencies between decisions one-by-one. 

- For each question, provide your recommended answer and reasoning.
- If a question can be answered by exploring the codebase, explore the codebase
instead.
- Propose 2-3 different approaches with trade-offs.
- Lead with your recommended option and explain why. Weigh options per
  [../../references/decision-weighting.md](../../references/decision-weighting.md)
  — prefer quality, simplicity, robustness, scalability, and maintainability
  over build cost.
- Go back and clarify when something doesn't make sense

When a recommendation touches a problem that well-known companies
(e.g. Stripe, Spotify, GitHub, AWS, Shopify) have solved publicly, research how
those leaders approach it and weave the winning practice into your
recommendation. Cite the company and the specific practice so I can evaluate
the reasoning. Reach for these whenever a leader's approach informs the
decision — not only to break a tie — but don't force-fit them; skip only when
none genuinely applies.

Do not write any code in this phase.
