# python-refactor

Agentic Python codebase analysis suite for **Claude Code** and **GitHub Copilot CLI**.

Installs as a proper plugin on **both platforms** using the same `plugin.json` manifest.
Once installed, skills are invoked with the `/python-refactor:` namespace prefix — exactly
like Superpowers' `/superpowers:` prefix — on both Claude Code and Copilot CLI.

Modelled on the Superpowers subagent-driven-development pattern: each skill announces
itself, uses TodoWrite for progress, dispatches fresh isolated subagents per phase,
and passes only compact JSON handoffs between phases to prevent context rot.

---

## Repository Structure

This plugin lives inside `STEN-AGENT-SKILLS`, a mono-repo that hosts both standalone
skills (top-level `skills/`) and installable plugins (`plugins/`).

```
STEN-AGENT-SKILLS/                       ← Repo root
│
├── plugins/
│   └── python-refactor/                 ← This plugin
│       │
│       ├── plugin.json                  ← Plugin manifest (BOTH platforms)
│       │                                  Declares name "python-refactor" →
│       │                                  creates /python-refactor: namespace
│       │
│       ├── hooks.json                   ← Hooks placeholder (empty)
│       │
│       ├── marketplace.json             ← Self-hosted marketplace descriptor
│       │   (referenced as               ← Enables: copilot plugin marketplace add
│       │    .github/plugin/ by host)       OWNER/STEN-AGENT-SKILLS
│       │
│       ├── skills/                      ← All plugin skills
│       │   ├── orchestrate/
│       │   │   └── SKILL.md            ← /python-refactor:orchestrate
│       │   │                             Full pipeline controller. Chains all four
│       │   │                             phases via isolated subagents. Files a
│       │   │                             GitHub summary issue, then cleans up.
│       │   │
│       │   ├── measure/
│       │   │   └── SKILL.md            ← /python-refactor:measure
│       │   │                             Runs radon, vulture, bandit, semgrep,
│       │   │                             skylos, grimp in parallel.
│       │   │                             Writes codebase_metrics.json.
│       │   │
│       │   ├── hunt-bugs/
│       │   │   └── SKILL.md            ← /python-refactor:hunt-bugs
│       │   │                             Phase 1: Organic exploration of high-signal
│       │   │                             files with step-by-step reasoning.
│       │   │                             Phase 2: Hypothesis PBT to confirm bugs.
│       │   │                             Writes BUG_REPORT + test files.
│       │   │
│       │   ├── architecture/
│       │   │   └── SKILL.md            ← /python-refactor:architecture
│       │   │                             Organic deep-module analysis. Parallel
│       │   │                             subagents design multiple interfaces.
│       │   │                             Creates GitHub issue RFCs via gh CLI.
│       │   │
│       │   ├── plan-refactor/
│       │   │   └── SKILL.md            ← /python-refactor:plan-refactor
│       │   │                             P0-P3 triage, topological execution
│       │   │                             sequence, bug/security fix stubs,
│       │   │                             test gap analysis.
│       │   │                             Writes REFACTOR_PLAN.
│       │   │
│       │   └── cleanup/
│       │       └── SKILL.md            ← /python-refactor:cleanup
│       │                                 Removes .python-refactor/ and all
│       │                                 project-root tool caches.
│       │
│       ├── references/
│       │   ├── platform-tools.md       ← Claude Code → Copilot CLI tool name map
│       │   └── output-convention.md    ← Output directory layout and cleanup rules
│       │
│       └── README.md                   ← This file
│
├── skills/                              ← Standalone skills (no namespace, flat install)
│   └── ...                             ← Other individual skills in the repo
│
├── .gitignore
├── README.md                            ← Repo-level readme
└── SOURCES.md
```

### Output files written to `.python-refactor/` (at analysis time)

All output is written to a `.python-refactor/` directory at the project root. This directory
contains a `.gitignore` with `*` so nothing is ever committed. Each run uses a timestamped
suffix (RUN_ID) to distinguish files across multiple invocations.

```
your-python-project/
└── .python-refactor/                       ← git-ignored (self-ignoring .gitignore)
    ├── .gitignore                          ← contains "*"
    ├── manifest.json                       ← run metadata + pre-existence snapshot
    ├── tmp/                                ← raw tool scratch (cleaned by measure)
    │   └── pyr_*.json                      ← radon, bandit, semgrep, skylos, grimp
    ├── codebase_metrics.json               ← canonical (latest, always overwritten)
    ├── codebase_metrics_<RUN_ID>.json      ← archive copy
    ├── BUG_REPORT_<RUN_ID>.md              ← Written by: hunt-bugs
    ├── REFACTOR_PLAN_<RUN_ID>.md           ← Written by: plan-refactor
    └── tests/
        └── test_pyr_hunt_*_<RUN_ID>.py     ← Written by: hunt-bugs (Hypothesis tests)
```

When run via the orchestrator, all deliverables are filed as a GitHub issue and then
cleaned up automatically. See references/output-convention.md for full details.

---

## How the namespace works

The `name` field in `plugin.json` (`"python-refactor"`) is automatically used by both
Claude Code and Copilot CLI as a command prefix for all skills in the plugin:

```
Plugin name:   python-refactor
Skill folder:  orchestrate      →  /python-refactor:orchestrate
Skill folder:  measure          →  /python-refactor:measure
Skill folder:  hunt-bugs        →  /python-refactor:hunt-bugs
Skill folder:  architecture     →  /python-refactor:architecture
Skill folder:  plan-refactor    →  /python-refactor:plan-refactor
Skill folder:  cleanup          →  /python-refactor:cleanup
```

> ⚠️ The `name` field inside each `SKILL.md` must be plain kebab-case with **no prefix**.
> The platform adds the prefix automatically. Writing `python-refactor:orchestrate` in the
> `name` field causes the skill to silently fail to load on both platforms.

---

## Install — GitHub Copilot CLI

GitHub Copilot CLI only supports plugins via a registered marketplace —
direct install from a local path or `OWNER/REPO:PATH` is no longer
supported.

```bash
# Register the marketplace (once per machine)
copilot plugin marketplace add stevenengland/sten-agent-skills

# Browse available plugins
copilot plugin marketplace browse sten-agent-skills-marketplace

# Install
copilot plugin install python-refactor@sten-agent-skills-marketplace
```

### Verify

```bash
copilot plugin list
# → python-refactor  3.0.0

/python-refactor:measure
```

---

## Install — Claude Code

Claude Code discovers plugins via the repo-level `.claude-plugin/marketplace.json`.

```
# Register the marketplace (once)
/plugin marketplace add stevenengland/sten-agent-skills

# Install
/plugin install python-refactor@sten-agent-skills
```

### Project-scoped (auto-discovered)

Copy the plugin into the project you want to analyze:

```bash
cp -r plugins/python-refactor /path/to/your-python-project/.claude/plugins/python-refactor
```

Claude Code discovers and loads it automatically. Reload if already running:

```
/reload-plugins
```

### Verify

```
/reload-plugins
/python-refactor:measure
```

---

## Standalone fallback (no namespace, from root `skills/`)

If you want to install individual skills from the repo's top-level `skills/` folder
without the plugin system (flat `/skillname` invocation, no namespace):

```bash
# Claude Code (personal)
mkdir -p ~/.claude/skills
cp -r skills/some-skill ~/.claude/skills/

# Copilot CLI (personal)
mkdir -p ~/.copilot/skills
cp -r skills/some-skill ~/.copilot/skills/
```

The `python-refactor` plugin is **not** duplicated in `skills/` — it lives exclusively
under `plugins/python-refactor/` and is installed via the plugin system above to get
the `/python-refactor:` namespace.

---

## Usage

### Full pipeline (recommended)

```
/python-refactor:orchestrate
```

Chains all four phases via isolated subagents:
1. **measure** — runs all static analysis tools, writes `codebase_metrics.json` to `.python-refactor/`
2. **hunt-bugs** — explores high-signal files, runs Hypothesis PBT, writes `BUG_REPORT` to `.python-refactor/`
3. **architecture** — identifies deep-module candidates, cross-references confirmed bugs
4. **plan-refactor** — triages all findings, sequences by dependency graph, writes `REFACTOR_PLAN` to `.python-refactor/`
5. **file issue** — creates a single GitHub issue with collapsible full content of all deliverables
6. **cleanup** — deletes all temporary files and deliverables from `.python-refactor/`

Each phase subagent receives only the compact JSON handoff from the previous phase.
Your session context stays clean throughout.

### Individual skills

```
/python-refactor:measure           # Just instrument — useful for a quick baseline
/python-refactor:hunt-bugs         # Bug hunt only — auto-runs measure if needed
/python-refactor:architecture      # Architecture review — presents candidates, creates GitHub RFCs
/python-refactor:plan-refactor     # Refactor plan only — auto-runs measure, incorporates bug report
/python-refactor:cleanup           # Remove all .python-refactor/ output and tool caches
```

---

## How the pipeline prevents context rot

Each phase in the orchestrator runs as a **fresh isolated subagent** — it never inherits
the controller's session history or the previous phase's raw output. The controller passes
only a compact JSON handoff:

```
Phase 1 (measure)      →  handoff: top_risk_signals, high_cc_files,
                                    circular_imports, security counts

Phase 2 (hunt-bugs)    →  handoff: confirmed_bugs array
                           (id / file / line / type / impact / fix_sketch)

Phase 3 (architecture) →  handoff: architecture_candidates array

Phase 4 (plan-refactor) ←  consumes all three handoffs +
                            reads codebase_metrics.json from .python-refactor/ directly

Phase 5 (file issue)   →  files single GitHub issue with collapsible detail sections

Phase 6 (cleanup)      →  deletes .python-refactor/ and plugin-created tool caches
```

The full `codebase_metrics.json` is never forwarded between phases — only distilled signals.
All intermediate and deliverable files live in `.python-refactor/` and are cleaned after
the summary issue is filed. This is the same isolation pattern used by Superpowers'
subagent-driven-development skill.

---

## Dimensions covered

| Dimension                     | Skill         | Tools                                |
|-------------------------------|---------------|--------------------------------------|
| Cyclomatic complexity         | measure       | radon cc                             |
| Maintainability index         | measure       | radon mi                             |
| Halstead complexity           | measure       | radon hal                            |
| Dead code                     | measure       | vulture, skylos                      |
| Security patterns (OWASP)     | measure, plan | bandit, semgrep                      |
| Taint analysis (SSRF, SQLi)   | measure       | skylos                               |
| Module coupling graph         | measure, plan | grimp                                |
| Real logic bugs               | hunt-bugs     | Hypothesis + organic exploration     |
| Architecture smells           | architecture  | organic exploration + metrics        |
| Refactor sequencing           | plan-refactor | topological sort on dependency graph |

---

## Platform differences

| Feature                  | Claude Code (Plugin) | Copilot CLI (Plugin) |
|--------------------------|----------------------|----------------------|
| Plugin install command   | `claude /plugin install ./plugins/python-refactor` | `copilot plugin install ./plugins/python-refactor` |
| Namespaced commands      | `/python-refactor:measure` | `/python-refactor:measure` |
| Skill tool invocation    | `Skill` tool         | `skill` tool             |
| Shell commands           | `Bash`               | `runCommand`             |
| File reads               | `Read`               | `readFile`               |
| Parallel subagents       | `Agent` tool         | `spawnSubagent`          |
| Reload without restart   | `/reload-plugins`    | `/skills reload`         |
| Cleanup                  | `/python-refactor:cleanup` | `/python-refactor:cleanup` |

> Skills use Claude Code tool names throughout. On Copilot CLI, substitute as shown
> in `references/platform-tools.md`.

---

## Requirements

- Python 3.10+
- pip or pip3
- gh CLI (for GitHub issue creation in the `architecture` skill)
- Claude Code (latest) **or** GitHub Copilot CLI

Tools installed automatically on first run:
`radon`, `vulture`, `bandit`, `semgrep`, `grimp`, `skylos`, `hypothesis`, `pytest`
