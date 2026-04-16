# python-refactor

Agentic Python codebase analysis suite for **Claude Code** and **GitHub Copilot CLI**.

Installs as a proper plugin on **both platforms** using the same `plugin.json` manifest.
Once installed, skills are invoked with the `/python-refactor:` namespace prefix — exactly
like Superpowers' `/superpowers:` prefix — on both Claude Code and Copilot CLI.

Modelled on the Superpowers subagent-driven-development pattern: each skill announces
itself, uses TodoWrite for progress, dispatches fresh isolated subagents per phase,
and passes only compact JSON handoffs between phases to prevent context rot.

---

## File Structure

```
python-refactor/                         ← Plugin root
│
├── plugin.json                          ← Plugin manifest (BOTH platforms)
│                                          Declares name "python-refactor" →
│                                          creates /python-refactor: namespace
│
├── hooks.json                           ← SessionStart hook
│                                          Injects skill awareness at session start
│                                          via additionalContext (Copilot CLI v1.0.11+)
│
├── marketplace.json                     ← Optional: self-hosted marketplace
│   (place in .github/plugin/ of        ← Enables: copilot plugin marketplace add
│    your GitHub repo)                     OWNER/REPO
│
├── skills/                              ← All skills (default path per plugin spec)
│   │
│   ├── orchestrate/
│   │   └── SKILL.md                    ← /python-refactor:orchestrate
│   │                                     Full pipeline controller. Chains all four
│   │                                     phases via isolated subagents. Compact JSON
│   │                                     handoff between phases prevents context rot.
│   │
│   ├── measure/
│   │   └── SKILL.md                    ← /python-refactor:measure
│   │                                     Runs radon, vulture, bandit, semgrep,
│   │                                     skylos, pydeps in parallel.
│   │                                     Writes codebase_metrics.json.
│   │
│   ├── hunt-bugs/
│   │   └── SKILL.md                    ← /python-refactor:hunt-bugs
│   │                                     Phase 1: Organic exploration of high-signal
│   │                                     files with step-by-step reasoning.
│   │                                     Phase 2: Hypothesis PBT to confirm bugs.
│   │                                     Writes BUG_REPORT.md + test files.
│   │
│   ├── architecture/
│   │   └── SKILL.md                    ← /python-refactor:architecture
│   │                                     Organic deep-module analysis. Parallel
│   │                                     subagents design multiple interfaces.
│   │                                     Creates GitHub issue RFCs via gh CLI.
│   │
│   └── plan-refactor/
│       └── SKILL.md                    ← /python-refactor:plan-refactor
│                                         P0-P3 triage, topological execution
│                                         sequence, bug/security fix stubs,
│                                         test gap analysis.
│                                         Writes REFACTOR_PLAN.md.
│
└── references/
    └── platform-tools.md               ← Claude Code → Copilot CLI tool name map
```

### Output files written to your project root

```
your-project/
├── codebase_metrics.json               ← Written by: measure
├── BUG_REPORT.md                       ← Written by: hunt-bugs
├── REFACTOR_PLAN.md                    ← Written by: plan-refactor
└── tests/
    └── test_pyr_hunt_*.py              ← Written by: hunt-bugs (Hypothesis tests)
```

---

## How the namespace works

The plugin `name` field (`"python-refactor"` in `plugin.json`) is automatically used by
both Claude Code and Copilot CLI as a command prefix for all skills in the plugin:

```
Plugin name:   python-refactor
Skill name:    orchestrate      →  /python-refactor:orchestrate
Skill name:    measure          →  /python-refactor:measure
Skill name:    hunt-bugs        →  /python-refactor:hunt-bugs
Skill name:    architecture     →  /python-refactor:architecture
Skill name:    plan-refactor    →  /python-refactor:plan-refactor
```

> ⚠️ The `name` field inside each `SKILL.md` must be plain kebab-case with **no prefix**.
> The platform adds the prefix automatically. Writing `python-refactor:orchestrate` in the
> `name` field causes the skill to silently fail to load on both platforms.

---

## Install — GitHub Copilot CLI

### Option A: Direct install from GitHub (recommended)

```bash
# Install directly from your GitHub repo
copilot plugin install OWNER/python-refactor

# Or from a local directory
copilot plugin install ./python-refactor
```

### Option B: Via marketplace (team/org distribution)

First, push the repo to GitHub. The `marketplace.json` must live at
`.github/plugin/marketplace.json` in the repo root.

```bash
# Register the marketplace (once per machine)
copilot plugin marketplace add OWNER/python-refactor

# Browse available plugins in the marketplace
copilot plugin marketplace browse python-refactor-marketplace

# Install the plugin
copilot plugin install python-refactor@python-refactor-marketplace
```

### Verify install

```bash
copilot plugin list
# Should show: python-refactor  2.0.0

# List all skills (should show /python-refactor: prefixed)
/skills list
```

### Use

```
/python-refactor:orchestrate       ← Full pipeline (recommended)
/python-refactor:measure           ← Static analysis only
/python-refactor:hunt-bugs         ← Bug exploration + Hypothesis PBT
/python-refactor:architecture      ← Architecture review + GitHub RFCs
/python-refactor:plan-refactor     ← Prioritized refactor plan
```

---

## Install — Claude Code

### Option A: Direct install from GitHub

```bash
claude /plugin install OWNER/python-refactor

# Or from local directory
claude /plugin install ./python-refactor
```

### Option B: Via marketplace

```bash
# Register the marketplace
claude /plugin marketplace add OWNER/python-refactor

# Install
claude /plugin install python-refactor@python-refactor-marketplace
```

### Option C: Project-scoped (committed to your repo)

Drop the plugin into your project. No install command needed — Claude Code discovers it:

```bash
cp -r python-refactor .claude/plugins/python-refactor
# Restart or reload: /reload-plugins
```

### Verify and reload

```
/reload-plugins
/python-refactor:measure
```

---

## Install — Both platforms (standalone fallback, no namespace)

If you don't want to publish to GitHub yet, copy skills directly. Skills load without the
`/python-refactor:` prefix in this mode:

```bash
# Claude Code (personal)
mkdir -p ~/.claude/skills ~/.claude/skills/references
for skill in orchestrate measure hunt-bugs architecture plan-refactor; do
  cp -r python-refactor/skills/$skill ~/.claude/skills/
done
cp python-refactor/references/platform-tools.md ~/.claude/skills/references/

# Copilot CLI (personal)
mkdir -p ~/.copilot/skills/references
for skill in orchestrate measure hunt-bugs architecture plan-refactor; do
  cp -r python-refactor/skills/$skill ~/.copilot/skills/
done
cp python-refactor/references/platform-tools.md ~/.copilot/skills/references/
```

Invoke without namespace prefix:

```
/orchestrate
/measure
/hunt-bugs
/architecture
/plan-refactor
```

---

## How the pipeline prevents context rot

Each phase in the orchestrator runs as a **fresh isolated subagent** — it never inherits
the controller's session history or the previous phase's raw output. The controller passes
only a compact JSON handoff:

```
Phase 1 (measure)     →  handoff: top_risk_signals, high_cc_files,
                                   circular_imports, security counts

Phase 2 (hunt-bugs)   →  handoff: confirmed_bugs array
                          (id / file / line / type / impact / fix_sketch)

Phase 3 (architecture)→  handoff: architecture_candidates array

Phase 4 (plan-refactor)←  consumes all three handoffs +
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
| Plugin install command   | `claude /plugin install OWNER/REPO` | `copilot plugin install OWNER/REPO` |
| Namespaced commands      | `/python-refactor:measure` | `/python-refactor:measure` |
| Skill tool invocation    | `Skill` tool         | `skill` tool             |
| Shell commands           | `Bash`               | `runCommand`             |
| File reads               | `Read`               | `readFile`               |
| Parallel subagents       | `Agent` tool         | `spawnSubagent`          |
| SessionStart hook        | hooks.json           | hooks.json (v1.0.11+)    |
| Reload without restart   | `/reload-plugins`    | `/skills reload`         |
| Manifest discovery order | plugin.json → .plugin/ → .github/plugin/ → .claude-plugin/ | same |

> Skills use Claude Code tool names throughout. On Copilot CLI, substitute as shown
> in `references/platform-tools.md`.

---

## Requirements

- Python 3.10+
- pip or pip3
- gh CLI (for GitHub issue creation in the architecture skill)
- Claude Code (latest) **or** GitHub Copilot CLI (v1.0.11+ for SessionStart hooks)

Tools installed automatically on first run:
`radon`, `vulture`, `bandit`, `semgrep`, `pydeps`, `skylos`, `hypothesis`, `pytest`
