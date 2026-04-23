---
name: sync-upstream-skills
description: Walk the tracked skills in sources.yaml, compare each local skill against its upstream source, and interview the user about which upstream changes are worth importing. Use when user wants to refresh skills from upstream, check for upstream updates, sync sources, or review divergence from original sources.
disable-model-invocation: true
---

# Sync Upstream Skills

Keep this repository's skills in informed conversation with the upstream skills they were copied from. The goal is **not** to blindly mirror upstream — most entries have been edited deliberately. The goal is to surface upstream changes, evaluate them, and let the user decide what to import.

## Inputs

- `sources.yaml` at repo root — the machine-readable registry of tracked skills.
- The local skill files under `skills/`, `plugins/*/skills/`, etc.
- The upstream repositories referenced in `sources.yaml`.

## `sources.yaml` schema

```yaml
- skill: skills/grill-me            # path to local skill folder (or file)
  upstream: https://github.com/mattpocock/skills/tree/main/skills/grill-me
  ref: a1b2c3d                      # upstream commit SHA last reviewed
  last_reviewed: 2026-04-22         # ISO date
  status: tracked                   # tracked | own-invention | unknown-source | abandoned
  notes: ""                         # intentional divergences; rejected imports; rename history
```

Rules:

- `upstream` may point at a **folder** (preferred, resilient to file renames) or a **file**.
- `status: own-invention` and `status: abandoned` entries are **skipped** — do not diff, do not interview.
- `status: unknown-source` entries are reported to the user once, then skipped until a source is filled in.

## Workflow

Process one entry at a time. Never batch upstream network calls in ways that hide per-skill reasoning from the user.

### 1. Enumerate and filter

Load `sources.yaml`. List the entries the agent will process (`tracked` only) and the entries it will skip, with reasons. Confirm with the user before hitting the network if the list is large (>10 entries).

### 2. Resolve the upstream pointer

For each tracked entry:

1. **Try the pinned pointer first.** Fetch the referenced folder/file at the upstream repo's default branch HEAD.
2. **If it resolves** → continue to step 3 (diff).
3. **If it 404s** → enter the rename-discovery flow:
   1. List the upstream repo's skill folders (e.g., `skills/*/SKILL.md`).
   2. Score candidates by:
      - folder/file name edit-distance to the old name,
      - front-matter `name:` / `description:` keyword overlap with the local `SKILL.md`,
      - body keyword overlap (only as a tiebreaker — generic prose produces false positives).
   3. Present the **top 3 candidates with explicit reasoning** to the user, e.g.:

      ```
      Pinned path no longer exists: mattpocock/skills/skills/grill-me
      Candidates @ HEAD:
        1. skills/interview-me/SKILL.md
           - name distance: 0.4 (grill-me → interview-me)
           - description overlap: "interview", "relentlessly", "design tree" (3/5)
           - verdict: LIKELY match
        2. skills/stress-test-plan/SKILL.md
           - description overlap: "plan", "stress-test" (2/5)
           - verdict: possible
        3. ...
      ```

   4. User picks one, skips, or marks the entry `abandoned`.
   5. On a confirmed pick, **update** `sources.yaml` (`upstream`, and append a note to `notes` recording the rename, e.g. `"renamed upstream grill-me → interview-me on 2026-04-22"`) so the next run is a direct hit.

### 3. Diff against the pinned ref

Compare upstream HEAD against the pinned `ref`. The diff universe is **upstream-only**; the agent is not trying to reconcile local edits back upstream.

If `ref` is empty or the entry is new, treat upstream HEAD as the full candidate content (there is no baseline).

Classify each upstream change into one of:

- **Additive** — new sections, new guidance, new examples.
- **Substantive rewrite** — the same section reworded with new reasoning.
- **Cosmetic** — formatting, typo fixes, link updates.
- **Removal** — upstream deleted content the local skill still has.

Cosmetic-only diffs can be summarized in one line; do not interview on them unless the user asks.

### 4. Cross-reference local divergences

Before recommending an import, read the local `SKILL.md` **and** the `notes` field for that entry. Intentional divergences must not be re-imported. Examples:

- If `notes` says "removed the 'cite well-known companies' requirement", do **not** recommend re-importing that requirement just because upstream still has it.
- If the local skill rewords a section, flag when upstream's new wording still conflicts with the local rewording — ask the user rather than silently picking a side.

### 5. Interview the user — one change at a time

For each non-cosmetic upstream change, present:

1. **What changed upstream** — a short diff or before/after excerpt.
2. **Why this might be worth importing** — the agent's reasoning. This is mandatory. State the concrete benefit (e.g., "adds a fallback step when the user rejects all candidates — currently your skill has no escape hatch"). No reasoning → no recommendation.
3. **Why it might not fit** — conflicts with local edits, contradictions with `notes`, stylistic mismatch, scope creep.
4. **Recommendation** — `import` / `adapt` / `skip`, with a one-line justification.
5. **User decision** — wait for it. Do not bulk-apply.

Do not write to any skill file during the interview. Collect decisions.

### 6. Apply and record

After the interview for an entry is complete:

1. Apply accepted changes to the local skill file. For `adapt` decisions, the user dictates the wording — do not paraphrase silently.
2. Append to `notes` any **rejected** imports so future runs don't re-ask ("rejected 2026-04-22: upstream added company citations requirement, intentionally kept out").
3. Update `ref` to the upstream SHA just reviewed.
4. Update `last_reviewed` to today's date.
5. Commit each entry as its own change (one skill per commit) so the rationale is preserved in history.

### 7. Summary

At the end of the run, produce a table:

| Skill | Status | Imports accepted | Imports rejected | New ref |
|---|---|---|---|---|

Flag anything that needs human follow-up: `unknown-source` entries, abandoned skills, and entries where rename discovery failed.

## Principles

- **Reasoning is mandatory, not decorative.** Every recommendation must state the concrete benefit or risk. A recommendation without reasoning is a bug in this skill.
- **The `notes` field is sticky.** Rejected imports stay rejected until the user explicitly revisits them.
- **Folder pointers over file pointers.** Default new entries to folder URLs so file renames don't trigger rename-discovery unnecessarily.
- **One skill at a time.** Never interleave interview questions across skills — the user loses context.
- **Never edit `sources.yaml` fields the user didn't sign off on**, except `ref`, `last_reviewed`, and appends to `notes` after a completed review.

## Out of scope

- Pushing local improvements back upstream.
- Tracking skills that were never copied (own inventions) beyond a bookkeeping entry.
- Automatic scheduled runs — this skill is user-invoked.
