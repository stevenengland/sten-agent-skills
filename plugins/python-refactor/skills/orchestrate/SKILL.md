---
name: orchestrate
description: Full python-refactor pipeline orchestrator. Chains measure, hunt-bugs, architecture, and plan-refactor in strict sequence using isolated subagents. Each phase receives only a compact JSON handoff from the previous phase — never the full session history. This prevents context rot across a long pipeline. After all phases complete, files a single summary issue with collapsible detail sections, then cleans up all temporary and deliverable files for this run. All output goes to .python-refactor/ at the project root. Use when the user says "analyze this codebase", "full refactor analysis", "find all issues", or invokes /python-refactor:orchestrate directly.
---

# python-refactor: Orchestrate

You are the **controller**. You coordinate — you never implement directly.

Core isolation rule (Superpowers subagent-driven-development pattern): Each phase runs in a
**fresh subagent with exactly the context it needs and nothing more**. Your own context stays
clean. Subagents signal completion via a compact JSON handoff — you pass only those fields
forward. Raw tool outputs, exploration logs, and full JSON files never cross phase boundaries.

Announce: "Using python-refactor:orchestrate to run the full analysis pipeline."

**Output convention:** All output goes to `.python-refactor/`. See references/output-convention.md.

---

## Phase 0: Confirm project root and scaffold output directory

Use Bash to verify this is a Python project:

  find . -maxdepth 3 -name "pyproject.toml" -o -name "setup.py" -o -name "setup.cfg" -o -name "*.py" | head -10

If no Python files found: stop and tell the user this suite requires a Python project.
Otherwise record PROJECT_ROOT (usually ".").

Scaffold the output directory and generate run metadata:

  OUTPUT_DIR="PROJECT_ROOT/.python-refactor"
  RUN_ID=$(date -u +"%Y-%m-%dT%H-%M-%S")
  mkdir -p "$OUTPUT_DIR/tmp" "$OUTPUT_DIR/tests"

  # Self-ignoring .gitignore
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

Record OUTPUT_DIR and RUN_ID — you will pass both to every subagent.

---

## Phase 1 — Measure (dispatch isolated subagent)

Create a TodoWrite item: "Phase 1: Measure — run static analysis, write codebase_metrics.json"

Dispatch a fresh subagent using the Agent tool. Pass ONLY this brief — nothing else:

```
PROJECT_ROOT: <value>
OUTPUT_DIR: <value>
RUN_ID: <value>

You are a measurement subagent. Invoke the Skill tool with skill name "python-refactor:measure".
Follow that skill exactly for PROJECT_ROOT. Use OUTPUT_DIR and RUN_ID as provided — do NOT
generate your own. The output directory and manifest already exist.

When the skill completes, return ONLY this JSON — no prose, no summaries:
{
  "status": "DONE",
  "metrics_path": "<OUTPUT_DIR>/codebase_metrics.json",
  "top_risk_signals": [
    {"file": "...", "type": "...", "severity": "HIGH|MEDIUM|LOW", "evidence": "..."}
  ],
  "circular_imports": [],
  "high_cc_files": ["src/x.py (CC=F/28)"],
  "security_high_count": 0,
  "security_medium_count": 0,
  "avg_cc": 0.0,
  "avg_mi": 0.0
}
```

Wait for status DONE. Mark Phase 1 todo complete.

---

## Phase 2 — Bug Hunt (dispatch isolated subagent)

Create a TodoWrite item: "Phase 2: Bug Hunt — organic exploration + Hypothesis PBT"

Dispatch a fresh subagent. Pass ONLY this brief — do NOT include the full metrics JSON:

```
PROJECT_ROOT: <value>
OUTPUT_DIR: <value>
RUN_ID: <value>
HIGH_SIGNAL_FILES: <high_cc_files from Phase 1 handoff>
TOP_RISK_SIGNALS: <top_risk_signals from Phase 1 handoff>

You are a bug hunting subagent. Invoke the Skill tool with skill name "python-refactor:hunt-bugs".
Follow that skill exactly. Use OUTPUT_DIR and RUN_ID as provided — do NOT generate your own.
HIGH_SIGNAL_FILES and TOP_RISK_SIGNALS are your starting orientation.

When the skill completes, return ONLY this JSON:
{
  "status": "DONE",
  "confirmed_bugs": [
    {"id": "BUG-001", "file": "...", "line": 0, "function": "...",
     "type": "...", "impact": "HIGH|MEDIUM|LOW",
     "reproduction": "...", "fix_sketch": "..."}
  ],
  "test_files_written": [],
  "unconfirmed_count": 0,
  "false_alarm_count": 0
}
```

Wait for status DONE. Mark Phase 2 todo complete.

---

## Phase 3 — Architecture (dispatch isolated subagent)

Create a TodoWrite item: "Phase 3: Architecture — identify deepening candidates"

Dispatch a fresh subagent. Pass ONLY:

```
PROJECT_ROOT: <value>
OUTPUT_DIR: <value>
RUN_ID: <value>
HIGH_CC_FILES: <high_cc_files from Phase 1>
CIRCULAR_IMPORTS: <circular_imports from Phase 1>
CONFIRMED_BUGS_SUMMARY: <confirmed_bugs array from Phase 2 — id/file/type/impact only>

You are an architecture subagent. Invoke the Skill tool with skill name "python-refactor:architecture".
Follow that skill exactly. Use OUTPUT_DIR and RUN_ID as provided — do NOT generate your own.
In this pipeline context:
- Produce architecture candidates only — do NOT create issues yet.
- The orchestrator will handle issue creation in a separate step.

When the skill completes, return ONLY this JSON:
{
  "status": "DONE",
  "architecture_candidates": [
    {"id": "ARCH-001", "cluster": ["src/a.py", "src/b.py"],
     "coupling_type": "cross-layer-up",
     "evidence": "CC=F/32, MI=48, fanout=12",
     "bug_connection": "BUG-001 hides here due to shared state",
     "deepening_opportunity": "one-sentence description"}
  ]
}
```

Wait for status DONE. Mark Phase 3 todo complete.

---

## Phase 4 — Plan (dispatch isolated subagent)

Create a TodoWrite item: "Phase 4: Plan — generate REFACTOR_PLAN"

Dispatch a fresh subagent. Pass ONLY:

```
PROJECT_ROOT: <value>
OUTPUT_DIR: <value>
RUN_ID: <value>
METRICS_SUMMARY: {avg_cc: <value>, avg_mi: <value>, security_high: <value>, security_medium: <value>, circular_imports: <list>}
CONFIRMED_BUGS: <confirmed_bugs from Phase 2>
ARCHITECTURE_CANDIDATES: <architecture_candidates from Phase 3>

You are a refactor planning subagent. Invoke the Skill tool with skill name "python-refactor:plan-refactor".
Follow that skill exactly. Use OUTPUT_DIR and RUN_ID as provided — do NOT generate your own.
The skill will read codebase_metrics.json directly from OUTPUT_DIR for security finding details.
CONFIRMED_BUGS and ARCHITECTURE_CANDIDATES are pre-triaged inputs — incorporate them into the plan.

When the skill completes, return ONLY this JSON:
{
  "status": "DONE",
  "plan_path": "<OUTPUT_DIR>/REFACTOR_PLAN_<RUN_ID>.md",
  "p0_count": 0,
  "p1_count": 0,
  "p2_count": 0,
  "p3_count": 0
}
```

Wait for status DONE. Mark Phase 4 todo complete.

---

## Phase 5 — File summary issue

Create a TodoWrite item: "Phase 5: File summary issue"

Read the deliverables from $OUTPUT_DIR:
  - $OUTPUT_DIR/BUG_REPORT_$RUN_ID.md
  - $OUTPUT_DIR/REFACTOR_PLAN_$RUN_ID.md

Compose an issue body with the summary table at the top and collapsible full content
for each deliverable. Use the architecture_candidates from Phase 3 handoff (already in memory).

Issue body structure:

```
## python-refactor analysis — $RUN_ID

| Phase | Findings |
|-------|----------|
| Measure | avg CC: X.X / avg MI: X.X / HIGH security: N |
| Bug Hunt | N confirmed bugs |
| Architecture | N deepening candidates |
| Plan | P0:N  P1:N  P2:N  P3:N |

<details><summary>Bug Report (N confirmed bugs)</summary>

(full BUG_REPORT_$RUN_ID.md content)

</details>

<details><summary>Refactor Plan (P0:N P1:N P2:N P3:N)</summary>

(full REFACTOR_PLAN_$RUN_ID.md content)

</details>

<details><summary>Architecture Candidates (N)</summary>

(formatted architecture_candidates from Phase 3 handoff)

</details>
```

Use the project's issue tracker CLI to create the issue. For example:

  gh issue create \
    --title "python-refactor analysis — $RUN_ID" \
    --label "refactor,analysis" \
    --body "$ISSUE_BODY"

Adapt the command for the available CLI tool (e.g. `gh`, `glab`). If no CLI is available, present the formatted issue body for manual creation.

Capture the issue URL from the command output.

If the CLI call fails (not authenticated, no remote repo, etc.):
  Print: "Could not file issue — deliverables retained in $OUTPUT_DIR"
  Skip Phase 6 cleanup of deliverables (only clean tmp/ and tool caches).
  Proceed to Final summary showing file paths instead of issue URL.

Mark Phase 5 todo complete.

---

## Phase 6 — Cleanup

Create a TodoWrite item: "Phase 6: Cleanup temporary files"

Read $OUTPUT_DIR/manifest.json to get pre_existing list.

Delete this run’s files from $OUTPUT_DIR:
  rm -f "$OUTPUT_DIR/codebase_metrics_$RUN_ID.json"
  rm -f "$OUTPUT_DIR/codebase_metrics.json"
  rm -f "$OUTPUT_DIR/BUG_REPORT_$RUN_ID.md"
  rm -f "$OUTPUT_DIR/REFACTOR_PLAN_$RUN_ID.md"
  rm -f "$OUTPUT_DIR"/tests/test_pyr_hunt_*_$RUN_ID.py
  rm -rf "$OUTPUT_DIR/tmp"
  rm -f "$OUTPUT_DIR/manifest.json"

Delete project-root tool caches NOT in the pre_existing list:
  For each of .hypothesis, .pytest_cache, .semgrep, .skylos_cache:
    If the directory exists at PROJECT_ROOT AND is NOT in pre_existing:
      rm -rf "PROJECT_ROOT/$d"

If $OUTPUT_DIR is now empty (no files from other runs):
  rm -rf "$OUTPUT_DIR"

Mark Phase 6 todo complete.

---

## Final: Present summary

Present a clean status table — do NOT reproduce the detailed findings:

```
python-refactor pipeline complete

Phase           Output                    Findings
1  Measure      (cleaned)                 avg CC: X.X / avg MI: X.X / HIGH security: N
2  Bug Hunt     (cleaned)                 N confirmed bugs
3  Architecture (handoff only)            N deepening candidates identified
4  Plan         (cleaned)                 P0:N  P1:N  P2:N  P3:N
5  Issue        <ISSUE_URL>               Summary + full reports filed
6  Cleanup      Done                      Temporary files removed

All findings are preserved in the issue: <ISSUE_URL>

Next steps:
  Fix all P0 items before any refactoring (bugs + security + circular imports)
  Write missing tests for P0/P1 modules — see Test Gap Analysis in the issue
  Run /python-refactor:architecture to generate issue RFCs for P1 clusters
  Re-run /python-refactor:measure after each P1 completion to update baseline
  Re-run /python-refactor:hunt-bugs after major refactors to catch regressions
```

If issue filing failed, show file paths in $OUTPUT_DIR instead of issue URL.
