# Rulebook — test-file-refactor

The rule catalog cited by [SKILL.md](SKILL.md). Every PLAN row references a
rule ID here. If a rule is not listed below, the skill does not flag it.

Sources:
- Matt Pocock, *TDD Skill* (2026) and *aihero.dev / skill-test-driven-development-claude-code* (2026)
- Vladimir Khorikov, *Unit Testing Principles, Practices, and Patterns* — "observable behavior vs implementation detail"
- Google, *Software Engineering at Google* ch. 11–12 — "change-detector tests"

---

## Core principle

> **Tests verify behavior through public interfaces, not implementation details.**
> Code can change entirely; tests shouldn't.

All rules below are specializations of this principle.

---

## §Prune rules (bad tests to propose removing)

### P1 — `MOCK_INTERNAL` · mock of an internal collaborator

**Confidence:** High (deterministic).

A test calls `patch(...)`, `mock.patch(...)`, `MagicMock(...)`, or
`mocker.patch(...)` whose target string resolves to a module inside the
project's own package — **and** the target is not on the boundary allowlist
(`requests`, `httpx`, `urllib`, `boto3`, `botocore`, `psycopg2`, `mysql`,
`sqlalchemy.engine`, `redis`, `kafka`, `paramiko`, `smtplib`, `subprocess`,
`os.environ`, `pathlib`, `open`, `time`, `datetime.datetime.now`,
`random`, `uuid`, plus anything declared in a project-level
`.test-file-refactor/boundaries.txt`).

```python
# FLAG — UserRepo is internal
@patch("app.repository.UserRepo")
def test_list(mock_repo): ...

# DO NOT FLAG — requests is on the boundary allowlist
@patch("requests.get")
def test_fetch(mock_get): ...
```

**Why bad:** the test no longer exercises the real path through `UserRepo`;
refactoring `UserRepo` will break the test even when behavior is unchanged.

**Counter-argument to capture in the plan:** "Is `UserRepo` a wrapper around an
external boundary?" — check its imports. If yes, the mock is defensible.

---

### P2 — `CALL_COUNT_ASSERT` · assert on mock call count / args / order

**Confidence:** High when the mock is provably internal; Medium when the
receiver cannot be classified; **not flagged at all** for boundary mocks.

Any of: `mock.assert_called`, `.assert_called_with`, `.assert_called_once`,
`.assert_called_once_with`, `.call_count ==`, `.call_args`, `.mock_calls ==`,
`.method_calls ==`. The analyzer classifies the receiver by tracing mock
bindings in the enclosing function:

- `@patch("target")` decorators → params (reverse decorator order)
- `x = mocker.patch("target")` / `x = patch("target").start()` assignments
- `with patch("target") as x:` context manager bindings

Classification uses the same allowlist as P1. Asserting call counts on a
**boundary** mock (e.g., that the HTTP client was called with the right URL)
is correct practice and is explicitly not flagged.

```python
# FLAG (HIGH) — service is a project module
@patch("app.services.email.send")
def test_register(mock_send):
    mock_send.assert_called_once_with("x@y")

# NOT flagged — requests is on the boundary allowlist
@patch("requests.get")
def test_fetch(mock_get):
    mock_get.assert_called_once_with("https://api.example.com")

# FLAG (MEDIUM) — receiver not traceable to a patch; LLM must classify
def test_logger(mock_logger):
    mock_logger.info.assert_called_once_with("user created")
```

**Why bad (internal case):** verifies *how* the code worked, not *whether*
it worked. Output-based assertions catch the same failures without coupling
to the call shape of internal collaborators.

---

### P3 — `PRIVATE_METHOD_TEST` · test calls a private method directly

**Confidence:** High on import; attribute-access form deferred to LLM adjudication.

A test imports a `_name` symbol from a project module — and that symbol is
**not** listed in the module's `__all__`. The deterministic analyzer flags
only this import-based form at High confidence.

The attribute-access form (`obj._name(...)` inside a test body) is **not**
flagged by the deterministic analyzer: the receiver is rarely a project
object (it may be a namedtuple's `_asdict`, a mock's `_mock_name`, a
framework attribute, or a third-party API). The LLM phase is expected to
catch genuine private-method tests where the receiver is clearly a project
instance.

```python
# FLAG (import-based, deterministic)
from app.parser import _normalize_line
def test_normalize(): assert _normalize_line(" x ") == "x"

# NOT auto-flagged (attribute form) — LLM may still surface in Phase 2
def test_parser(parser):
    assert parser._internal_state == "ready"
```

**Why bad:** tests an implementation detail. Either the helper is important
enough to be public (extract it) or it should be tested through the public
caller.

**Exception:** dunder methods (`__init__`, `__call__`, `__iter__`, etc.) are
not private for testing purposes.

---

### P4 — `CHANGE_DETECTOR` · exact-match assertion on volatile text

**Confidence:** Medium (requires LLM read).

Assertions of the form `str(exc) == "exact sentence"` or
`pytest.raises(X, match="^literal sentence$")` where the matched string
contains no regex metachars and the exception message is not a published
contract.

```python
# FLAG — brittle to i18n / rewording
with pytest.raises(ValueError, match="^Invalid user id 42$"):
    parse(...)
```

**Why bad:** tests break every time the message is reworded, even when
behavior is identical. Known in Google's parlance as a "change-detector test."

**Safe rewrite:** match on a stable substring with a regex, or assert only
on the exception type.

---

### P5 — `MOCK_RETURN_TAUTOLOGY` · mock returns X, test asserts X

**Confidence:** High (pattern) but Medium overall (can mimic legitimate
fixture setup).

```python
mock_repo.get.return_value = {"id": 1, "name": "Alice"}
result = service.fetch(1)
assert result == {"id": 1, "name": "Alice"}   # FLAG — circular
```

The return value is literally handed to the assertion without any
transformation in between. The test verifies nothing about `service.fetch`
beyond that it passes the value through.

**Why bad:** will pass even if `service.fetch` is rewritten to `return mock_repo.get(...)` with no real logic. Useless as a regression detector.

---

### P6 — `SKIP_WITHOUT_REASON` · `@pytest.mark.skip` / `xfail` with no reason

**Confidence:** High.

```python
@pytest.mark.skip                 # FLAG — no reason, no issue link
def test_feature(): ...
@pytest.mark.xfail(strict=False)  # FLAG — no reason
def test_other(): ...
```

**Why bad:** skipped tests rot. Without a reason or issue link, nobody
remembers why. Delete the test or link it to tracked work.

**Safe form:** `@pytest.mark.skip(reason="flaky on ARM — issue #1234")`.

---

### P7 — `DEAD_TEST_NO_ASSERT` · test function with no reachable assertion

**Confidence:** High.

Test function has zero `assert`, zero `pytest.raises`, zero
`pytest.approx`-style checks on its observable path. The function runs code
but verifies nothing.

```python
# FLAG
def test_parse_user():
    parse_user({"id": 1})   # no assertion — runs but checks nothing
```

**Exception:** the test is explicitly documented as a "does not raise" smoke
test with a comment on the body. Otherwise, flag.

---

### P8 — `DUPLICATE_TEST_BODY` · identical canonical AST

**Confidence:** Medium.

Two or more test functions in the same file share a canonical AST
(statements, calls, assertions) after abstracting literals. The intent is
obviously to parametrize.

```python
def test_add_pos(): assert add(2, 3) == 5
def test_add_neg(): assert add(-1, -1) == -2
def test_add_zero(): assert add(0, 0) == 0
```

**Proposed action:** parametrize (this is **not** destructive — coverage is
preserved). Mark as "merge, not delete."

**Why Medium confidence:** subtle setup differences (e.g., one uses a
fixture, the other doesn't) can fool canonicalization; always show the
matched AST signature in the evidence cell.

---

### P9 — `BYPASS_INTERFACE` · verifies via side channel

**Confidence:** Medium.

After calling the function under test, the test queries a side channel
(database, file system, HTTP) directly to verify the effect — instead of
using a read-side interface.

```python
# FLAG
create_user(name="Alice")
row = db.fetchone("SELECT * FROM users WHERE name=?", ["Alice"])
assert row is not None

# OK
user = create_user(name="Alice")
retrieved = get_user(user.id)
assert retrieved.name == "Alice"
```

**Why bad:** couples the test to storage layout. Replacing the DB breaks the
test even when behavior is identical.

**Exception:** if no read-side interface exists (e.g., legacy write-only
API), keep the test but flag the missing read interface in the gap section.

---

### P10 — `DEAD_TEST_SYMBOL` · unused helper / import in a test file

**Confidence:** High (requires vulture).

Unused imports, unused helper functions, unused classes inside test modules.
Detected by running `vulture` over `tests/` when it is available on the
system. If vulture is not installed, this rule is silently skipped.

Housekeeping, not semantic pruning; mirrors the `stenswr:test-file-compaction`
rule 10 but includes full-symbol removal, not just dedup.

---

## §Prune rules rejected (do not flag — false-positive rate too high)

The skill **deliberately** refuses to emit these categories. If tempted,
stop.

- **"Redundant coverage"** between two tests with different names — cannot
  prove redundancy without runtime traces. `test-file-compaction` handles
  safe merging.
- **"Over-simple test"** / "looks trivial" — simplicity is a virtue; many
  one-line assertions guard important invariants.
- **"Too many mocks"** / "over-mocked" as a raw count — count alone is not
  evidence; the mock target matters.
- **Mocking at system boundaries** (requests, boto3, DB drivers, clock,
  random, FS, subprocess) — this is the correct pattern.
- **Fixture style preferences** (scope, arity, placement) — handled by
  `test-file-compaction`.
- **Parametrize shape preferences** (id naming, tuple vs pytest.param) —
  handled by `test-file-compaction`.

---

## §Gap rules (missing tests worth proposing)

### G1 — `BROKEN_IMPORT` · test imports a symbol that does not exist

**Confidence:** High.

`from app.x import foo` where `foo` is not defined in `app.x`. Either the
symbol was renamed/removed or the test is orphaned.

---

### G2 — `HAPPY_PATH_ONLY` · test file has zero raise/exception coverage

**Confidence:** High.

A test file contains ≥ 3 test functions and zero `pytest.raises` /
`with pytest.raises(` / `pytest.approx`-for-tolerance / `pytest.warns`
blocks, while the corresponding source module contains `raise` statements.

**Why a gap:** error paths are the most common site of real bugs. Zero
coverage of them is almost always a gap, not a choice.

---

### G3 — `UNDOCUMENTED_RAISE_UNTESTED` · specific exception not tested

**Confidence:** Medium.

A public source function contains `raise SomeError(...)` (explicitly, or via
`raise` in a conditional). The corresponding test file contains no
`pytest.raises(SomeError)`.

---

### G4 — `PUBLIC_FN_UNTESTED` · exported symbol never referenced in tests

**Confidence:** Medium.

A symbol is in `__all__` or is a top-level name in a package's `__init__.py`
and no file under `tests/` mentions it by name (grep — lexical match, not
import resolution).

**Exception:** symbols re-exported purely for library consumers (documented
in a README as "public API") — downgrade to Low.

---

### G5 — `INTEGRATION_BLIND_SPOT` · boundary always mocked, no integration file

**Confidence:** Low (advisory).

The source imports a boundary package (see P1 allowlist), every test that
touches it uses a mock, and no file matches `*integration*`, `*e2e*`,
`*contract*`, or `@pytest.mark.integration`.

**Advisory only** — many projects intentionally keep boundary integration
tests out-of-tree (separate job, nightly, etc.). The plan should ask, not
demand.

---

### G6 — `COVERAGE_GAP_UNCOVERED_LINES` · coverage report shows gap

**Confidence:** Low (opt-in).

**Only** emitted if the Phase 0.4 coverage gate passed (fresh `coverage.xml`
or equivalent newer than `tests/`). Uncovered lines inside a public function
are surfaced. If coverage is unavailable or stale, this rule is skipped and
the plan records that.

---

## §Red-flag / rationalization table

Pre-emptive blocks for common "the flag is wrong" excuses. Before keeping a
flagged test, match the excuse here and apply the counter.

| Excuse | Counter | Plan action |
|--------|---------|-------------|
| "I need to isolate component A from component B, so I mock B." | Coupling that forces a mock is a **design** problem. Refactor the seam or promote to an integration test. | Keep the flag; note "design smell" in evidence. |
| "I need to verify the dependency is called." | If behavior works without the call, the call is noise. If behavior breaks without it, an output-based assertion catches it. Call-count assertions are insurance against nothing. | Keep the flag. Replace with output assertion. |
| "The exception message is part of the contract." | Exception **types** are contracts; message text drifts (i18n, rewording, logging). Use `match=` with a regex on a stable substring, or assert only on type. | Keep the flag. Loosen the assertion. |
| "Private methods are complex, so they need direct tests." | A complex private is a **deep module** wanting to be extracted. Extract, then test the new public interface. | Keep the flag. Don't delete the coverage — relocate it. |
| "Skipped because of a flaky environment — I'll fix it later." | "Later" does not come. Skips without issue links accumulate and rot. | Keep the flag. Add an issue link or delete the test. |
| "This test is a regression guard for a past bug." | Then it should carry either an issue link in a docstring or a speaking name. Undocumented "regression guards" look identical to dead weight. | Downgrade to "keep — annotate." Never delete silently. |
| "We can't use a real DB in tests." | Use a test container (testcontainers, dockerized Postgres) or an in-memory double (SQLite for simple cases). Mocking is the last resort, not the default. | Keep the P1 flag; suggest a test container in the plan. |
| "Other teams mock internal modules all the time." | Other teams have other problems. The rulebook cites Pocock / Khorikov / Google — the consensus is clear. | Keep the flag. |

---

## §Confidence-tier meaning (reading the PLAN)

- **High** — deterministic signal, false-positive rate typically < 5%.
  Review briefly, approve unless evidence is actually wrong.
- **Medium** — pattern match plus LLM adjudication; false-positive rate
  5–25%. Read the evidence and counter-argument before approving.
- **Low** — advisory only; often heuristic or coverage-dependent.
  Approve only with strong domain knowledge.

---

## §Rule cross-reference

| Rule | Category                      | Source                                      |
|------|-------------------------------|---------------------------------------------|
| P1   | MOCK_INTERNAL                 | Pocock TDD §mocking                         |
| P2   | CALL_COUNT_ASSERT             | Pocock TDD §tests; Khorikov ch. 5           |
| P3   | PRIVATE_METHOD_TEST           | Pocock TDD §tests                           |
| P4   | CHANGE_DETECTOR               | Google SWE ch. 11 "change-detector tests"   |
| P5   | MOCK_RETURN_TAUTOLOGY         | Khorikov ch. 5                              |
| P6   | SKIP_WITHOUT_REASON           | Operational — skip rot                      |
| P7   | DEAD_TEST_NO_ASSERT           | Operational — no-op tests                   |
| P8   | DUPLICATE_TEST_BODY           | Pocock / sibling `test-file-compaction` R1  |
| P9   | BYPASS_INTERFACE              | Pocock TDD §tests (DB-query example)        |
| P10  | DEAD_TEST_SYMBOL              | Vulture (optional, auto-skipped if missing) |
| G1   | BROKEN_IMPORT                 | Operational — orphaned test                 |
| G2   | HAPPY_PATH_ONLY               | Pocock TDD — error paths                    |
| G3   | UNDOCUMENTED_RAISE_UNTESTED   | Pocock TDD — error paths                    |
| G4   | PUBLIC_FN_UNTESTED            | Interface-coverage gap                      |
| G5   | INTEGRATION_BLIND_SPOT        | Fowler — test pyramid                       |
| G6   | COVERAGE_GAP_UNCOVERED_LINES  | Coverage tooling (lcov / coverage.py)       |
