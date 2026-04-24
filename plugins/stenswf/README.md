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
/stenswf:plan <issue-num>      → design interview + local plan tree under
                                 `.stenswf/<issue>/` (manifest, per-task
                                 fragments, stable-prefix for caching)
/stenswf:ship <issue-num>      → TDD + clean code + PR + CI + merge,
                                 driven off the local plan tree; archives
                                 to `.stenswf/.archive/` on merge
/stenswf:plan-light <issue>    → lightweight plan; single `plan-light.md`
                                 plus a 4-field identity stub under
                                 `.stenswf/<issue>/`; no interview, no
                                 subtree. Escalates via ROUTE_HEAVY.
/stenswf:ship-light <issue>    → single-session lite path: branch + TDD +
                                 PR + CI (issue-body-only by default;
                                 auto-consumes `plan-light.md` if present
                                 and the issue body hasn't drifted)
/stenswf:slice-e2e <issue>     → one-shot lite pipeline: dispatches
                                 `plan-light` then `ship-light` as
                                 separate subagent sessions for context
                                 separation; thin orchestrator
/stenswf:review <target>       → plan-only review; slice-mode writes
                                 `.stenswf/<issue>/review/slice.md`;
                                 PRD-mode writes `prd-review.xml` (and
                                 `apply` later mirrors it onto the PR)
/stenswf:apply <target>        → slice-mode: interactive apply + close;
                                 PRD-mode: themed cleanup PR
```

`review` and `apply` auto-detect **mode** from the target issue's body
`## Type` marker (set by `prd-from-grill-me` / `prd-to-issues`). No
labels are used anywhere.

- `## Type` = `PRD` → PRD-mode (capstone review / themed cleanup).
- `## Type` starts with `slice` → Slice-mode.

PRD-mode `review` is **gated**: refuses to run while any slice is still
open (queried by body reference `"Parent PRD" "#N"`, not by labels).
Close abandoned slices before re-running.

### Choosing the right path

Three ways to take a slice issue from creation to merged PR:

- **Lite shortest — `/stenswf:ship-light <issue>`.** Issue body IS the
  spec. Single session. Use when ALL:

  - Slice is single-subsystem, plausibly ≤ ~5 files, no schema migration.
  - ACs are crisp checkbox items (no "figure out X" wording).
  - `Lite-eligible: true` in the issue body (set by `prd-to-issues`).
  - No open `Blocked by`.

- **Lite guided one-shot — `/stenswf:slice-e2e <issue>`.** Dispatches
  `plan-light` then `ship-light` as separate subagent sessions with
  context separation. Writes an advisory `plan-light.md` to
  `.stenswf/<issue>/`. Use when the issue would qualify for the lite
  shortest path but a written plan will help — e.g. task ordering is
  non-obvious, you want an assumptions record, or you want to walk
  away while it runs.

- **Full pipeline — `/stenswf:plan` + `/stenswf:ship`.** Full local
  plan tree with per-task subagent dispatch, prompt caching, drift
  detection, archived state. Use when ANY:

  - Multi-subsystem, schema/migration involved, architecturally
    uncertain.
  - HITL slice (human design review wanted).
  - `Lite-eligible: false` or absent.
  - Either light skill returned `ROUTE_HEAVY` for this issue.

Both light skills' preflight gates abort cleanly to `plan` + `ship` if
a slice doesn't qualify — nothing is posted to the issue on abort.

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
| `/stenswf:plan-light` | Any (Sonnet or Opus) | Bounded planning, single artifact, no interview |
| `/stenswf:ship-light` | Any (Sonnet or Opus) | Single-session lite path; preflight-gated |
| `/stenswf:slice-e2e` | Any (cheapest orchestrator OK) | Thin facade; dispatches subagents; zero judgment calls |
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
| `/stenswf:plan-reviewer` | Multi-perspective plan critique (standalone; not invoked by `review` — that skill inlines its own plan-only critique) |

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
│       │   ├── plan-light/
│       │   ├── ship-light/
│       │   ├── slice-e2e/
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

Skill-to-skill references inside a SKILL.md body use bare names too (e.g. `` `brevity` ``, `` `tdd` ``, `` `clean-code` ``). The loader resolves them within the plugin — do not treat them as filesystem paths.

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
copilot plugin install stenswf@sten-agent-skills-marketplace
```

### Verify

```bash
copilot plugin list
# → stenswf  0.5.0

/stenswf:plan 123
```

---

## Install — Claude Code

Claude Code discovers plugins via a repo-level `.claude-plugin/marketplace.json`.

```
# Register the marketplace (once)
/plugin marketplace add stevenengland/sten-agent-skills

# Install
/plugin install stenswf@sten-agent-skills
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
2. **Write the PRD.** `/stenswf:prd-from-grill-me` → issue filed with
   `## Type\n\nPRD` marker; PRD base SHA recorded (git tag
   `prd-<N>-base`).
3. **Break it down.** `/stenswf:prd-to-issues` → vertical-slice issues,
   each with `## Type\n\nslice — HITL|AFK|spike` marker.
4. **For each slice:**
   - **Lite shortest** (`Lite-eligible: true` in the issue body):
     1. `/stenswf:ship-light <slice-N>` → branch, TDD, PR, CI green in
        one session. No local plan. Auto-consumes `plan-light.md` if
        present (and current).
   - **Lite guided one-shot** (borderline-lite, plan helps):
     1. `/stenswf:slice-e2e <slice-N>` → dispatches `plan-light` then
        `ship-light` as separate subagent sessions. Writes
        `.stenswf/<slice-N>/plan-light.md` + `plan-light.json`.
        `ship-light` consumes the plan automatically.
     Or split manually: `/stenswf:plan-light <slice-N>` then
     `/stenswf:ship-light <slice-N>` in the same session.
   - **Full path** (HITL, multi-subsystem, or `Lite-eligible: false`):
     1. `/stenswf:plan <slice-N>` → writes `.stenswf/<slice-N>/` locally:
        manifest, per-task fragments, pre-assembled `stable-prefix.md`.
     2. `/stenswf:ship <slice-N>` → dispatches one subagent per task
        (`cat tasks/T<id>.md`), updates manifest as it goes, watches
        CI, archives `.stenswf/<slice-N>/` to `.archive/` on merge.
   - *(optional, all paths)* `/stenswf:review <slice-N>` → slice-mode
     suggestions at `.stenswf/<slice-N>/review/slice.md`.
   - *(optional, all paths)* `/stenswf:apply <slice-N>` → interactive
     apply + close.
5. **When all slices are shipped (or closed as abandoned):**
   1. `/stenswf:review <PRD-N>` → PRD-mode 5-axis capstone review,
      written to `.stenswf/<PRD-N>/review/prd-review.xml`.
   2. `/stenswf:apply <PRD-N>` → PRD-mode themed cleanup PR; mirrors the
      `<prd-review>` XML onto the PR as a comment for team visibility;
      archives local tree on merge.

### Local plumbing overview

```
.stenswf/                      (gitignored; per-developer)
├── <issue>/                   (active plan + execution state)
│   ├── manifest.json          (heavy-plan: materialised state: tasks[], pr, hashes)
│   ├── concept.md             (heavy-plan: issue body snapshot for drift detection)
│   ├── stable-prefix.md       (heavy-plan: verbatim dispatch prefix for prompt caching)
│   ├── conventions.md         (heavy-plan: verbatim from slice body)
│   ├── house-rules.md, design-summary.md, acceptance-criteria.md,
│   │   file-structure.md, assumptions.md, review-step.md
│   ├── tasks/T10.md, T20.md …  (heavy-plan: self-contained task fragments)
│   ├── plan-light.md          (plan-light: single advisory plan, if used)
│   ├── plan-light.json        (plan-light: 4-field identity stub + source_signature)
│   ├── review/slice.md OR review/prd-review.xml
│   ├── apply-state.json
│   └── log.jsonl              (heavy-plan: append-only audit)
└── .archive/<issue>-<date>/   (cold storage after merge)
```

Heavy-plan and plan-light artifacts coexist peacefully — neither skill
touches the other's files. A slice is heavy-planned iff `manifest.json`
exists; light-planned iff `plan-light.json` exists. If both happen to
exist (e.g. you re-planned), they remain independent: `ship` reads the
heavy tree, `ship-light` reads only the plan-light artifacts.

Subagents dispatched by `ship` read `stable-prefix.md` + exactly one
`tasks/T<id>.md` — no `awk` extraction on the hot path, no plan-comment
fetches. Prompt caching hits on dispatches 2..N because the prefix is
byte-identical across dispatches.

### Drift detection

`ship`, `plan --resume`, `review`, and `apply` re-hash the current
issue body on start and compare against
`manifest.json:concept_sha256` + per-section hashes. On mismatch they
present `(r)e-plan / (c)ontinue / (a)bort`. `plan --resume` preserves
completed task SHAs and regenerates the rest.

`ship-light` uses a lighter mechanism for plan-light artifacts: it
recomputes a sha256 over the issue body's `What to build` ∥
`Conventions (from PRD)` ∥ `Acceptance criteria` sections and compares
to `plan-light.json:source_signature`. On mismatch the plan is
silently ignored and `ship-light` proceeds from the issue body — no
prompt, no deletion.

## Migration notes (v0.3 → v0.4)

Breaking change: the issue-comment plumbing is removed.

- **Issues hold only the conceptual slice** (What to build, ACs,
  Conventions, Files hint, `## Type` marker). No implementation plan
  comment, no implementation-log table, no per-task comments.
- **Fine plans + execution state live locally** under `.stenswf/<issue>/`
  (gitignored).
- **Lifecycle labels (`prd`, `slice`, `hitl`, `afk`, `needs-plan`,
  `planned`, `shipping`, `shipped`, `abandoned`, `applied`) are no longer
  written or read by any skill.** If they still exist in your repo from
  v0.3, they do no harm — delete at leisure.
- **Mode detection** now reads the issue body's `## Type` marker
  (`PRD` | `slice — HITL|AFK|spike`). PRD-slice gating queries by body
  reference.
- **Prompt caching** now uses a pre-materialised `stable-prefix.md`
  (byte-identical across all `ship` dispatches).

For in-flight issues planned under v0.3: either finish them under v0.3
or re-plan under v0.4 (`/stenswf:plan <issue>` writes fresh local
artifacts; the old plan comment is ignored).

The craft skills (`tdd`, `clean-code`, `lint-escape`, `brevity`,
`test-file-compaction`, `architecture`) are invoked by the workflow
skills automatically. `plan-reviewer` is standalone-only — the workflow
skills (notably `review`) do not invoke it, since its contract rewrites
plan files in place. You can invoke any craft skill directly.

---

## License

MIT
