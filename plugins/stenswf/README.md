# stenswf

**Sten Software Workflow** — an opinionated SDLC bundle for **Claude Code** and **GitHub Copilot CLI**.

Installs as a plugin on both platforms using the same `plugin.json` manifest. Once installed, skills are invoked with the `/stenswf:` namespace prefix.

Contains three coordinated workflows plus always-on craft skills.

---

## Workflows

### Feature inception (idea → PRD → issues)

```
/stenswf:grill-me              → stress-test the idea, resolve decision tree
/stenswf:prd-from-grill-me     → produce a PRD and file it as an issue
/stenswf:prd-to-issues         → split the PRD into vertical-slice issues
```

### Issue lifecycle (plan → ship → review → apply)

```
/stenswf:plan <issue-num>      → design interview + implementation plan comment
/stenswf:ship <issue-num>      → TDD + clean code + PR + CI + merge → shipped
/stenswf:review <target>       → plan-only review; slice-mode (suggestions) OR
                                 PRD-mode (5-axis capstone after all slices shipped)
/stenswf:apply <target>        → slice-mode: interactive apply + close;
                                 PRD-mode: themed cleanup PR → applied label
```

`review` and `apply` auto-detect **mode** from the target issue's labels:

- Label `prd` → PRD-mode (capstone review / themed cleanup).
- Label `slice` (or neither) → Slice-mode (per-slice suggestions).

PRD-mode `review` is **gated**: refuses to run while any slice is still
open. Ship or `abandoned`-label them first.

### Recommended model routing

These workflow skills benefit from different model strengths. Configure
your harness (or manually invoke) accordingly.

| Skill | Recommended model | Rationale |
|---|---|---|
| `/stenswf:grill-me` | Sonnet | Fast interactive Q&A; relentlessness over depth |
| `/stenswf:prd-from-grill-me` | Opus | Long-context design synthesis; industry-pattern research |
| `/stenswf:prd-to-issues` | Sonnet | Structured slicing; tight templates |
| `/stenswf:plan` | Opus | Architecture, invariants, deep file-structure reasoning |
| `/stenswf:ship` | Sonnet | Orchestrator dispatch; subagents do the heavy lifting |
| `/stenswf:review` | Opus | Capstone synthesis; 5-axis architectural critique |
| `/stenswf:apply` | Sonnet | Execution against a structured findings list |

Craft skills (`tdd`, `clean-code`, `lint-escape`, etc.) run in whatever
parent session invokes them — no separate routing.

### Craft skills (invoked by the above, or standalone)

| Skill | Purpose |
|---|---|
| `/stenswf:clean-code` | Readability, simplicity, SOLID/DRY/KISS |
| `/stenswf:tdd` | Red-green-refactor; integration-style tests |
| `/stenswf:lint-escape` | Tiered protocol for unresolvable lint/type errors |
| `/stenswf:architecture` | Architectural decision guidance |
| `/stenswf:brevity` | Plain-English brevity for internal reasoning (full prose for artifacts) |
| `/stenswf:test-file-compaction` | Lossless test-file compaction |
| `/stenswf:plan-reviewer` | Multi-perspective plan critique (used by `review` slice-mode) |

Conventional Commits formatting is inlined in `plan`, `ship`, and `apply`
— no separate skill load needed.

---

## Repository Structure

```
STEN-AGENT-SKILLS/                       ← Repo root
│
├── plugins/
│   └── stenswf/                         ← This plugin
│       ├── plugin.json                  ← Manifest (both platforms)
│       ├── hooks.json                   ← Hooks placeholder (empty)
│       ├── skills/                      ← All plugin skills
│       │   ├── plan/
│       │   ├── ship/
│       │   ├── review/
│       │   ├── apply/
│       │   ├── grill-me/
│       │   ├── prd-from-grill-me/
│       │   ├── prd-to-issues/
│       │   ├── clean-code/
│       │   ├── tdd/                     (+ adjacent reference .md files)
│       │   ├── lint-escape/
│       │   ├── architecture/
│       │   ├── brevity/
│       │   ├── plan-reviewer/
│       │   └── test-file-compaction/
│       └── README.md                    ← This file
│
├── skills/                              ← Standalone skills (not bundled)
└── ...
```

---

## How the namespace works

The `name` field in `plugin.json` (`"stenswf"`) is automatically used by both Claude Code and Copilot CLI as a command prefix for all skills in the plugin:

```
Plugin name:  stenswf
Skill folder: plan     →  /stenswf:plan
Skill folder: ship     →  /stenswf:ship
Skill folder: tdd      →  /stenswf:tdd
...
```

> ⚠️ The `name` field inside each `SKILL.md` is plain kebab-case with **no prefix**. The platform adds the prefix automatically. Writing `stenswf:plan` in the `name` field causes the skill to silently fail to load.

Sibling-skill references inside a SKILL.md body use bare names too (e.g. `` `brevity` ``, `` `tdd` ``, `` `clean-code` ``). The loader resolves them within the plugin.

---

## Install — GitHub Copilot CLI

### Direct install

```bash
# From a local clone of STEN-AGENT-SKILLS
copilot plugin install ./plugins/stenswf

# Or directly from GitHub (colon-separated OWNER/REPO:PATH)
copilot plugin install stevenengland/sten-agent-skills:plugins/stenswf
```

### Verify

```bash
copilot plugin list
# → stenswf  0.1.0

/stenswf:plan 123
```

---

## Install — Claude Code

### Direct install from local clone

```bash
claude /plugin install ./plugins/stenswf
```

### From GitHub

```bash
claude /plugin install stevenengland/sten-agent-skills:plugins/stenswf
```

### Project-scoped (auto-discovered)

Copy the plugin into the project you want to use it in:

```bash
cp -r plugins/stenswf /path/to/your-project/.claude/plugins/stenswf
```

Claude Code discovers and loads it automatically. Reload if already running:

```
/reload-plugins
```

---

## Typical end-to-end flow

1. **Capture the idea.** `/stenswf:grill-me` → shared understanding.
2. **Write the PRD.** `/stenswf:prd-from-grill-me` → issue filed; PRD base SHA recorded (git tag `prd-<N>-base`).
3. **Break it down.** `/stenswf:prd-to-issues` → vertical-slice issues.
4. **For each slice:**
   1. `/stenswf:plan <slice-N>` → plan comment on the slice.
   2. `/stenswf:ship <slice-N>` → code, tests, PR, CI green, merged → `shipped`.
   3. *(optional)* `/stenswf:review <slice-N>` → slice-mode suggestions.
   4. *(optional)* `/stenswf:apply <slice-N>` → interactive apply + close.
5. **When all slices are `shipped` (or `abandoned`):**
   1. `/stenswf:review <PRD-N>` → PRD-mode 5-axis capstone review.
   2. `/stenswf:apply <PRD-N>` → PRD-mode themed cleanup PR → `applied`.

The craft skills (`tdd`, `clean-code`, `lint-escape`, `brevity`,
`test-file-compaction`, `architecture`, `plan-reviewer`) are invoked by
the workflow skills automatically. You can also invoke any of them directly.

---

## License

MIT
