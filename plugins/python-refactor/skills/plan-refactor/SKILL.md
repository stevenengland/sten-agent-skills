---
name: plan-refactor
description: Generate a prioritized, dependency-safe refactor plan from codebase_metrics.json and BUG_REPORT.md. Produces REFACTOR_PLAN.md with P0-P3 triage, per-finding action items, bug fix stubs with minimal reproductions, security fix stubs with CWE references, a topologically-sorted execution sequence respecting module dependencies, and a test gap analysis listing all P0/P1 files with no test coverage. Auto-runs measure if codebase_metrics.json is missing. Incorporates BUG_REPORT.md if present. When invoked by the orchestrator, returns a compact JSON handoff.
---

# python-refactor: Plan Refactor

Convert metrics, security findings, and bug reports into a concrete, dependency-safe refactor plan.

Announce: "Using python-refactor:plan-refactor to generate the refactor plan."

**Platform note:** Claude Code tool names used. On Copilot CLI: Bash -> runCommand, Write -> writeFile.

---

## 0. Load inputs

**Required:** Check for PROJECT_ROOT/codebase_metrics.json.
If missing: invoke Skill tool with skill name "python-refactor:measure" first, then continue.

**Optional:** Check for PROJECT_ROOT/BUG_REPORT.md.
If found: print "Incorporating confirmed bugs from BUG_REPORT.md" and load confirmed_bugs.

---

## 1. Triage all findings

Apply this priority matrix to every finding from codebase_metrics.json and BUG_REPORT.md:

  P0 — Fix immediately (no refactoring until P0 is clean):
    Confirmed bugs with HIGH impact from BUG_REPORT.md
    Bandit or Semgrep findings with HIGH severity
    Circular imports (block topological sequencing of entire cycle)

  P1 — Critical debt (require tests written before touching):
    Confirmed bugs with MEDIUM impact
    Files with cyclomatic complexity above 25 (grade F)
    Cross-layer upward dependency violations (lower layer imports higher layer)

  P2 — Significant debt:
    Files with cyclomatic complexity 15 to 25 (grade D or E)
    Files with maintainability index below 65
    Bandit or Semgrep findings with MEDIUM severity
    Dead code clusters covering more than 20 percent of a file

  P3 — Quality improvement:
    Files with cyclomatic complexity 10 to 15 (grade C)
    Files with maintainability index 65 to 75
    Bandit or Semgrep findings with LOW severity
    Small dead code clusters

  Backlog:
    Files with maintainability index above 75
    Cosmetic issues

For each P0, P1, and P2 finding, produce an action record:

  [PRIORITY] path/to/file.py :: function_name (evidence: CC=F/32, BUG-001)
  Action: specific action — e.g., "Extract three decision branches into named strategy objects"
  Test required before fix: path/to/test_file.py — or "MISSING — must write tests first"
  Depends on: list of modules that must be stable before this one is touched
  Effort estimate: 30min | 2h | 4h

---

## 2. Topological execution sequence

Read the dependency_graph from codebase_metrics.json.
Compute a topological ordering:

  Step 1: Identify leaf nodes — modules with no inbound imports from other project modules.
          These are safe to change first. No other module depends on them.

  Step 2: Work inward — after leaves are clean, process the modules that only depend on
          already-clean leaves.

  Step 3: Hub modules last — modules with high fanout (many other modules import them)
          must be changed only after all their dependencies are stable.

  Step 4: Circular imports block — any module involved in a circular import cycle cannot
          be sequenced safely until the cycle is resolved. Mark the entire cycle as P0.

Emit the sequence as a numbered ordered list. For each position: module name, action, and
one sentence explaining why it is at this position in the sequence.

---

## 3. Write REFACTOR_PLAN.md

Write PROJECT_ROOT/REFACTOR_PLAN.md with this exact structure:

---

  # Refactor Plan — PROJECT_NAME
  Generated: ISO8601_TIMESTAMP
  Inputs: codebase_metrics.json + BUG_REPORT.md (if present)

  ## P0 — Fix Immediately

  ### Confirmed Bugs (from python-refactor:hunt-bugs)
  For each confirmed HIGH-impact bug from BUG_REPORT.md:
    BUG-ID — file.py:LINE — function_name — impact level
    Reproduction: minimal code that triggers the bug
    Fix: description of the correct fix

  ### Security — HIGH Severity
  For each HIGH-severity finding from bandit/semgrep/skylos:
    TOOL [CWE-ID] description — file.py:LINE
    Fix: one-line description of the correct pattern

  ### Circular Imports
  For each cycle detected in pydeps output:
    Cycle: module_a -> module_b -> module_a
    Resolution: description of how to break the cycle

  ## P1 — Critical Architectural Debt
  (action records for each P1 finding)

  ## P2 — Significant Debt
  (action records for each P2 finding)

  ## P3 — Quality Improvements
  (action records for each P3 finding)

  ---

  ## Execution Sequence (dependency-safe topological order)

  1. module/path.py — action — reason for this position in the sequence
  2. ...

  ---

  ## Test Gap Analysis

  These files are scheduled for P0 or P1 changes but have no corresponding test file.
  Write tests BEFORE touching these files. Refactoring without tests is guessing.

  | File | Priority | Suggested test file |
  |------|----------|---------------------|
  | src/x.py | P1 | tests/test_x.py |

  ---

  ## Security Fix Stubs

  For each P0 security finding, show the exact pattern change:

  ### [CWE-89] SQL Injection — src/db/queries.py:47
  Current:
    cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")
  Fix:
    cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
  Why: parameterized queries prevent the user-controlled input from being interpreted as SQL.

  ---

  ## Bug Fix Stubs

  For each P0 confirmed bug from BUG_REPORT.md:

  ### BUG-001 — src/parser.py:87 — parse_nested_dict
  Minimal reproduction (from Hypothesis counterexample):
    parse_nested_dict({"a": 1})
    parse_nested_dict({"b": 2})  # Returns {"a": 1, "b": 2} — incorrect
  Fix:
    Replace `result={}` default with `result=None`.
    Add guard: `if result is None: result = {}`

  ---

  ## Success Metrics

  | Metric | Current | Target | Done |
  |--------|---------|--------|------|
  | P0 confirmed bugs | N | 0 | no |
  | P0 security findings HIGH | N | 0 | no |
  | Circular imports | N | 0 | no |
  | Files with CC above F (25) | N | 0 | no |
  | Files with MI below 65 | N | 0 | no |
  | P0/P1 files with no test coverage | N | 0 | no |

---

## 4. Suggest workflow (standalone invocation only)

After writing the file, print:

  REFACTOR_PLAN.md written to PROJECT_ROOT.

  Recommended execution order:
  1. Fix all P0 items before any refactoring — bugs + security + circular imports
  2. Write missing tests for all P0/P1 files listed in Test Gap Analysis
  3. Run /python-refactor:architecture on P1 clusters to generate GitHub issue RFCs
  4. Implement changes in the topological sequence order
  5. Re-run /python-refactor:measure after each P1 batch to update the baseline
  6. Re-run /python-refactor:hunt-bugs after major refactors to catch regressions

---

## Handoff to orchestrator (when invoked by orchestrator)

After writing REFACTOR_PLAN.md, return ONLY this JSON:

{
  "status": "DONE",
  "plan_path": "PROJECT_ROOT/REFACTOR_PLAN.md",
  "p0_count": N,
  "p1_count": N,
  "p2_count": N,
  "p3_count": N
}
