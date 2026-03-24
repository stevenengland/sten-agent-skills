---
name: documentation-with-mermaid
description: Diagram-first documentation patterns for any project.  Use when creating or updating docs, ADRs, changelogs, docstrings, or any reference material.
license: MIT
metadata:
  tags: documentation, diagrams, mermaid, markdown
  scope: all-projects
  token-optimized: "true"
---

# SKILL: Documentation
> Diagram-first documentation patterns. Minimal prose. Use mermaid wherever structure exists.

---

## Doc Types & When to Use

```mermaid
flowchart TD
    Need[What do you need to document?]
    Need --> API[API / Interface]
    Need --> Proc[Process / Workflow]
    Need --> Arch[Architecture]
    Need --> Ref[Reference / Config]
    Need --> Guide[How-To / Tutorial]

    API --> OpenAPI[OpenAPI / JSDoc / Docstring]
    Proc --> Mermaid_Flow[Mermaid flowchart]
    Arch --> Mermaid_C4[Mermaid C4 / block diagram]
    Ref --> Table[Markdown table]
    Guide --> Steps[Numbered steps + code blocks]
```

---

## Documentation Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Draft
    Draft --> Review
    Review --> Approved
    Review --> Draft : needs changes
    Approved --> Published
    Published --> Outdated : code changes
    Outdated --> Draft : update triggered
    Outdated --> Deprecated
    Deprecated --> [*]
```

---

## Ownership & Responsibility

```mermaid
flowchart LR
    Dev[Developer] -->|writes| Inline[Inline docs / docstrings]
    Dev -->|creates| ADR[Architecture Decision Records]
    TW[Tech Writer] -->|owns| Guides[Guides & Tutorials]
    TW -->|reviews| Inline
    PM[Product Manager] -->|owns| Changelog[CHANGELOG / Release Notes]
    All -->|contribute to| Wiki[Team Wiki]
```

---

## Doc Quality Checklist

```mermaid
flowchart TD
    Start([New/Updated Doc]) --> Q1{Answers a real question?}
    Q1 -->|No| Fix1[Reframe around user need]
    Q1 -->|Yes| Q2{Has a working example?}
    Q2 -->|No| Fix2[Add code/diagram example]
    Q2 -->|Yes| Q3{Accurate & tested?}
    Q3 -->|No| Fix3[Verify against source]
    Q3 -->|Yes| Q4{Discoverable / linked?}
    Q4 -->|No| Fix4[Add to index / nav]
    Q4 -->|Yes| Done([✅ Publish])
```

---

## File Naming Convention

| Type | Pattern | Example |
|---|---|---|
| Guide | `how-to-<verb>-<topic>.md` | `how-to-deploy-api.md` |
| Reference | `ref-<topic>.md` | `ref-config-options.md` |
| ADR | `adr-<NNN>-<slug>.md` | `adr-042-auth-strategy.md` |
| Changelog | `CHANGELOG.md` | — |
| Skill file | `SKILL.md` | — |

---

## ADR Template

```markdown
# ADR-NNN: <Title>
- **Status:** proposed | accepted | deprecated | superseded
- **Date:** YYYY-MM-DD
- **Context:** Why this decision was needed.
- **Decision:** What was decided.
- **Consequences:** Trade-offs and impact.
```

---

## Docstring Template

```python
def fn(param: type) -> type:
    """
    One-line summary.

    Args:
        param: Description.

    Returns:
        Description.

    Raises:
        ErrorType: When/why.
    """
```

---

## Changelog Format (Keep a Changelog)

```markdown
## [1.2.0] - YYYY-MM-DD
### Added
- Feature X
### Changed
- Behavior Y
### Fixed
- Bug Z
### Deprecated / Removed / Security
```

---

## Mermaid Cheat Sheet

```mermaid
mindmap
  root((Mermaid))
    flowchart
      TD top-down
      LR left-right
    stateDiagram-v2
      states and transitions
    sequenceDiagram
      actor interactions
    classDiagram
      data models
    erDiagram
      DB schemas
    gantt
      timelines
    mindmap
      concept maps
```

---

## Mermaid Quick Syntax

| Diagram | Trigger words |
|---|---|
| `flowchart TD/LR` | process, flow, decision, pipeline |
| `sequenceDiagram` | API call, request/response, actors |
| `classDiagram` | model, object, inheritance, schema |
| `erDiagram` | database, table, relation |
| `stateDiagram-v2` | lifecycle, state machine, status |
| `gantt` | timeline, schedule, milestone |
| `mindmap` | concept map, overview, cheat sheet |

---

## AI Consumption Rules

1. Load this skill when any documentation task is detected.
2. Default to mermaid — only use prose when structure cannot be diagrammed.
3. Always apply the Doc Quality Checklist before finalising output.
4. Use file naming convention for any new files created.
5. Front matter is required on all SKILL.md and reference files.
