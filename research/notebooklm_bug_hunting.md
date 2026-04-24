This structured report details methodologies for identifying functional (logic and reliability) defects, drawing from the provided sources. It highlights concepts applicable by Large Language Models (LLMs) to automate or assist in the "hunting" process.

### 1. Automated Logic Modeling (FSM Inference)

*   **Concept/Method:** **Finite State Machine (FSM) Synthesis**.
*   **Application:** Modeling complex software behavior (e.g., network protocols, smart contracts, or UI state) as a deterministic set of states and transitions to find logical contradictions. 
*   **LLM Role:** **Can be applied by an LLM.** Tools like ProtocolGPT use LLMs to identify states and message types from source code and deduce the transition relationships.
*   **Prerequisites:** 
    *   Explicit definitions of states/messages in the code (e.g., enums).
    *   Targeted prompts using "Chain-of-Thought" to navigate state spaces.
    *   Historical "ground truth" or specifications to identify discrepancies.
*   **Possible Outcomes:** Average precision exceeding 90% in identifying state transitions. Detection of "silent" failures where code transitions to a state that is technically reachable but logically impossible.

### 2. Lexical Exploration and "Grep" Mindset

*   **Concept/Method:** **Hypothesis-Driven Searching**.
*   **Application:** Using lexical search (e.g., `grep`, `ripgrep`) to locate "sinks" where untrusted data or complex logic might fail.
*   **LLM Role:** **Can be applied by an LLM.** Agentic assistants prefer `grep` as their primary navigation API because it is token-efficient and faster than reading entire files.
*   **Prerequisites:** 
    *   **Searchable Naming:** Functions and variables must have unique, distinctive names (e.g., `InvoiceLineItemTotal` instead of `data`).
    *   **Small Code Units:** Functions should be 4-20 lines to prevent truncation in the agent's context window.
*   **Possible Outcomes:** Rapid identification of potential bug candidates across large codebases without loading full file contexts.

### 3. Directional Reasoning (Tracing)

*   **Concept/Method:** **Forward and Backward Tracing**.
*   **Application:**
    1.  **Forward:** Following logical flow from a known state/input to observe outcomes.
    2.  **Backward:** Starting from a failure point (e.g., an error log or incorrect output) and working up to the source.
*   **LLM Role:** **Can be applied by an LLM.** LLMs are effective at line-by-line reading and identifying "sinks" during backward tracing. 
*   **Prerequisites:** Human direction to define the "start" or "sink" points. Version history (e.g., `git diff`) helps LLMs perform "historic analysis" to find where logic changed.
*   **Possible Outcomes:** Localization of faulty code in unfamiliar systems where human developers might struggle with "archaeology".

### 4. Differential and Property-Based Testing

*   **Concept/Method:** **Invariant-Based Verification**.
*   **Application:** Validating results against mathematical "ground truth" or comparing outputs across multiple simulator configurations.
*   **LLM Role:** **LLM can assist.** While humans define the invariants, LLMs can generate the test harnesses and randomized inputs needed for property-based testing.
*   **Prerequisites:** Defined global semantic invariants (e.g., "probability must always normalize to 1").
*   **Possible Outcomes:** Discovery of "silent" incorrect results where execution completes without error but the numerical output is systematically wrong.

### 5. Code Summarization for Mental Model Development

*   **Concept/Method:** **Knowledge Acquisition and Elaboration**.
*   **Application:** Translating complex, unfamiliar code into high-level logic summaries to reduce "intrinsic cognitive load".
*   **LLM Role:** **Can be applied by an LLM.** Developers use LLMs to explain what a specific segment of code is doing to bypass the need to read every manual.
*   **Prerequisites:** Clear "Docstrings" and comments describing the *why* (provenance) rather than just the *what*.
*   **Possible Outcomes:** Faster "mental model" updates, allowing the auditor to learn the *least* amount necessary to fix a bug.

### 6. "Cognitive Forcing" and Socratic Auditing

*   **Concept/Method:** **Teaching Back / Socratic Tutor**.
*   **Application:** Instead of asking the AI to find bugs, the human explains their logic *to* the AI, which then probes for gaps.
*   **LLM Role:** **Applied by an LLM** in a "navigator/driver" or "tutor" role.
*   **Prerequisites:** Deliberate interaction patterns that avoid "Autocomplete Without Examination".
*   **Possible Outcomes:** Forces the human to articulate assumptions, which often surfaces logic gaps that were previously overlooked. Prevents "happy path" bias where auditors only look for why code *works* rather than why it *fails*.