---
name: test-file-compaction
description: Refactors existing test files to reduce line count and eliminate repetition without dropping any test case, assertion, or edge-case coverage. Extracts fixtures, parametrizes duplicate test bodies, introduces shared assertion helpers, and hoists repeated constants — preserving full test semantics throughout.
---

# Skill: Compact Test File (Lossless)

## Intent
Reduce the line count and cognitive load of an existing test file **without
dropping any test case, assertion, or edge-case coverage**.
Preserve the exact semantics of every test; only restructure *how* they are
expressed.

---

## Phase 1 — Analysis (read-only, no edits yet)

Before touching a single line, produce a structured inventory:

1. **Coverage map** — List every distinct input/output or behavior being
   verified (not by function name, but by *what* is checked).
2. **Repetition scan** — Identify blocks of code that differ only by:
   - Input values or expected outputs → candidate for `@pytest.mark.parametrize`
   - Setup/teardown sequences → candidate for `@pytest.fixture`
   - Multi-step assertion patterns → candidate for a shared assertion helper
3. **Smell list** — Flag:
   - Inline duplication of fixture data (same dict/object built >1×)
   - Literal constants repeated across tests
   - `setUp`/`tearDown` methods that could be fixtures
   - Test classes wrapping unrelated tests (split or flatten)
   - Dead assertions (`assert True`, trivially-always-true conditions)

Output the inventory as a comment block at the top of your working diff so
a reviewer can audit it.

---

## Phase 2 — Transformation Rules (apply in order)

### Rule 1 · Parametrize identical test bodies
If ≥2 test functions share the same body and differ only in their inputs or
expected outputs, collapse them into a single parametrized test.

```python
# BEFORE
def test_add_positive():
    assert add(2, 3) == 5

def test_add_negative():
    assert add(-1, -1) == -2

def test_add_zero():
    assert add(0, 0) == 0

# AFTER
@pytest.mark.parametrize("a,b,expected", [
    (2,  3,  5),
    (-1, -1, -2),
    (0,  0,  0),
])
def test_add(a, b, expected):
    assert add(a, b) == expected
```

**Constraint:** Each parametrize tuple must include a meaningful `id` when the
values alone are not self-documenting:
```python
pytest.param(None, 0, id="none-input")
```

---

### Rule 2 · Extract fixtures for repeated setup
If the same object construction or mock setup appears in ≥2 tests, move it
into a `@pytest.fixture`. Prefer function-scoped fixtures unless the object is
provably immutable, in which case `scope="module"` is acceptable.

```python
# BEFORE
def test_parse_ok():
    cfg = Config({"host": "localhost", "port": 1883})
    assert cfg.host == "localhost"

def test_parse_missing_port():
    cfg = Config({"host": "localhost", "port": 1883})
    assert cfg.port == 1883

# AFTER
@pytest.fixture
def default_cfg():
    return Config({"host": "localhost", "port": 1883})

def test_parse_ok(default_cfg):
    assert default_cfg.host == "localhost"

def test_parse_missing_port(default_cfg):
    assert default_cfg.port == 1883
```

---

### Rule 3 · Shared assertion helpers
If a multi-assertion pattern recurs (e.g. checking a response object's status
+ body + headers), extract it into a local helper function prefixed with
`assert_`.

```python
def assert_valid_response(resp, expected_status, expected_key):
    assert resp.status_code == expected_status
    assert expected_key in resp.json()
    assert resp.headers["Content-Type"] == "application/json"
```

Helpers live at the **top of the same test module** or in `conftest.py` if
shared across modules.

---

### Rule 4 · Constant tables over inline literals
If the same constant (URL, timeout, topic name, device ID, etc.) is spelled
out inline across tests, hoist it to a module-level constant or a
`conftest.py` variable.

```python
# BEFORE (scattered)
assert msg.topic == "home/sensor/temperature"
...
assert msg.topic == "home/sensor/temperature"

# AFTER
TEMP_TOPIC = "home/sensor/temperature"
assert msg.topic == TEMP_TOPIC
```

---

### Rule 5 · Flatten single-test classes
A `TestClass` containing only one test method adds indirection with no
benefit. Flatten it to a module-level function unless the class provides
shared fixtures via `setup_method` / class-scoped state.

---

### Rule 6 · Remove redundant assertions
Delete assertions that are always trivially true given the preceding logic
(e.g. `assert result is not None` immediately after `result = []`).
**Do NOT remove assertions that guard against future regressions**, even if
they seem obvious today.

---

## Phase 3 — Hard Constraints (never violate)

| Constraint | Rationale |
|---|---|
| Every original test case ID/scenario must survive | Zero coverage loss |
| Test names must remain descriptive after parametrization | Debuggability |
| Do not merge tests that check *different behaviors* even if structurally similar | Prevents silent coverage collapse |
| Do not change the order of assertions within a single test | May affect mock call order verification |
| Preserve all `xfail`, `skip`, and `raises` markers | They encode intentional negative cases |
| Do not inline fixtures that are used in >1 test file | Keep them in `conftest.py` |
| Keep mocks scoped as they were (patch target, autospec, etc.) | Changing mock scope changes what is tested |

---

## Phase 4 — Output Format

Return:
1. **The refactored file** — complete, runnable, no placeholders.
2. **Diff summary** — a brief bullet list:
   - Lines removed / added
   - Number of test functions before → after (parametrized tests count as 1
     function but N cases)
   - Fixtures extracted
   - Helpers introduced
3. **Coverage assertion** — Explicitly confirm each scenario from the Phase 1
   inventory is still covered and state *which* parametrized case or test
   function covers it.

---

## Language / Framework Defaults

| Context | Default tooling |
|---|---|
| Python | `pytest`, `@pytest.mark.parametrize`, `@pytest.fixture` in `conftest.py` |
| Async tests | `pytest-asyncio`, `@pytest.mark.asyncio` |
| Mocking | `unittest.mock.patch` / `pytest-mock`'s `mocker` fixture |
| JavaScript/TS | `describe` / `it` blocks, `beforeEach` shared setup, `test.each` |
| Java | JUnit 5 `@ParameterizedTest` + `@MethodSource` |

If the file uses a different framework, infer from imports and adapt the
transformation rules accordingly.
