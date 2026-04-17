# Output Convention

All python-refactor skills write output to a dedicated `.python-refactor/` directory
at the project root. This directory is self-ignoring via an internal `.gitignore` and
is never committed. The orchestrator cleans it after filing a summary issue;
standalone skills leave it for manual cleanup via `/python-refactor:cleanup`.

---

## Directory layout

```
PROJECT_ROOT/
└── .python-refactor/
    ├── .gitignore                          ← contains "*" (self-ignoring)
    ├── manifest.json                       ← run metadata and pre-existence snapshot
    ├── tmp/                                ← raw tool scratch (cleaned by measure)
    │   ├── pyr_cc.json
    │   ├── pyr_mi.json
    │   ├── pyr_hal.json
    │   ├── pyr_raw.json
    │   ├── pyr_vulture.txt
    │   ├── pyr_bandit.json
    │   ├── pyr_semgrep.json
    │   ├── pyr_skylos.json
    │   └── pyr_deps.json
    ├── codebase_metrics.json               ← canonical (always latest, overwritten)
    ├── codebase_metrics_<RUN_ID>.json      ← archive copy
    ├── BUG_REPORT_<RUN_ID>.md              ← bug report
    ├── REFACTOR_PLAN_<RUN_ID>.md           ← refactor plan
    └── tests/
        └── test_pyr_hunt_<MODULE>_<RUN_ID>.py  ← Hypothesis PBT evidence
```

## RUN_ID

A filesystem-safe ISO 8601 timestamp generated once per pipeline or standalone invocation.
Format: `YYYY-MM-DDTHH-MM-SS` (colons replaced with hyphens).

When invoked by the orchestrator: the orchestrator generates RUN_ID in Phase 0 and passes
it to every subagent. All skills in the pipeline share the same RUN_ID.

When invoked standalone: the skill generates its own RUN_ID at startup.

## OUTPUT_DIR

Constant: `PROJECT_ROOT/.python-refactor`

All skills reference this path. Use the shell variable `OUTPUT_DIR` set during scaffolding.

## Scaffolding (Phase 0 preamble)

Every skill must ensure the output directory exists before writing. When invoked by the
orchestrator, the orchestrator handles scaffolding and passes OUTPUT_DIR and RUN_ID.
When invoked standalone, the skill runs this preamble itself:

```bash
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

# Write manifest
cat > "$OUTPUT_DIR/manifest.json" <<MANIFEST
{
  "run_id": "$RUN_ID",
  "pre_existing": $PRE_EXISTING,
  "created_caches": [],
  "deliverables": []
}
MANIFEST
```

## Canonical vs. archive files

Some files are written in two copies:
- **Canonical** (fixed name, always overwritten): used for inter-skill discovery.
  Example: `.python-refactor/codebase_metrics.json`
- **Archive** (timestamped suffix): preserved across runs for audit trail.
  Example: `.python-refactor/codebase_metrics_2026-04-17T14-30-00.json`

Skills always READ from the canonical path. Skills always WRITE both copies.

## Two-tier cleanup

1. **Per-skill scratch cleanup:** Each skill deletes its own `.python-refactor/tmp/` scratch
   files after aggregating them into deliverables. Example: measure deletes `tmp/pyr_*.json`
   after writing `codebase_metrics.json`.

2. **Orchestrator scoped cleanup:** After all phases and issue filing, the orchestrator
   reads `manifest.json`, deletes all files belonging to this `run_id`, and removes
   project-root tool caches not in `pre_existing`. If `.python-refactor/` is empty
   afterward, it removes the directory.

3. **Manual cleanup via /python-refactor:cleanup:** Hard nuke — deletes the entire
   `.python-refactor/` directory and all project-root tool caches regardless of
   pre-existence.

## Tool caches cleaned

Project-root directories cleaned by the orchestrator (if not pre-existing) or by
the cleanup skill (unconditionally):

| Directory | Tool | Notes |
|-----------|------|-------|
| `.hypothesis/` | Hypothesis | Counterexample database |
| `.pytest_cache/` | pytest | Test result cache |
| `.semgrep/` | semgrep | Local rule cache |
| `.skylos_cache/` | skylos | Analysis cache |

Global caches (e.g. `~/.semgrep/`) are never touched.
