# QA: stenswf Skills — Research-Aligned Token-Efficiency Audit

## Purpose
Stress-test whether the stenswf skills are aligned with current research on
agent skill design and token efficiency. Three frontier models research in
parallel against `frameworks/*` (the only trusted best-practice corpus) and
`research/*`, then propose compression / restructuring ideas for the listed
stenswf skills. Findings are then grilled and turned into an update plan that
also covers docs and plugin ceremony.

## Inputs
- `SKILLS_UNDER_REVIEW` — `prd-from-grill-me`, `prd-to-issues`, `plan`,
  `plan-light`, `ship`, `ship-light`, `review`, `apply`
- `MODELS` — exactly: `gpt-5.4`, `gemini-3.1-pro`, `opus-4.6` (max thinking
  effort each). No others.
- `PLUGIN_ROOT` — `plugins/stenswf/skills`
- `BEST_PRACTICE_CORPUS` — `frameworks/**` (treat as authoritative)
- `RESEARCH_CORPUS` — `research/**/*.md`

## Disclaimer (must be passed verbatim to every subagent)
- Skills **outside** `frameworks/*` are NOT best practice and MUST NOT be used
  as optimization examples.
- Skill descriptions MUST NOT exceed one line / one sentence.
- Read-only audit. No file modifications.

## Prompt

Run `grill-me` framing first, then dispatch three **read-only** research
subagents in parallel — one each on `gpt-5.4`, `gemini-3.1-pro`, and `opus-4.6`,
each at maximum thinking effort. Use exactly these three; no substitutions, no
additions.

Each subagent reads:
1. Every `SKILL.md` under `{{BEST_PRACTICE_CORPUS}}` (authoritative reference).
2. Every `*.md` under `{{RESEARCH_CORPUS}}`.
3. The stenswf skills under `{{PLUGIN_ROOT}}` listed in `SKILLS_UNDER_REVIEW`.

### Questions each subagent must answer (per skill, with citations)

1. **Token efficiency baseline** — Is the skill token-efficient as written?
   Report approximate token weight and the share that is decision-time-relevant
   vs reference material.
2. **Compression opportunities** — Can the skill be made less verbose without
   losing meaning? Evaluate at minimum:
   - Caveman-style compression (telegraphic phrasing).
   - Deduplication across skills (shared rules pulled to one place).
   - Logical compression (collapsing parallel sections, removing restated
     rationale).
   - Tabularization of repeated structures.
3. **Missed efficiency gains** — Any technique from `frameworks/*` or
   `research/*` that the stenswf skill does not yet apply? Name the source.
4. **Body externalization** — Per Anthropic's guidance referenced in
   `frameworks/anthropic-skills/.../anthropic-best-practices.md` (around the
   "SKILL.md body should carry only what's needed at decision time" rule),
   what content should be moved to `references/`, `scripts/`, or sibling docs?
   Cite the exact best-practice line.
5. **Bash / grep / awk bugs** — Audit every shell snippet for:
   correctness (quoting, `set -euo pipefail`, portable flags), POSIX vs GNU
   assumptions, unsafe `eval`/word-splitting, broken regex, off-by-one in
   `awk`, missing `--` guards, and shellcheck-class issues.

### Output format (every subagent uses this exact shape)

```
## Summary
<one paragraph per skill in SKILLS_UNDER_REVIEW>

## Findings
### F1 — <skill>: <short title>
- Category: token-efficiency | compression | missed-gain | externalization | shell-bug
- Severity: blocker | major | minor | nit
- Evidence: path/to/SKILL.md#Lx (quote)
- Best-practice / research citation: frameworks/...#Lx OR research/...#Lx
- Proposed change: <concrete rewrite sketch — no edits applied>
- Estimated token delta: <-N tokens / +clarity>
```

Hard constraints for every subagent:
- Do not modify any file.
- Cite every claim with `path#Lx`.
- Only `frameworks/*` counts as a best-practice example. Anything cited from
  `skills/`, `plugins/`, or `tmp/` is **not** a best-practice reference.
- Keep the one-line skill-description rule intact in any proposed rewrite.

### Reviewer step (after all three agents return)

1. Build a 3-column agreement matrix:
   `Finding | gpt-5.4 | gemini-3.1-pro | opus-4.6 | Agreement`.
   Mark unanimous findings as `consensus`, 2/3 as `majority`, 1/3 as `outlier`.
2. Invoke the `grill-me` skill on **me** (the user) using the consensus and
   majority findings as the topic. Grill until each one has:
   - a chosen direction (apply / reshape / reject) with rationale, and
   - identified target file(s) for the change.
3. Produce an **update plan** at `tmp/stenswf-research-alignment-plan.md`
   covering:
   - Skill rewrites (per skill, per finding, with target token delta).
   - Externalized assets to create under `references/` or `scripts/`.
   - Documentation updates: `plugins/stenswf/README.md`, top-level `README.md`,
     `AGENTS.md`, `CLAUDE.md`, `docs/stenswf/**`.
   - Plugin ceremony: `plugins/stenswf/plugin.json` and
     `plugins/stenswf/.claude-plugin/plugin.json` (version bump, description
     sync, skill registry).
   - One-line skill descriptions verified.
4. Do not apply the plan. Stop after writing it.
