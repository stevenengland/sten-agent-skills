# QA: stenswf End-to-End Flow Consistency

## Purpose
Catch inconsistencies, broken hand-offs, and unrunnable instructions across the
stenswf workflow tracks. Two models run the same matrix in parallel so their
findings can be cross-checked, then the results are stress-tested via
`grill-me`.

## Inputs
- `MODEL_A` — e.g. `gpt-5.4`
- `MODEL_B` — e.g. `opus-4.6`
- `PLUGIN_ROOT` — `plugins/stenswf/skills`

## Prompt

Dispatch two **read-only** subagents in parallel, one on `{{MODEL_A}}` and one on
`{{MODEL_B}}`. Both must execute the **identical test matrix** below against the
stenswf plugin at `{{PLUGIN_ROOT}}` so their reports are directly comparable.

### Tracks under test

stenswf is a parallel-track bundle, not a single linear chain. The
audit must walk every track end-to-end:

- **Bug intake.** `triage-issue` →
  - `C-1`: emits a single slice → routes to `plan` (heavy) or
    `plan-light` (lite, only if `type: slice — AFK`); HITL slices
    always go heavy.
  - `C-N`: hands off to `prd-to-issues` (bug-brief mode) which emits
    fan-out slices.
- **PRD inception.** `grill-me` → `prd-from-grill-me` → `prd-to-issues`.
- **Heavy slice.** `plan` → `ship` → `review` (slice-mode) → `apply`
  (slice-mode).
- **Lite slice.** `plan-light` → `ship-light` → `review` (slice-mode)
  → `apply` (slice-mode); or one-shot via `slice-e2e`.
- **PRD capstone.** `review` (PRD-mode) → `apply` (PRD-mode).

If the actual track shape in the repo differs from the above, treat
the discrepancy itself as a finding and continue using the layout
documented in each SKILL.md.

### Test matrix (each agent must cover every row)

1. **Happy path per track.** Walk every track listed above. At each
   hand-off verify:
   - The producing skill's declared outputs match the consuming skill's
     declared inputs (file paths, frontmatter fields, artifact names).
   - Referenced files, scripts, and commands actually exist in the repo.
   - Code/CLI snippets are syntactically valid and runnable as written
     (no undefined vars, no stale paths, no missing flags).

2. **Branch coverage.** For every conditional branch a skill exposes (e.g.
   `plan` vs `plan-light`, `ship` vs `ship-light`, triage outcomes,
   PRD-skip conditions), trace the branch end-to-end and confirm downstream
   skills handle the branch's artifact shape.

3. **Mid-workflow entry points.** Start the workflow at each of these skills
   *without* running prior skills, using only what their SKILL.md says is
   required as input:
   - `triage-issue`
   - `plan` and `plan-light`
   - `slice-e2e`
   - `tdd`
   - `review`
   - `ship` and `ship-light`
   - `apply`
   For each entry point, confirm the skill's stated preconditions are
   sufficient — i.e. it does not silently assume artifacts only produced by
   upstream skills.

4. **Cross-skill consistency.** Check for:
   - Conflicting terminology (same concept, different names) across SKILL.md files.
   - Conflicting file/path conventions (e.g. `tmp/` vs `docs/stenswf/decisions/`).
   - Frontmatter schema drift between skills.
   - Tool/permission assumptions that contradict each other.

5. **Documentation up to date.** Verify the surrounding docs match the current
   skill behaviour:
   - `plugins/stenswf/README.md` (skill list, flow diagram, examples).
   - Top-level `README.md`, `AGENTS.md`, `CLAUDE.md` references to stenswf.
   - `docs/stenswf/**` (decisions, ADRs) — flag stale or contradicted entries.
   - Any example commands / artifact paths quoted in docs must exist verbatim
     in the skills they describe.

6. **Plugin ceremony up to date.** Verify the plugin manifests and metadata:
   - `plugins/stenswf/plugin.json` and `plugins/stenswf/.claude-plugin/plugin.json`
     are in sync (version, name, description, declared skills/commands).
   - Every skill folder under `{{PLUGIN_ROOT}}` is registered (and vice versa —
     no manifest entry points to a missing folder).
   - SKILL.md frontmatter (`name`, `description`, allowed tools) matches the
     manifest entry; description is one sentence (repo rule).
   - Version bump is warranted if behaviour changed since last tag; flag if not.
   - Any `scripts/` or `references/` paths cited from skills resolve.

### Output format (both agents must use this exact shape)

```
## Summary
<one paragraph>

## Findings
### F1 — <short title>
- Severity: blocker | major | minor | nit
- Skills involved: <skill-a> -> <skill-b>
- Branch / entry point: <happy | branch:X | mid-entry:Y>
- Evidence: path/to/SKILL.md#Lx (quote the exact lines)
- Why it breaks: <one paragraph>
- Suggested fix: <one paragraph, no code edits applied>

### F2 ...
```

Constraints for both agents:
- **Do not modify any file.** Read-only audit.
- Cite every claim with `path#Lx` line references.
- If a snippet is claimed broken, include the minimal repro (command + expected
  vs actual).
- Do not invent skills, paths, or branches that are not in the repo.

### Reviewer step (after both agents return)

1. Diff the two reports. Produce a merged table:
   `Finding | A says | B says | Agreement (yes/partial/no)`.
2. Promote agreed-blockers to the top; quarantine disagreements as "needs
   adjudication".
3. Then invoke the `grill-me` skill on **me** (the user) using the merged
   findings as the topic. Grill until every blocker has either:
   - a confirmed root cause and a chosen fix direction, or
   - an explicit decision to defer with rationale.
4. Produce an **update plan** (still no edits) covering: skill fixes, docs to
   refresh (`README.md`, `AGENTS.md`, `CLAUDE.md`, `docs/stenswf/**`), and
   plugin ceremony (`plugin.json`, `.claude-plugin/plugin.json`, version bump).
   Save to `tmp/stenswf-flow-consistency-plan.md`.
