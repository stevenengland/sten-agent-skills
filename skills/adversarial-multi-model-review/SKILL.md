---
name: adversarial-multi-model-review
description: >
  Adversarial review using multiple AI models, each covering all expert
  perspectives independently. Models cross-review each other to produce a
  definitive, consolidated list of improvements. Use when asked for a
  thorough adversarial review, multi-model review, cross-model critique,
  or when you want multiple AI perspectives on code, plans, designs, or
  architecture. Runs in four phases — switch models between phases for
  maximum adversarial value.
argument-hint: 'Pass the file path, code block, plan, or design to review'
---

# Adversarial Multi-Model Review

## Purpose

You are running a structured adversarial review that combines **all expert
perspectives** across **multiple AI models** to surface issues that a single
reviewer would miss. Every model independently examines the artifact through
every lens — engineering, security, architecture, operations, production,
and devil's advocate. Then each model challenges the previous models'
conclusions. Different training data, reasoning styles, and blind spots
mean genuine disagreements emerge — and those disagreements are where the
most valuable insights hide.

---

## How It Works

The review runs in **four phases**. Each phase is designed to be executed by
a different model. Between phases, the user switches models in the VS Code
model picker. All intermediate findings are written to a **review artifact
file** stored in a temp directory outside the repository.

| Phase | Model | Action |
|-------|-------|--------|
| 1 | **Claude Sonnet 4.6** | Independent full-spectrum review |
| 2 | **Claude Opus 4.6** | Independent full-spectrum review, then counter-review of Phase 1 |
| 3 | **GPT 5.3 Codex** | Independent full-spectrum review, then challenge Phases 1 & 2 |
| 4 | Any model | Consolidate, deduplicate, resolve disputes → definitive list |

Every model reviews from **all six perspectives** independently. This makes
cross-review much richer — you can directly compare how different models
assessed the same concern from the same angle.

> **Single-model fallback:** If model switching is not possible, run all
> four phases sequentially with the current model. The multi-perspective
> structure still provides value through forced adversarial framing, even
> when the underlying model is the same.

---

## Review Artifact Location

The review file is stored **outside the repository** in a temp directory to
avoid polluting the codebase:

1. Create the directory `/tmp/adversarial-reviews/` if it does not exist.
2. The review file is named using the pattern:
   `adversarial-review-[target-name]-[YYYY-MM-DD].md`
   where `[target-name]` is a slugified version of the review target
   (e.g., the filename, module name, or a short descriptor).
3. On Phase 1, print the full path so the user can find it and subsequent
   phases can locate it.

---

## The Six Perspectives

Every phase must review the artifact through **all six** of these lenses.
Do not skip any.

### 1. Engineering
- **Correctness:** Does this actually solve the stated problem, or a proxy of it?
- **Simplicity:** Is there a materially simpler approach being ignored?
- **Edge cases:** Empty input, concurrent access, failure mid-sequence, off-by-one, boundary conditions.
- **Error handling:** Are failures handled or silently swallowed?
- **Dependencies:** Are there unnecessary coupling points or fragile assumptions?
- **Testability:** Can this be tested in isolation? Are critical paths covered?

### 2. Security
- **Trust boundaries:** Are new ones introduced without justification?
- **Input validation:** Is external input trusted without sanitisation?
- **Secrets and credentials:** Are they handled safely?
- **Injection surfaces:** SQL, XSS, command injection, path traversal.
- **Authentication and authorisation:** Are access controls present where needed?

### 3. Architecture
- **Structural fit:** Is this the right approach for the problem size and context?
- **Coupling and cohesion:** Are components properly separated? Are abstractions at the right level?
- **Extensibility:** Does the design accommodate likely future changes without overengineering?
- **Consistency:** Does this match the existing patterns in the codebase?
- **Naming and contracts:** Are interfaces clear and self-documenting?

### 4. Operations
- **Operational readiness:** Logging, observability, configuration, rollback — addressed or deferred?
- **Failure modes:** What breaks first in production? How obvious will it be?
- **Performance:** Are there obvious bottlenecks, N+1 queries, or unbounded operations?
- **Data integrity:** Are state transitions safe under concurrent access?
- **Deployment complexity:** Does this introduce operational burden disproportionate to its value?

### 5. Production
- **Real-world behaviour:** How will this actually perform under load, not in a test harness?
- **Failure recovery:** When (not if) this fails, how does the system recover?
- **User impact:** What does the end user experience when something goes wrong?
- **Monitoring gaps:** Will operators know something is wrong before users complain?
- **Backwards compatibility:** Does this break existing consumers?

### 6. Devil's Advocate
- **Assumptions:** What unstated assumptions does this design rely on? Are they valid?
- **Alternatives:** Is there a fundamentally different approach that everyone is ignoring?
- **Overengineering:** Is the solution more complex than the problem warrants?
- **Premature abstraction:** Are abstractions being added before the pattern is proven?
- **Cargo culting:** Are patterns used because they are fashionable, not because they fit?

---

## Phase Detection

Determine which phase to execute:

1. Look for the review artifact file in `/tmp/adversarial-reviews/`.
   If `$ARGUMENTS` contains a file path or name, use it to infer the
   expected file name. If multiple review files exist, pick the most
   recent one matching the target and confirm with the user.
2. If **no matching file exists** → execute **Phase 1**.
3. If a file exists, read it:
   - Contains only a `## Phase 1` section → execute **Phase 2**.
   - Contains `## Phase 1` and `## Phase 2` sections → execute **Phase 3**.
   - Contains Phases 1–3 → execute **Phase 4**.
   - Contains `## Final Verdict` → the review is complete. Inform the user
     and ask if they want to start fresh.

---

## Phase 1 — First Review (Claude Sonnet 4.6)

### 1.1 — Identify the Review Target

Read the input from `$ARGUMENTS`. This can be:
- A file path → read the file
- A code block in the conversation → use it directly
- A plan or design description → treat it as the artifact

If the target is ambiguous, ask the user to clarify before proceeding.

### 1.2 — Independent Full-Spectrum Review

Review the artifact through **all six perspectives** defined above. For
each perspective, work through every checklist item. Record a finding only
when you identify a genuine issue — do not force findings for perspectives
where nothing is wrong.

### 1.3 — Write Findings

Create the review artifact file (see Review Artifact Location) with:

```markdown
# Adversarial Multi-Model Review

**Target:** [description of what is being reviewed]
**Original location:** [file path or "conversation input"]
**Date:** [current date]
**Review file:** [full path to this file]

---

## Phase 1

**Model:** Claude Sonnet 4.6

### Findings

[For each finding:]

#### P1-[N]: [Short title]
- **Severity:** Critical | High | Medium | Low
- **Perspective:** Engineering | Security | Architecture | Operations | Production | Devil's Advocate
- **Problem:** [What is wrong and why it matters]
- **Evidence:** [Quote or reference from the artifact]
- **Suggestion:** [Concrete fix or improvement]

### Phase 1 Summary
- Total findings: [count]
- By severity — Critical: [count] | High: [count] | Medium: [count] | Low: [count]
- By perspective — Engineering: [count] | Security: [count] | Architecture: [count] | Operations: [count] | Production: [count] | Devil's Advocate: [count]
```

Inform the user that Phase 1 is complete and prompt them:

> **Phase 1 complete.** Review file: `[full path]`
>
> Switch to **Claude Opus 4.6** in the model picker, then invoke this skill
> again with the same arguments to continue.

---

## Phase 2 — Counter-Review (Claude Opus 4.6)

### 2.1 — Independent Full-Spectrum Review

Review the **original artifact** (not Phase 1's findings yet) through **all
six perspectives**. Do not read Phase 1 until this step is complete. Record
your own findings independently.

### 2.2 — Cross-Review Phase 1

Now read the Phase 1 findings. For each Phase 1 finding:

- **Agree** — the finding is valid. Optionally add depth or a better fix.
- **Disagree** — explain why the finding is a false positive, overstated, or misframed.
- **Extend** — the finding is correct but misses a deeper root cause or related issue.

Then identify any issues Phase 1 **missed entirely** that your independent
review found.

### 2.3 — Append Findings

Append to the review artifact file:

```markdown
---

## Phase 2

**Model:** Claude Opus 4.6

### Independent Findings

[Same format as Phase 1, using P2-N identifiers]

### Cross-Review of Phase 1

[For each Phase 1 finding:]

#### P1-[N]: [Title]
- **Verdict:** Agree | Disagree | Extend
- **Comment:** [Substantive explanation]

### Missed by Phase 1

[Any new issues not covered in Phase 1, with perspective noted]

### Phase 2 Summary
- Independent findings: [count]
- Agreements with Phase 1: [count]
- Disagreements with Phase 1: [count]
- Extensions of Phase 1: [count]
```

Inform the user:

> **Phase 2 complete.** Switch to **GPT 5.3 Codex** in the model picker,
> then invoke this skill again with the same arguments to continue.

---

## Phase 3 — Final Challenge (GPT 5.3 Codex)

### 3.1 — Independent Full-Spectrum Review

Review the **original artifact** through **all six perspectives**. Do not
read Phase 1 or Phase 2 findings until this step is complete.

### 3.2 — Cross-Review Phases 1 & 2

Read all findings from Phase 1 and Phase 2. For each finding across both:

- **Confirm** — this will actually cause problems. Keep it.
- **Downgrade** — the severity is overstated. Suggest a new severity.
- **Reject** — false positive or theoretical concern. Explain.
- **Escalate** — the severity is understated. Explain why it is worse.

Flag any instances where Phase 1 and Phase 2 **contradicted each other** and
take a position on who is right.

Compare how different models assessed the **same perspective** — where
Sonnet and Opus looked at the same angle but reached different conclusions,
explain which assessment is stronger and why.

### 3.3 — Append Findings

Append to the review artifact file:

```markdown
---

## Phase 3

**Model:** GPT 5.3 Codex

### Independent Findings

[Same format, using P3-N identifiers]

### Cross-Review of Phases 1 & 2

[For each finding from Phase 1 and Phase 2:]

#### P[1|2]-[N]: [Title]
- **Verdict:** Confirm | Downgrade | Reject | Escalate
- **Revised severity:** [if changed]
- **Rationale:** [Substantive explanation]

### Cross-Perspective Comparison

[Where models assessed the same perspective differently, compare and rule:]

#### [Perspective name]: [Topic]
- **Sonnet's take:** [summary]
- **Opus's take:** [summary]
- **GPT's take:** [your own assessment]
- **Ruling:** [which is right and why]

### Contradictions Resolved

[Any cases where Phase 1 and Phase 2 disagreed, with your ruling]

### Missed by Previous Phases

[Any new issues not covered by Phase 1 or Phase 2]

### Phase 3 Summary
- Independent findings: [count]
- Confirmed from earlier phases: [count]
- Downgraded: [count]
- Rejected: [count]
- Escalated: [count]
```

Inform the user:

> **Phase 3 complete.** You may switch to any model for the final synthesis.
> Invoke this skill one more time with the same arguments to produce the
> definitive recommendation list.

---

## Phase 4 — Synthesis

**Role: Impartial Synthesiser**

You are a neutral arbiter. Your job is to produce the **definitive list** of
improvements by consolidating all three phases.

### 4.1 — Read All Phases

Read the full review artifact file. Understand all findings, cross-reviews,
agreements, disagreements, and resolutions.

### 4.2 — Consolidation Rules

1. **Deduplicate:** Merge findings that describe the same underlying issue
   (even if framed differently across perspectives or phases). Credit all
   phases that identified it.
2. **Resolve disputes:** When models disagree on severity or validity,
   apply majority-rules. If it is 2-vs-1, go with the majority. If all
   three disagree, favour the most conservative (highest severity) position
   and note the disagreement.
3. **Leverage cross-perspective agreement:** If multiple perspectives
   across multiple models converge on the same issue, that is high-
   confidence — escalate if needed.
4. **Drop rejected findings:** If a finding was rejected in a later phase
   AND the rejection rationale is convincing, remove it. Otherwise, keep it
   with a note.
5. **Adjust severities:** Use the final cross-reviewed severity, not the
   original.
6. **Rank by impact:** Order the final list by severity (Critical → Low),
   then by the number of phases that independently identified the issue.

### 4.3 — Write the Final Verdict

Append to the review artifact file:

```markdown
---

## Final Verdict

### Definitive Improvement List

[For each consolidated item:]

#### [Rank]. [Short title]
- **Final severity:** Critical | High | Medium | Low
- **Perspectives:** [which of the 6 perspectives flagged this]
- **Identified by:** Phase 1, Phase 2, Phase 3 (list which)
- **Consensus:** Unanimous | Majority (2/3) | Disputed (explain)
- **Problem:** [Consolidated description]
- **Recommendation:** [Concrete, actionable fix]

### Review Statistics
- Total unique issues: [count]
- Critical: [count] | High: [count] | Medium: [count] | Low: [count]
- Unanimous agreement: [count]
- Disputed (resolved by majority): [count]
- Findings rejected during cross-review: [count]

### Model Agreement Matrix

| Finding | Sonnet 4.6 | Opus 4.6 | GPT 5.3 Codex | Consensus |
|---------|------------|----------|---------------|-----------|
| [title] | [stance]   | [stance] | [stance]      | [result]  |

### Perspective Coverage Heatmap

| Perspective      | Phase 1 findings | Phase 2 findings | Phase 3 findings | Total |
|------------------|------------------|------------------|------------------|-------|
| Engineering      | [count]          | [count]          | [count]          |       |
| Security         | [count]          | [count]          | [count]          |       |
| Architecture     | [count]          | [count]          | [count]          |       |
| Operations       | [count]          | [count]          | [count]          |       |
| Production       | [count]          | [count]          | [count]          |       |
| Devil's Advocate | [count]          | [count]          | [count]          |       |

### Process Notes
[Observations about where models systematically agreed or diverged per
perspective, and what that reveals about the artifact's strengths and
weaknesses.]
```

### 4.4 — Present to User

Output the Final Verdict section to the user in the conversation. Close with:

> **Adversarial review complete.** The full review history is in
> `[full path to review file]`. The definitive list above reflects the
> consensus of all three models after cross-review and dispute resolution.

---

## Behavioural Rules

- **Never skip the independent review.** Each phase must review the original
  artifact through all six perspectives on its own merits before reading
  previous phases' findings. This prevents anchoring bias.
- **Be genuinely adversarial.** Do not rubber-stamp previous findings. Look
  for false positives, overstated severities, and missed issues. The value
  of this process comes from disagreement, not consensus.
- **Stay concrete.** Every finding must include evidence from the artifact
  and a specific, actionable recommendation. No vague "consider improving..."
  suggestions.
- **Calibrate severity to context.** A homelab project and an enterprise
  payment system have different threat models. Assess risk relative to the
  project's actual context.
- **Do not invent issues to appear thorough.** If a perspective reveals
  nothing significant, say so explicitly. A short, honest review is better
  than a padded one.
- **Respect the phase boundary.** Each phase writes its section and stops.
  Do not execute multiple phases in a single run — the model switch between
  phases is what creates adversarial value.
- **The review file is the source of truth.** All findings, cross-reviews,
  and the final verdict live in the review artifact file outside the repo.
  The conversation is ephemeral; the file persists.
