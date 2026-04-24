# stenswr

**StEn Software Refactor** — an opinionated, language-agnostic refactor bundle
for **Claude Code** and **GitHub Copilot CLI**.

Installs as a plugin on both platforms using the same `plugin.json` manifest.
Once installed, skills are invoked with the `/stenswr:` namespace prefix.

---

## Charter — one distinct refactor purpose per skill

Every skill in this plugin has **exactly one distinct refactor purpose**.
Skills do not overlap. New skills must fit a vacant cell in the matrix
below, or propose a new axis.

### Phase × lossy-ness matrix

| Phase | Skill | Lossy? | Purpose |
|---|---|---|---|
| 0 — Understand | `comprehension-to-taste` | n/a | Capture repo "taste" — conventions, invariants, design decisions — before touching anything |
| 1 — Discover | `improve-codebase-architecture` | n/a | Find structural refactor opportunities (deep modules, testability) |
| 1 — Discover | `functional-bug-hunting` *(placeholder)* | n/a | Find behavioural bugs worth fixing during the refactor |
| 1 — Discover | `security-bug-hunting` *(placeholder)* | n/a | Find security defects worth fixing during the refactor |
| 2 — Critique | `plan-reviewer` | n/a | Multi-perspective critique of a refactor plan |
| 3 — Test hygiene | `test-file-compaction` | **lossless** | Shrink test files without changing coverage |
| 3 — Test hygiene | `test-file-refactor` *(placeholder)* | **lossy** | Cull needless tests, surface coverage gaps worth filling |

### What belongs here

- Skills that *analyse*, *critique*, or *hygiene-treat* code and tests with the explicit goal of refactoring.
- Language-agnostic skills. Language-specific tooling belongs in a dedicated plugin (see below).

### What does NOT belong here

- **Execution skills** — planning, TDD, shipping, PR/CI orchestration. Those live in [`stenswf`](../stenswf/).
- **Language-specific static-analysis pipelines** — e.g. radon / vulture / bandit / semgrep. Those live in [`python-refactor`](../python-refactor/).
- **Skills whose purpose overlaps an existing `stenswr` skill.** Pick a new axis or improve the existing skill.

---

## Skills

| Skill | Purpose |
|---|---|
| `/stenswr:comprehension-to-taste` | Three-quiz interview producing a layered `TASTE.md` for downstream skills |
| `/stenswr:improve-codebase-architecture` | Explore for module-deepening refactor opportunities; propose issue RFCs |
| `/stenswr:plan-reviewer` | Multi-perspective plan critique; rewrites the plan in place and implements it |
| `/stenswr:test-file-compaction` | Lossless test-file compaction |
| `/stenswr:functional-bug-hunting` | **Placeholder** — behavioural bug hunting |
| `/stenswr:security-bug-hunting` | **Placeholder** — security defect hunting |
| `/stenswr:test-file-refactor` | **Placeholder** — lossy test cull + coverage-gap surfacing |

Placeholder skills declare their `name` and `description` but have no
process body yet. They are visible to the platform's skill index but
should not be invoked until implemented.

**Explicit invocation only.** Every skill in this plugin is marked
`disable-model-invocation: true`. The model will not auto-fire them
based on description matching — you must invoke them explicitly
(e.g. `/stenswr:plan-reviewer path/to/plan.md`). This is intentional:
refactor skills rewrite files in place, and placeholder skills are
unimplemented stubs that must never run silently.

---

## Repository Structure

```
STEN-AGENT-SKILLS/                       ← Repo root
│
├── plugins/
│   └── stenswr/                         ← This plugin
│       ├── plugin.json                  ← Manifest (both platforms)
│       ├── .claude-plugin/plugin.json   ← Mirror for Claude Code
│       ├── skills/
│       │   ├── comprehension-to-taste/
│       │   ├── improve-codebase-architecture/
│       │   ├── plan-reviewer/
│       │   ├── test-file-compaction/
│       │   ├── functional-bug-hunting/  ← placeholder
│       │   ├── security-bug-hunting/    ← placeholder
│       │   └── test-file-refactor/      ← placeholder
│       └── README.md                    ← This file
│
├── plugins/stenswf/                     ← Sibling: execution workflow
├── plugins/python-refactor/             ← Sibling: Python-specific analysis
└── ...
```

---

## How the namespace works

The `name` field in `plugin.json` (`"stenswr"`) is automatically used by
both Claude Code and Copilot CLI as a command prefix for all skills in
the plugin:

```
Plugin name:   stenswr
Skill folder:  improve-codebase-architecture  →  /stenswr:improve-codebase-architecture
Skill folder:  plan-reviewer                  →  /stenswr:plan-reviewer
Skill folder:  test-file-compaction           →  /stenswr:test-file-compaction
...
```

> ⚠️ The `name` field inside each `SKILL.md` is plain kebab-case with **no prefix**. The platform adds the prefix automatically. Writing `stenswr:<name>` in the `name` field causes the skill to silently fail to load.

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
copilot plugin install stenswr@sten-agent-skills-marketplace
```

### Verify

```bash
copilot plugin list
# → stenswr  0.1.0

/stenswr:improve-codebase-architecture
```

---

## Install — Claude Code

Claude Code discovers plugins via a repo-level `.claude-plugin/marketplace.json`.

```
# Register the marketplace (once)
/plugin marketplace add stevenengland/sten-agent-skills

# Install
/plugin install stenswr@sten-agent-skills
```

### Project-scoped (auto-discovered)

Copy the plugin into the project you want to use it in:

```bash
cp -r plugins/stenswr /path/to/your-project/.claude/plugins/stenswr
```

Claude Code discovers and loads it automatically. Reload if already running:

```
/reload-plugins
```

---

## Relationship to sibling plugins

- [`stenswf`](../stenswf/) — **Execution workflow.** Plan → ship → review → apply. Uses the skills in `stenswr` as external helpers (invoke `/stenswr:plan-reviewer` on a plan; invoke `/stenswr:test-file-compaction` when test files have drifted). `stenswf` does not implicitly invoke any `stenswr` skill.
- [`python-refactor`](../python-refactor/) — **Python-specific, tool-driven.** Runs radon / vulture / bandit / semgrep / skylos / grimp and produces a metrics bundle. Complementary to `stenswr`: run `python-refactor:measure` for quantitative signals, then `stenswr:improve-codebase-architecture` for design-level recommendations.
