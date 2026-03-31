---
name: architecture
description: Guide architectural decision-making for new projects or significant code changes. Use when starting a new project, choosing a design pattern, evaluating architecture for a large refactor, or when the user asks which architecture pattern to use.
---

# Architecture Guidance

Based on research across academic literature, practitioner consensus (Mark Richards, Simon Brown, Gregor Hohpe), and Matt Pocock's codebase improvement methodology. This skill operationalizes those insights into a structured decision process.

**Use this skill when:**
- Starting a greenfield project and choosing an initial architecture
- Planning non-minor changes that affect a larger portion of the codebase
- Evaluating which design pattern fits the current context
- Refactoring toward better structural boundaries

**Do not use this skill when:**
- The change is confined to a single module or function
- Architecture is already decided and the task is implementation

---

## Core Principle

> "Everything in software architecture is a trade-off." — First Law of Software Architecture

A senior architect's job is not to find the one correct pattern — it is to make trade-offs **explicit**, document them, and choose the option that best satisfies the system's **quality attributes**.

---

## Step 1: Establish Quality Attributes

Before choosing any pattern, identify what the system must achieve *beyond* its functional requirements. Ask the user (or infer from context):

| Attribute | Question to ask |
|---|---|
| **Scalability** | Will load grow? Must it scale horizontally? |
| **Maintainability** | How often will it change? How large is the team? |
| **Testability** | Must individual behaviors be verified in isolation? |
| **Observability** | Do we need to infer internal state from outputs? |
| **Security** | Is the attack surface or data sensitivity a concern? |
| **Reliability** | What happens when a dependency fails? |
| **Deployability** | How fast and safely must changes reach production? |

**Output:** A ranked shortlist of the 2–4 quality attributes that matter most *for this system*. Everything else flows from this prioritization.

If the quality attributes are unclear, surface them before proceeding by interviewing me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer. If a question can be answered by exploring the codebase, explore the codebase instead.

---

## Step 2: Identify the Artifact Type

Architecture choices differ fundamentally by what is being built. Classify the artifact:

### Single-Page Application (SPA)

SPAs manage routing, state, caching, domain logic, and real-time updates on the client. Key decisions:

- **Component decomposition:** Use Atomic Design (atoms → molecules → organisms → pages) for reuse and testability.
- **State management:** Prefer `useState`/`useContext`/`useReducer` for most SPAs. Adopt centralized stores (Redux, Zustand) only when shared state is genuinely complex and frequently updated.
- **Feature organization:** For multi-team SPAs, adopt **Feature-Sliced Design (FSD)** — strict layer-dependency rules with public module APIs, enforceable via ESLint.
- **API style:** GraphQL maps naturally to component data needs. Use Backend-for-Frontend (BFF) when SPA and mobile clients have diverging data requirements.
- **Avoid MVC** — its bidirectional data flow becomes unpredictable at scale in the browser.
- Micro-Frontends (Module Federation) only when independent deployment of UI segments is a *proven* team requirement.

### CLI Tool

CLIs are developer-facing, pipe-composable, and embedded in automation. Their API is their flags and subcommands — treat them like a versioned public interface.

- **Unix philosophy first:** Do one thing well. Prefer composable utilities over feature-heavy monoliths.
- **Subcommand pattern:** `tool [noun] [verb]` (e.g., `git branch list`). Use it as functionality grows.
- **Flag discipline:** One argument is fine, two are questionable, three is an anti-pattern.
- **Thin CLI layer:** Separate the CLI parsing layer (presentation) from core logic. If the core has significant business logic, apply Clean or Hexagonal Architecture there and wrap it with a thin CLI adapter.
- **Layered architecture usually suffices** for the CLI layer itself. Do not over-engineer with complex DI frameworks.
- **Backward compatibility is non-negotiable:** Treat flags as a versioned public API.

### Library or SDK

Libraries are the most API-sensitive artifact — the interface *is* the product.

- **Define the abstraction level first.** A utility library (low-level) and a framework (high-level) have different design principles. Mixing levels creates incoherent APIs.
- **Minimize surface area.** Make everything private that can be private. Every public symbol is a commitment.
- **Design from the consumer's perspective.** Write client code before implementing ("code early, code often"). This surfaces usability issues before they are baked in.
- **Progressive disclosure of complexity:** The simplest use case requires minimal API surface; power-user cases are *possible* without polluting the default path.
- **Prefer interfaces over abstract classes** for flexibility and information hiding.
- **Semantic versioning is the contract:** MAJOR for breaking changes, MINOR for backward-compatible additions, PATCH for fixes. Violating this destroys trust.
- Hexagonal/Ports-and-Adapters is valuable internally when the library abstracts external systems (DB driver, HTTP client) — the port is stable, the adapter can be swapped.

### Backend Application / Service

For applications with significant business logic, proceed to Step 3 to select a structural pattern.

---

## Step 3: Select the Structural Pattern

Apply the tier system below. Start with Tier 1 options; move to Tier 2 only when the quality attributes require it; use Tier 3 only when the use case is explicit.

### Tier 1 — Universally Important (know these fluently)

| Pattern | Best fit | Key trade-off |
|---|---|---|
| **Layered (N-Tier)** | Default starting point; maps to most frameworks | Cheap to start; cross-layer changes at scale → Big Ball of Mud |
| **Hexagonal (Ports & Adapters)** | Significant business logic; testability is top priority | Maximally testable core; requires explicit port/adapter discipline |
| **Clean Architecture** | Rich, evolving business rules; long-term flexibility | Strong testability; upfront abstraction overhead |
| **Event-Driven (EDA)** | Loose coupling; async workflows; audit trails | Hard to debug and test; eventual consistency complexity |

**Hexagonal Architecture** is the single most important structural pattern for applications with meaningful business logic. It isolates the domain from all external systems (HTTP, DB, queues) via ports (interfaces) and adapters (implementations).

**Clean Architecture** is the domain-centric extreme: dependencies flow strictly inward through Entities → Use Cases → Interface Adapters → Frameworks. The core never knows about HTTP or databases. Use for products where domain rules are the primary complexity driver.

### Tier 2 — Important in Many Contexts

| Pattern | When it pays off | Why to skip otherwise |
|---|---|---|
| **Modular Monolith** | Medium-sized products; deployment independence not yet needed | Gets 80% of microservices' benefits at 20% of the operational cost |
| **Vertical Slice Architecture (VSA)** | CRUD-heavy APIs; fast-moving teams; feature-aligned delivery | Reduced cross-feature coupling; can coexist with Clean Architecture within slices |
| **CQRS** | High read/write asymmetry; event-sourced systems; analytics | Pure overhead for simple CRUD |
| **Microservices** | Proven need for team autonomy and independent deployability | On a single machine, a monolith outperforms its microservice equivalent; distributed systems cost is substantial |

**Default recommendation for new backend applications:** Start with a **Modular Monolith**. Extract microservices only when deployment independence is a *proven and funded* requirement.

### Tier 3 — Situational / Specialized

Use only when the specific use case demands it:

| Pattern | Use case | Default stance |
|---|---|---|
| **Microkernel (Plugin)** | Products with genuine extension points (IDEs, CMS, build tools) | Overkill without real extensibility needs |
| **Space-Based** | Extreme high-concurrency, low-latency (trading systems) | High infrastructure cost |
| **Serverless** | Event-triggered, sporadically-used workloads | Cold starts, vendor lock-in, difficult local testing |
| **Reactive** | High-throughput streams, IoT sensor ingestion | Paradigm shift; steep learning curve |

### Patterns to Resist Over-Applying

- **Clean Architecture for small projects** — disproportionate for a 5-endpoint service with no complex business rules; use Layered or VSA instead.
- **Microservices by default** — independent of scale, they add distributed systems complexity (network failures, serialization, service discovery, distributed tracing).
- **CQRS everywhere** — valuable only for high read/write asymmetry.
- **Premature barrel files** in JS/TS — creates shallow module illusions, hides real dependency structure, reduces bundle-splitting effectiveness.
- **DI frameworks as a solution to coupling** — heavy DI can create hidden coupling through the container rather than explicit coupling through code.

---

## Step 4: Greenfield vs. Brownfield

### Greenfield (New Application)

Freedom demands discipline. The primary risk is over-engineering.

- [ ] Start with the **simplest architecture that satisfies the current quality attributes**. You can always extract microservices later; you cannot un-complicate a premature one.
- [ ] Use **Modular Monolith** as the default; microservices only when deployment independence is a proven requirement.
- [ ] Write **Architecture Decision Records (ADRs) from day one** to capture why key decisions were made.
- [ ] Run an **EventStorming** or DDD strategic design workshop to identify bounded contexts before writing code.
- [ ] Resist "astronaut architecture" — solving problems that don't exist yet.

### Brownfield (Refactoring Existing Application)

Decisions are constrained by live systems, team knowledge, and existing consumers. The key principle is **incremental, validated change**.

#### Choose the right brownfield strategy:

| Scenario | Strategy |
|---|---|
| Good core logic, poor structure | Module Deepening (Pocock approach) |
| Need to migrate monolith to services | Strangler Fig Pattern |
| New code must interact with legacy models | Anti-Corruption Layer (ACL) |
| Critical security/compliance gap | Greenfield rebuild |
| Sprawling spaghetti, low test coverage | Strangler Fig for key domains; leave stable parts |

**Strangler Fig:** Build new functionality alongside the monolith. A routing layer intercepts requests and gradually redirects to new services. The monolith is strangled incrementally — no big-bang rewrites.

**Anti-Corruption Layer (ACL):** Translate between the old system's model and the new domain model. Prevents legacy design decisions from contaminating modern services — it is a semantic and technical firewall.

**Module Deepening (Pocock Approach):** Converts shallow modules into deep modules by merging tightly-coupled small files into coherent units with thin public interfaces. Safe, incremental, no external behavior change.

A **deep module** has a small interface hiding a large implementation. The opposite — shallow modules where the interface is nearly as complex as the implementation — creates a codebase that is hard to test, hard to navigate, and hard to reason about (Ousterhout, *A Philosophy of Software Design*).

> *"What you really want to avoid are lots of little shallow modules... really hard to navigate and really hard to keep in your head."* — Matt Pocock

Module deepening process:
1. Explore organically — note where understanding one concept requires bouncing between many small files
2. Identify clusters of tightly-coupled modules sharing types, call patterns, or co-ownership of a concept
3. Classify dependencies (in-process, local-substitutable, remote-but-owned, true external)
4. Design a radically simpler public interface for the merged module (use `/design-an-interface` skill)
5. Replace shallow unit tests with boundary tests on the new interface; delete the old tests

---

## Step 5: Document with ADRs and C4

### Architecture Decision Records (ADRs)

For every significant architectural decision, create a short ADR capturing:
- **Context** — what forces are at play?
- **Decision** — what was chosen and why?
- **Options considered** — what alternatives were evaluated?
- **Consequences** — what becomes easier or harder?

ADRs prevent future teams from unknowingly reversing past decisions and create a living audit trail of the system's evolution.

### C4 Model (Communication)

Use Simon Brown's C4 model to communicate architecture at four levels:
1. **System Context** — how the system fits into the broader world
2. **Container** — the major technical building blocks (apps, services, databases)
3. **Component** — the key logical modules within each container
4. **Code** — class-level detail (usually optional)

C4 is notation-independent and tool-independent. Logical components are the building blocks of software architecture — the structural units the architect is responsible for.

---

## Step 6: Validate and Recommend

After working through the steps above, produce a structured recommendation:

```
## Architecture Recommendation

**Artifact type:** [SPA | CLI | Library | Backend]
**Project type:** [Greenfield | Brownfield]

**Quality attributes (ranked):**
1. [Most important]
2. [Second]
3. [Third]

**Recommended pattern:** [Pattern name]
**Why this fits:** [1–3 sentences tied to the quality attributes]
**Key trade-offs accepted:** [What this pattern costs]
**Starting point:** [Concrete first step]

**Patterns explicitly rejected:**
- [Pattern]: [Why it doesn't fit here]

**ADR topics to document immediately:**
- [Decision 1]
- [Decision 2]
```

Then ask: "Does this match your constraints? Are there quality attributes I'm missing?"

---

## Reference: SOLID Principles (Module-Level Design)

Apply these at the component and module level regardless of which architecture is chosen:

- **Single Responsibility** — a module has only one reason to change
- **Open/Closed** — behavior can be extended without modifying existing code
- **Liskov Substitution** — subtypes must be interchangeable with their base types
- **Interface Segregation** — clients should not depend on interfaces they don't use
- **Dependency Inversion** — high-level modules must not depend on low-level ones; both depend on abstractions

## Reference: DDD Tactical Concepts

When the domain is complex, align structure with business reality:

- **Bounded Contexts** — explicit boundaries within which a domain model is defined and applicable
- **Aggregates** — clusters of domain objects treated as a single unit for data changes
- **Domain Events** — immutable facts that something significant happened in the domain
- **Ubiquitous Language** — a shared vocabulary between developers and domain experts

DDD provides the *semantic* layer; Hexagonal/Clean Architecture provides the *structural* enforcement.
