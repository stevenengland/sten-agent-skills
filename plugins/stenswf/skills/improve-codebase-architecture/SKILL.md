---
name: improve-codebase-architecture
description: Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick.
disable-model-invocation: true
---

**Load and apply `brevity` now.** See [../../references/brevity-load.md](../../references/brevity-load.md).
The HTML report is an artifact: it follows [html-report.md](html-report.md), not brevity.

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities**: refactors that turn shallow modules into deep ones. The aim is testability and AI-navigability.

This command is _informed_ by the project's domain model and built on a shared design vocabulary:

- Load `codebase-design` ([../codebase-design/SKILL.md](../codebase-design/SKILL.md)) for the architecture vocabulary (**module**, **interface**, **depth**, **seam**, **adapter**, **leverage**, **locality**) and its principles (the deletion test, "the interface is the test surface", "one adapter = hypothetical seam, two = real"), applied as questions, not verdicts. Use these terms exactly in every suggestion, and don't drift into "component," "service," "API," or "boundary."
- When the repo has a domain glossary (GLOSSARY.md, CONTEXT.md or UBIQUITOUS_LANGUAGE.md), its language gives names to good seams; ADRs (in `docs/adr/` or a `docs/**/decisions/` directory), when present, record decisions this command should not re-litigate.

## Process

### 1. Explore

**Scope before you scan: YAGNI.** Deepening a module pays off by making future changes to it easier, so put extra weight on the parts of the codebase that have recently changed. Decide *where* to look before you look:

- If the user named a direction (a module, a subsystem, a pain point), take it, and skip the inference below.
- Otherwise, walk back a good stretch of the commit history (`git log --oneline`) to find the codebase's hot spots, the files and areas that keep coming up, and let those paths pull your attention first. If the changes are scattered with no clear hot spot, widen the net.

Read the project's domain glossary and any ADRs in the area you're touching first, when they exist.

Then dispatch an `Explore` subagent to walk the codebase, with `codebase-design` in its SKILLS TO LOAD. Don't follow rigid heuristics; explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow**, with an interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their current interface?

Apply the **deletion test** to anything you suspect is shallow: would deleting it concentrate complexity, or just move it? A "yes, concentrates" is the signal you want.

### 2. Present candidates as an HTML report

Write a self-contained HTML file into the local state directory, which git ignores for this clone, so nothing lands in the repo. Each run gets a fresh file:

```bash
DIR=$(bash ../../scripts/ensure-stenswf-dir.sh .show-me)
TS=$(date -u +%Y%m%dT%H%M%SZ)
REPORT="$DIR/architecture-review-$TS.html"
# write the report to "$REPORT", then open it:
bash ../../scripts/open-html.sh "$REPORT"
```

`open-html.sh` picks the opener for macOS, Linux and WSL and prints the absolute path; pass that path on to the user, especially when no browser opened.

The report uses **Tailwind via CDN** for layout and styling, and **Mermaid via CDN** for diagrams where a graph/flow/sequence reliably communicates the structure. Mix Mermaid with hand-crafted CSS/SVG visuals: use Mermaid when relationships are graph-shaped (call graphs, dependencies, sequences), and hand-built divs/SVG when you want something more editorial (mass diagrams, cross-sections, collapse animations). Each candidate gets a **before/after visualisation**. Be visual.

For each candidate, render a card with:

- **Files**: which files/modules are involved
- **Problem**: why the current architecture is causing friction
- **Solution**: plain English description of what would change, naming the invariants it must keep (transaction boundaries, error behaviour, authorization, ordering)
- **Benefits**: explained in terms of locality and leverage, and how tests would improve
- **Before / After diagram**: side-by-side, custom-drawn, illustrating the shallowness and the deepening
- **Recommendation strength**: one of `Strong`, `Worth exploring`, `Speculative`, rendered as a badge

End the report with a **Top recommendation** section: which candidate you'd tackle first and why.

**Use the domain glossary's vocabulary for the domain, when the repo has one, and the `codebase-design` vocabulary for the architecture.** If the glossary defines "Order," talk about "the Order intake module," not "the FooBarHandler," and not "the Order service."

**ADR conflicts**: if a candidate contradicts an existing ADR, only surface it when the friction is real enough to warrant revisiting the ADR. Mark it clearly in the card (e.g. a warning callout: _"contradicts ADR-0007, but worth reopening because…"_). Don't list every theoretical refactor an ADR forbids.

See [html-report.md](html-report.md) for the full HTML scaffold, diagram patterns, and styling guidance.

Do NOT propose interfaces yet. After the file is written, ask the user: "Which of these would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, load `grill-me` to walk the decision tree with them: constraints, dependencies, the shape of the deepened module, what sits behind the seam, what tests survive.

Side effects happen inline as decisions crystallize. They honor what the repo already has and never create a glossary or an ADR unasked:

- **Naming a deepened module after a concept not in the glossary?** Add the term to the glossary, only when the repo already has one (GLOSSARY.md, CONTEXT.md or UBIQUITOUS_LANGUAGE.md); never create one unasked.
- **Sharpening a fuzzy term during the conversation?** Update that existing glossary right there.
- **User rejects the candidate with a load-bearing reason?** Offer an ADR, framed as: _"Want me to record this as an ADR so future architecture reviews don't re-suggest it?"_ Write it in the repo's existing ADR location; when there is none, offer to create `docs/adr/` using the ADR fields from the `architecture` skill (Context, Decision, Options considered, Consequences). Never create either unasked. Only offer when the reason would actually be needed by a future explorer to avoid re-suggesting the same thing; skip ephemeral reasons ("not worth it right now") and self-evident ones.
- **Want to explore alternative interfaces for the deepened module?** Use the design-it-twice parallel sub-agent pattern from `codebase-design` ([../codebase-design/design-it-twice.md](../codebase-design/design-it-twice.md)).

### 4. Hand off to a PRD

When the grilling has resolved the candidate's shape, offer to turn it into planned work: invoke `prd-from-grill-me` with argument text that starts with `class: refactor` followed by the grilled brief (the candidate, the deepened module's interface, what sits behind the seam, which tests survive, the decisions made and the alternatives rejected). Do not create the PRD here; if the user declines, stop.

## Feedback

Log workflow friction per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=improve-codebase-architecture`.
