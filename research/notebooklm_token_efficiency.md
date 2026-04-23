Optimization Strategies for Token Efficiency and Logical Accuracy in Generative Agentic Architectures

The advancement of generative artificial intelligence in 2025 and 2026 has transitioned from simple chat-based interactions to complex, autonomous coding agents capable of executing multi-step tasks across large codebases. This progression, however, has encountered a critical structural bottleneck: the \"contextual wall.\" As agents operate in loops---reasoning, calling tools, and processing outputs---their conversation trajectories grow quadratically, leading to exorbitant costs, increased latency, and a measurable decline in reasoning precision. The research community has responded with radical techniques designed to prune these trajectories and enforce brevity, revealing that the relationship between context volume and agent performance is often inverse. The emergence of specialized strategies such as trajectory reduction, contextual compaction, and stylized brevity protocols like the \"caveman\" mode represents a shift from \"brute-force\" context window expansion toward a disciplined methodology of context engineering.

Radical Token Efficiency Techniques in Agentic Workflows

The fundamental challenge in agentic efficiency is the O(T2) growth of cumulative costs in multi-turn sessions, where T represents the number of turns.\[1\] In a standard agentic loop, the entire conversation history, including every tool call and its corresponding result, is resubmitted to the model at each turn.\[2\] This leads to a scenario where, by the end of a session, input tokens accumulated in the trajectory can account for over 99% of total token usage, while the generated output constitutes only 1%.\[2, 3\] Addressing this imbalance requires identifying and removing informational \"waste\" through automated pruning and structural refinement.

Trajectory Reduction and the AgentDiet Framework

The AgentDiet framework, introduced in late 2025, formalizes the process of trajectory reduction by identifying specific categories of informational waste that can be removed without degrading task performance.\[2, 3\] By analyzing existing agent trajectories, researchers determined that a significant portion of the context consists of useless, redundant, or expired data that distracts the model and inflates costs.\[3\]

+---------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------+---------------------------------------------------------------------------------------------------------------------+
| Waste Category            | Description and Origin                                                                                                                                                | Technical Mitigation                                                                                                |
+===========================+=======================================================================================================================================================================+=====================================================================================================================+
| **Useless Information**   | Data irrelevant to the core task from its inception, such as file lists containing `__pycache__` or verbose build logs.\[3\]                                          | Syntactic filtering and regex-based exclusion of known noise directories and non-informative shell outputs.\[1, 3\] |
+---------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------+---------------------------------------------------------------------------------------------------------------------+
| **Redundant Information** | Repeated data strings, often seen in the JSON arguments of tools like `str_replace_editor` where the replacement string appears in both the call and the result.\[3\] | Cross-referencing tool arguments with responses; collapsing identical string fragments into single references.\[3\] |
+---------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------+---------------------------------------------------------------------------------------------------------------------+
| **Expired Information**   | Data necessary for a specific local reasoning step (e.g., diagnostic grep searches) that becomes obsolete once the faulty file is identified.\[3\]                    | LLM-based reflection modules that identify completed sub-goals and discard preparatory exploratory data.\[3\]       |
+---------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------+---------------------------------------------------------------------------------------------------------------------+

The application of AgentDiet to high-performing coding agents has yielded substantial improvements in efficiency. Evaluation on benchmarks like SWE-bench Verified indicates that this technique can reduce input tokens by 39.9% to 59.7% while maintaining identical agent performance.\[3, 4\] Furthermore, the total computational cost is reduced by 21.1% to 35.9%, demonstrating that inference-time trajectory reduction is a viable path for production-grade agents.\[2, 3\] Importantly, performance does not degrade even with frequent reduction, as the core technical substance remains intact while only the linguistic and structural \"fluff\" is removed.\[3, 5\]

Context Compaction Strategies and Model Comparison

While trajectory reduction focuses on the content of the history, context compaction provides the architectural framework for managing conversation growth when token counts exceed safety thresholds.\[6\] Modern frameworks provide several distinct compaction strategies, each with a different profile of aggressiveness and context preservation.

The Microsoft Agent Framework, as of 2026, utilizes an experimental compaction pipeline that operates on a \"MessageIndex,\" grouping messages into atomic units called \"MessageGroups\" to prevent logical breaks in tool-call sequences.\[6\] The `ToolResultCompactionStrategy` is a low-aggressiveness method that collapses older tool-call groups into compact summary strings, such as \`\`.\[6\] This preserves the historical record of the agent\'s actions without the token overhead of raw data.\[6\] In contrast, the `SummarizationStrategy` uses a secondary, more cost-effective model (e.g., GPT-4o-mini or Claude Haiku 4.5) to condense entire historical spans into a single narrative summary.\[6\]

Anthropic\'s `compaction_control` parameter offers a similar automated capability, primarily optimized for server-side execution in models like Claude Opus 4.6 and 4.7.\[7\] This mechanism monitors turn-by-turn token usage and, upon hitting a threshold, triggers the model to generate a summary wrapped in `<summary>` tags.\[7\] The existing history is then cleared, and the session resumes using only the summary as the foundational context.\[7\]

+----------------------------+----------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------+
| Strategy Type              | Best Use Case                                                                                | Risk / Failure Mode                                                                                  |
+============================+==============================================================================================+======================================================================================================+
| **Tool Result Compaction** | Reclaiming space from data-heavy tool outputs while maintaining a trace of logic.\[6\]       | Loss of specific raw data values if they are needed for future cross-referencing.\[6\]               |
+----------------------------+----------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------+
| **Summarization**          | Long-running sessions requiring the preservation of key decisions and user preferences.\[6\] | Hallucination of prior context or loss of nuanced technical details during the summary turn.\[6, 8\] |
+----------------------------+----------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------+
| **Sliding Window**         | Sessions where only the most recent context is relevant to the immediate next step.\[6\]     | \"Context Rot\": the agent forgets early constraints or foundational project requirements.\[6\]      |
+----------------------------+----------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------------------+

Mid-conversation compaction is typically triggered by predicates such as `TokensExceed(threshold)`, `TurnsExceed(count)`, or `GroupsExceed(count)`.\[6\] Developers can also manually force compaction using specific CLI commands or API hooks like `CompactionProvider.CompactAsync` to sanitize the history before initiating a new complex sub-task.\[1, 6\]

Tool Output Trimming: Implementation and Design Patterns

Tool Output Trimming is a structural design pattern that filters data at the point of ingestion into the context window, distinct from retrospective compaction.\[9, 10\] By stripping unnecessary fields from tool responses, developers ensure that only high-signal data enters the history. This is often implemented via \"hooks\" that manipulate message objects in-place.\[9\]

Concrete implementation patterns identified in Pydantic AI and the Claude Agent SDK include the \"Keep Last N Tool Calls\" pattern, which trims all but the most recent tool call arguments and results while preserving the pairing IDs to avoid API errors.\[9\] Another common pattern is \"Critical Preservation,\" where results from security or database tools are always whitelisted, while verbose outputs from general search tools are aggressively truncated.\[9\]

```
# Example: Keep Last N Tool Calls Pattern (Conceptual Implementation)
async def keep_last_n_tool_calls(messages: list[ModelMessage], ctx: CompactionContext, n: int = 3):
    tool_ids_to_keep = identify_recent_tool_ids(messages, n)
    for msg in messages:
        for part in msg.parts:
            if isinstance(part, (ToolCallPart, ToolReturnPart)):
                if part.tool_call_id not in tool_ids_to_keep:
                    part.content = f"[Cleared: {part.tool_call_id}]"
                    part.args = {"cleared": True}
    return messages
```

This structural trimming has a token savings profile that is more efficient than broad summarization because it prevents the context window from ever filling with noise, rather than cleaning it after the fact.\[9, 10\] It also mitigates the risk of the model becoming distracted by stale, detailed data from early exploratory steps.\[9\]

Output Quality Boosters and the Brevity-Accuracy Connection

A common assumption in agentic design is that more detailed reasoning leads to higher logical accuracy. However, research from 2026 suggests that excessive verbosity, particularly in large models, can introduce significant errors through a mechanism known as \"overthinking\".\[11, 12\]

Brevity Constraints and Benchmarking Results

The paper \"Brevity Constraints Reverse Performance Hierarchies in Language Models\" (Hakim, March 2026) reveals an \"inverse scaling\" phenomenon on approximately 7.7% of standard benchmark problems.\[11\] In these instances, larger models (70B-405B parameters) were found to underperform smaller models by an average of 28.4 percentage points due to spontaneous, scale-dependent verbosity.\[11, 12\] Large models generate responses roughly 59% longer than their smaller counterparts, but this extra volume consists of verbose elaboration that accumulates logical flaws and reduces calibration.\[12\]

+--------------------------------+------------------------------------------------+----------------------------------------------------------------------+
| Constraint Type                | Accuracy Impact on Large Models                | Performance Shift                                                    |
+================================+================================================+======================================================================+
| **Unconstrained**              | Baseline underperformance (Losing by 13-27pp)  | Hierarchy favors small models.\[11, 12\]                             |
+--------------------------------+------------------------------------------------+----------------------------------------------------------------------+
| **Brief (\"Under 50 words\")** | +26.3 percentage point improvement in accuracy | Hierarchy reverses; large models achieve 7-15pp advantage.\[11, 12\] |
+--------------------------------+------------------------------------------------+----------------------------------------------------------------------+
| **Answer-Only**                | Significant reduction in reasoning errors      | Optimal for math/science tasks.\[11\]                                |
+--------------------------------+------------------------------------------------+----------------------------------------------------------------------+

This causal evidence establishes that brevity constraints are not merely a cost-saving measure but a critical quality booster. Constraining large models to be concise unlocks masked latent capabilities and improves their performance on mathematical reasoning and scientific knowledge benchmarks by up to two-thirds.\[11, 12\]

Context Clarity and Structural Patterns

Beyond token counts, the structural organization of context independent of length significantly influences model output quality. \"Context Engineering\" emphasizes techniques that maximize the signal-to-noise ratio within the prompt.

One such pattern is explicit role separation and task boundaries. In long agentic runs, instruction drift is a common failure mode where the model forgets its core constraints.\[13\] Implementing a \"One-feature-at-a-time\" lockdown, where the agent is instructed to focus exclusively on a single module and stop if unrelated changes are detected, prevents context rot and the \"cascading breaks\" typical of early vibe coding agents.\[13, 14\] Furthermore, providing explicit positive instructions (e.g., \"Use tool X for task Y\") rather than generic tool restrictions has been shown to improve success rates from 43% to 100% in tool-dependency benchmarks.\[15\]

Anti-patterns that degrade quality include skill overload---registering too many concurrent tools that confuse the model\'s selection logic---and poor agent handoffs that lead to context bleeding.\[13, 16\] To combat this, developers are moving toward multi-agent architectures with isolated contexts, where research sub-agents pass only distilled summaries back to the primary manager agent.\[17, 18, 19\]

The Caveman Skill: Mechanical and Community Analysis

The \"caveman\" mode, developed by Julius Brussee, represents a radical implementation of brevity constraints as a stylized communication protocol for coding agents.\[20, 21, 22\] It viralized in April 2026, precisely because it addressed the \"AI Yap\" pain point---the tendency of models to generate excessive conversational filler that consumes tokens without adding value.\[21, 23\]

Mechanical Implementation and Intensity Levels

Mechanically, caveman mode functions as a persistent skill or system prompt modification that forces the model to inhabit a terse, high-signal persona.\[24, 25\] It operates by grammatical deletion: explicitly dropping articles (a, an, the), filler words (just, really, basically), pleasantries, and hedging.\[24, 25\] It encourages the use of short fragments and synonyms, adhering to a pattern of `[thing][action][reason]. [next step]`.\[24\]

+-----------------------+-----------------------------------------------------------------------+---------------------------------------------+
| Level                 | Mechanical Change                                                     | Impact on Token Consumption                 |
+=======================+=======================================================================+=============================================+
| **Lite**              | Removes filler and hedging; keeps full sentences.\[24, 25\]           | Moderate savings (\~20-30%).\[26\]          |
+-----------------------+-----------------------------------------------------------------------+---------------------------------------------+
| **Full**              | Default mode; drops articles and uses fragments.\[23, 24\]            | High savings (\~65-75%).\[23, 27\]          |
+-----------------------+-----------------------------------------------------------------------+---------------------------------------------+
| **Ultra**             | Telegraphic; extreme abbreviations (DB, auth, req, res).\[24, 25\]    | Maximum output reduction (\>80%).\[23, 28\] |
+-----------------------+-----------------------------------------------------------------------+---------------------------------------------+
| **Wenyan**            | Semi-classical or full Classical Chinese register (文言文).\[20, 24\] | 80-90% character reduction.\[24\]           |
+-----------------------+-----------------------------------------------------------------------+---------------------------------------------+

Crucially, the mode maintains technical substance: code blocks, technical terms, and exact error quotes remain unchanged.\[21, 24\] The implementation also includes \"Auto-Clarity\" triggers where caveman speech is temporarily suspended for security warnings, irreversible action confirmations, or when the user asks for explicit clarification.\[24, 28\]

The 75% Claim vs. the 1% Reality: A Cost Discrepancy

A contentious Reddit thread in the r/vibecoding community (April 2026) criticized the marketing of caveman mode, arguing that while it may save 75% of *output* tokens, it saves only \~1% of total session costs.\[26\] This investigation into cost-source decomposition highlights that input context---including trajectories and memory files---is the primary driver of API bills.\[3, 26\]

Quantitative analysis reveals that for a typical refactoring task, input tokens can exceed 250,000 while output tokens remain under 40,000.\[19\] Reducing the 40,000 output tokens by 75% is statistically significant for raw text, but in long agentic loops where the 250,000 input tokens are re-read every turn, the net savings are diluted.\[26, 29\] Furthermore, the caveman skill itself injects roughly 300-350 tokens of instructions into the context on every turn, meaning the net \"break-even\" point only occurs if the response suppression exceeds the overhead of the skill prompt.\[29\]

+------------------------+-------------------------+----------------------------------+-------------------------------------------------------------+
| Metric                 | Caveman Claim           | Practical Reality (Coding Agent) | Underlying Cause                                            |
+========================+=========================+==================================+=============================================================+
| **Output Tokens**      | \~75% Reduction         | 65-87% (Validated) \[20, 23\]    | Stylized grammar is highly efficient for raw text.\[23\]    |
+------------------------+-------------------------+----------------------------------+-------------------------------------------------------------+
| **Total Session Cost** | \"Cut API bill by 75%\" | 1-5% Reduction \[26\]            | Cost is dominated by input history (O(T2) growth).\[1\]     |
+------------------------+-------------------------+----------------------------------+-------------------------------------------------------------+
| **Input Token Impact** | Not specified           | +350 tokens per turn \[29\]      | Fixed overhead of the `SKILL.md` ruleset.\[29\]             |
+------------------------+-------------------------+----------------------------------+-------------------------------------------------------------+
| **Readability**        | \"Easier to read\"      | Paradoxically clearer \[30\]     | Compression forces engagement; \"peels back layers\".\[30\] |
+------------------------+-------------------------+----------------------------------+-------------------------------------------------------------+

Invocation Timing and Deactivation Risk

The core risk of caveman mode is its persistence during user-facing output.\[24\] If left active during a final explanation of a destructive database migration, the fragmented \"caveman\" instructions can lead to user error.\[13, 31\] Modern implementations solve this through conditional skill toggling.\[24, 32\] The mode should be active during internal tool-call reasoning steps---where \"thoughts\" are not visible or where the agent is talking to itself---but deactivated before a `final_answer` or a response marked as a security warning.\[24\]

Documented implementations of this toggling use statusline badges or metadata flags (e.g., `[CAVEMAN:FULL]`) to notify the user of the current active intensity.\[33\] If the model detects a high-risk operation (triggered by keywords like \"delete\", \"permanent\", or \"destructive\"), it automatically drops the mode for one turn to explain the consequences clearly before resuming.\[24\]

Comprehensive Optimization and Actionable Implementation Rules

Synthesizing the research from 2025 and 2026, it is evident that agentic performance is maximized when developers treat context as a finite, expensive resource that must be engineered with precision. The following implementation rules provide a blueprint for radical token efficiency and high output quality.

Rule 1: Multi-Pass Trajectory Pruning

Agents must not rely on the raw history of the conversation. Implement a proactive, multi-pass pruning pipeline \[3, 6\]:

-   **Pass 1 (Syntactic)**: Filter distractor tabs and noise files before they enter the history.\[1\]
-   **Pass 2 (Structural)**: Apply `ToolResultCompaction` to older tool-call groups to reclaim space from data-heavy outputs.\[6\]
-   **Pass 3 (Semantic)**: Use an LLM-based reflection module to identify \"Expired\" exploratory data (e.g., failed grep searches) and prune it from the context.\[3\]

Rule 2: Scale-Aware Brevity Routing

Large language models (70B+) require explicit brevity constraints to mitigate the \"inverse scaling\" phenomenon.\[11\]

-   For reasoning-intensive tasks, inject a \"Concise Chain of Thought\" instruction: \"Reason step-by-step, but keep each step under 15 words\".\[12, 34\]
-   Use problem-aware routing: apply aggressive brevity to mathematical and scientific tasks where \"overthinking\" leads to a 28pp drop in accuracy.\[11, 12\]

Rule 3: Stylized Grammar for Memory, Not Execution

The stylized brevity of caveman grammar is most effective when applied to project memory, not just conversation.\[35\]

-   **Memory Compression**: Use tools like `caveman-compress` to reduce the size of `CLAUDE.md` and project instruction files by \~46%.\[35\] Since these files are read on *every* turn, this provides a massive recurring cost reduction.\[35\]
-   **Internal Drafting**: Enable caveman mode for intermediate \"thinking\" steps and internal sub-agent coordination.\[32, 36\]
-   **Boundary Control**: Force a revert to standard English for all security-critical operations and final user-facing responses.\[24\]

Rule 4: Context Caching and Economic Breaks

Developers must leverage prompt caching to offset the cost of large input trajectories.\[1, 8\]

-   The economic break-even point for Anthropic prompt caching is just 2 reuses; at 10 reuses, input costs are reduced by 76%.\[1\]
-   Cache the system prompt, instruction files, and the summary of the conversation up to the last \"milestone\" to ensure the agent only pays for the active turn\'s changes.\[1\]

Conclusion: The Shift to Context Engineering

The research of 2025 and 2026 has decisively shifted the focus of agent development from \"more tokens\" to \"higher signal.\" The discovery that unconstrained verbosity harms large model reasoning accuracy proves that the \"contextual wall\" is as much a logical hurdle as it is a financial one. Techniques like AgentDiet's mathematical pruning, Microsoft's experimental compaction strategies, and the radical stylized brevity of the caveman mode are no longer optional \"tricks\" but foundational requirements for scalable agentic architectures. By treating every token as a compute unit that must earn its place in the context window, developers can build coding agents that are not only 40-60% more cost-effective but are measurably more accurate, finally delivering on the promise of autonomous, enterprise-ready AI software engineers.

\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\--

1.  Tokalator: A Context Engineering Toolkit for Artificial \... - arXiv, [https://arxiv.org/pdf/2604.08290](https://www.google.com/url?sa=E&q=https%3A%2F%2Farxiv.org%2Fpdf%2F2604.08290)
2.  Reducing Cost of LLM Agents with Trajectory Reduction - arXiv, [https://arxiv.org/pdf/2509.23586](https://www.google.com/url?sa=E&q=https%3A%2F%2Farxiv.org%2Fpdf%2F2509.23586)
3.  Reducing Cost of LLM Agents with Trajectory Reduction - arXiv, [https://arxiv.org/html/2509.23586v2](https://www.google.com/url?sa=E&q=https%3A%2F%2Farxiv.org%2Fhtml%2F2509.23586v2)
4.  Improving the Efficiency of LLM Agent Systems through Trajectory Reduction \| Request PDF, [https://www.researchgate.net/publication/395970553_Improving_the_Efficiency_of_LLM_Agent_Systems_through_Trajectory_Reduction](https://www.google.com/url?sa=E&q=https%3A%2F%2Fwww.researchgate.net%2Fpublication%2F395970553_Improving_the_Efficiency_of_LLM_Agent_Systems_through_Trajectory_Reduction)
5.  Diet code is healthy: simplifying programs for pre-trained models of code - ResearchGate, [https://www.researchgate.net/publication/365273843_Diet_code_is_healthy_simplifying_programs_for_pre-trained_models_of_code](https://www.google.com/url?sa=E&q=https%3A%2F%2Fwww.researchgate.net%2Fpublication%2F365273843_Diet_code_is_healthy_simplifying_programs_for_pre-trained_models_of_code)
6.  Compaction \| Microsoft Learn, [https://learn.microsoft.com/en-us/agent-framework/agents/conversations/compaction](https://www.google.com/url?sa=E&q=https%3A%2F%2Flearn.microsoft.com%2Fen-us%2Fagent-framework%2Fagents%2Fconversations%2Fcompaction)
7.  Automatic context compaction \| Claude Cookbook, [https://platform.claude.com/cookbook/tool-use-automatic-context-compaction](https://www.google.com/url?sa=E&q=https%3A%2F%2Fplatform.claude.com%2Fcookbook%2Ftool-use-automatic-context-compaction)
8.  Mastering Claude 4.6 Context Window: 1M Token Complete Configuration Guide and 5 Major Practical Scenarios, [https://help.apiyi.com/en/claude-4-6-context-window-1m-token-guide-en.html](https://www.google.com/url?sa=E&q=https%3A%2F%2Fhelp.apiyi.com%2Fen%2Fclaude-4-6-context-window-1m-token-guide-en.html)
9.  Feature Request: First-class Context Compaction API · Issue #4137 \..., [https://github.com/pydantic/pydantic-ai/issues/4137](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2Fpydantic%2Fpydantic-ai%2Fissues%2F4137)
10. How to Become a Claude Certified Architect: Complete Guide - AI Tools Club, [https://aitoolsclub.com/how-to-become-a-claude-certified-architect-complete-guide/](https://www.google.com/url?sa=E&q=https%3A%2F%2Faitoolsclub.com%2Fhow-to-become-a-claude-certified-architect-complete-guide%2F)
11. Brevity Constraints Reverse Performance Hierarchies in Language Models - arXiv, [https://arxiv.org/html/2604.00025v1](https://www.google.com/url?sa=E&q=https%3A%2F%2Farxiv.org%2Fhtml%2F2604.00025v1)
12. Paper page - Brevity Constraints Reverse Performance Hierarchies in Language Models, [https://huggingface.co/papers/2604.00025](https://www.google.com/url?sa=E&q=https%3A%2F%2Fhuggingface.co%2Fpapers%2F2604.00025)
13. Vibe Coding 2026: We All Hit the Wall --- Here\'s the 7 Guardrails That Actually Stopped My Projects from Dying (No Hype Edition) : r/nocode - Reddit, [https://www.reddit.com/r/nocode/comments/1rxguqh/vibe_coding_2026_we_all_hit_the_wall_heres_the_7/](https://www.google.com/url?sa=E&q=https%3A%2F%2Fwww.reddit.com%2Fr%2Fnocode%2Fcomments%2F1rxguqh%2Fvibe_coding_2026_we_all_hit_the_wall_heres_the_7%2F)
14. Vibe Coding in 2026 is a Complete Scam -- Lovable, Replit, Emergent, Bolt & the Rest Are Trash Fires : r/vibecodingcommunity - Reddit, [https://www.reddit.com/r/vibecodingcommunity/comments/1rvnq11/vibe_coding_in_2026_is_a_complete_scam_lovable/](https://www.google.com/url?sa=E&q=https%3A%2F%2Fwww.reddit.com%2Fr%2Fvibecodingcommunity%2Fcomments%2F1rvnq11%2Fvibe_coding_in_2026_is_a_complete_scam_lovable%2F)
15. experiment: evaluate pipeline execution quality with simplified permission model · Issue #282 · re-cinq/wave - GitHub, [https://github.com/re-cinq/wave/issues/282](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2Fre-cinq%2Fwave%2Fissues%2F282)
16. Workflow orchestrations in Agent Framework - Microsoft Learn, [https://learn.microsoft.com/en-us/agent-framework/workflows/orchestrations/](https://www.google.com/url?sa=E&q=https%3A%2F%2Flearn.microsoft.com%2Fen-us%2Fagent-framework%2Fworkflows%2Forchestrations%2F)
17. Agent Reasoning in Azure SRE Agent \| Microsoft Learn, [https://learn.microsoft.com/en-us/azure/sre-agent/agent-reasoning](https://www.google.com/url?sa=E&q=https%3A%2F%2Flearn.microsoft.com%2Fen-us%2Fazure%2Fsre-agent%2Fagent-reasoning)
18. Effective context engineering for AI agents - Anthropic, [https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents](https://www.google.com/url?sa=E&q=https%3A%2F%2Fwww.anthropic.com%2Fengineering%2Feffective-context-engineering-for-ai-agents)
19. Reduce Claude Code Costs 60% With These Four Habits - systemprompt.io, [https://systemprompt.io/guides/claude-code-cost-optimisation](https://www.google.com/url?sa=E&q=https%3A%2F%2Fsystemprompt.io%2Fguides%2Fclaude-code-cost-optimisation)
20. JuliusBrussee/caveman: why use many token when few token do trick --- Claude Code skill that cuts 65% of tokens by talking like caveman · GitHub, [https://github.com/juliusbrussee/caveman](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2Fjuliusbrussee%2Fcaveman)
21. Forcing AI to act like a caveman: Claude\'s anti-wordy plugin goes viral. Netizens: Fed up with AI\'s nonsense. - 36氪, [https://eu.36kr.com/en/p/3756289723286272](https://www.google.com/url?sa=E&q=https%3A%2F%2Feu.36kr.com%2Fen%2Fp%2F3756289723286272)
22. Julius Brussee JuliusBrussee - GitHub, [https://github.com/JuliusBrussee](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2FJuliusBrussee)
23. 19-Year-Old\'s Token-Saving Tool Gains 4,100 Stars in 3 Days, Saves Up to 87% of Tokens Without Info Loss - 36氪, [https://eu.36kr.com/en/p/3756573503963912](https://www.google.com/url?sa=E&q=https%3A%2F%2Feu.36kr.com%2Fen%2Fp%2F3756573503963912)
24. SKILL.md - JuliusBrussee/caveman - GitHub, [https://github.com/JuliusBrussee/caveman/blob/main/caveman/SKILL.md](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2FJuliusBrussee%2Fcaveman%2Fblob%2Fmain%2Fcaveman%2FSKILL.md)
25. SKILL.md - JuliusBrussee/caveman · GitHub, [https://github.com/JuliusBrussee/caveman/blob/main/skills/caveman/SKILL.md](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2FJuliusBrussee%2Fcaveman%2Fblob%2Fmain%2Fskills%2Fcaveman%2FSKILL.md)
26. Taught Claude to talk like a caveman to use 75% less tokens. : r/ClaudeAI - Reddit, [https://www.reddit.com/r/ClaudeAI/comments/1sble09/taught_claude_to_talk_like_a_caveman_to_use_75/](https://www.google.com/url?sa=E&q=https%3A%2F%2Fwww.reddit.com%2Fr%2FClaudeAI%2Fcomments%2F1sble09%2Ftaught_claude_to_talk_like_a_caveman_to_use_75%2F)
27. Token Savings with Caveman Skills - Peerlist, [https://peerlist.io/scroll/post/ACTHOK8GMNRGEO9LRCAMQQQ9RMR6RA](https://www.google.com/url?sa=E&q=https%3A%2F%2Fpeerlist.io%2Fscroll%2Fpost%2FACTHOK8GMNRGEO9LRCAMQQQ9RMR6RA)
28. JuliusBrussee/caveman v1.2.0 on GitHub - NewReleases.io, [https://newreleases.io/project/github/JuliusBrussee/caveman/release/v1.2.0](https://www.google.com/url?sa=E&q=https%3A%2F%2Fnewreleases.io%2Fproject%2Fgithub%2FJuliusBrussee%2Fcaveman%2Frelease%2Fv1.2.0)
29. README makes two inaccurate claims about token savings · Issue #18 · JuliusBrussee/caveman - GitHub, [https://github.com/JuliusBrussee/caveman/issues/18](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2FJuliusBrussee%2Fcaveman%2Fissues%2F18)
30. CAVEMAN: Does Talking Like a Caveman Actually Make AI Better? - Rushi\'s, [https://www.rushis.com/caveman-does-talking-like-a-caveman-actually-make-ai-better/](https://www.google.com/url?sa=E&q=https%3A%2F%2Fwww.rushis.com%2Fcaveman-does-talking-like-a-caveman-actually-make-ai-better%2F)
31. Vibe Coding in 2026 is a Complete Scam -- Lovable, Replit, Emergent, Bolt & the Rest Are Trash Fires - Reddit, [https://www.reddit.com/r/lovable/comments/1rui1j9/vibe_coding_in_2026_is_a_complete_scam_lovable/](https://www.google.com/url?sa=E&q=https%3A%2F%2Fwww.reddit.com%2Fr%2Flovable%2Fcomments%2F1rui1j9%2Fvibe_coding_in_2026_is_a_complete_scam_lovable%2F)
32. Releases · JuliusBrussee/caveman - GitHub, [https://github.com/JuliusBrussee/caveman/releases](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2FJuliusBrussee%2Fcaveman%2Freleases)
33. caveman/CLAUDE.md at main - GitHub, [https://github.com/JuliusBrussee/caveman/blob/main/CLAUDE.md](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2FJuliusBrussee%2Fcaveman%2Fblob%2Fmain%2FCLAUDE.md)
34. CROP: Token-Efficient Reasoning in Large Language Models via Regularized Prompt Optimization - arXiv, [https://arxiv.org/html/2604.14214v1](https://www.google.com/url?sa=E&q=https%3A%2F%2Farxiv.org%2Fhtml%2F2604.14214v1)
35. caveman/caveman-compress/README.md at main · JuliusBrussee/caveman - GitHub, [https://github.com/JuliusBrussee/caveman/blob/main/caveman-compress/README.md](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2FJuliusBrussee%2Fcaveman%2Fblob%2Fmain%2Fcaveman-compress%2FREADME.md)
36. caveman-commit • caveman • JuliusBrussee • Skills • Registry - Tessl, [https://tessl.io/registry/skills/github/JuliusBrussee/caveman/caveman-commit/review](https://www.google.com/url?sa=E&q=https%3A%2F%2Ftessl.io%2Fregistry%2Fskills%2Fgithub%2FJuliusBrussee%2Fcaveman%2Fcaveman-commit%2Freview)
