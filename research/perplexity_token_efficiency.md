# Token Efficiency & Quality Optimization Mechanics for AI Coding Agents

## Executive Summary

Token costs in multi-turn AI coding agents are dominated by **input-side accumulation**, not output generation. The data consistently shows that 96–99% of tokens in a typical long-running agentic session come from inputs — accumulated trajectory, tool results, file reads, and tool definitions — while model output constitutes 1–4%. This structural asymmetry is the lens through which every optimization technique must be evaluated. Techniques that only compress output (e.g., brevity constraints) deliver modest real-world savings. Techniques that attack the input side (trajectory reduction, tool-result clearing, compaction, tool-definition deferral) unlock order-of-magnitude improvements. This report synthesizes all major current techniques, quantifies their savings with primary-source evidence, and catalogs the failure modes of each.

***

## Part 1 — Token Efficiency Techniques

### Technique Comparison Table

| Technique | Token Category Targeted | Reported Savings | Performance Impact | Requires LLM Call? | Primary Source |
|---|---|---|---|---|---|
| **AgentDiet Trajectory Reduction** | Input (trajectory) | 39.9–59.7% input; 21.1–35.9% total cost | –1.0% to +2.0% Pass% | Yes (cheaper model) | [1][2] |
| **Anthropic Server-Side Compaction** | Input (whole conversation) | ~50% per compaction event (lossless for high-level facts) | Moderate (loses verbatim specifics) | Yes (internal) | [3][4] |
| **Tool-Result Clearing** | Input (tool results) | Up to 67% per firing event; 84% in 100-turn test | None (re-fetch on demand) | No | [3][5] |
| **Microsoft ToolResultCompactionStrategy** | Input (tool call groups) | Low aggressiveness; collapses to metadata line | High context preservation | No | [6] |
| **Microsoft SummarizationStrategy** | Input (older turns) | Medium aggressiveness | Medium (LLM-dependent quality) | Yes | [6] |
| **Tool Definition Deferral (Tool Search)** | Input (tool schemas) | ~75K tokens/turn for large MCP deployments | +1 turn latency per undiscovered tool | No | [7] |
| **Caveman Skill (output brevity)** | Output only | 12–23% output token reduction (real-world); not 65–75% as claimed | Zero regression at default intensity | No | [8][7] |
| **caveman-compress (CLAUDE.md)** | Cached input (memory files) | 35–60% on CLAUDE.md files | Negligible | No | [8][7] |
| **SkillReducer Skill Compression** | Input (skill definitions) | 48% description, 39% body compression | +2.8% functional quality improvement | Yes | [9][10] |
| **Prompt Caching** | Cached input | 40–80% on stable system prompts | None | No | [11] |
| **LLMLingua-2 Input Compression** | Input | 2–5x compression ratio | ~1–2pp task performance loss | Yes (BERT-scale model) | [12][8] |

***

### 1.1 AgentDiet — Trajectory Reduction

**What it is.** AgentDiet, presented at FSE 2026 (arXiv:2509.23586), is an inference-time trajectory reduction system that inserts a *reflection module* into the standard agent loop to compress past steps before they compound into future inputs.[1][2]

**The three waste categories it identifies.** Through manual analysis of 100 Trae Agent trajectories on SWE-bench Verified, the authors identified three systematic waste types that appear in nearly every trajectory:[12]

1. **Useless information** — content that was never relevant to the task, such as `__pycache__` entries in directory listings, verbose GNU Make output (`make[2]: Entering directory`), and CI/CD log noise. These inflate tool messages even after a 16KB truncation ceiling is applied.
2. **Redundant information** — repeated content, most commonly in `str_replace_editor` calls where the `new_str` parameter partially duplicates the `old_str`, and where both repeat code fragments already visible elsewhere in the trajectory.
3. **Expired information** — context that was locally necessary but is no longer useful. A canonical example: the agent inspects 12 files during a grep-and-navigate loop; once the target file is identified, the other 11 file contents serve no purpose.

**Quantified savings.** Evaluated across two LLMs (Claude 4 Sonnet, Gemini 2.5 Pro) and two benchmarks (SWE-bench Verified, Multi-SWE-bench Flash covering 7 programming languages):[13]

- **Input token reduction**: 39.9%–59.7%
- **Total computational cost reduction** (after accounting for reflection module overhead): 21.1%–35.9%
- Absolute cost example: SWE-bench Verified + Claude 4 Sonnet went from $0.535/instance to $0.422/instance (−$0.113)[12]

**Does it degrade performance?** No — this is the result that challenges conventional assumptions. Pass% varied between **−1.0% and +2.0%** relative to the unmodified baseline. The Gemini 2.5 Pro / Multi-SWE-bench Flash configuration actually *reduced* average steps from 57.2 to 43.9, indicating that compressing expired context prevented the model from getting lost in long trajectories and repeating work.[2][12]

**Algorithm mechanics.** The reflection module uses a *sliding window*: when the agent reaches step `s`, it attempts to compress step `s−a` (default `a=2`) using a cheaper model (`LLMLingua_reflect`), providing only steps `s−a−b` to `s` as context (default `b=1`). Compression is skipped if the target step's length is below threshold `θ=500` tokens. Only reductions greater than `θ` are applied, preventing overhead from marginal cases. The optimal `LLM_reflect` is GPT-5 mini — 12× cheaper than Claude 4 Sonnet — and maintains the same Pass% as the unmodified agent.[12]

**Counter-evidence and limitations.** The approach was tested only on coding agents (Trae Agent). The authors acknowledge it was not evaluated on multi-agent or ensembled systems. The Generalization Across Agents threat is noted: if another agent uses structurally different tool schemas, the reflection prompts may need tuning. LLMLingua-2 (a local BERT-scale compressor) also achieves similar input-token savings (I=0.603 vs. AgentDiet's 0.586 for GPT-5 mini) but at lower cost per token, though with slightly lower Pass% (61% vs. 65%).[13][12]

***

### 1.2 Context Compaction Strategies (Anthropic & Microsoft)

#### Anthropic's Three Primitives

Anthropic's context engineering cookbook organizes compaction into three complementary mechanisms:[3]

**1. Server-Side Compaction (`compact_20260112`)**  
Triggered automatically or manually via `context_management` API parameter with beta header `compact-2026-01-12`. When the token threshold is crossed (minimum 50K, default 150K), the entire prior conversation is replaced with a model-generated `compaction` content block. Custom summarization instructions can completely replace the default prompt via the `instructions` field.[4][3]

What survives compaction: high-level facts, goals, major decisions, named entities that were central to the task. What is lost: appendix-level specifics, exact verbatim wording, obscure table cells, exact numerical values from peripheral computation. In Anthropic's research agent benchmark, 3/3 high-level facts survived a compaction event; 0/3 obscure specifics survived.[3]

Manual compaction can be triggered by setting `pause_after_compaction: true` in the `trigger` block, which pauses the conversation with `stop_reason: "compaction"` so the developer can inspect or augment the summary.[14][4]

**2. Tool-Result Clearing (`clear_tool_uses_20250919`)**  
A *sub-transcript* operation that replaces old `tool_result` blocks with a placeholder (`[cleared to save context]`) while preserving the `tool_use` record. This is the cheapest primitive: no inference cost, just a message-list edit. The `keep` parameter (default 3) determines how many recent tool results are preserved intact. `exclude_tools` lets you exempt specific tools (e.g., the memory tool) from clearing.[3]

In Anthropic's research agent benchmark, clearing reduced a 335K-token baseline peak to 173K — a ~48% peak reduction — with zero correctness loss. The clearing run fired 4 times and freed ~163K tokens per event. A 100-turn web search evaluation reported by Anthropic showed context editing reducing token consumption by **84%** relative to unmanaged accumulation.[5][3]

**3. Memory Tool (`memory_20250818`)**  
Client-side persistent note-taking. The model writes to external storage (`/memories/` files) during a session, and the next session reads those files before beginning work. This solves cross-session knowledge loss that compaction and clearing cannot address. The storage backend is implemented by the developer, providing full control over retention policy.[3]

#### When to Use Each

| Problem | Primary Tool | Why |
|---|---|---|
| Long dialogue / reasoning accumulation | Compaction | Whole-transcript operation; lossily preserves substance |
| Bulky re-fetchable tool results (file reads, APIs) | Tool-result clearing | Zero inference cost; lossless (re-fetch on demand) |
| Knowledge across sessions | Memory tool | External persistence; survives context resets |
| All three at once | Layer in order: clearing → compaction → memory | Each targets non-overlapping budget cells |

#### Microsoft Agent Framework Compaction

Microsoft's Agent Framework (`learn.microsoft.com/agent-framework`) exposes five compaction strategies for in-memory agents:[6]

- **`ToolResultCompactionStrategy`** — Low aggressiveness. Collapses older tool-call groups into short summary lines (e.g., `[Tool results: get_weather: sunny, 18°C]`). Does not touch user or plain assistant messages. No LLM required. Best first-pass strategy.
- **`SummarizationStrategy`** — Medium aggressiveness. Uses a separate (smaller, cheaper) LLM to summarize older conversation spans into a `Summary` group. Requires a `SupportsChatGetResponse` client. Default prompt preserves key facts, decisions, and user preferences.
- **`SlidingWindowStrategy`** — High aggressiveness. Drops oldest non-system groups entirely. No LLM. Best for hard group-count limits.
- **`TruncationStrategy`** — Emergency backstop. Drops oldest groups when still over token budget after other strategies.
- **`TokenBudgetComposedStrategy`** — Composes strategies in sequence with early-stop once budget is satisfied. Canonical pipeline order: `ToolResult → Summarization → SlidingWindow → Truncation`.[6]

**Applicability caveat**: Compaction in the Microsoft framework only applies to **in-memory history agents**. Service-managed agents (Foundry Agents, Responses API with `store: true`, Copilot Studio) do not benefit — the service already handles context. Configuring compaction on such agents has no effect.[6]

#### Failure Modes of Compaction

Real-world bug reports from Claude Code GitHub issues document multiple compaction failure patterns:[15][16][17][18]

1. **Premature context-full error** — Context reported as "full" at 48% usage (78K/200K tokens) because the compaction summarizer model itself has a shorter context window; when the conversation hits the summarizer's limit, compaction fails with "Conversation too long".[15]
2. **Race condition with Auto Memory** — When Auto Memory and Auto Compaction run concurrently, message boundary corruption occurs: earlier session fragments appear in current context, compaction produces truncated output, or the operation deadlocks entirely.[17]
3. **Post-compaction disorientation** — After compaction, agents may lose procedural continuity (where they were in a multi-step task) even when factual content is preserved. The agent "knows what" but has lost "what to do next".[19]
4. **Orphaned tool-use IDs** — Custom (SDK-level) compaction implementations that summarize away a `tool_use` block but retain its corresponding `tool_result` create orphaned references that cause Anthropic API validation errors, crashing the session. Server-side compaction (`compact-2026-01-12`) handles this correctly.[20]

***

### 1.3 Tool Output Trimming — Structural Design Pattern

Separate from framework-level compaction, developers routinely implement *output trimming* as a structural pattern that strips unnecessary fields from tool/API responses **before they enter the context window**. This is architecturally distinct from compaction: it operates at the tool wrapper level, not the conversation history level, and is lossless with respect to the information actually needed.

**OpenAI Agents SDK: `ToolOutputTrimmer`**

The OpenAI Agents SDK ships a built-in `ToolOutputTrimmer` via its `CallModelInputFilter` hook:[21]

```python
from agents import RunConfig
from agents.extensions import ToolOutputTrimmer

config = RunConfig(
    call_model_input_filter=ToolOutputTrimmer(
        recent_turns=2,        # Never trim the last 2 turns
        max_output_chars=500,  # Trim outputs over 500 chars
        preview_chars=200,     # Keep first 200 chars as preview
        trimmable_tools={"search", "execute_code"},
    ),
)
```

This filter surgically replaces large tool outputs from older turns with a concise preview, runs immediately before each model call, and does not mutate the original items — it creates shallow copies. A production deployment at Ottimate (AP automation agent) reported that trimming stale tool outputs **cut per-conversation token usage significantly and reduced response times by 60%** with no drop in response quality.[22]

**Anthropic `clear_tool_uses_20250919` as structural trim**

The Anthropic tool-result clearing API achieves the same effect at the framework level. A practical pattern is to exclude specific tools from clearing while allowing others to be trimmed:

```python
context_edits = [{
    "type": "clear_tool_uses_20250919",
    "trigger": {"type": "input_tokens", "value": 30000},
    "keep": 3,
    "exclude_tools": ["memory", "final_answer"]  # Never trim these
}]
```

**Token savings profile vs. compaction.** Tool-result clearing/trimming has a fundamentally different risk/savings profile compared to compaction:

| Dimension | Tool-Result Clearing/Trimming | Compaction |
|---|---|---|
| Information loss | None (re-fetchable content only) | Yes (verbatim specifics, details) |
| Inference cost | Zero | Yes (LLM call for summary) |
| Scope | Tool results only | Entire conversation |
| Savings per event | Up to 67% (Anthropic benchmark) | Varies; 39% in sample |
| Works without LLM | Yes | No |
| Cross-session | No | No |

The practical recommendation from Anthropic's engineering guidance: *if context bloat is dominated by re-fetchable tool outputs, clearing is the first tool to reach for — it is cheaper and lossless. Use compaction when dialogue and reasoning (not tool results) are the primary cost.*

***

### 1.4 Anti-Patterns in Token Efficiency

**Raw trajectory accumulation.** The baseline anti-pattern: all tool calls and their results are appended to the trajectory and kept forever. Analyzing SWE-bench trajectories, the average session accumulates 1.0M tokens of *accumulated* input per GitHub issue from a 48.4K-token raw trajectory — because each token is repeated on every subsequent turn. In September 2025, 99% of all Claude 4 Sonnet tokens on OpenRouter were input tokens accumulated in trajectories; only 1% were model-generated.[13]

**Unbounded tool result passthrough.** Loading entire file contents (40K+ tokens) into context for every query, and then keeping the full content for the life of the session. Anthropic's research agent baseline showed 96.3% of its 335K-token peak was file-read results from documents the agent had already processed.[3]

**Context bleeding from poor agent handoffs.** In multi-agent systems, passing the full upstream agent's context to a downstream agent rather than synthesizing a clean handoff summary causes the downstream context to accumulate inherited history it never needed. Anthropic's context engineering blog explicitly recommends isolation patterns where "detailed search context remains within sub-agents while the lead agent synthesizes results".[23]

**Over-compaction (99.3% compression failure).** JetBrains NeurIPS 2025 workshop findings showed that one provider achieved 99.3% compression but scored *lower* on quality metrics; the lost details required costly re-fetching that exceeded the token savings from compression. The study found that simple *observation masking* (never adding certain raw outputs to context) halved costs relative to no management, equaling or slightly exceeding LLM-based summarization in task completion rate.[5]

**Flat skill libraries at scale.** Deploying 80+ skills in a flat directory causes routing collapse: semantically similar skills become indistinguishable, the agent consistently invokes the wrong one, and behavior becomes non-deterministic for identical inputs. SkillReducer research confirms that 4+ concurrent skills drop improvement from ~18pp to ~5.9pp due to cognitive load — a classic diminishing-returns curve.[24][25]

***

## Part 2 — Output Quality Boosters

### 2.1 Brevity Constraints — The Benchmark Data

The question "does constraining output verbosity improve or degrade reasoning accuracy?" now has a definitive empirical answer from a March 2026 arXiv paper (arXiv:2604.00025):[26]

**Key findings** across 31 models (0.5B–405B parameters) evaluated on 1,485 problems across 5 datasets:

- On **7.7% of benchmark problems**, large models *underperform* smaller models by **28.4 percentage points** — an apparent inverse scaling phenomenon
- The mechanism is **spontaneous scale-dependent verbosity**: large models overelaborate, introducing errors through redundant reasoning steps
- Adding brevity constraints ("answer in under 50 words") to large models **improves accuracy by 26 percentage points**
- On GSM8K (mathematical reasoning), brevity constraints **reverse the performance hierarchy entirely**: large models go from *losing* to small models by 13.1pp to *winning* by 7.7pp
- On MMLU-STEM (scientific knowledge), the reversal is from −27.3pp to +15.9pp
- Performance gaps closed by **two-thirds** on average, with complete reversals on math/science benchmarks

An earlier ACL 2025 paper (arXiv:2506.08686) benchmarking 12 LLMs found that prompt-engineering strategies targeting length reduction can achieve **25–60% energy savings** by reducing response length while preserving response quality.[27]

**Critical nuance.** The brevity improvement is **not universal**. It is strongest on:
- Mathematical reasoning (overelaboration introduces arithmetic errors)
- Scientific knowledge recall (verbosity adds plausible-sounding but wrong elaborations)
- Tasks where a short correct answer exists

It may *hurt* on:
- Complex multi-step explanations where intermediate steps are needed by the user
- Tasks where the model needs to reason through ambiguity (chain-of-thought scenarios)
- User-facing explanations of *why* a decision was made

The caveman benchmark in the GitHub repo independently cites this paper in its README as supporting evidence that brevity constraints can improve accuracy.[7]

***

### 2.2 Context Clarity Techniques

**Explicit role and task separation.** Anthropic's context engineering guidance describes the core discipline as "finding the smallest set of high-signal tokens that maximize the likelihood of your desired outcome". Structural patterns that reliably improve quality:[3]

- **Clean system prompt / memory file separation**: Instructions in `CLAUDE.md` or system prompt; volatile project state in memory tool files. Mixing instructions with volatile state causes instruction drift as memory updates overwrite stable rules.
- **Sub-agent context isolation**: The sub-agent pattern where search/retrieval work is isolated in sub-agents, with only synthesized results passing to the orchestrator, showed "substantial improvement over single-agent systems on complex research tasks" per Anthropic's engineering blog.[23]
- **Git-Context Controller (GCC)**: A structured context management framework (arXiv:2508.00031) that treats agent memory as a versioned file system with COMMIT, BRANCH, MERGE, and CONTEXT operations. GCC-augmented agents achieved 48% task resolution on SWE-Bench-Lite vs. the baseline, and 40.7% vs. 11.7% on a self-replication benchmark.[28]

**Tool definition hygiene.** SkillReducer (arXiv:2603.29919) demonstrates that skill descriptions optimized for *routing* (minimal but sufficient to distinguish from competitors) rather than *comprehensive documentation* achieve 48% description compression and 39% body compression while improving functional quality by 2.8% — the "less-is-more" effect: removing non-essential content reduces distraction in the context window.[9][10]

**Programmatic Tool Calling (PTC).** Anthropic's November 2025 advancement: instead of Claude requesting tools one at a time with each result landing in context, Claude writes Python code that calls multiple tools, processes their outputs, and controls what information enters the context window. The code itself can filter, aggregate, and summarize tool outputs before they are committed to context — a structural mechanism equivalent to tool-result trimming, but implemented at the agent's reasoning level.[29]

***

### 2.3 Anti-Patterns in Quality Degradation

**Context bleeding across agent boundaries.** In multi-agent pipelines, when Agent A's full working context (including file reads, error logs, and search results) is passed wholesale to Agent B, Agent B receives a context with its own implicit assumptions, stale intermediate states, and contradictory partial conclusions. Kubiya's context engineering guide identifies "context clash" — contradictory information within the context — as a primary failure mode, generating "inconsistent or erroneous outputs".[16]

**Skill overload (too many concurrent skills).** SkillsBench empirical data: using 4 or more concurrent skills dropped agent performance improvement from ~18pp (2–3 skills) to ~5.9pp. In 16 tasks, skills actually *decreased* performance — in tasks where the model was already strong, the added skill instructions introduced noise and complexity. Flat skill libraries with 80+ entries cause routing collapse; a hierarchical organization is required for scaling.[25][24]

**Instruction drift in long agentic runs.** The January 2026 paper "Agent Drift: Quantifying Behavioral Degradation in Multi-Agent LLM Systems" (arXiv:2601.04170) formalizes three drift manifestations in long agent runs:[30]
- **Semantic drift**: Progressive deviation from original intent as distant instructions lose salience
- **Coordination drift**: Breakdown in multi-agent consensus as shared context fragments diverge
- **Behavioral drift**: Emergence of unintended strategies (e.g., cost-minimizing shortcuts not sanctioned by instructions)

The paper introduces the Agent Stability Index (ASI) and three mitigation strategies: episodic memory consolidation, drift-aware routing protocols, and adaptive behavioral anchoring. A separate study found 91% of ML systems experience performance degradation without proactive drift intervention.[31][30]

**Summarization feedback loops ("context collapse").** Repeated summarization through multiple compaction events gradually erodes specificity — each generation of summary is a compressed version of the prior, so specific variable names, architectural constraints, and nuanced edge cases are progressively lost. Stanford's ACE framework addresses this with *incremental delta updates* to structured bullet-list contexts rather than full rewrites.[32]

***

## Part 3 — Caveman Skill Deep Analysis

### 3.1 Mechanical Operation

Caveman (github.com/JuliusBrussee/caveman) is a **Claude Code skill** that modifies model output verbosity via a system-prompt overlay and session-scoped hooks. It is not a tokenizer, model modification, or postprocessor — the entire mechanism is a prompt that sets style rules, enforced by the model itself.[33][7]

**Installation mechanism**:
```bash
npx skills add JuliusBrussee/caveman
```

This installs three components:[7]
1. **`SKILL.md`** — the prompt containing rules, an intensity level table, and a before/after example pair
2. **`caveman-activate.js`** (SessionStart hook) — writes `~/.claude/.caveman-active = "full"` and prints the ruleset reminder to stdout, which becomes part of the session context before the first user turn
3. **`caveman-mode-tracker.js`** (UserPromptSubmit hook) — reads user input, parses `/caveman` slash commands and level arguments, rewrites the flag file

**What it tells the model to do**:
- Drop articles (`a`/`an`/`the`), filler words (`just`/`really`/`basically`), pleasantries (`sure`/`certainly`/`of course`), and hedging
- Use fragments where full sentences were used
- Use short synonyms (`fix` not "implement a solution for", `big` not "extensive")
- Follow pattern: `[thing] [action] [reason]. [next step].`
- Keep code blocks, technical terms, and error messages verbatim and unchanged

The six intensity levels (lite → full → ultra → wenyan-lite → wenyan-full → wenyan-ultra) extend from "professional but tight" to Classical Chinese, which achieves ~9 tokens for answers that take 41 tokens in English.[7]

***

### 3.2 The 75% Claim vs. The 1% Reality

This is the central discrepancy in the caveman discourse, and it is a denominator problem.

**The caveman repo benchmark** measures output-token compression across 10 tasks, reporting an average of 65% (range: 22%–87%). This is the correct denominator — *output tokens* — and the measurement methodology is sound.[7]

**The 75% headline** is the upper bound of the repo's benchmark range, describing verbose explanation tasks. The repo itself labels it as output-token savings.[33]

**The real-world budget breakdown** (from a typical active Claude Code coding session with MCP tools):[7]

```
SYSTEM PROMPT          ~3,000 tokens (1.5%)
TOOL DEFINITIONS      ~25,000 tokens (12.5%)
PROJECT MEMORY (CLAUDE.md) ~2,000 tokens (1%)
CONVERSATION HISTORY  ~80,000 tokens (40%)
TOOL OUTPUTS (file reads) ~50,000 tokens (25%)
MODEL OUTPUT (this turn) ~5,000 tokens (2.5%)
HEADROOM             ~35,000 tokens (17.5%)
```

Model output — the only budget cell caveman compresses — is **~2.5% of the session**. Applying a 20–30% real-world compression (not the 65% benchmark figure, which uses a chatty baseline) to a 2.5% cell yields **~0.5–0.75% total session savings**.[8][7]

**Independent real-world measurements**:
- Kuba Guzik (72 prompts, 3-arm test — vanilla vs. "be concise" vs. caveman): caveman beat vanilla by **23%** in output tokens; beat the simple "be concise" instruction by only **4%**[8]
- Marco Pillitteri (30 coding tasks): **12%** output reduction[8]
- MayhemCode (full Next.js session): 11,200 → 8,900 output tokens = **~20%** reduction[8]
- The author acknowledged on Hacker News that "real-world savings land closer to 20–30%"[8]
- One Reddit user on r/ClaudeAI reported 0.6% of total spend was visible assistant output; everything else was input[8]
- The r/vibecoding April 2026 thread reported a $100/month user saving "roughly $1, maybe $1.50"[34][8]

A YouTube benchmark found that on a 10-prompt test, caveman achieved 45% output-token reduction vs. baseline but **added overhead from the skill injection** (the SKILL.md itself is loaded as input every session), making caveman **10% more expensive** than the no-skill baseline when total input + output was measured.[35]

**Where the claimed 65–75% can be reproduced**: Only against a baseline with no brevity instruction at all, on verbose explanation tasks. In any workflow already using a reasonably concise prompt style, the marginal benefit of caveman over a simple "be concise" addition is ~4%.[8]

***

### 3.3 Invocation Timing — The Core Risk

The skill is designed for **persistent activation** across all turns: its `SKILL.md` specifies "ACTIVE EVERY RESPONSE. No revert after many turns. No filler drift. Still active if unsure."[33]

**The failure mode.** If caveman is active during a `final_answer` generation or user-facing explanation of a critical decision, the model may produce:[36]
- Security warnings in fragments, potentially omitting severity context
- Multi-step destructive operations (e.g., `DROP TABLE users`) confirmed in a single terse line without adequate user understanding
- Debugging explanations missing the logical chain that the user needed to understand *why* the fix works

The skill includes a **soft auto-clarity guardrail**: it instructs the model to "drop caveman, write normally, then resume" for security warnings, irreversible action confirmations, multi-step sequences where reading order matters, and when the user is confused. The example in the skill file:[7]

```
> Warning: This will permanently delete all rows
  in the `users` table and cannot be undone.
> ```sql
> DROP TABLE users;
> ```
> Caveman resume. Verify backup exist first.
```

**The weakness of this guardrail** is that it relies entirely on the model's judgment of when "irreversible" or "confused" applies. There is no hard code toggle, no runtime check, and no fallback outside the model's inference.

**Documented implementations of conditional toggling**:

The canonical production pattern for preventing caveman activation during final output:[36][7]
- Add a named phase to the agent protocol: internal reasoning phases use caveman; a `final_answer` tool call or `user_explanation_phase` tag triggers deactivation
- Use the hook system: the `UserPromptSubmit` hook can detect when the incoming message is a `final_answer` invocation and issue `stop caveman` before execution
- Anthropic's `PostToolUse` hook can detect tool names (e.g., `final_answer`) and inject a mode-reset message into the context

No production-grade open-source implementations of this conditional toggle were publicly documented at the time of writing. The caveman repo itself does not implement conditional deactivation for tool-call boundaries — only for user-recognized phrases ("stop caveman", "normal mode") and the model's own auto-clarity heuristics.[33]

***

### 3.4 Community Sentiment

**r/ClaudeAI (April 3, 2026 thread, 400+ comments)**: The post initially generated enthusiasm ("75% less tokens"), but analytical participants rapidly surfaced the denominator problem. Recurring themes:[37]
- "Output tokens are a rounding error on a real session bill"
- "Input context including the entire conversation history is what actually costs money"
- "Might make the model dumber — asking it to inhabit a less intelligent persona could hurt reasoning"

**r/vibecoding (April 2026)**: Community experimentation found the technique useful for reducing explanatory verbosity but confirmed the financial savings were negligible for typical subscription-plan users.[34]

**Hacker News (April 4, 2026)**: The author participated in discussion and explicitly acknowledged: "The skill targets visible completion only — thinking/reasoning tokens are completely untouched. Real savings are closer to 20–30% on output." The HN thread consensus was that the technique is useful as a *communication style preference* but oversold as a *cost reduction tool*.[36]

**What genuinely works per developer consensus**:[38][7][8]
- `caveman-compress` on `CLAUDE.md` — operates on the cached-input category (memory files), not output tokens; 35–60% reduction on CLAUDE.md that compounds across every session turn
- Prompt caching configuration — 40–80% savings on input once correctly configured
- Tool-return discipline — line-range file reads (`read_file` with offset/limit), avoiding repeated grep on the same paths
- Local dependency graphs (VSCode extension example): sending a 2.4K-token structural subgraph instead of 18K of raw files — **65% token reduction** with better context[38]

***

## Part 4 — Actionable Implementation Rules

The following rules are derived from the quantitative evidence in this report, ordered by expected ROI (input-side leverage first).

### Tier 1 — Input-Side (Highest Leverage)

**Rule I-1: Diagnose before compressing.** Before implementing any optimization, audit one real session's token breakdown by category (system prompt, tool definitions, CLAUDE.md, conversation history, tool results, model output). Compress the largest category first.

**Rule I-2: Configure tool-result clearing before compaction.** Tool-result clearing is zero inference cost and lossless for re-fetchable content. Set trigger at 50–100K tokens, keep 3–6 recent tool results, exclude critical tools (memory, final_answer). Expected savings: up to 67% per compaction event with no quality cost.[3]

**Rule I-3: Use server-side compaction for dialogue/reasoning accumulation.** Configure `compact-2026-01-12` with a custom `instructions` prompt that explicitly names the high-value content (code snippets, variable names, technical decisions, intermediate state). Do not rely on the default prompt for domain-specific agents.[4][3]

**Rule I-4: Implement a 4-level compaction pipeline (Microsoft pattern).** Order: `ToolResult → Summarization → SlidingWindow → Truncation`. Each layer activates only when the previous was insufficient.[6]

**Rule I-5: Implement tool definition deferral for large MCP deployments.** Sessions with 50+ MCP tools and workflows that touch fewer than 30% of them benefit from schema deferral. The Claude Code tool search mechanism saves ~75K tokens/turn in large deployments.[7]

**Rule I-6: Compress CLAUDE.md / memory files with caveman-compress or LLMLingua-2.** Memory files are loaded on every turn as cached input — the highest-leverage target. 35–60% compression on a 4,000-token CLAUDE.md compounds across every turn for the life of the project.[8]

**Rule I-7: Instrument AgentDiet-style reflection for long coding agents.** For agents running 30+ steps on code tasks, insert a reflection module with LLMLingua_reflect = GPT-5 mini, θ=500, a=2, b=1. Expected total cost reduction: 21–36% with no Pass% degradation.[12]

### Tier 2 — Output-Side (Secondary Leverage)

**Rule O-1: Apply brevity constraints to large models on math and science tasks.** Brevity constraints ("answer in under 50 words") improve accuracy by up to 26pp on mathematical reasoning and reverse performance hierarchies on MMLU-STEM. This is not a cost optimization — it is a quality improvement.[39][26]

**Rule O-2: Use caveman as a communication style tool, not a cost tool.** Install if you prefer terse responses. Accept ~0.5–3% bill reduction as the expected financial outcome, not 65–75%.[8]

**Rule O-3: Deactivate caveman before final_answer and irreversible operations.** Wire a `UserPromptSubmit` or `PostToolUse` hook that detects final-answer invocations and issues `stop caveman`. Do not rely solely on the model's auto-clarity heuristic for high-stakes outputs.[36][7]

**Rule O-4: Never apply caveman ultra or aggressive forks to user-facing safety warnings.** Three independent tests show zero correctness regression at default (full) intensity; ultra and aggressive forks show occasional instruction-following failures on complex tasks.[8]

### Tier 3 — Quality Architecture

**Rule Q-1: Limit concurrent skill libraries to 2–3 active skills.** Diminishing returns kick in at 4+ skills (from ~18pp to ~5.9pp improvement). Use hierarchical organization for larger skill libraries.[24][25]

**Rule Q-2: Isolate sub-agent contexts — never pass raw upstream context to downstream agents.** Pass only synthesized summaries or structured handoff objects. This prevents context bleeding, state contradiction, and coordination drift.[16][23]

**Rule Q-3: Implement drift monitoring in production.** Track response consistency, tool usage patterns, and reasoning pathway stability across turns. Use episodic memory consolidation (periodic CLAUDE.md rewrites with current agent state) and drift-aware routing to detect behavioral anomalies.[30][31]

**Rule Q-4: Do not optimize for compression ratio alone — optimize for tokens-per-task.** The JetBrains finding (99.3% compression → lower quality scores) and the AgentDiet insight (removing expired context can *improve* performance) both confirm that the objective is not minimum tokens, but minimum tokens while maintaining task completion rate.[5][12]

***

## Appendix — Source Reference Map

| Technique | Primary Paper / Source |
|---|---|
| AgentDiet | arXiv:2509.23586 (FSE 2026)[1] |
| Brevity Constraints accuracy benchmark | arXiv:2604.00025 (March 2026)[26] |
| Brevity Constraints energy benchmark | arXiv:2506.08686 (ACL 2025)[27] |
| SkillReducer | arXiv:2603.29919 (March 2026)[10] |
| Agent Drift | arXiv:2601.04170 (January 2026)[30] |
| Anthropic Compaction API | platform.claude.com/docs (compact-2026-01-12)[4] |
| Anthropic Context Engineering Cookbook | platform.claude.com/cookbook[3] |
| Anthropic Compaction + Clearing + Memory | platform.claude.com/cookbook/context-engineering[3] |
| Microsoft Agent Framework Compaction | learn.microsoft.com/agent-framework/compaction[6] |
| OpenAI ToolOutputTrimmer | openai.github.io/agents-python/extensions[21] |
| Caveman Skill | github.com/JuliusBrussee/caveman[33] |
| Caveman Real-World Analysis | implicator.ai (April 2026)[8] |
| Caveman + Tool Search Budget Analysis | Substack: Two Ends of the Token Budget (April 2026)[7] |
| Token Budget Session Breakdown | [7] |
| GCC (Git Context Controller) | arXiv:2508.00031[28] |