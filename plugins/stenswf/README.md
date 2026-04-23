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
/stenswf:ship <issue-num>      → TDD + clean code + PR + CI loop to green
/stenswf:review <issue-num>    → plan-only review of staged changes, posts comment
/stenswf:apply <issue-num>     → interactively apply the review plan, close issue
```

### Craft skills (invoked by the above, or standalone)

| Skill | Purpose |
|---|---|
| `/stenswf:clean-code` | Readability, simplicity, SOLID/DRY/KISS |
| `/stenswf:tdd` | Red-green-refactor; integration-style tests |
| `/stenswf:lint-escape` | Tiered protocol for unresolvable lint/type errors |
| `/stenswf:architecture` | Architectural decision guidance |
| `/stenswf:conventional-commits` | Conventional Commits v1.0.0 messages |
| `/stenswf:caveman` | Ultra-compressed response mode (~75% fewer tokens) |
| `/stenswf:test-file-compaction` | Lossless test-file compaction |

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
│       │   ├── conventional-commits/    (+ references/)
│       │   ├── caveman/
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

Sibling-skill references inside a SKILL.md body use bare names too (e.g. `` `caveman` ``, `` `tdd` ``, `` `clean-code` ``). The loader resolves them within the plugin.

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
2. **Write the PRD.** `/stenswf:prd-from-grill-me` → issue filed.
3. **Break it down.** `/stenswf:prd-to-issues` → vertical-slice issues.
4. **Pick an issue.** `/stenswf:plan <N>` → plan comment on the issue.
5. **Implement.** `/stenswf:ship <N>` → code, tests, PR, CI green.
6. **Self-review.** `/stenswf:review <N>` → review plan posted as comment.
7. **Polish.** `/stenswf:apply <N>` → interactive apply + close.

The craft skills (`tdd`, `clean-code`, `conventional-commits`, `lint-escape`, `caveman`, `test-file-compaction`) are invoked by the workflow skills automatically. You can also invoke any of them directly.

---

## License

MIT
