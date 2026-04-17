---
name: measure
description: Instrument a Python project with static analysis tools and write codebase_metrics.json to .python-refactor/. Runs radon (cyclomatic complexity, maintainability index, Halstead metrics), vulture (dead code), bandit (security patterns), semgrep (OWASP), skylos (taint analysis), and grimp (module coupling graph) in parallel. Raw tool output goes to .python-refactor/tmp/ and is cleaned after aggregation. Invoked automatically by other skills in this suite when codebase_metrics.json is missing. When invoked by the orchestrator, returns a compact JSON handoff instead of a prose summary.
---

# python-refactor: Measure

Produce codebase_metrics.json. This is Phase 1 of the pipeline.

Announce: "Using python-refactor:measure to instrument the codebase."

**Platform note:** This skill uses Claude Code tool names (Bash, Read, Write).
On GitHub Copilot CLI substitute: Bash -> runCommand, Read -> readFile, Write -> writeFile.
Full mapping in references/platform-tools.md.

**Output convention:** All output goes to `.python-refactor/`. See references/output-convention.md.

---

## 0. Scaffolding and check for existing metrics

If OUTPUT_DIR and RUN_ID were provided by the orchestrator, use those values.
Otherwise (standalone invocation), run the scaffolding preamble:

  OUTPUT_DIR="PROJECT_ROOT/.python-refactor"
  RUN_ID=$(date -u +"%Y-%m-%dT%H-%M-%S")
  mkdir -p "$OUTPUT_DIR/tmp" "$OUTPUT_DIR/tests"
  [ -f "$OUTPUT_DIR/.gitignore" ] || echo '*' > "$OUTPUT_DIR/.gitignore"

  # Snapshot pre-existing tool caches for safe cleanup
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

If $OUTPUT_DIR/codebase_metrics.json already exists and is less than 24 hours old:
print "Existing metrics found — loading codebase_metrics.json" and skip to section 4.

## 1. Verify Python project

Use Glob/Bash to confirm at least one of: .py files, pyproject.toml, setup.py, setup.cfg.
If none found: stop and report "No Python project detected at PROJECT_ROOT."

## 2. Install tools

Run as a single command:

  pip install radon vulture bandit semgrep grimp skylos --quiet 2>/dev/null || pip3 install radon vulture bandit semgrep grimp skylos --quiet 2>/dev/null

## 3. Run all tools in parallel

Use Bash to launch all tools with & (background) then wait.
All scratch output goes to $OUTPUT_DIR/tmp/:

  radon cc PROJECT_ROOT -j -a > "$OUTPUT_DIR/tmp/pyr_cc.json" &
  radon mi PROJECT_ROOT -j > "$OUTPUT_DIR/tmp/pyr_mi.json" &
  radon hal PROJECT_ROOT -j > "$OUTPUT_DIR/tmp/pyr_hal.json" &
  radon raw PROJECT_ROOT -j > "$OUTPUT_DIR/tmp/pyr_raw.json" &
  python -m vulture PROJECT_ROOT --min-confidence 70 --sort-by-size 2>/dev/null > "$OUTPUT_DIR/tmp/pyr_vulture.txt" &
  bandit -r PROJECT_ROOT -f json -o "$OUTPUT_DIR/tmp/pyr_bandit.json" -q 2>/dev/null &
  semgrep --config p/python --config p/owasp-top-ten --json -o "$OUTPUT_DIR/tmp/pyr_semgrep.json" PROJECT_ROOT --quiet 2>/dev/null || semgrep --config auto --json -o "$OUTPUT_DIR/tmp/pyr_semgrep.json" PROJECT_ROOT --quiet 2>/dev/null || echo '{"results":[],"errors":["semgrep registry unreachable"]}' > "$OUTPUT_DIR/tmp/pyr_semgrep.json" &
  skylos PROJECT_ROOT --json 2>/dev/null > "$OUTPUT_DIR/tmp/pyr_skylos.json" &
  python -c "
import grimp, json, sys
try:
    graph = grimp.build_graph('PACKAGE_NAME')
    deps = {m: list(graph.find_modules_directly_imported_by(m)) for m in graph.modules}
    json.dump({'adjacency': deps}, open('$OUTPUT_DIR/tmp/pyr_deps.json','w'))
except Exception as e:
    json.dump({'adjacency': {}, 'error': str(e)}, open('$OUTPUT_DIR/tmp/pyr_deps.json','w'))
" &
  wait

Replace PROJECT_ROOT with the actual path and PACKAGE_NAME with the detected importable
package name. Detect PACKAGE_NAME using this priority:

  1. pyproject.toml [project.name] or [tool.poetry.name]
  2. src-layout: look for src/<name>/__init__.py — if found, PACKAGE_NAME is <name>
     (grimp resolves src-layout automatically when run from PROJECT_ROOT)
  3. Flat layout: look for <name>/__init__.py at the project root
  4. Fallback: skip grimp and note "could not detect package name for dependency graph"

If any tool is not installed or fails: continue without it, note the gap in the summary.

## 4. Aggregate into codebase_metrics.json

Read each $OUTPUT_DIR/tmp/pyr_*.json file. Parse vulture text output into structured records:
  each line "path:LINE: TYPE 'NAME' (confidence N%)" becomes
  {"file": "path", "line": LINE, "type": "unused_function|unused_class|unused_import", "confidence": N}

Compute summary fields:
  total_files: count of .py files
  total_sloc: sum of raw_metrics SLOC values
  avg_cyclomatic_complexity: mean CC score across all functions
  avg_maintainability_index: mean MI score across all files
  security_findings: count bandit results by severity (HIGH/MEDIUM/LOW)
  dead_code_items: total vulture findings above 70% confidence
  circular_imports: list any cycles found in grimp adjacency output

Write TWO copies — canonical (for inter-skill discovery) and archive (for audit trail):

  Canonical: $OUTPUT_DIR/codebase_metrics.json (always overwritten)
  Archive:   $OUTPUT_DIR/codebase_metrics_$RUN_ID.json

Both contain identical content:
{
  "project": "PROJECT_ROOT",
  "generated_at": "ISO8601_TIMESTAMP",
  "run_id": "$RUN_ID",
  "summary": {
    "total_files": N, "total_sloc": N,
    "avg_cyclomatic_complexity": N.N, "avg_maintainability_index": N.N,
    "security_findings": {"HIGH": N, "MEDIUM": N, "LOW": N},
    "dead_code_items": N, "circular_imports": []
  },
  "complexity": FROM_pyr_cc,
  "maintainability": FROM_pyr_mi,
  "halstead": FROM_pyr_hal,
  "raw_metrics": FROM_pyr_raw,
  "dead_code": PARSED_vulture,
  "security_bandit": FROM_pyr_bandit,
  "security_semgrep": FROM_pyr_semgrep,
  "security_skylos": FROM_pyr_skylos,
  "dependency_graph": FROM_pyr_deps
}

## 4a. Clean scratch files

After aggregation, delete all scratch files:

  rm -f "$OUTPUT_DIR"/tmp/pyr_*

The tmp/ directory itself is kept (other skills may use it).

## 5a. When invoked standalone — show summary table

Print a markdown summary table:

| Metric                      | Value | Status                       |
|-----------------------------|-------|------------------------------|
| Files analyzed              | N     |                              |
| Avg cyclomatic complexity   | N.N   | A=green / B=yellow / C-F=red |
| Avg maintainability index   | N.N   | >85=green / 65-85=yellow / <65=red |
| Security findings HIGH      | N     | red if > 0                   |
| Security findings MEDIUM    | N     | yellow if > 0                |
| Dead code items             | N     |                              |
| Circular imports            | N     | red if > 0                   |

Print: "Output written to $OUTPUT_DIR/codebase_metrics.json"

List the top 3 risk signals (highest severity x complexity product).

Then suggest next steps:
  Run /python-refactor:hunt-bugs to find real runtime bugs via exploration and Hypothesis
  Run /python-refactor:architecture to identify module deepening opportunities
  Run /python-refactor:plan-refactor to generate a full prioritized refactor roadmap
  Or run /python-refactor:orchestrate to chain all phases automatically
  Run /python-refactor:cleanup to remove all plugin output when done

## 5b. When invoked by orchestrator — return JSON handoff only

Return this JSON and nothing else:
{
  "status": "DONE",
  "metrics_path": "$OUTPUT_DIR/codebase_metrics.json",
  "top_risk_signals": [
    {"file": "...", "type": "...", "severity": "HIGH|MEDIUM|LOW", "evidence": "CC=F/28, MI=42"}
  ],
  "circular_imports": [],
  "high_cc_files": ["src/service.py (CC=F/32)", "src/parser.py (CC=D/18)"],
  "security_high_count": N,
  "security_medium_count": N,
  "avg_cc": N.N,
  "avg_mi": N.N
}
