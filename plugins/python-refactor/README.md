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
│       ├── hooks.json                   ← SessionStart hook
│       │                                  Injects skill awareness at session start
│       │                                  via additionalContext (Copilot CLI v1.0.11+)
│       │
│       ├── marketplace.json             ← Self-hosted marketplace descriptor
│       │   (referenced as               ← Enables: copilot plugin marketplace add
│       │    .github/plugin/ by host)       OWNER/STEN-AGENT-SKILLS
│       │
│       ├── skills/                      ← All plugin skills
│       │   ├── orchestrate/
│       │   │   └── SKILL.md            ← /python-refactor:orchestrate
│       │   │                             Full pipeline controller. Chains all four
│       │   │                             phases via isolated subagents. Compact JSON
│       │   │                             handoff between phases prevents context rot.
│       │   │
│       │   ├── measure/
│       │   │   └── SKILL.md            ← /python-refactor:measure
│       │   │                             Runs radon, vulture, bandit, semgrep,
│       │   │                             skylos, pydeps in parallel.
│       │   │                             Writes codebase_metrics.json.
│       │   │
│       │   ├── hunt-bugs/
│       │   │   └── SKILL.md            ← /python-refactor:hunt-bugs
│       │   │                             Phase 1: Organic exploration of high-signal
│       │   │                             files with step-by-step reasoning.
│       │   │                             Phase 2: Hypothesis PBT to confirm bugs.
│       │   │                             Writes BUG_REPORT.md + test files.
│       │   │
│       │   ├── architecture/
│       │   │   └── SKILL.md            ← /python-refactor:architecture
│       │   │                             Organic deep-module analysis. Parallel
│       │   │                             subagents design multiple interfaces.
│       │   │                             Creates GitHub issue RFCs via gh CLI.
│       │   │
│       │   └── plan-refactor/
│       │       └── SKILL.md            ← /python-refactor:plan-refactor
│       │                                 P0-P3 triage, topological execution
│       │                                 sequence, bug/security fix stubs,
│       │                                 test gap analysis.
│       │                                 Writes REFACTOR_PLAN.md.
│       │
│       ├── references/
│       │   └── platform-tools.md       ← Claude Code → Copilot CLI tool name map
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

### Output files written to your project root (at analysis time)

```
your-python-project/
├── codebase_metrics.json               ← Written by: measure
├── BUG_REPORT.md                       ← Written by: hunt-bugs
├── REFACTOR_PLAN.md                    ← Written by: plan-refactor
└── tests/
    └── test_pyr_hunt_*.py              ← Written by: hunt-bugs (Hypothesis tests)
```

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
```

> ⚠️ The `name` field inside each `SKILL.md` must be plain kebab-case with **no prefix**.
> The platform adds the prefix automatically. Writing `python-refactor:orchestrate` in the
> `name` field causes the skill to silently fail to load on both platforms.

---

## Install — GitHub Copilot CLI

### Option A: Direct install from the STEN-AGENT-SKILLS repo

Point the install command at the `plugins/python-refactor` subdirectory:

```bash
# From a local clone of STEN-AGENT-SKILLS
copilot plugin install ./plugins/python-refactor

# Or directly from GitHub (installs the plugin subdirectory from the repo)
copilot plugin install stevenengland/sten-agent-skills --plugin-path plugins/python-refactor
```

### Option B: Via marketplace

The `marketplace.json` inside `plugins/python-refactor/` must be referenced by the repo's
`.github/plugin/marketplace.json`. Add a symlink or copy it there once:

```bash
mkdir -p .github/plugin
cp plugins/python-refactor/marketplace.json .github/plugin/marketplace.json
git add .github/plugin/marketplace.json && git commit -m "chore: register python-refactor marketplace"
git push
```

Then from any machine:

```bash
# Register the marketplace (once per machine)
copilot plugin marketplace add stevenengland/sten-agent-skills

# Browse available plugins
copilot plugin marketplace browse

# Install
copilot plugin install python-refactor@sten-agent-skills
```

### Verify

```bash
copilot plugin list
# → python-refactor  2.0.0

/python-refactor:measure
```

---

## Install — Claude Code

### Option A: Direct install from local clone

```bash
claude /plugin install ./plugins/python-refactor
```

### Option B: From GitHub

```bash
claude /plugin install stevenengland/sten-agent-skills --plugin-path plugins/python-refactor
```

### Option C: Project-scoped (no install command, auto-discovered)

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
1. **measure** — runs all static analysis tools, writes `codebase_metrics.json`
2. **hunt-bugs** — explores high-signal files, runs Hypothesis PBT, writes `BUG_REPORT.md`
3. **architecture** — identifies deep-module candidates, cross-references confirmed bugs
4. **plan-refactor** — triages all findings, sequences by dependency graph, writes `REFACTOR_PLAN.md`

Each phase subagent receives only the compact JSON handoff from the previous phase.
Your session context stays clean throughout.

### Individual skills

```
/python-refactor:measure           # Just instrument — useful for a quick baseline
/python-refactor:hunt-bugs         # Bug hunt only — auto-runs measure if needed
/python-refactor:architecture      # Architecture review — presents candidates, creates GitHub RFCs
/python-refactor:plan-refactor     # Refactor plan only — auto-runs measure, incorporates bug report
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
                            reads codebase_metrics.json security detail directly
```

The full `codebase_metrics.json` is never forwarded between phases — only distilled signals.
This is the same isolation pattern used by Superpowers' subagent-driven-development skill.

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
| Module coupling graph         | measure, plan | pydeps                               |
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
| SessionStart hook        | hooks.json           | hooks.json (v1.0.11+)    |
| Reload without restart   | `/reload-plugins`    | `/skills reload`         |

> Skills use Claude Code tool names throughout. On Copilot CLI, substitute as shown
> in `references/platform-tools.md`.

---

## Requirements

- Python 3.10+
- pip or pip3
- gh CLI (for GitHub issue creation in the `architecture` skill)
- Claude Code (latest) **or** GitHub Copilot CLI (v1.0.11+ for SessionStart hooks)

Tools installed automatically on first run:
`radon`, `vulture`, `bandit`, `semgrep`, `pydeps`, `skylos`, `hypothesis`, `pytest`
