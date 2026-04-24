---
name: test-file-compaction
description: Refactors existing test files to reduce line count and eliminate repetition without dropping any test case, assertion, or edge-case coverage. Extracts fixtures, parametrizes duplicate test bodies, introduces shared assertion helpers, and hoists repeated constants — preserving full test semantics throughout.
disable-model-invocation: true
---

# Skill: Compact Test File (Lossless)

## Intent
Reduce the line count and cognitive load of an existing test file **without
dropping any test case, assertion, or edge-case coverage**.
Preserve the exact semantics of every test; only restructure *how* they are
expressed.

---

## Phase 1 — Analysis (read-only, no edits yet)

Before touching a single line, mentally inventory:

1. **Coverage map** — every distinct input/output or behavior being verified.
2. **Repetition scan** — blocks differing only by input/expected.
3. **Smell list** — inline duplication, repeated literals, dead assertions.

Do NOT output the inventory into the file. Proceed directly to transforms.

---

## Phase 2 — Transformation Rules (apply in order)

### Rule 1 · Parametrize identical test bodies
If ≥2 test functions share the same body structure and differ only in their
inputs or expected outputs, collapse them into a single parametrized test.
This applies to ALL of these patterns:
- Simple assertion tests with different values
- `pytest.raises` blocks with different inputs/match strings
- Tests that construct an object with one varying field and assert on it

```python
# BEFORE
def test_add_positive():
    assert add(2, 3) == 5

def test_add_negative():
    assert add(-1, -1) == -2

# AFTER
@pytest.mark.parametrize("a,b,expected", [
    pytest.param(2, 3, 5, id="positive"),
    pytest.param(-1, -1, -2, id="negative"),
])
def test_add(a, b, expected):
    assert add(a, b) == expected
```

**Constraint:** Each parametrize tuple must include a meaningful `id` via
`pytest.param(..., id="...")` when the values alone are not self-documenting.

**Raises pattern:** Collapse identical `pytest.raises` blocks:
```python
# BEFORE
def test_empty_name_raises():
    with pytest.raises(ValueError, match="Empty name"):
        parse(",data")

def test_empty_id_raises():
    with pytest.raises(ValueError, match="Empty id"):
        parse("name,")

# AFTER
@pytest.mark.parametrize("csv_input,match", [
    pytest.param(",data", "Empty name", id="empty-name"),
    pytest.param("name,", "Empty id", id="empty-id"),
])
def test_parse_invalid_input_raises(csv_input, match):
    with pytest.raises(ValueError, match=match):
        parse(csv_input)
```

---

### Rule 2 · Extract fixtures for repeated setup
If the same object construction or mock setup appears in ≥2 tests, move it
into a `@pytest.fixture`. Prefer function-scoped fixtures unless the object is
provably immutable, in which case `scope="module"` is acceptable.

---

### Rule 3 · Consolidate over-isolated attribute tests
If ≥2 tests perform **identical setup** and each checks a single attribute or
key of the same result, merge them into one test with multiple assertions.
Each original scenario is preserved — just in fewer test functions.

```python
# BEFORE (3 tests, same setup, one assert each)
def test_result_has_entries_key(builder):
    result = builder.build()
    assert "entries" in result

def test_result_has_count_key(builder):
    result = builder.build()
    assert "count" in result

# AFTER (1 test, same assertions preserved)
def test_build_result_keys(builder):
    result = builder.build()
    assert "entries" in result
    assert "count" in result
```

When merging, keep test name descriptive of all checked attributes.
**Guardrail:** Only merge when setup is truly identical. Never merge tests
whose setup, input, or tested behavior differs.

---

### Rule 4 · Collapse cloned test classes differing by one parameter
If two test classes repeat similar tests but differ only by a constructor
argument (e.g., `strict=True` vs `strict=False`), merge them using
`@pytest.mark.parametrize` at class level or by parametrizing individual
tests. Tests unique to one variant stay as standalone tests.

```python
# BEFORE: TestFoo and TestFooStrict with duplicated tests
# AFTER
@pytest.mark.parametrize("strict", [False, True], ids=["default", "strict"])
def test_add_single_entry(strict):
    builder = Builder(strict=strict)
    builder.add(item)
    assert len(builder.items) == 1
```

---

### Rule 5 · Shared assertion helpers
If a multi-assertion pattern recurs (e.g. checking a response object's status
+ body + headers), extract it into a local helper function prefixed with
`assert_`.

Helpers live at the **top of the same test module** or in `conftest.py` if
shared across modules.

---

### Rule 6 · Constant tables over inline literals
If the same constant (URL, timeout, topic name, device ID, etc.) is spelled
out inline across tests, hoist it to a module-level constant or a
`conftest.py` variable.

---

### Rule 7 · Flatten single-test classes
A `TestClass` containing only one test method adds indirection with no
benefit. Flatten it to a module-level function unless the class provides
shared fixtures via `setup_method` / class-scoped state.

---

### Rule 8 · Remove redundant assertions
Delete assertions that are always trivially true given the preceding logic
(e.g. `assert result is not None` immediately after `result = []`).
**Do NOT remove assertions that guard against future regressions**, even if
they seem obvious today.

---

### Rule 9 · Absorb shape-of-output tests into content tests
If one test checks "key X exists in result" and another test already reads
`result["X"]` (which would fail if the key were missing), the shape test is
redundant. Absorb it — do NOT drop the scenario; instead merge the key-check
assertion into the test that uses the value.

---

### Rule 10 · Deduplicate stub/mock setup
If multiple tests (or a helper called before tests) set up the same mock/stub
(e.g. `when(httpx).get(...).thenReturn(resp)`), extract it into a fixture or
a module-level helper. Preserve the framework — if the file uses `mockito`,
keep `mockito`; if it uses `unittest.mock`, keep that.

---

### Rule 11 · Merge small related test classes
If ≥2 test classes in the same file each contain ≤3 test methods and test
the same function or closely-related behavior, merge them into one class.
The merged class name should cover the common theme. This removes class
definition overhead and inter-class blank lines.

```python
# BEFORE (2 classes, 2 tests each, same function)
class TestDeterministicIds:
    def test_same_input_same_id(self): ...
    def test_different_rule_different_id(self): ...

class TestReasonDisplay:
    def test_template_renders(self): ...
    def test_sum_template(self): ...

# AFTER (1 class, 4 tests)
class TestOutputProperties:
    def test_same_input_same_id(self): ...
    def test_different_rule_different_id(self): ...
    def test_template_renders(self): ...
    def test_sum_template(self): ...
```

**Guardrail:** Only merge classes whose tests are logically related.
Never merge classes that use different fixtures, different setup_method,
or test different source modules.

---

### Rule 12 · Parametrize same-shape error/log assertions
If ≥2 tests differ only in the exception type, error setup, or trigger
but check the same assertion pattern (e.g., all assert a warning is logged),
collapse into a parametrized test:

```python
# BEFORE (3 tests, same assertion pattern)
def test_http_error_logs_warning(self, caplog):
    when(httpx).post(...).thenRaise(httpx.HTTPStatusError(...))
    with caplog.at_level(logging.WARNING):
        export(...)
    assert any("Failed" in m for m in caplog.messages)

def test_connect_error_logs_warning(self, caplog):
    when(httpx).post(...).thenRaise(httpx.ConnectError("refused"))
    with caplog.at_level(logging.WARNING):
        export(...)
    assert any("Failed" in m for m in caplog.messages)

# AFTER
@pytest.mark.parametrize("exc", [
    pytest.param(httpx.HTTPStatusError(...), id="http-error"),
    pytest.param(httpx.ConnectError("refused"), id="connect-error"),
])
def test_error_logs_warning(self, caplog, exc):
    when(httpx).post(...).thenRaise(exc)
    with caplog.at_level(logging.WARNING):
        export(...)
    assert any("Failed" in m for m in caplog.messages)
```

---

## Phase 2b — Optional Style Rules (ask first)

**These rules improve conciseness but are opinionated — they touch
documentation, formatting, or annotation style rather than test structure.**

Before applying any rule in this section:

1. **Ask the user** whether they want optional style rules applied.
   Present the three sub-categories and let them opt in/out per category:
   - *Documentation* (S1–S2): remove docstrings from tests
   - *Formatting* (S3–S4): compact call arguments, collapse signatures
   - *Annotation & variable style* (S5–S6): drop `-> None`, inline variables
2. **Check the repo's toolchain.** Inspect `setup.cfg`, `pyproject.toml`,
   `.flake8`, `.mypy.ini`, `tox.ini`, and any formatter config. If a rule
   would be **reversed by the formatter** or would **introduce linter /
   type-checker violations**, skip it silently — do not fight the toolchain.
   Specific conflicts to watch for:
   - **S1/S2** (docstrings): skip if `pydocstyle` or `flake8-docstrings`
     enforces `D100`–`D107` (i.e. those codes are **not** in the ignore list).
   - **S3/S4** (formatting): skip if `black`, `autopep8`, or `yapf` is
     configured — the formatter owns line layout and will reformat anyway.
   - **S5** (`-> None`): skip if `mypy` has `disallow_untyped_defs = true`
     — removing the return annotation would cause a type error.

---

### S1 · Remove test method docstrings
Test method names should be self-documenting. Remove docstrings from
individual test methods. Keep the module-level docstring and class-level
docstrings only if they add context not obvious from the class name.

---

### S2 · Remove module-level docstrings
Test filenames already describe their purpose. Remove the module-level
docstring (the top `"""..."""`) to save lines. Keep import statements
immediately after the frontmatter.

---

### S3 · Compact function call arguments
Where a function call or constructor spans many lines with one argument per
line, collapse to fewer lines if the total stays under ~88 chars:

```python
# BEFORE
record = HitCountRecord(
    policy_id="P001",
    policy_name="Test",
    sysname="SYS1",
    day=_DAY1,
    hour=0,
    hits=0,
)

# AFTER
record = HitCountRecord(
    policy_id="P001", policy_name="Test",
    sysname="SYS1", day=_DAY1, hour=0, hits=0,
)
```

---

### S4 · Single-line method signatures
Check whether the `def` line can fit entirely on one line (under ~99 chars).
If so, collapse the arguments:

```python
# BEFORE (3 lines)
def test_logs_info(
    self, caplog: pytest.LogCaptureFixture,
):

# AFTER (1 line)
def test_logs_info(self, caplog: pytest.LogCaptureFixture):
```

---

### S5 · Drop `-> None` from test method signatures
Test methods always return None. Remove the `-> None` annotation to save
characters and, in some cases, allow the entire `def` line + arguments to
fit on a single line that would otherwise wrap:

```python
# BEFORE (3 lines)
def test_foo(
    self, caplog: pytest.LogCaptureFixture, exc: Exception,
) -> None:

# AFTER (1 line)
def test_foo(self, caplog: pytest.LogCaptureFixture, exc: Exception):
```

---

### S6 · Inline single-use intermediate variables
If a variable is assigned and used exactly once on the next line as part of
a simple assertion, inline it:

```python
# BEFORE
result = foo()
assert result == 42

# AFTER
assert foo() == 42
```

**Exception:** Keep the variable when:
- It is used more than once, OR
- The expression is complex (readability matters), OR
- The variable is needed for a meaningful assertion message.

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
| Preserve the file's existing mock/stub framework — never replace, wrap, or add imports from a different mocking library | Swapping frameworks changes test semantics and breaks CI |

---

## Phase 4 — Output Format

Return the **refactored file** — complete, runnable, no placeholders.

Do NOT include a diff summary, comment block, or coverage assertion in the
output file. The file should contain only valid Python — no analysis comments.

---

## Language / Framework Defaults

| Context | Default tooling |
|---|---|
| Python | `pytest`, `@pytest.mark.parametrize`, `@pytest.fixture` |
| Mocking | Infer from imports — if the file uses `mockito`, keep `mockito`; if `unittest.mock`, keep that |

If the file uses a different framework, infer from imports and adapt the
transformation rules accordingly. **Never introduce a mock library the file
does not already import.**
