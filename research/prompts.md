# Deep Research Prompt 1/4: Multi-Agent Orchestration & Workflow Fundamentals

## Objective
Analyze the foundational architectures of state-of-the-art multi-agent workflows.
Focus purely on how agents and sub-agents are orchestrated in software engineering
and coding environments — not marketing, writing, or general AI assistants.

## Scope & Constraints
- Prioritize sources from 2025 and 2026 only.
- Sources: developer discussions (r/ClaudeCode, r/opencodeCLI, Hacker News),
  technical blogs (Anthropic Engineering), and academic papers on multi-agent
  architectures.
- Exclude generic AI definitions. Focus strictly on engineering patterns.
- Actively seek out failure modes, edge cases, and known limitations of each
  pattern — do not just document what works.

## Key Research Areas

### 1. Architectural Patterns
What specific patterns define a robust, production-ready workflow for coordinating
agents and sub-agents?
- Analyze at minimum: ReAct, Plan-and-Execute, and Supervisor/Orchestrator models.
- For each pattern: describe the execution loop, how planning is separated from
  execution, and what happens when a sub-agent fails or goes off-course.
- Reference production coding agents such as Claude Code, SWE-agent, OpenHands,
  or Devin as real-world case studies where these patterns are operationalized.

### 2. Context & State Management
How do successful systems handle "context bleeding" — the degradation of agent
specialization as shared context grows — and maintain clean state during handoffs?
- How is state passed between orchestrator and sub-agents (shared memory, message
  passing, file-based handoff)?
- What strategies prevent a sub-agent from inheriting planning noise or irrelevant
  history from the orchestrator's context?
- What does broken state management look like in practice? Find real examples of
  agents that failed due to state contamination.

## Output Format
Deliver a structured Markdown report with:
1. A section per orchestration pattern (name, execution loop, failure modes)
2. A section on state management strategies with concrete implementation examples
3. A short "Anti-Patterns" section: the top 3 mistakes developers make in
   orchestration design, with real-world evidence

# Deep Research Prompt 2/4: Agent Skill Design & Execution Mechanics

## Context from Prompt 1
[PASTE 3–5 bullet summary of key findings from Prompt 1 here before submitting]

## Objective
Building on the orchestration patterns identified above, conduct a deep technical
analysis of individual "Agent Skills." Focus on the mechanical design of skills
and how they are structured to interact with orchestrators in software engineering
workflows.

## Scope & Constraints
- Prioritize sources from 2025 and 2026 only.
- Perform direct source code analysis of GitHub repositories:
  - Primary: gsd-build/get-shit-done and obra/superpowers
  - Fallback: If skill subdirectories are not directly accessible, use GitHub
    search queries of the form `repo:gsd-build/get-shit-done path:skills` or
    `repo:obra/superpowers path:.claude` to identify specific file paths, then
    fetch those raw file URLs directly at
    raw.githubusercontent.com/{owner}/{repo}/main/{path}.
- Search for benchmarks evaluating curated versus self-generated skills
  (e.g., SkillsBench, ScienceAgentBench, or equivalent 2025/2026 papers).
- Actively seek out failure modes, brittle designs, and known limitations.

## Key Research Areas

### 1. Skill Anatomy (Source Code–Grounded)
Based on direct inspection of skill files in the repositories above:
- What does a single skill consist of? (System prompt? Tool list? Context
  injection? Behavioral constraints?)
- What design principles appear across top-performing skills?
  Analyze specifically: portability, deterministic boundaries, and the
  separation of task logic from system prompts.
- What does a poorly designed skill look like? Find examples of skills that
  cause agent confusion, scope leakage, or context pollution.

### 2. Tool Output Trimming
As a skill design principle, how do developers trim or filter tool/API output
before passing it to the LLM to minimize context bloat?
- What fields are typically stripped from raw tool results?
- Is this filtering done at the skill level, the orchestrator level, or both?
- Find concrete code examples of output trimming in the wild.

### 3. Curated vs. Dynamic Skills
Contrast carefully engineered/curated skills against self-generated/dynamic
skills:
- What do benchmarks (e.g., SkillsBench or equivalent) say about performance
  differences?
- Where do dynamic/self-generated skills break down?
- What is the cost of skill proliferation (too many skills loaded simultaneously)?

## Output Format
Deliver a structured Markdown report with:
1. Skill anatomy breakdown grounded in actual source code from the repositories
2. A section on tool output trimming with code-level examples
3. Curated vs. dynamic skill comparison with benchmark data
4. A "Skill Design Principles" synthesis: the 5 properties of a technically
   robust agent skill, based on the evidence gathered


# Deep Research Prompt 3/4: Framework Comparison & Critical Evaluation

## Context from Prompts 1 & 2
[PASTE 3–5 bullet summary of key findings from Prompts 1 and 2 here before submitting]

## Objective
Using the insights gathered on workflows and skills, critically evaluate and
compare the GSD (Get Shit Done) framework against the Superpowers framework and
other modern alternatives. The goal is not to summarize documentation — it is to
identify where these systems succeed, where they fail, and why.

## Scope & Constraints
- Prioritize sources from 2025 and 2026 only.
- Perform deep source code analysis of gsd-build/get-shit-done and obra/superpowers.
  Use the raw GitHub fetch method if nested directories are not directly accessible:
  raw.githubusercontent.com/{owner}/{repo}/main/{path}
- Cross-reference code findings with external developer sentiment:
  r/ClaudeCode, GitHub Issues, Hacker News (search "superpowers Claude Code" and
  "GSD Claude Code"), and YouTube developer walkthroughs.
- Trust your reasoning: actively seek out contradictions between what creators
  claim and what developers report. Do not just summarize what works.
- For gstack and Speckit: if insufficient information exists, substitute the
  most-discussed alternative frameworks found during research (e.g., SuperClaude,
  ClaudeTools, or frameworks with active GitHub Issues and community traction).

## Key Research Areas

### 1. Comparative Architecture Analysis
Compare GSD and Superpowers across their fundamental design philosophy:
- GSD: meta-prompting + spec-driven development + fresh 200K-token sub-agent
  contexts. How does the planning/execution split actually work in practice?
- Superpowers: agentic skills with auto-triggered workflows + TDD enforcement.
  How do skills activate automatically, and what happens when they misfire?
- Where do their architectural assumptions conflict? (e.g., GSD's fresh context
  model vs. Superpowers' persistent skill injection)

### 2. Critical Evaluation — Where Do They Break?
This is the most important section. Find concrete evidence of:
- Failure modes reported by real developers (GitHub Issues, Reddit, HN comments)
- Features described as "working" in documentation but reported as brittle in
  practice
- Token cost profile: how much overhead does each framework add per task?
- Any hidden biases in how creators benchmark or describe their own tools

### 3. Layer Integration
How do developers successfully combine elements of different frameworks?
- Examples of GSD + Superpowers used together, or GSD/Superpowers + caveman?
- What breaks when you layer frameworks, and what are the documented fixes?

## Output Format
Deliver a structured Markdown report including:
1. A detailed comparison table with these exact columns:
   | Framework | Architecture Style | Token Efficiency | Context Management |
   Execution Loop | Known Failure Points |
   — covering GSD, Superpowers, and at least one other framework
2. A "Creator Claims vs. Developer Reality" section with specific contradictions
3. A "Layer Integration" section with concrete combination patterns
4. Synthesized "Golden Rules" for framework selection based on the evidence

# Deep Research Prompt 4/4: Token Efficiency & Quality Optimization Mechanics

## Context from Prompts 1–3
[PASTE 3–5 bullet summary of key findings from Prompts 1–3 here before submitting]

## Objective
Gather and critically evaluate all major techniques designed to radically optimize
token efficiency and improve output quality in AI coding agents. Synthesize them
into actionable implementation rules.

## Scope & Constraints
- Prioritize sources from 2025 and 2026 only.
- Investigate peer-reviewed papers, production API documentation, and developer
  community reports.
- Actively seek contradictions: if a technique claims X% savings, find the
  counter-evidence. Resolve discrepancies quantitatively where possible.
- Key sources to anchor research:
  - ArXiv: "Reducing Cost of LLM Agents with Trajectory Reduction" (AgentDiet,
    Sept 2025)
  - Anthropic Claude Cookbook: compaction_control, ToolResultCompactionStrategy,
    SummarizationStrategy
  - Microsoft Agent Framework: Compaction documentation (learn.microsoft.com)
  - GitHub: JuliusBrussee/caveman
  - Reddit: r/vibecoding thread criticizing caveman's real-world impact
    (April 2026)

## Key Research Areas

### 1. Radical Token Efficiency Techniques
Investigate each technique below, quantify its reported savings, and find
counter-evidence or limitations:

- **Trajectory Reduction (AgentDiet)**: What specific "waste categories" does
  AgentDiet identify in agent trajectories? What are its reported input token
  savings (39.9–59.7%)? Does it degrade task performance, and at what threshold?

- **Context Compaction Strategies**: Compare ToolResultCompactionStrategy vs.
  SummarizationStrategy vs. Anthropic's automatic compaction:
  - When should each be used?
  - What is the failure mode of compaction (information loss, hallucination of
    prior context)?
  - How is mid-conversation compaction triggered, and can it be forced manually?

- **Tool Output Trimming**: As a structural design pattern (separate from
  compaction), how do developers strip unnecessary fields from raw tool/API
  results before they enter the context window? Find concrete code examples.
  What is the token savings profile vs. compaction strategies?

- **Anti-patterns (what NOT to do)**: What practices represent the exact opposite
  of token efficiency? Document: raw trajectory accumulation, unbounded tool
  result passthrough, and context bleeding from poor agent handoffs.

### 2. Output Quality Boosters
Investigate techniques that improve logical accuracy and output quality:

- **Brevity constraints**: Does constraining output verbosity (e.g., via caveman)
  measurably improve model reasoning accuracy, or does it degrade it? Find
  benchmark data, not just anecdotal claims.

- **Context clarity techniques**: What structural patterns (e.g., explicit role
  separation, clean task boundaries, tool result filtering) improve model output
  quality independent of token count?

- **Anti-patterns**: What causes quality degradation? Document: context bleeding
  across agent boundaries, skill overload (too many concurrent skills), and
  instruction drift in long agentic runs.

### 3. The Caveman Skill — Deep Analysis
Perform a detailed technical and community analysis of JuliusBrussee/caveman:

- **What it does mechanically**: How does caveman suppress verbosity at the
  model level? Does it modify the system prompt, inject tokens, or operate as
  a tool constraint?

- **The 75% claim vs. the 1% reality**: A Reddit thread (r/vibecoding, April
  2026) argues that caveman saves ~1% of total agent costs in practice vs. the
  75% output reduction claimed. Investigate this discrepancy. Which framing is
  correct (output tokens vs. total session cost)?

- **Invocation timing — the core risk**: How do developers ensure caveman is
  active during internal tool-call reasoning steps but deactivated before
  final_answer generation or user-facing explanation? Find documented
  implementations of conditional skill toggling. What breaks if caveman is left
  on during user-facing output?

- **Community sentiment**: What do developers in r/ClaudeCode and related
  communities report as the real-world outcome after extended caveman use?

## Output Format
Deliver a structured Markdown report with:
1. A **Token Efficiency** section: table of techniques with columns
   | Technique 
