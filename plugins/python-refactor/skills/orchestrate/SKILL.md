---
name: orchestrate
description: Full python-refactor pipeline orchestrator. Chains measure, hunt-bugs, architecture, and plan-refactor in strict sequence using isolated subagents. Each phase receives only a compact JSON handoff from the previous phase — never the full session history. This prevents context rot across a long pipeline. Use when the user says "analyze this codebase", "full refactor analysis", "find all issues", or invokes /python-refactor:orchestrate directly.
---

# python-refactor: Orchestrate

You are the **controller**. You coordinate — you never implement directly.

Core isolation rule (Superpowers subagent-driven-development pattern): Each phase runs in a
**fresh subagent with exactly the context it needs and nothing more**. Your own context stays
clean. Subagents signal completion via a compact JSON handoff — you pass only those fields
forward. Raw tool outputs, exploration logs, and full JSON files never cross phase boundaries.

Announce: "Using python-refactor:orchestrate to run the full analysis pipeline."

---

## Phase 0: Confirm project root

Use Bash to verify this is a Python project:

  find . -maxdepth 3 -name "pyproject.toml" -o -name "setup.py" -o -name "setup.cfg" -o -name "*.py" | head -10

If no Python files found: stop and tell the user this suite requires a Python project.
Otherwise record PROJECT_ROOT (usually ".").

---

## Phase 1 — Measure (dispatch isolated subagent)

Create a TodoWrite item: "Phase 1: Measure — run static analysis, write codebase_metrics.json"

Dispatch a fresh subagent using the Agent tool. Pass ONLY this brief — nothing else:

```
PROJECT_ROOT: <value>

You are a measurement subagent. Invoke the Skill tool with skill name "python-refactor:measure".
Follow that skill exactly for PROJECT_ROOT.

When the skill completes, return ONLY this JSON — no prose, no summaries:
{
  "status": "DONE",
  "metrics_path": "<PROJECT_ROOT>/codebase_metrics.json",
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
HIGH_SIGNAL_FILES: <high_cc_files from Phase 1 handoff>
TOP_RISK_SIGNALS: <top_risk_signals from Phase 1 handoff>

You are a bug hunting subagent. Invoke the Skill tool with skill name "python-refactor:hunt-bugs".
Follow that skill exactly. HIGH_SIGNAL_FILES and TOP_RISK_SIGNALS are your starting orientation.

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
HIGH_CC_FILES: <high_cc_files from Phase 1>
CIRCULAR_IMPORTS: <circular_imports from Phase 1>
CONFIRMED_BUGS_SUMMARY: <confirmed_bugs array from Phase 2 — id/file/type/impact only>

You are an architecture subagent. Invoke the Skill tool with skill name "python-refactor:architecture".
Follow that skill exactly. In this pipeline context:
- Produce architecture candidates only — do NOT create GitHub issues yet.
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

Create a TodoWrite item: "Phase 4: Plan — generate REFACTOR_PLAN.md"

Dispatch a fresh subagent. Pass ONLY:

```
PROJECT_ROOT: <value>
METRICS_SUMMARY: {avg_cc: <value>, avg_mi: <value>, security_high: <value>, security_medium: <value>, circular_imports: <list>}
CONFIRMED_BUGS: <confirmed_bugs from Phase 2>
ARCHITECTURE_CANDIDATES: <architecture_candidates from Phase 3>

You are a refactor planning subagent. Invoke the Skill tool with skill name "python-refactor:plan-refactor".
Follow that skill exactly. The skill will read codebase_metrics.json directly for security finding details.
CONFIRMED_BUGS and ARCHITECTURE_CANDIDATES are pre-triaged inputs — incorporate them into the plan.

When the skill completes, return ONLY this JSON:
{
  "status": "DONE",
  "plan_path": "<PROJECT_ROOT>/REFACTOR_PLAN.md",
  "p0_count": 0,
  "p1_count": 0,
  "p2_count": 0,
  "p3_count": 0
}
```

Wait for status DONE. Mark Phase 4 todo complete.

---

## Final: Present summary

Present a clean status table — do NOT reproduce the detailed findings:

```
python-refactor pipeline complete

Phase           Output                    Findings
1  Measure      codebase_metrics.json     avg CC: X.X / avg MI: X.X / HIGH security: N
2  Bug Hunt     BUG_REPORT.md             N confirmed bugs
3  Architecture (handoff only)            N deepening candidates identified
4  Plan         REFACTOR_PLAN.md          P0:N  P1:N  P2:N  P3:N

Next steps:
  Fix all P0 items before any refactoring (bugs + security + circular imports)
  Write missing tests for P0/P1 modules — see Test Gap Analysis in REFACTOR_PLAN.md
  Run /python-refactor:architecture to generate GitHub issue RFCs for P1 clusters
  Re-run /python-refactor:measure after each P1 completion to update baseline
  Re-run /python-refactor:hunt-bugs after major refactors to catch regressions
```
