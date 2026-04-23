---
name: lint-escape
description: Tiered escape protocol for lint and type errors that cannot be resolved with clean code alone.
disable-model-invocation: true
---

## Purpose

When a lint or static-analysis error cannot be resolved with clean code,
this skill defines the exact sequence of escalating responses. Each tier
is only entered when the previous tier is exhausted. No tier is skipped.
No suppression is added silently or opportunistically.

---

## Constraint Baseline

Before applying any tier, confirm the project's hard constraints from
`CLAUDE.md` or equivalent. Typical constraints:

- Certain config files (e.g. `setup.cfg`, `pyproject.toml`, `.eslintrc`)
  must never be modified without deliberate escalation.
- Inline suppressions (e.g. `noqa`, `type: ignore`, `eslint-disable`,
  `@SuppressWarnings`) are forbidden unless explicitly permitted.
- Commit hooks must always run. Never use `--no-verify` or equivalent.

These constraints are non-negotiable in Tiers 1 and 2. They are relaxed
only in Tier 3, deliberately, with a logged rationale.

---

## Escalation Tiers

### Tier 1 — Clean Code Fix (attempts 1–3)

Resolve the error using only clean, idiomatic code changes. No suppressions,
no config edits.

Approaches to try (in order, stop at first success):

1. Restructure the offending expression or statement.
2. Extract to a named helper or intermediate variable.
3. Change the type, shape, or contract of the involved symbol.

**Cap: 3 structurally distinct attempts.** An attempt counts as distinct only
if it changes the approach, not just reformats the same code. After 3 failed
distinct attempts, proceed to Tier 2.

If the error is **definitively structural** — meaning the tool or framework
imposes a shape that inherently conflicts with the rule (e.g. a schema
library requiring explicit `Any`, a generated file, a protocol stub) —
skip remaining Tier 1 attempts and proceed directly to Tier 2.

Log each attempt in the running log:

    LINT_ATTEMPT 1/3 | <file>:<line> | <rule> | approach: <one sentence>
    LINT_ATTEMPT 2/3 | <file>:<line> | <rule> | approach: <one sentence>
    LINT_ATTEMPT 3/3 | <file>:<line> | <rule> | approach: <one sentence>
    → Tier 1 exhausted. Proceeding to Tier 2.

---

### Tier 2 — Inline Suppression (if eligible)

An inline suppression is eligible only when **all** of the following are true:

- [ ] The suppression is file-scoped or line-scoped (not file-wide or
      project-wide).
- [ ] The occurrence count is low (1–3 sites). If the same rule fires in
      more than 3 places, the problem is structural — go to Tier 3.
- [ ] The suppression does not mask a logic error or real bug.
- [ ] The project's `CLAUDE.md` does not explicitly forbid inline suppressions
      for this rule or this file.

If eligible, add the narrowest possible suppression comment in the toolchain's
native syntax (e.g. `# noqa: E501`, `// eslint-disable-next-line no-unused-vars`,
`@SuppressWarnings("unchecked")`). Use the specific rule code, never a blanket
suppression.

Log the action:

    LINT_TIER2 | <file>:<line> | <rule> | inline suppression added
    Rationale: <one sentence explaining why clean code cannot satisfy this rule>

If the suppression is not eligible, proceed to Tier 3.

---

### Tier 3 — Config Exception (if structural)

A config exception is eligible only when **all** of the following are true:

- [ ] Tier 1 is exhausted (3 distinct clean attempts or structural skip).
- [ ] Tier 2 is ineligible (occurrence count > 3, or file-wide exception
      required, or inline suppression forbidden by project rules).
- [ ] The exception is **scoped as narrowly as possible** — to the specific
      module, file, or rule — never project-wide.
- [ ] The rationale is structurally sound (framework/library constraint, not
      agent preference).

Modify the lint config file (e.g. `setup.cfg`, `pyproject.toml`, `.eslintrc`)
with the minimum required exception. Use per-file or per-module scoping where
the toolchain supports it.

Log the action:

    LINT_TIER3 | <config file> | <rule> | scoped exception added
    Scope:     <module, file, or glob pattern>
    Rationale: <one sentence — must name the structural reason>
    Before:    <original config block, if modified>
    After:     <new config block>

---

### Tier 4 — Dead End (stop)

Reached when Tier 3 is also ineligible or fails. This means:
- The error cannot be fixed with clean code.
- Inline suppression is forbidden or insufficient.
- A scoped config exception cannot resolve it (e.g. the rule cannot be
  scoped, or modifying the config would violate an explicit hard constraint
  in `CLAUDE.md`).

Do not loop further. Do not modify anything. Write the following structured
report to the running log and stop:

    LINT_BLOCKER
    ─────────────────────────────────────────────
    File:      <exact path>
    Line:      <line number>
    Rule:      <rule code and human name>
    Error:     <exact error message from the tool>
    Tiers tried:
      Tier 1:  <summary of 3 approaches tried, or "structural skip">
      Tier 2:  <why ineligible>
      Tier 3:  <why ineligible>
    Options for resolution (choose one):
      A) <concrete code change that would fix this — even if non-trivial>
      B) <config or rule relaxation the user can apply deliberately>
    ─────────────────────────────────────────────

Stage all files that are clean and passing. Do not stage files with
unresolved errors. Stop. Do not proceed to further tasks.

---

## Invariants (never violated at any tier)

- Never use `--no-verify` or any mechanism that bypasses commit hooks.
- Never add a suppression without a log entry and a rationale.
- Never add a project-wide suppression or disable a rule globally.
- Never modify a file explicitly marked untouchable in `CLAUDE.md` without
  reaching Tier 3 eligibility and logging the action.
- Never retry the same approach twice and count it as two attempts.
