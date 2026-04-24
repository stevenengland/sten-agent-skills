---
name: test-file-refactor
description: Lossy test-file hygiene — propose pruning low-value tests and flag coverage gaps as a PLAN for user review, never deleting on its own.
disable-model-invocation: true
---

# Skill: Lossy Test-File Refactor

## Intent
Decide which tests deserve to stay, which should be deleted, and which
coverage gaps are worth filling — backed by evidence from each test, not by
vibes. The skill produces a **PLAN file** that lists prune candidates and
gap candidates with confidence tiers, evidence, and a "why I might be wrong"
column. **No tests are deleted by this skill.** The user confirms each row
before any destructive action.

Sibling to `stenswr:test-file-compaction`:
- `test-file-compaction` shrinks test files **losslessly** — every case preserved.
- `test-file-refactor` (this skill) is **lossy** — bad tests are proposed for
  removal, missing tests are proposed for addition.

Use in this order: compact first (cheap, safe), then refactor (expensive,
requires judgment).

## Philosophy (the rulebook this skill enforces)

> **Tests verify behavior through public interfaces, not implementation.**
> Code can change entirely; tests shouldn't. Every bad test is a liability
> you maintain forever — it rots, breaks refactors, and costs cognitive load.
> *(Matt Pocock, aihero.dev, 2026)*

- **Good tests** describe _what_ the system does, through the public API, and
  survive internal refactors unchanged.
- **Bad tests** couple to implementation (mock internal collaborators, assert
  on call counts, verify via side channels like direct DB queries, test
  private methods, match exception messages exactly).
- **Mocking rule**: mock only at system boundaries (external APIs, time,
  randomness, sometimes DB/FS). Never mock your own modules.

Full taxonomy with examples lives in the skill's `rulebook.md`.

---

## Phase 0 — Scaffolding and mode detection

**Platform note:** Uses Claude Code tool names (Bash, Read, Write, Glob).
On GitHub Copilot CLI substitute: Bash → runCommand, Read → readFile,
Write → writeFile, Glob → listFiles.

Announce: "Using stenswr:test-file-refactor — producing a PLAN only; no files
will be deleted."

### 0.1 Locate the plan directory

Probe for an existing plan convention in the target repo, first match wins:

```
docs/plans/
plans/
.plans/
.stenswf/
```

If any exists, write the plan there as
`test-file-refactor-<RUN_ID>.md`.

Otherwise, create a self-ignoring scratch directory:

```bash
OUTPUT_DIR="PROJECT_ROOT/.test-file-refactor"
RUN_ID=$(date -u +"%Y-%m-%dT%H-%M-%S")
mkdir -p "$OUTPUT_DIR/tmp"
[ -f "$OUTPUT_DIR/.gitignore" ] || echo '*' > "$OUTPUT_DIR/.gitignore"
```

Plan file path: `$OUTPUT_DIR/PLAN_$RUN_ID.md`.

### 0.2 Detect language / mode

Glob for one of: `**/test_*.py`, `**/*_test.py`, `**/tests/**/*.py`,
`pyproject.toml`, `setup.py`, `setup.cfg`.

- **Found** → **Analyzer mode**. Proceed to Phase 1.
- **Not found** → **Pure-LLM fallback mode**. Announce:
  "No Python/pytest project detected. Running in pure-LLM mode — slower,
  higher false-positive rate, rulebook applied by reading only."
  Skip Phase 1; go straight to Phase 2 with `candidates.json = []`.

### 0.3 Optional coverage gate (existence-only)

Look for coverage artefacts like these: `coverage.xml`, `.coverage`,
`htmlcov/index.html`, `lcov.info`. If found **and** the artefact's mtime is
newer than the newest file under `tests/`, load it and surface uncovered
public-function lines as gap signals. Otherwise, note in the plan:

> Coverage data unavailable or stale — branch-level gap detection skipped.

Never re-run the test suite to generate coverage. That is the user's choice.

---

## Phase 1 — Deterministic analysis (analyzer script)

Run the shipped analyzer:

```bash
python3 "$SKILL_DIR/scripts/analyze_tests.py" \
  --project-root PROJECT_ROOT \
  --output "$OUTPUT_DIR/tmp/candidates_$RUN_ID.json"
```

The analyzer writes structured JSON with one entry per candidate:

```json
{
  "file": "tests/test_user.py",
  "line": 42,
  "category": "MOCK_INTERNAL",
  "confidence": "HIGH",
  "evidence": "@patch('app.repository.UserRepo')",
  "rule_id": "P1"
}
```

See the skill's `scripts/README.md` for the analyzer contract and the
exact list of deterministic checks.

**If the analyzer fails** (missing Python, vulture unavailable, import error)
→ continue without it, note the gap in the plan, proceed to Phase 2 with an
empty candidate list. Do not block.

---

## Phase 2 — LLM adjudication

For each candidate from Phase 1:

1. Read the test file around the flagged line (±15 lines).
2. Apply the rulebook to confirm or downgrade the flag.
3. Write a **"why I might be wrong"** counter-argument for every High/Medium
   candidate. If you cannot write one, the flag is probably wrong.
4. Consult the **red-flag / rationalization table** in the rulebook before
   keeping a candidate — these are pre-emptive blocks against common
   over-pruning mistakes.

Additionally, scan for categories that the analyzer cannot detect reliably on
its own (these require reading code):

- **Change-detector tests** — exact exception-message matches, asserts on
  internal variable names, hardcoded IDs that look like implementation echoes.
- **Mock-return-then-assert tautology** — mock configured to return X,
  assertion only checks X was returned.
- **Shape-over-behavior** — test asserts a key exists but the value is never
  used by any other assertion.

Mark every such candidate as **Medium confidence at best**.

### Explicit REJECT list (do not flag)

These categories are tempting but cannot be detected with acceptable
precision; the skill refuses to emit them:

- "Redundant coverage" between two tests (requires runtime traces).
- "Test is too simple" / "over-tested" (simplicity is a virtue).
- Mocking at system boundaries (e.g., `requests`, `boto3`, DB drivers) —
  that is **correct** behavior.
- Fixture style preferences (handled by `test-file-compaction`, not here).

If you find yourself about to flag one of these, stop. Re-read the rulebook's Rejects section.

---

## Phase 3 — Gap detection

Run these gap checks (the analyzer handles the first three deterministically;
the LLM handles the last one):

| # | Category                       | Rule                                                                                       | Confidence |
|---|--------------------------------|--------------------------------------------------------------------------------------------|------------|
| 1 | `BROKEN_IMPORT`                | Test imports a symbol that no longer exists in the source module.                          | **High**   |
| 2 | `HAPPY_PATH_ONLY`              | Test file exercises ≥ 3 tests but contains zero `pytest.raises` / `with raises` blocks.    | **High**   |
| 3 | `UNDOCUMENTED_RAISE_UNTESTED`  | Source function has `raise X` and no test in the sibling test file uses `pytest.raises(X)`.| **Medium** |
| 4 | `PUBLIC_FN_UNTESTED`           | Symbol exported via `__all__` or top-level of `__init__.py` is never referenced in tests/. | **Medium** |
| 5 | `INTEGRATION_BLIND_SPOT`       | Source imports a boundary package (`requests`, `boto3`, DB driver) but every test mocks it and no `@pytest.mark.integration` / `*integration*.py` file exists. | **Low**    |
| 6 | `COVERAGE_GAP_UNCOVERED_LINES` | **Only** if the coverage gate in 0.3 passed — uncovered lines in a public function.        | **Low**    |

Gate (6) behind coverage availability per user directive: if no fresh
coverage data exists, the check is skipped and the plan records this.

---

## Phase 4 — Write the PLAN file

Write `$OUTPUT_DIR/PLAN_$RUN_ID.md` (or the detected `docs/plans/…` path)
using the template below. **Write only this file; change nothing else.**

Then print to chat:

```
Plan written: <path>
Prune candidates: N (H/M/L = a/b/c)
Gap candidates:   M (H/M/L = a/b/c)
Next: review the plan; confirm rows; delete/add manually or ask a separate
      skill to apply the confirmed rows.
```

Stop. Do not edit test files. Do not invoke another skill.

---

## PLAN template

```markdown
# Test-File Refactor Plan — <RUN_ID>

**Scope:** <PROJECT_ROOT>
**Mode:** <Analyzer | Pure-LLM fallback>
**Coverage data:** <used (path, mtime) | unavailable or stale — see §Gaps>

## Summary
- Prune candidates: N (High: a, Medium: b, Low: c)
- Gap candidates:   M (High: a, Medium: b, Low: c)
- Rejected signals: K (see §Rejected — included for audit, not action)

> ⚠️ This skill does not delete tests. Every row below requires your
> explicit confirmation before any file is changed.

## 1. Prune Candidates

| # | File:Line | Category | Confidence | Evidence | Proposed action | Why I might be wrong |
|---|-----------|----------|------------|----------|-----------------|----------------------|
| 1 | tests/test_user.py:42 | MOCK_INTERNAL (Rule P1) | High | `@patch('app.repository.UserRepo')` — `UserRepo` is in the project package | Replace with a real or stub at the boundary; delete this test | If `UserRepo` is a thin wrapper around an external service, mocking it is defensible — check its imports |
| … | … | … | … | … | … | … |

## 2. Gap Candidates

| # | Location | Category | Confidence | Gap description | Suggested test |
|---|----------|----------|------------|-----------------|----------------|
| 1 | src/auth.py::validate_token | UNDOCUMENTED_RAISE_UNTESTED (Rule G3) | Medium | Function raises `TokenExpired`; no `pytest.raises(TokenExpired)` in tests/test_auth.py | `test_validate_token_raises_on_expired()` using `pytest.raises(TokenExpired)` |
| … | … | … | … | … | … |

## 3. Rejected Signals (audit only — not flagged)

Included so you can see what the skill chose **not** to flag and why.

| Signal seen | Reason for rejection |
|-------------|----------------------|
| `@patch('requests.get')` in tests/test_api.py:10 | Boundary mock; correct behavior |
| Two tests with similar names in tests/test_parse.py | Cannot prove redundancy without runtime traces |

## 4. Rule references

- **P1** mock-internal-collaborators — rulebook §Prune P1
- **P2** assert-on-call-count — rulebook §Prune P2
- … (all cited rules resolve to sections in the rulebook)

## 5. Approval workflow

For each prune row:
- [ ] Reviewed evidence at file:line
- [ ] Read the "why I might be wrong" column
- [ ] Approve for removal **or** mark "keep" with a one-line reason

For each gap row:
- [ ] Confirmed gap is real (not covered elsewhere)
- [ ] Approve for implementation **or** mark "accept gap" with reason

When done: delete approved prune rows manually (or via a separate apply
step), and add gap tests via TDD in a new session.
```

---

## Red flags (rationalization counters)

When the LLM (or the user) is about to *keep* a flagged test, check this
table. These are the common excuses that protect bad tests. Full version
with examples in the rulebook.

| Excuse | Counter | Action |
|--------|---------|--------|
| "I need to isolate component A from component B, so I mock B." | If A and B are coupled enough that B has to be mocked, that is a **design** smell, not a test smell. Refactor or promote to integration test. | Flag the coupling in the plan; don't silence the mock detection. |
| "I need to verify my code calls the dependency." | If behavior works without the call, the call is unnecessary. If behavior breaks without the call, an output-based assertion will catch it. Call-count assertions add noise without safety. | Keep the flag. Replace with output assertion. |
| "The exception message is part of the contract." | Exception **types** are contracts; message text is not. Messages drift, get translated, get reformatted. Use `match=` with a regex on the stable substring, or assert only on type. | Keep the flag. Loosen the assertion. |
| "We test private methods because they are complex." | Complex privates are hiding a deep module that wants to be extracted. Extract, then test the extracted public interface. | Keep the flag. Refactor, don't delete the coverage. |
| "Skipped because of a flaky environment — I'll fix it later." | Later does not come. Skips without tracking-links accumulate until they bit-rot. | Keep the flag. Add an issue link or delete the test. |
| "This test is a regression guard for a past bug." | Then it should have either: a link to the issue in the docstring, or a meaningful assertion name. If it has neither, it looks identical to dead weight. | Downgrade to "keep — annotate with issue reference." Do not delete silently. |

---

## Done criteria

The skill is done when:

1. `$OUTPUT_DIR/PLAN_$RUN_ID.md` exists and is well-formed per the template above.
2. Every prune candidate has an evidence cell and a "why I might be wrong" cell.
3. The Rejected Signals section is populated (possibly empty, but present).
4. Every cited rule ID resolves to a section in the rulebook.
5. No test file has been modified by the skill.

## Pitfalls (what this skill refuses to do)

- **It will not delete tests.** Not even high-confidence ones.
- **It will not invoke other skills.** It produces a plan and stops.
- **It will not re-run the test suite.** Coverage is consumed only if already present and fresh.
- **It will not flag boundary mocks.** Mocking `requests`, `boto3`, DB drivers, the clock, and the filesystem is *correct*.
- **It will not auto-generate replacement tests.** Gaps are proposed, never filled here — use the `stenswf:tdd` skill for that.
