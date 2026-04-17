---
name: architecture
description: Explore a Python codebase to find opportunities to deepen shallow modules, reduce coupling, and improve testability. Reads codebase_metrics.json from .python-refactor/ (auto-runs measure if missing) and cross-references BUG_REPORT_<RUN_ID>.md if present to show which architectural patterns are hiding confirmed bugs. Presents numbered candidates, spawns parallel design subagents for the chosen candidate, recommends the strongest interface design, and creates GitHub issue RFCs. Use when the user wants architecture review, module deepening, or coupling reduction.
---

# python-refactor: Architecture

Find opportunities to deepen shallow modules and improve testability.

Announce: "Using python-refactor:architecture to analyze codebase architecture."

**Platform note:** Claude Code tool names used. On Copilot CLI: Bash -> runCommand, Read -> readFile.

**Output convention:** All output goes to `.python-refactor/`. See references/output-convention.md.

A **deep module** (Ousterhout, A Philosophy of Software Design) has a small interface hiding a
large implementation. Deep modules are more testable, more AI-navigable, and let you test at the
boundary instead of inside the implementation.

---

## 0. Scaffolding and load inputs

If OUTPUT_DIR and RUN_ID were provided by the orchestrator, use those values.
Otherwise (standalone invocation), run the scaffolding preamble:

  OUTPUT_DIR="PROJECT_ROOT/.python-refactor"
  RUN_ID=$(date -u +"%Y-%m-%dT%H-%M-%S")
  mkdir -p "$OUTPUT_DIR/tmp" "$OUTPUT_DIR/tests"
  [ -f "$OUTPUT_DIR/.gitignore" ] || echo '*' > "$OUTPUT_DIR/.gitignore"

  # Snapshot pre-existing tool caches (only if manifest does not exist yet)
  if [ ! -f "$OUTPUT_DIR/manifest.json" ]; then
    PRE_EXISTING="[]"
    for d in .hypothesis .pytest_cache .semgrep .skylos_cache; do
      [ -d "PROJECT_ROOT/$d" ] && PRE_EXISTING=$(echo "$PRE_EXISTING" | python3 -c "import sys,json; l=json.load(sys.stdin); l.append('$d'); print(json.dumps(l))")
    done
    cat > "$OUTPUT_DIR/manifest.json" <<MANIFEST
    {
      "run_id": "$RUN_ID",
      "pre_existing": $PRE_EXISTING,
      "created_caches": [],
      "deliverables": []
    }
    MANIFEST
  fi

Check for $OUTPUT_DIR/codebase_metrics.json. If missing: invoke Skill tool with skill name
"python-refactor:measure" first, then continue.

If a BUG_REPORT_*.md exists in $OUTPUT_DIR (use glob, prefer the one matching $RUN_ID,
otherwise the most recent): load confirmed_bugs for cross-reference in step 3.

---

## 1. Explore organically

Use Read to navigate the codebase. Do not follow rigid heuristics.
Cross-reference with codebase_metrics.json as you go.

Note where you experience friction as someone reading this code for the first time:

Where you must bounce between many small files to understand one concept — the concept is
scattered. Shallow modules force callers to know too much.

Where the module interface is nearly as complex as the implementation — there is nothing to
abstract, no depth. Adding the abstraction adds cost without reducing cognitive load.

Where pure functions were extracted just for testability but real bugs hide in how they are
wired together — the abstraction boundary is in the wrong place.

Where tightly coupled modules would break together during refactoring — the seam between
them is an integration risk, not a module boundary.

Python-specific friction signals to look for:
  God modules: single .py files with 500+ SLOC and multiple unrelated responsibilities
  Module-level side effects on import: make mocking hard and test ordering fragile
  Protocol-less duck typing: AI tools and type checkers cannot navigate the contract
  Missing __init__.py abstractions: internal implementation details leak at the package boundary
  High-fanout hubs in the dependency_graph: many modules import this one and it imports many

Metrics cross-reference: files with CC above 10 AND MI below 65 are shallow-and-complex.
High fanout in dependency_graph.adjacency indicates an architectural hub.

---

## 2. Classify coupling type

For each candidate cluster, classify the coupling:

  Intra-layer: two modules at the same architectural layer import each other
  Cross-layer downward: higher layer depends on lower layer — Controller -> Service -> Repository — correct direction
  Cross-layer upward: lower layer depends on higher layer — Repository imports Controller — architectural violation
  Cross-boundary: one bounded context imports internals of another bounded context

---

## 3. Present candidates

Create a numbered list. For each candidate:

  Number and cluster: which files are involved (with full relative paths)
  Coupling type: from the classification above
  Metrics evidence: CC score, MI score, fanout degree from dependency_graph
  Test impact: which existing tests would be replaced by boundary tests, and what the boundary tests would look like
  Bug connection: if BUG_REPORT.md is present, does any confirmed bug hide inside this coupling?

Present the complete list. Then ask:

  Which of these would you like to explore? Enter a number, a comma-separated list, or 'all'.

---

## 4. Frame the problem space

For the chosen candidate, write a user-facing explanation:

  The constraints any new interface must satisfy
  The dependencies it must rely on (traced from dependency_graph)
  The metrics evidence justifying the change
  A rough illustrative code sketch to ground the constraints — this is NOT a proposal,
  it is a way to make the constraints concrete while sub-agents design real proposals

Show this to the user, then immediately dispatch the design sub-agents (step 5).
The user reads while the agents work in parallel.

---

## 5. Design multiple interfaces (parallel sub-agents)

Spawn 3 or 4 sub-agents using the Agent tool. Each receives a separate technical brief:
file paths, coupling type, dependency category, metrics evidence, what complexity must be hidden.
The brief is independent of the user-facing explanation in step 4.

Design constraint per agent:

  Agent 1: Minimize interface. Aim for 1 to 3 entry points maximum.
           Use Python Protocol for structural subtyping at the boundary.
           Caller should not need to know anything about the implementation.

  Agent 2: Maximize flexibility. Support many use cases and future extension.
           Use abstract base classes or pluggable strategy pattern.
           Optimize for replaceability — multiple implementations must be swappable.

  Agent 3: Optimize for the most common caller.
           Make the default case completely trivial with no configuration.
           Advanced behavior available via keyword-argument overrides only.

  Agent 4 (only for cross-boundary coupling):
           Design for ports and adapters.
           Define an abstract Port in the core domain.
           Push the concrete Adapter to the infrastructure layer.
           The core must not import from infrastructure.

Each sub-agent must output:
  1. Interface signature: type hints, Protocol or ABC definition, method signatures
  2. Usage example: exact code showing how a typical caller uses the new interface
  3. What complexity is hidden: the list of things callers no longer need to know
  4. Dependency strategy: constructor injection, factory function, or DI container
  5. Trade-offs: verbosity, testability, Python idiom alignment, migration cost

Present all designs sequentially. Compare them in prose — do not just list features.
Then give your own recommendation. Name which design is strongest and why.
If elements from different designs would combine well, propose a hybrid explicitly.
Be opinionated. The user wants a strong read, not a menu.

---

## 6. User picks an interface or accepts the recommendation

---

## 7. Create issue RFC

Depending on the infrastructure, for example use Bash to run gh issue create:

  gh issue create \
    --title "RFC: Deepen MODULE_NAME — ONE_LINE_DESCRIPTION" \
    --label "refactor,rfc" \
    --body "BODY"

RFC body structure:

  ## Problem
  Description of the architectural friction.
  Metric evidence: CC=X, MI=X, fanout=X.
  Bug connection if any: which confirmed bugs are symptoms of this shallow module.

  ## Proposed Interface
  The selected design from step 5.
  Full type signatures and usage example.

  ## What Complexity Is Hidden
  Bulleted list of what callers no longer need to know or manage.

  ## Dependency Strategy
  How dependencies are injected into the new deep module.

  ## Test Strategy
  Description of the boundary tests that replace current fine-grained unit tests.
  What test fixtures the new interface enables.

  ## Migration Path
  Step-by-step: how existing callers are updated without breaking changes.
  Does the migration require a compatibility shim? If yes, describe it.

  ## Metrics Baseline
  | Metric | Current | Target |
  |--------|---------|--------|
  | Cyclomatic Complexity | X | below 10 |
  | Maintainability Index | X | above 65 |
  | Coupling fanout | X | reduced |

  ## Acceptance Criteria
  - All existing tests pass via boundary tests
  - No caller imports internal implementation details
  - CC of all public methods is 10 or below
  - MI of all new files is 65 or above
  - Re-run python-refactor:hunt-bugs after merge to verify no new bugs introduced

Do NOT ask the user to review before creating the issue. Create it and share the URL.

---

## Handoff to orchestrator (when invoked by orchestrator)

Skip steps 3 through 7. Return ONLY this JSON after completing organic exploration:

{
  "status": "DONE",
  "architecture_candidates": [
    {"id": "ARCH-001",
     "cluster": ["src/a.py", "src/b.py"],
     "coupling_type": "cross-layer-up",
     "evidence": "CC=F/32, MI=48, fanout=12",
     "bug_connection": "BUG-001 hides here due to shared mutable state",
     "deepening_opportunity": "one-sentence description of the deepening opportunity"}
  ]
}
