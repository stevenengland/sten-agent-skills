# stenswf

**Sten Software Workflow** — an opinionated SDLC bundle for **Claude Code** and **GitHub Copilot CLI**.

Installs as a plugin on both platforms using the same `plugin.json` manifest. Once installed, skills are invoked with the `/stenswf:` namespace prefix.

Contains three coordinated workflows plus always-on craft skills.

---

## Four tracks at a glance

```
             Raw GitHub issue (bug | feature | refactor request)
                             │
             ┌───────────────┴────────────────┐
             │ broken behavior?               │ desired change?
             │                                │
   /stenswf:triage-issue          /stenswf:prd-from-grill-me <N>
   ├─ REJECT (dup/oos/info)        ├─ Phase 0 issue intake
   └─ CONVERT                       └─ class auto-detect
      bug-brief + slice(s)            (capability/integration/
         │                              migration/refactor)
         ▼                                  │
                     ┌─────────────────────────────────────────┐
                     │    front-matter: stenswf:v1 marker      │
                     │    (type, lite_eligible, prd_ref, …)    │
                     └──────────────────┬──────────────────────┘
                                        │
                 ┌──────────────────────┼──────────────────────┐
                 │                      │                      │
          lite_eligible:true     lite_eligible:false    type: PRD | bug-brief
                 │                      │                      │
         ┌───────┴────────┐             │                      │
         │                │             │                      │
   ship-light       slice-e2e        plan                   review
   (single-         (plan-light      + ship                 (PRD-mode
    session)         + ship-light)    (heavy tree)           capstone /
                                                              bug-brief
                                                              slice-mode
                                                              on children)
                                                                 │
                                                                 ↓
                                                              apply
                                                              (themed
                                                               cleanup PR)
```

| Track | Entry command | Planner | Shipper | Typical slice |
|---|---|---|---|---|
| Heavy slice | `/stenswf:plan N` | `plan` (interview + local tree) | `/stenswf:ship N` | multi-subsystem, HITL, schema migration |
| Lite slice, plan-ahead | `/stenswf:plan-light N` | `plan-light` (single advisory md) | `/stenswf:ship-light N` | borderline-lite, plan helps |
| Lite slice, one-shot | `/stenswf:slice-e2e N` | chains both above | — | lite-eligible, walk away |
| Slice corrective loop | `/stenswf:review N` | — | `/stenswf:apply N` | per-slice suggestions on staged diff |
| PRD capstone | `/stenswf:review P` (PRD) | — | `/stenswf:apply P` (PRD) | post-delivery cleanup PR |

---

## Workflows

### Bug triage (raw issue → bug-brief + slice)

```
/stenswf:triage-issue <N>      → REJECT (duplicate / out-of-scope /
                                 needs-info), or CONVERT: emit a
                                 bug-brief issue + child slice(s) and
                                 close the original. No quick-fix lane;
                                 every accepted bug becomes a slice.
```

Dedup uses GitHub search PLUS persistent `.stenswf/.out-of-scope/`
rejection memory (per-clone, not committed). The original issue
stays untouched as the durable intake record. The bug-brief is a
narrow PRD-shaped artifact (`type: bug-brief`, `class: bug-brief`),
with its own decision anchor and base SHA. See
[references/bug-brief-class.md](references/bug-brief-class.md) and
[references/out-of-scope-memory.md](references/out-of-scope-memory.md).

### Feature inception (idea → PRD → issues)

```
/stenswf:grill-me                  → stress-test the idea, resolve decision tree
/stenswf:prd-from-grill-me         → produce a PRD and file it as an issue
/stenswf:prd-from-grill-me <N>     → from an existing feature/refactor
                                     request issue (Phase 0 intake;
                                     class auto-detect: capability /
                                     integration / migration / refactor;
                                     closes the original on PRD create)
/stenswf:prd-to-issues             → split the PRD into vertical-slice issues
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

`review` and `apply` auto-detect **mode** from the target issue's
`<!-- stenswf:v1 ... -->` front-matter `type:` field (set by
`prd-from-grill-me` / `prd-to-issues` / `triage-issue`). No labels are
used anywhere.

- `type: PRD` → PRD-mode (capstone review / themed cleanup).
- `type: bug-brief` → slice-mode-on-children (no capstone). See
  [references/mode-detection.md](references/mode-detection.md).
- `type: slice — HITL|AFK|spike` → Slice-mode.

PRD-mode and bug-brief-mode `review` are **gated**: refuse to run
while any child slice is still open (queried by body reference
`"Parent PRD" "#N"`, not by labels). Close abandoned slices before
re-running.

### Choosing the right path

Three ways to take a slice issue from creation to merged PR:

- **Lite shortest — `/stenswf:ship-light <issue>`.** Issue body IS the
  spec. Single session. Use when ALL:

  - Slice is single-subsystem, ≤ 15 files, no schema migration.
  - ACs are crisp checkbox items (no "figure out X" wording).
  - `Lite-eligible: true` in the issue body (set by `prd-to-issues`).
  - No open `Blocked by`.

  **Manual override.** A slice marked `lite_eligible: false` whose
  disqualifier is `files>15` or `cross-module` may carry a
  `lite_override: <reason>` front-matter field to force the lite path
  (e.g. mechanical renames, codemod-driven sweeps). Other
  disqualifiers (`schema-migration`, `arch-unknown`, `hitl-cat3`)
  cannot be overridden — they signal work the lite path is
  structurally unfit to handle. Honored overrides are logged via
  `user_override`. See
  [references/front-matter-schema.md](references/front-matter-schema.md).

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
| `/stenswf:triage-issue` | Opus | Backward tracing + root-cause analysis on unfamiliar code |
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

> Refactor-focused skills (`plan-reviewer`, `test-file-compaction`, etc.) moved to the sibling [`stenswr`](../stenswr/) plugin. Invoke them explicitly as `/stenswr:<skill>` when needed — `stenswf` no longer invokes them implicitly.

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
│       ├── references/                  ← Lazy-loaded reference bodies
│       │   ├── front-matter-schema.md
│       │   ├── extractors.md
│       │   ├── mode-detection.md
│       │   ├── drift-check.md
│       │   ├── brevity-load.md
│       │   ├── context-hygiene.md
│       │   ├── decision-anchor-link.md
│       │   ├── pr-ci-merge.md
│       │   ├── feedback-log.md
│       │   ├── feedback-session.md
│       │   ├── prd-template.md
│       │   ├── issue-template.md
│       │   ├── bug-brief-class.md
│       │   ├── out-of-scope-memory.md
│       │   ├── plan-task-template.md
│       │   ├── plan-artifact-schemas.md
│       │   └── reasoning-effects.md
│       ├── scripts/                     ← Shared executables
│       │   └── log-issue.sh
│       ├── tests/                       ← Fixtures for manual verification
│       │   └── fixtures/
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
│       │   ├── triage-issue/
│       │   ├── bootstrap/
│       │   ├── clean-code/
│       │   ├── tdd/
│       │   ├── lint-escape/
│       │   ├── architecture/
│       │   └── brevity/
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
   `type: PRD` front-matter; PRD base SHA recorded in front-matter
   (`prd_base_sha`).
3. **Break it down.** `/stenswf:prd-to-issues` → vertical-slice issues,
   each with `type: slice — HITL|AFK|spike` front-matter.
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

> **Per-clone setup:** `.stenswf/` is excluded via `.git/info/exclude`
> (not `.gitignore`), so nothing under it is ever committed. Each
> developer must run `/stenswf:bootstrap` once after cloning to install
> the exclusion rule.

```
.stenswf/                      (excluded per-clone via .git/info/exclude; per-developer)
├── <issue>/                   (active plan + execution state)
│   ├── manifest.json          (heavy-plan: materialised state: tasks[], pr, hashes)
│   ├── concept.md             (heavy-plan: issue body snapshot for drift detection)
│   ├── stable-prefix.md       (heavy-plan: verbatim dispatch prefix for prompt caching)
│   ├── conventions.md         (heavy-plan: verbatim from slice body)
│   ├── decisions.md           (cross-skill decision anchor; see section below)
│   ├── house-rules.md, design-summary.md, acceptance-criteria.md,
│   │   file-structure.md, review-step.md
│   ├── tasks/T10.md, T20.md …  (heavy-plan: self-contained task fragments)
│   ├── plan-light.md          (plan-light: single advisory plan, if used)
│   ├── plan-light.json        (plan-light: 4-field identity stub + source_signature)
│   ├── lite-notes.md          (plan-light / ship-light: soft constraints for review)
│   ├── review/slice.md OR review/prd-review.xml
│   └── apply-state.json
└── .archive/<issue>-<date>/   (cold storage after merge)
```

Heavy-plan and plan-light artifacts coexist peacefully — neither skill
touches the other's files. A slice is heavy-planned iff `manifest.json`
exists; light-planned iff `plan-light.json` exists. If both happen to
exist (e.g. you re-planned), they remain independent: `ship` reads the
heavy tree, `ship-light` reads only the plan-light artifacts.

**`decisions.md` lives alongside both** — the cross-skill decision
anchor. Every lifecycle skill either reads or appends to it; see the
[Decision Anchor Contract](#decision-anchor-contract) section below.
Unlike the heavy/light split, the anchor is path-agnostic: any skill
that touches an issue may contribute.

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

## Decision Anchor Contract

Every lifecycle skill contributes to a single persistent, reviewer-facing
memory of **decisions that would otherwise be lost**:
`.stenswf/<N>/decisions.md`. Any reviewer — the `review` skill, a future
reviewing skill, or an external tool looking at diffs — can consult one
artifact to answer *"why this, not the obvious alternative?"* beyond what
the issue body, diff, and PR body disclose.

### What qualifies as an entry

Record only if **both** tests pass:

1. **Grep-blame test.** Someone doing `git blame` on the resulting code
   would ask *"why this and not an obvious alternative?"*.
2. **Surfaces test.** The answer is **not** already findable in
   `conventions.md`, `CLAUDE.md`/`AGENTS.md`, the commit message, or the
   PR body.

### What is NOT an entry

- Following `conventions.md` or `CLAUDE.md` verbatim (convention IS the
  answer).
- Local helper extraction inside established naming rules.
- Codebase-analog mirroring when no alternative was considered.
- Silent Phase-2 resolutions in `ship-light` / `plan-light` whose answer
  is "mirror the analog" — those stay in PR body `## Notable assumptions`
  (transient review surface) or in `plan-light.md`'s `## Assumptions`
  section (phase artifact). They are non-decisions and do not belong in
  the durable anchor.
- Anything you could redirect a reader to by one-line comment in the
  commit message.

### Categories (only two)

- **`arch`** — architectural calls: deep module extractions, dependency
  shape, boundary choices, protocol selection, state-machine vocabulary.
  Contradictions by later diffs are auto-**High** severity.
- **`decision`** — non-arch calls that pass both tests: AC
  interpretations, non-obvious dependency picks, rubberduck-rejected
  alternatives, drift-accept meta-entries. Contradictions are
  **Medium**, upgraded to **High** if the entry's `Refs:` contains
  `AC#`.

`assumption`, `bikeshed`, and `override` are **not** categories.
`override` is a relationship expressed via the `Supersedes:` field; an
override of an `arch` entry is itself category `arch`.

### Schema

```markdown
### D<n> — <title ≤60 chars, imperative, no period>

- **Category:** decision | arch
- **Source:** <skill-name>
- **Rationale:** <≤180 chars, "why this, not the obvious alternative">
- **Refs:** <AC#N, T<id>, path/to/file, sha7 — comma-sep, ≤8 tokens>
- **Supersedes:** D<n> — <≤100-char reason>   <!-- omit if none -->
```

- IDs are **local** to the file (`D1`, `D2`, …). Cross-file refs use
  path + anchor: `.stenswf/42/decisions.md#D3`.
- Supersession = append a new entry **and** strikethrough the ID in the
  old entry's header: `### ~~D<n>~~ — <title>`. Never rewrite an old
  entry's body.
- `Refs:` **must** list every file path the decision implicates. This
  is what makes external file-driven grep discovery work.

Superseded header stays readable top-to-bottom; `grep -E '^### D[0-9]+ '`
returns **active** entries only (strikethrough won't match the pattern).

### Inherited PRD stubs

When `prd-to-issues` creates a slice, it copies every active PRD entry
into the slice's anchor as a **reference stub** — no rationale inline:

```markdown
### D<n> — <title> (inherited from #<PRD>)

- **Category:** <inherited>
- **Source:** #<PRD>/D<n>
- **Refs:** <inherited refs>
```

Reader who needs the "why" does one hop:
`awk '/^### D<n> /,/^### /' .stenswf/<PRD>/decisions.md`.

In-flight slice stubs are **frozen at slice-creation time** — if the
PRD later supersedes, the slice's stub stays as-is. This matches how
`base_sha` locks plan-time state.

### Conciseness caps (hard)

| Field | Cap | On overflow |
|---|---|---|
| Title | 60 chars | Truncate with ellipsis + one-line warning |
| Rationale | 180 chars | Truncate + warning; if frequent, the entry is two entries |
| Refs | 8 tokens | Truncate + warning |
| Supersedes reason | 100 chars | Truncate + warning |

If a slice accumulates **>10 entries**, the writer emits a soft
warning: *"decisions.md has N entries — consider whether this slice
needs splitting."* No hard cap.

### Write contract (per skill)

| Skill | Writes? | When | Category | Typical count |
|---|---|---|---|---|
| `prd-from-grill-me` | yes | Step 5 seeding | arch, decision | 5–15 |
| `prd-to-issues` | yes | Step 6 (stubs) | inherited | N PRD actives |
| `plan` | yes | Phase 1 interview + Phase 2 write | decision, arch | 2–6 |
| `plan-light` | rare | Phase 3 batch (genuine decisions only) | decision | 0–1 |
| `ship` | yes | drift `(c)ontinue`, rare BLOCKED override | decision | 0–2 |
| `ship-light` | rare | Phase 3 rubberduck-rejected alternatives | decision | 0–2 |
| `review` | **no** | — (findings go to `review/slice.md`) | — | 0 |
| `apply` | yes | Phase 2 override implementation | matches superseded | 0–N |

Writers never ask the user for confirmation of routine anchor
operations. Truncation warnings are informational. Supersession is
silent.

### Read contract (reviewers)

`review` (and any future reviewer) reads `decisions.md` as a **third
input** alongside the issue body and the diff. Slice-mode Perspective 2
and PRD-mode Axis 1 (Alignment) check the diff against the anchor's
active entries; contradictions surface as findings per the severity
table above.

Absence of `decisions.md` is a context note, not a finding. A seed
comment like `<!-- Seeded by ship-light (upstream phases skipped) -->`
tells the reviewer that some upstream phases didn't run.

### Bootstrap snippet (canonical)

Every writer runs this before its first append in a session:

```bash
D=".stenswf/$ARGUMENTS"
mkdir -p "$D"
if [ ! -f "$D/decisions.md" ]; then
  cat > "$D/decisions.md" <<EOF
# Decisions — #$ARGUMENTS

<!-- Seeded by <skill-name>. Schema/recipes: plugins/stenswf/README.md#decision-anchor-contract -->

EOF
fi
```

### Append snippet (canonical)

```bash
D=".stenswf/$ARGUMENTS"
# max id across active + superseded (strikethrough) headers, + 1
NEXT=$(awk 'match($0, /^### (~~)?D[0-9]+/) {
  match($0, /D[0-9]+/); n=substr($0, RSTART+1, RLENGTH-1)+0
  if (n>max) max=n
} END { print max+1 }' "$D/decisions.md")
cat >> "$D/decisions.md" <<EOF

### D${NEXT} — <title>

- **Category:** <decision|arch>
- **Source:** <skill-name>
- **Rationale:** <≤180 chars>
- **Refs:** <AC#, T-id, paths, sha7>
EOF
```

### Supersede snippet (canonical)

Strikethrough the superseded entry's ID in its header, then append a
new entry whose body includes `- **Supersedes:** D<old> — <reason>`:

```bash
D=".stenswf/$ARGUMENTS"
OLD=3          # id being superseded
# Portable across GNU and BSD sed; the .bak file is removed.
sed -i.bak "s/^### D${OLD} /### ~~D${OLD}~~ /" "$D/decisions.md" \
  && rm -f "$D/decisions.md.bak"
# …then append a new entry as usual, including the Supersedes line.
```

### Drift interaction

On `concept_sha256` drift (existing mechanism):

- `(r)e-plan` → append one `decision` meta-entry (fork marker).
  Existing entries stay.
- `(c)ontinue` → append one `decision` meta-entry (stale-plan accepted).
- `(a)bort` → no anchor writes.

The anchor has no checksum of its own; append-only + strikethrough
semantics make it inherently stable under concurrent writes.

### Two-tier model (local vs committed excerpt)

- **Local:** `.stenswf/<N>/decisions.md` (full, per-developer; excluded via `.git/info/exclude`, see `bootstrap`).
- **Committed excerpt:** `docs/stenswf/decisions/prd-<N>.md`, written
  silently by `apply` PRD-mode at PRD close. Curation filter:
  `Category ∈ {arch, decision}` ∧ not-superseded ∧ `Refs:` contains a
  concrete file path. Staged with message
  `docs(stenswf): curated decisions for PRD #<N>`.

Solo-slice flows (no PRD) skip the excerpt by default. Manual recipe
in [docs/stenswf/decisions/README.md](../../docs/stenswf/decisions/README.md).

### Consuming decisions from outside stenswf

Any reviewer or tool can discover decision entries relevant to a file
path without an index:

```bash
# All anchors (live + archived) that reference the path
grep -l 'path/to/file' \
  .stenswf/*/decisions.md \
  .stenswf/.archive/*/decisions.md 2>/dev/null

# Extract one entry by id
awk '/^### D3 /,/^### /' .stenswf/<N>/decisions.md

# All active entries across live anchors
grep -hE '^### D[0-9]+ ' .stenswf/*/decisions.md
```

This works because every file-implicating decision lists the file paths
in its `Refs:` field — a hard schema rule.

---

## Known limitations

- **`prd-from-grill-me` → `prd-to-issues` chained handover relies on
  conversational memory.** The `y/N` prompt at the end of
  `prd-from-grill-me` only shortcuts slicing when answered in the
  *same* session. If the user replies "No, I'll review first" and
  later runs `/stenswf:prd-to-issues` in a fresh chat, the interview
  context is gone — `prd-to-issues` re-reads the PRD issue from GitHub
  and restarts at Step 1. No automated signal persists to disk.

- **`ship` "fresh-session-per-task" is aspirational.** Phase 1's
  dispatch loop *assumes* each subagent starts with a clean slate and
  the stable prefix is the only context. The skill cannot enforce
  this from inside the host harness; if a harness folds subagent
  output back into the orchestrator context, prompt caching still
  works but `brevity` and token accounting degrade. Watch for
  ballooning orchestrator turns as the canary.

- **Memory-file compression is manual.** `decisions.md`,
  `house-rules.md`, and `design-summary.md` grow unbounded across an
  issue's lifetime. `references/context-hygiene.md` §4 documents the
  pruning rules (archive superseded `~~D<n>~~` entries, rewrite rules
  in terser prose at slice archive time), but nothing automates the
  rewrite. Apply manually during `review` or `apply` when the file is
  already open.

---

## License

MIT
