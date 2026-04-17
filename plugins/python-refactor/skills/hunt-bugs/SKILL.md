---
name: hunt-bugs
description: Actively hunt real bugs in a Python codebase using two phases. Phase 1 is free agentic organic exploration guided by static metrics — the agent reads high-signal files completely, reasons step-by-step through logic errors, Python footguns, semantic drift, and integration failures, and builds a candidate list. Phase 2 uses Hypothesis property-based testing to confirm and reproduce each candidate. Outputs BUG_REPORT_<RUN_ID>.md and Hypothesis test files to .python-refactor/. Auto-runs python-refactor:measure if codebase_metrics.json is missing. When invoked by the orchestrator, returns a compact JSON handoff.
---

# python-refactor: Hunt Bugs

Find real bugs through organic exploration and Hypothesis property-based testing.

Announce: "Using python-refactor:hunt-bugs to hunt real bugs via exploration and PBT."

**Skill type: Rigid.** Follow exactly. The discipline is the point.

**Platform note:** Claude Code tool names used throughout.
On Copilot CLI: Bash -> runCommand, Read -> readFile, Write -> writeFile.

**Output convention:** All output goes to `.python-refactor/`. See references/output-convention.md.

**Research basis:** Agentic PBT (Maaz et al., NeurIPS 2025, Anthropic + Northeastern).
An agent crawls code, infers invariants from code and docstrings, writes Hypothesis tests, runs
them in a self-reflective validation loop. Result: 56% of generated bug reports were valid bugs;
86% of top-ranked reports confirmed. Bugs found in NumPy, pandas, AWS SDKs at ~$10/valid bug.

---

## 0. Scaffolding and load baseline

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

Check for $OUTPUT_DIR/codebase_metrics.json.
If present: load summary fields (avg_cc, avg_mi, complexity, halstead, maintainability).
If missing: invoke Skill tool with skill name "python-refactor:measure" first, then continue.

---

## Phase 1: Free Organic Exploration

You are a security researcher reading this codebase for the first time. Your job is to
**experience** the code, not scan it. Mechanical checklist execution produces false alarms.
Genuine curiosity produces confirmed bugs.

### 1a. Rank files by composite signal

Compute per-file: CC_score x (100 minus MI_score) x halstead_difficulty.
Rank descending. These are your starting files.
Also add any files listed in circular_imports — initialization-order bugs hide there.

### 1b. Read each file completely before forming any hypothesis

This is not optional. Partial reads cause false alarms. Read the whole file.
Only after reading completely, reason through these dimensions one at a time:

**LOGIC BUGS — reason about control flow:**

Mutable default arguments: look for def f(x=[], result={}, cache=set()).
Python creates default value objects exactly once at function definition time.
These objects accumulate state across all calls. Two calls with different inputs
share the same default object. This is almost never what the author intended.

Bare except clauses: look for except: pass or except Exception: pass with no logging.
Exceptions swallowed here become silent wrong results or phantom state corruption.

In-place mutation: does the function modify its input arguments?
Check: does it assign to input_arg[key] or input_arg.append() without documenting mutation?
Callers that expect immutable inputs will see corrupted state.

None dereference: trace every method call or attribute access. Is it possible for the
object to be None at that point? Especially after optional chaining, dict.get(), or
conditional assignment.

Float equality: any `==` comparison involving float values is suspect.
Division, multiplication, and accumulation all introduce floating point error.

Async shared state: in async functions, any mutable object accessed from multiple coroutines
without asyncio.Lock is a race condition waiting for scale.

**SEMANTIC BUGS — reason about specification:**

Read the docstring. Now read the implementation. Do they describe the same behavior?
Specification drift accumulates silently over time and is only found by reading both.

Scan return statements. Does every branch return a value of the same type?
A function that sometimes returns None and sometimes returns a list causes TypeErrors
in callers that don't expect None.

Does the function name imply pure, stateless behavior (get_, compute_, calculate_)?
If so, does it have side effects — file writes, global mutations, network calls?
Hidden side effects make functions impossible to test in isolation.

**INTEGRATION BUGS — reason about lifecycle:**

Look for open(), socket.connect(), db.cursor() not paired with a context manager or close().
These leak resources and cause intermittent failures at scale.

Find encode/serialize calls. Find the matching decode/deserialize. Call them in sequence
mentally: does roundtrip(x) == x for all valid x? Type conversions and encoding assumptions
break this silently.

Are there functions that must be called in a specific order? Is that order documented?
Is it enforced? Unenforced call-order assumptions are integration time bombs.

**PYTHON FOOTGUNS — reason about language traps:**

`x is "string"` — identity comparison works by accident on short strings due to interning.
Change the string and the comparison silently changes behavior.

Late-binding closures: [lambda: i for i in range(3)] — all three lambdas capture the same
variable i. When called, they all return the final value. This surprises most Python developers.

String percent-formatting on a tuple: "%s" % ("a", "b") raises TypeError at runtime.
The correct form is "%s %s" % ("a", "b"). This fails silently in test suites with mocking.

Mutable objects as dict keys or set members: lists, dicts, and other unhashable types
raise TypeError at insertion, but only when the code path is actually exercised.

### 1c. Build the candidate list

For each suspected bug, document:

  CANDIDATE N
  File: path/to/file.py:LINE
  Function: function_name
  Type: logic | semantic | integration | footgun
  Reasoning: step-by-step explanation of WHY this is a bug, not just what it is.
              Explain the mechanism. What state does it corrupt? What invariant does it break?
  Confidence: HIGH | MEDIUM | LOW
  Testable property: state the invariant that must hold as a falsifiable assertion.
                     Example: "Two independent calls with different inputs must never share result state."

Stop when you have 5 to 15 candidates, or when all high-signal files are covered.

---

## Phase 2: Property-Based Testing with Hypothesis

Install if needed: pip install hypothesis pytest --quiet

For each HIGH or MEDIUM confidence candidate, write a property test that expresses the
testable property from the candidate record.

Save all tests to: $OUTPUT_DIR/tests/test_pyr_hunt_MODULENAME_$RUN_ID.py

Test structure — follow this pattern:

  from hypothesis import given, settings, HealthCheck
  from hypothesis import strategies as st
  from src.module import target_function

  @given(STRATEGY_FOR_INPUT)
  @settings(max_examples=200, suppress_health_check=[HealthCheck.too_slow])
  def test_INVARIANT_NAME(input_value):
      # Invariant: restate the testable property from the candidate record
      ASSERTION_EXPRESSING_THE_INVARIANT

Strategy selection guide:
  Primitives: st.text(), st.integers(), st.floats(allow_nan=False), st.booleans()
  Collections: st.lists(st.integers()), st.dictionaries(st.text(), st.integers())
  Optional values: st.one_of(st.none(), st.integers())
  Domain objects: st.builds(MyClass, field=st.integers())
  Filter invalid inputs: st.assume(condition) — not try/except — inside the test body

Run: pytest $OUTPUT_DIR/tests/test_pyr_hunt_*$RUN_ID.py -v --tb=short

**For each failing test:**

1. Read the Hypothesis counterexample carefully — it is the minimal input that falsifies the invariant.
2. Verify manually: is this a real bug, or a test assumption error?
3. Classify: CONFIRMED BUG | FALSE ALARM | SPEC AMBIGUITY
4. For CONFIRMED BUG: write the minimal reproduction case — the simplest possible input.

**Self-validation questions for each CONFIRMED BUG:**
- Is this code path reachable in normal production usage?
- Impact category: data corruption | crash | silent wrong result | security vulnerability
- Is there already a test in the suite that should catch this but does not?

---

## Output

Write $OUTPUT_DIR/BUG_REPORT_$RUN_ID.md with these sections:

  # Bug Report — PROJECT_NAME
  Generated: ISO8601 by python-refactor:hunt-bugs

  ## Confirmed Bugs (N total)

  ### BUG-001 — Impact: HIGH
  Location: file.py:LINE — function_name
  Type: (type from candidate record)
  Minimal reproduction:
    (exact code to trigger the bug — from Hypothesis counterexample)
  Fix sketch: (one-paragraph description of the correct fix)
  Test: $OUTPUT_DIR/tests/test_pyr_hunt_MODULE_$RUN_ID.py::test_FUNCTION_NAME

  ## Unconfirmed Candidates (N)
  (Candidates Hypothesis did not falsify. Real bugs may exist but require manual review.)

  ## False Alarms (N)
  (Dismissed candidates with brief reason)

  ## Coverage Gap
  (Files in high_cc_files with no test_*.py — bugs suspected but not provable via PBT)

---

## Handoff to orchestrator (when invoked by orchestrator)

After writing the bug report, return ONLY this JSON:

{
  "status": "DONE",
  "confirmed_bugs": [
    {"id": "BUG-001", "file": "...", "line": 0, "function": "...",
     "type": "...", "impact": "HIGH|MEDIUM|LOW",
     "reproduction": "one-line reproduction", "fix_sketch": "one-line fix description"}
  ],
  "test_files_written": ["$OUTPUT_DIR/tests/test_pyr_hunt_MODULE_$RUN_ID.py"],
  "unconfirmed_count": 0,
  "false_alarm_count": 0
}
