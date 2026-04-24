# `scripts/analyze_tests.py` — analyzer contract

Deterministic static analyzer invoked by the skill's `SKILL.md` Phase 1.
Emits a JSON array of candidates keyed by the rule IDs in the skill's
`rulebook.md`.

## Invocation

```bash
python3 analyze_tests.py \
    --project-root /path/to/target/repo \
    --output /path/to/output/candidates.json \
    [--boundaries /path/to/boundaries.txt]
```

- `--project-root` — directory containing the target Python project.
- `--output` — JSON array written here (parent directories created as needed).
- `--boundaries` — optional; one additional boundary package per line;
  appended to the built-in allowlist for rule P1.

Exit codes:

- `0` — analyzer completed (regardless of candidate count).
- `2` — fatal error (project root not a directory, etc.).

Individual unparseable `.py` files are logged to stderr and skipped.

## Output schema

```json
[
  {
    "file": "tests/test_user.py",
    "line": 42,
    "category": "MOCK_INTERNAL",
    "rule_id": "P1",
    "confidence": "HIGH",
    "evidence": "patch('app.repository.UserRepo') — target resolves inside project package 'app'"
  }
]
```

- `confidence` is one of `HIGH`, `MEDIUM`, `LOW`. Rules are tiered in the
  rulebook; the analyzer never downgrades a rule below its rulebook tier, but
  may emit `MEDIUM` where the rule itself allows (e.g., attribute-based
  `PRIVATE_METHOD_TEST` on unknown receivers).
- `evidence` is human-readable and shown verbatim in the plan.

## Checks implemented

| Rule | Category                     | Method                                                                 |
|------|------------------------------|------------------------------------------------------------------------|
| P1   | `MOCK_INTERNAL`              | `patch(literal)` where literal starts with detected project package    |
| P2   | `CALL_COUNT_ASSERT`          | Method calls in `assert_called*` set; attribute access on `call_count` / `call_args` / `mock_calls` under `assert` — **scoped per-function to mocks provably bound to internal targets (HIGH) or unknown receivers (MEDIUM); boundary-bound mocks are not flagged** |
| P3   | `PRIVATE_METHOD_TEST`        | `from <project_pkg> import _name` (HIGH). The generic `obj._attr` attribute heuristic was intentionally dropped — too many false positives on namedtuple `_asdict`, mock internals, framework attributes, and third-party APIs. Private-method misuse without an import is left to the LLM phase. |
| P6   | `SKIP_WITHOUT_REASON`        | `@pytest.mark.skip` / `@pytest.mark.xfail` with no `reason=` kwarg     |
| P7   | `DEAD_TEST_NO_ASSERT`        | Test function with no `assert`, no `pytest.raises` / `warns`, no `assert_called*`, no `pytest.approx` reachable before first `return`/`raise` at body level |
| P8   | `DUPLICATE_TEST_BODY`        | ≥ 2 tests in one file share a canonical AST body (literals elided, names elided, structure preserved) |
| G1   | `BROKEN_IMPORT`              | `from <project_pkg>.<module> import X` where `X` is not a top-level symbol in that module |
| G2   | `HAPPY_PATH_ONLY`            | Test file with ≥ 3 test functions and 0 `pytest.raises` / `with raises` / `pytest.warns` **AND** the corresponding source module (by stem match) contains `raise` statements. If no project package is detected, downgraded to MEDIUM. |
| G3   | `UNDOCUMENTED_RAISE_UNTESTED`| Source function has `raise X`; sibling test file (`test_<stem>.py` or `<stem>_test.py`) never references `pytest.raises(X)` |

## Checks NOT implemented here (LLM adjudication required)

These are rulebook rules but require semantic reading beyond AST patterns.
The SKILL drives them in Phase 2.

- `P4 CHANGE_DETECTOR` — requires judgment on whether a matched message is
  a published contract.
- `P5 MOCK_RETURN_TAUTOLOGY` — requires reading data flow between mock
  setup and assertion; too many false positives with pure static matching.
- `P9 BYPASS_INTERFACE` — requires knowing which functions are read-side
  interfaces vs. raw DB/FS helpers.
- `P10 DEAD_TEST_SYMBOL` — fed from `python-refactor:measure` output when
  available, not computed here.
- `G4` / `G5` / `G6` — require `__all__` scanning, integration-file
  conventions, and coverage artefacts respectively; handled in SKILL phases.

## Boundary allowlist (built-in, rule P1)

Mocks of these packages are **not** flagged as `MOCK_INTERNAL`:

```
requests httpx urllib urllib3 aiohttp
boto3 botocore
psycopg2 psycopg pymysql mysql sqlite3
sqlalchemy.engine sqlalchemy.orm.session
redis pymongo
kafka pika kombu
paramiko smtplib subprocess socket ssl
os os.environ os.path pathlib shutil
builtins.open open
time datetime datetime.datetime
random secrets uuid
```

Projects can extend this list via `--boundaries`:

```
# .test-file-refactor/boundaries.txt
stripe
internal_sdk.clock   # if you have your own boundary module
```

## Project package detection

The analyzer tries, in order:

1. `pyproject.toml` `[project] name = "..."` (dashes normalized to
   underscores).
2. `src/<name>/__init__.py`.
3. `<name>/__init__.py` at root (excluding common non-package directories:
   `tests`, `test`, `docs`, `scripts`, `build`, `dist`).

If no package is detected, `G1` / `G3` / `P1`-via-package are skipped
(logged to stderr). Per-file rules still run.

## Determinism

- No network calls.
- No code execution of the target repo (pure AST parse via `ast` stdlib).
- No coverage reports consumed here — that is SKILL phase 0.4.
- Output is stable-sorted by `(file, line, rule_id)` for diff-friendly runs.

## Dependencies

Python 3.11+ stdlib only (uses `ast` and `tomllib`). No third-party packages
required.
[`vulture`](https://pypi.org/project/vulture/) is an optional enhancement
invoked by the skill for rule P10 when available — not invoked from this
script.
