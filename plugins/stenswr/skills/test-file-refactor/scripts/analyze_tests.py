#!/usr/bin/env python3
"""Deterministic analyzer for stenswr:test-file-refactor.

Scans a Python/pytest project for the High/Medium-confidence prune and gap
categories defined in ../rulebook.md. Emits a JSON array of candidates.

The analyzer is intentionally conservative: only checks that can be expressed
as AST / lexical rules with acceptable false-positive rate are implemented
here. Categories requiring semantic judgment (CHANGE_DETECTOR, MOCK_RETURN_
TAUTOLOGY, BYPASS_INTERFACE) are left for the LLM adjudication phase.

Usage:
    python3 analyze_tests.py \
        --project-root PATH \
        --output PATH/candidates.json \
        [--boundaries PATH/boundaries.txt]

Exit 0 on success even if no candidates found. Exit 2 on fatal error (no
.py files, invalid project root). Errors in individual files are logged and
skipped; the analyzer never aborts on a single bad parse.
"""

from __future__ import annotations

import argparse
import ast
import json
import os
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Iterable, Iterator

# --- Configuration -----------------------------------------------------------

# Boundary packages: mocks of these are OK (per rulebook P1).
DEFAULT_BOUNDARY_ALLOWLIST: set[str] = {
    # HTTP
    "requests", "httpx", "urllib", "urllib3", "aiohttp",
    # Cloud / AWS
    "boto3", "botocore",
    # DB drivers / engines
    "psycopg2", "psycopg", "pymysql", "mysql", "sqlite3",
    "sqlalchemy.engine", "sqlalchemy.orm.session",
    "redis", "pymongo",
    # Messaging
    "kafka", "pika", "kombu",
    # I/O and system
    "paramiko", "smtplib", "subprocess", "socket", "ssl",
    "os", "os.environ", "os.path", "pathlib", "shutil",
    "builtins.open", "open",
    # Time / random (non-determinism)
    "time", "datetime", "datetime.datetime",
    "random", "secrets", "uuid",
}

MOCK_FUNCS = {"patch", "patch.object", "patch.dict", "patch.multiple"}
MOCK_ATTR_CHAINS = {("mock", "patch"), ("unittest", "mock", "patch"), ("mocker", "patch")}
CALL_COUNT_ASSERT_METHODS = {
    "assert_called",
    "assert_called_once",
    "assert_called_with",
    "assert_called_once_with",
    "assert_any_call",
    "assert_has_calls",
    "assert_not_called",
}
CALL_COUNT_ATTRS = {"call_count", "call_args", "call_args_list", "mock_calls", "method_calls"}

TEST_FILE_GLOBS = ("test_*.py", "*_test.py")


# --- Data model --------------------------------------------------------------


@dataclass
class Candidate:
    file: str
    line: int
    category: str
    rule_id: str
    confidence: str  # HIGH | MEDIUM | LOW
    evidence: str


# --- Helpers -----------------------------------------------------------------


def _iter_python_files(root: Path, subdir: str | None = None) -> Iterator[Path]:
    base = root / subdir if subdir else root
    if not base.exists():
        return
    for p in base.rglob("*.py"):
        if any(part.startswith(".") for part in p.relative_to(root).parts):
            continue  # hidden dirs
        if "site-packages" in p.parts or "node_modules" in p.parts:
            continue
        yield p


def _iter_test_files(root: Path) -> Iterator[Path]:
    seen: set[Path] = set()
    for glob in TEST_FILE_GLOBS:
        for p in root.rglob(glob):
            if any(part.startswith(".") for part in p.relative_to(root).parts):
                continue
            if "site-packages" in p.parts or "node_modules" in p.parts:
                continue
            if p not in seen:
                seen.add(p)
                yield p


def _safe_parse(path: Path) -> ast.AST | None:
    try:
        return ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    except (SyntaxError, UnicodeDecodeError, OSError) as exc:
        print(f"[analyze] skip {path}: {exc}", file=sys.stderr)
        return None


def _detect_project_package(root: Path) -> str | None:
    """Best-effort: infer the top-level importable package name.

    Priority:
      1. pyproject.toml [project].name or [tool.poetry].name (parsed via tomllib)
      2. src/<name>/__init__.py
      3. <name>/__init__.py at root
    """
    py = root / "pyproject.toml"
    if py.exists():
        try:
            import tomllib  # Python 3.11+
            with py.open("rb") as fh:
                data = tomllib.load(fh)
            name = None
            project = data.get("project")
            if isinstance(project, dict):
                name = project.get("name")
            if not name:
                tool = data.get("tool", {})
                poetry = tool.get("poetry", {}) if isinstance(tool, dict) else {}
                if isinstance(poetry, dict):
                    name = poetry.get("name")
            if isinstance(name, str) and name:
                return name.replace("-", "_")
        except (OSError, ImportError, Exception) as exc:  # noqa: BLE001
            print(f"[analyze] pyproject.toml parse failed: {exc}", file=sys.stderr)
    src = root / "src"
    if src.is_dir():
        for child in src.iterdir():
            if child.is_dir() and (child / "__init__.py").exists():
                return child.name
    for child in root.iterdir():
        if (
            child.is_dir()
            and not child.name.startswith(".")
            and child.name not in {"tests", "test", "docs", "scripts", "build", "dist"}
            and (child / "__init__.py").exists()
        ):
            return child.name
    return None


def _is_internal_target(target: str, project_pkg: str | None, boundary_allowlist: set[str]) -> bool:
    """True if `target` looks like a same-project module (and not a boundary)."""
    return _classify_target(target, project_pkg, boundary_allowlist) == "internal"


def _classify_target(target: str, project_pkg: str | None, boundary_allowlist: set[str]) -> str:
    """Return one of 'internal', 'boundary', 'unknown' for a patch target string."""
    if not target:
        return "unknown"
    root = target.split(".", 1)[0]
    for boundary in boundary_allowlist:
        if target == boundary or target.startswith(boundary + "."):
            return "boundary"
        if root == boundary:
            return "boundary"
    if project_pkg and (target == project_pkg or target.startswith(project_pkg + ".")):
        return "internal"
    return "unknown"


def _literal_str(node: ast.AST | None) -> str | None:
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    return None


def _call_name(call: ast.Call) -> str:
    """Return a dotted name for Call.func, best effort."""
    return _dotted(call.func)


def _dotted(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return f"{_dotted(node.value)}.{node.attr}"
    return ""


# --- Rule checks -------------------------------------------------------------


def check_prune_rules(
    test_files: list[Path],
    project_root: Path,
    project_pkg: str | None,
    boundary_allowlist: set[str],
) -> list[Candidate]:
    results: list[Candidate] = []

    for path in test_files:
        tree = _safe_parse(path)
        if tree is None:
            continue
        rel = str(path.relative_to(project_root))

        # Gather symbols imported from project package for P3 import detection
        private_imports: dict[str, int] = {}
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module:
                mod = node.module
                if project_pkg and (mod == project_pkg or mod.startswith(project_pkg + ".")):
                    for alias in node.names:
                        name = alias.name
                        if name.startswith("_") and not (name.startswith("__") and name.endswith("__")):
                            private_imports[alias.asname or name] = node.lineno

        # Walk the AST once collecting rule hits
        for node in ast.walk(tree):

            # P1 / P2 — mock detection
            if isinstance(node, ast.Call):
                func_name = _call_name(node)
                # normalize `unittest.mock.patch` / `mock.patch` / `mocker.patch`
                is_patch = False
                if func_name.endswith(".patch") or func_name == "patch":
                    is_patch = True
                elif func_name.endswith(".patch.object") or func_name == "patch.object":
                    is_patch = True
                if is_patch:
                    target = _literal_str(node.args[0]) if node.args else None
                    if target and _is_internal_target(target, project_pkg, boundary_allowlist):
                        results.append(Candidate(
                            file=rel, line=node.lineno,
                            category="MOCK_INTERNAL", rule_id="P1",
                            confidence="HIGH",
                            evidence=f"{func_name}({target!r}) — target resolves inside project package"
                            + (f" '{project_pkg}'" if project_pkg else ""),
                        ))

            # P6 — @pytest.mark.skip / xfail without reason
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                for deco in node.decorator_list:
                    marker = _dotted(deco.func if isinstance(deco, ast.Call) else deco)
                    if marker.endswith(".skip") or marker.endswith(".xfail"):
                        has_reason = False
                        if isinstance(deco, ast.Call):
                            for kw in deco.keywords:
                                if kw.arg == "reason" and _literal_str(kw.value):
                                    has_reason = True
                                    break
                        if not has_reason:
                            results.append(Candidate(
                                file=rel, line=node.lineno,
                                category="SKIP_WITHOUT_REASON", rule_id="P6",
                                confidence="HIGH",
                                evidence=f"@{marker} on test '{node.name}' has no reason=",
                            ))

            # P7 — test function with no reachable assertion
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test"):
                if not _has_reachable_assertion(node):
                    results.append(Candidate(
                        file=rel, line=node.lineno,
                        category="DEAD_TEST_NO_ASSERT", rule_id="P7",
                        confidence="HIGH",
                        evidence=f"test '{node.name}' contains no assert / pytest.raises / approx",
                    ))

        # P2 — scoped per-function: only flag if the receiver is provably an
        # internal mock (decorator-based or local assignment). Unknown receivers
        # are emitted at MEDIUM confidence for LLM adjudication; boundary mocks
        # are not flagged (asserting on boundary mocks is correct practice).
        results.extend(_check_call_count_asserts(tree, rel, project_pkg, boundary_allowlist))

        # P3 follow-up: private symbol imports
        for name, line in private_imports.items():
            results.append(Candidate(
                file=rel, line=line,
                category="PRIVATE_METHOD_TEST", rule_id="P3",
                confidence="HIGH",
                evidence=f"imports private symbol '{name}' from project package",
            ))

        # P8 — duplicate canonical test bodies
        results.extend(_check_duplicate_bodies(tree, rel))

    return results


def _collect_mock_bindings(
    fn: ast.FunctionDef | ast.AsyncFunctionDef,
    project_pkg: str | None,
    boundary_allowlist: set[str],
) -> dict[str, str]:
    """Map local mock variable names -> classification ('internal'|'boundary'|'unknown').

    Picks up three forms:
      1. `@patch("target")` decorators inject a parameter (positional, in reverse
         decorator order — we map ALL mock-looking params to the union of
         decorator classifications; ambiguous cases are marked 'unknown').
      2. `name = mocker.patch("target")` / `name = patch("target").start()`
         assignments in the function body.
      3. `with patch("target") as name:` context manager bindings.
    """
    bindings: dict[str, str] = {}

    # (1) decorator-based: collect target classifications in order
    deco_targets: list[str] = []  # classifications in decorator source order (top-down)
    for deco in fn.decorator_list:
        call = deco if isinstance(deco, ast.Call) else None
        if call is None:
            continue
        name = _dotted(call.func)
        if not (name.endswith(".patch") or name == "patch"
                or name.endswith(".patch.object") or name == "patch.object"):
            continue
        target = _literal_str(call.args[0]) if call.args else None
        if target is None:
            deco_targets.append("unknown")
            continue
        deco_targets.append(_classify_target(target, project_pkg, boundary_allowlist))

    # pytest.mock / unittest.mock inject mocks in REVERSE decorator order (bottom-up).
    injected = list(reversed(deco_targets))
    # Skip `self` if present; count the trailing args matching injected mocks.
    params = [a.arg for a in fn.args.args]
    # Parameters that correspond to decorator-injected mocks are the last len(injected) ones.
    if injected and len(params) >= len(injected):
        for pname, cls in zip(params[-len(injected):], injected):
            bindings[pname] = cls

    # (2) / (3): scan body for assignments and with-blocks
    for node in ast.walk(fn):
        # x = mocker.patch("...") / x = patch("...").start()
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            value = node.value
            target_str: str | None = None
            if isinstance(value, ast.Call):
                name = _dotted(value.func)
                if name.endswith(".patch") or name == "patch" or name.endswith(".patch.object"):
                    target_str = _literal_str(value.args[0]) if value.args else None
                elif name.endswith(".start") and isinstance(value.func, ast.Attribute):
                    inner = value.func.value
                    if isinstance(inner, ast.Call):
                        iname = _dotted(inner.func)
                        if iname.endswith(".patch") or iname == "patch":
                            target_str = _literal_str(inner.args[0]) if inner.args else None
            if target_str is not None:
                bindings[node.targets[0].id] = _classify_target(target_str, project_pkg, boundary_allowlist)

        # with patch("...") as x:
        if isinstance(node, ast.With):
            for item in node.items:
                ctx = item.context_expr
                if isinstance(ctx, ast.Call) and isinstance(item.optional_vars, ast.Name):
                    name = _dotted(ctx.func)
                    if name.endswith(".patch") or name == "patch" or name.endswith(".patch.object"):
                        target = _literal_str(ctx.args[0]) if ctx.args else None
                        if target is not None:
                            bindings[item.optional_vars.id] = _classify_target(
                                target, project_pkg, boundary_allowlist
                            )
    return bindings


def _attr_root(node: ast.AST) -> str | None:
    """Return the leftmost Name in an attribute chain, e.g. `a.b.c` -> 'a'."""
    while isinstance(node, ast.Attribute):
        node = node.value
    if isinstance(node, ast.Name):
        return node.id
    return None


def _check_call_count_asserts(
    tree: ast.AST,
    rel: str,
    project_pkg: str | None,
    boundary_allowlist: set[str],
) -> list[Candidate]:
    """P2 — flag call-count / call-args assertions, scoped to internal mocks.

    - Receiver provably bound to an internal mock: HIGH.
    - Receiver provably bound to a boundary mock: not flagged (correct practice).
    - Receiver unknown: MEDIUM (LLM must classify).
    """
    out: list[Candidate] = []
    for fn in ast.walk(tree):
        if not isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        bindings = _collect_mock_bindings(fn, project_pkg, boundary_allowlist)

        for node in ast.walk(fn):
            # method-call form: mock.assert_called_once_with(...)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
                if node.func.attr in CALL_COUNT_ASSERT_METHODS:
                    root = _attr_root(node.func.value)
                    cls = bindings.get(root, "unknown") if root else "unknown"
                    if cls == "boundary":
                        continue
                    conf = "HIGH" if cls == "internal" else "MEDIUM"
                    out.append(Candidate(
                        file=rel, line=node.lineno,
                        category="CALL_COUNT_ASSERT", rule_id="P2",
                        confidence=conf,
                        evidence=f"{_dotted(node.func)}(...) on mock classified '{cls}'",
                    ))

            # assert form: assert mock.call_count == N
            if isinstance(node, ast.Assert):
                for sub in ast.walk(node.test):
                    if isinstance(sub, ast.Attribute) and sub.attr in CALL_COUNT_ATTRS:
                        root = _attr_root(sub.value)
                        cls = bindings.get(root, "unknown") if root else "unknown"
                        if cls == "boundary":
                            break
                        conf = "HIGH" if cls == "internal" else "MEDIUM"
                        out.append(Candidate(
                            file=rel, line=node.lineno,
                            category="CALL_COUNT_ASSERT", rule_id="P2",
                            confidence=conf,
                            evidence=f"assert on .{sub.attr} (mock classified '{cls}')",
                        ))
                        break
    return out


def _has_reachable_assertion(fn: ast.FunctionDef | ast.AsyncFunctionDef) -> bool:
    """Return True if the function contains at least one assert-like statement
    that is not preceded on its direct path by a return/raise."""
    # Simple linear scan: walk body; if we hit a Return/Raise at top level
    # before any assert, remaining statements are unreachable at that scope.
    # For nested blocks we conservatively say "has assertion" if any assert
    # appears inside (could be False positive for dead branches, but those
    # are rare and not worth chasing).
    for stmt in fn.body:
        if _stmt_has_assert(stmt):
            return True
        if isinstance(stmt, (ast.Return, ast.Raise)):
            return False
    return False


def _stmt_has_assert(stmt: ast.AST) -> bool:
    for node in ast.walk(stmt):
        if isinstance(node, ast.Assert):
            return True
        if isinstance(node, ast.With):
            # `with pytest.raises(...)` counts as an assertion
            for item in node.items:
                ctx = item.context_expr
                name = _dotted(ctx.func) if isinstance(ctx, ast.Call) else _dotted(ctx)
                if name.endswith("raises") or name.endswith("warns") or name.endswith("deprecated_call"):
                    return True
        if isinstance(node, ast.Call):
            name = _call_name(node)
            if name.endswith("pytest.raises") or name == "pytest.raises":
                return True
            if name.endswith("assert_called") or name.endswith("assert_called_once"):
                return True
            if name.endswith("assert_called_with") or name.endswith("assert_called_once_with"):
                return True
            if name.endswith("approx"):
                return True
    return False


def _check_duplicate_bodies(tree: ast.AST, rel_path: str) -> list[Candidate]:
    """Flag groups of test functions sharing a canonical AST body."""
    buckets: dict[str, list[tuple[str, int]]] = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test"):
            sig = _canonical_body(node)
            if sig:
                buckets.setdefault(sig, []).append((node.name, node.lineno))

    out: list[Candidate] = []
    for sig, members in buckets.items():
        if len(members) >= 2:
            first_line = members[0][1]
            names = ", ".join(n for n, _ in members)
            out.append(Candidate(
                file=rel_path, line=first_line,
                category="DUPLICATE_TEST_BODY", rule_id="P8",
                confidence="MEDIUM",
                evidence=f"{len(members)} tests with identical canonical body: {names}",
            ))
    return out


def _canonical_body(fn: ast.FunctionDef | ast.AsyncFunctionDef) -> str:
    """Canonicalize function body: structure + call/method names, literals elided."""
    parts: list[str] = []
    for stmt in fn.body:
        parts.append(_canonical_node(stmt))
    return "|".join(parts)


def _canonical_node(node: ast.AST) -> str:
    if isinstance(node, ast.Expr):
        return f"E({_canonical_node(node.value)})"
    if isinstance(node, ast.Assign):
        return f"A({_canonical_node(node.value)})"
    if isinstance(node, ast.Assert):
        return f"AS({_canonical_node(node.test)})"
    if isinstance(node, ast.Call):
        return f"C({_dotted(node.func)})"
    if isinstance(node, ast.Compare):
        ops = "/".join(type(o).__name__ for o in node.ops)
        return f"CMP({_canonical_node(node.left)}:{ops})"
    if isinstance(node, ast.Attribute):
        return f"AT({_dotted(node)})"
    if isinstance(node, ast.Name):
        # elide name (treat as wildcard); use '.' so `x` and `y` collapse
        return "N"
    if isinstance(node, ast.Constant):
        return "L"
    if isinstance(node, ast.With):
        return "W(" + ",".join(_canonical_node(s) for s in node.body) + ")"
    if isinstance(node, (ast.Return, ast.Raise)):
        return type(node).__name__
    return type(node).__name__


# --- Gap checks --------------------------------------------------------------


def check_gap_rules(
    test_files: list[Path],
    project_root: Path,
    project_pkg: str | None,
    boundary_allowlist: set[str],
) -> list[Candidate]:
    results: list[Candidate] = []

    # G1 — broken imports from project package
    if project_pkg:
        exported = _collect_project_symbols(project_root, project_pkg)
        for path in test_files:
            tree = _safe_parse(path)
            if tree is None:
                continue
            rel = str(path.relative_to(project_root))
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom) and node.module:
                    mod = node.module
                    if mod == project_pkg or mod.startswith(project_pkg + "."):
                        known = exported.get(mod, set())
                        if not known:
                            continue  # unknown module — could not verify
                        for alias in node.names:
                            if alias.name == "*":
                                continue
                            if alias.name not in known:
                                results.append(Candidate(
                                    file=rel, line=node.lineno,
                                    category="BROKEN_IMPORT", rule_id="G1",
                                    confidence="HIGH",
                                    evidence=f"'{alias.name}' not found in '{mod}'",
                                ))

    # G2 — happy-path-only (test file with ≥3 tests, 0 error-path assertions,
    # AND the corresponding source module contains `raise` statements).
    source_raises = _collect_source_raises(project_root, project_pkg) if project_pkg else {}
    for path in test_files:
        tree = _safe_parse(path)
        if tree is None:
            continue
        rel = str(path.relative_to(project_root))
        test_count = 0
        error_assert_count = 0
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test"):
                test_count += 1
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                name = _call_name(node)
                if (
                    name == "pytest.raises"
                    or name.endswith(".pytest.raises")
                    or name == "pytest.warns"
                    or name.endswith(".pytest.warns")
                    or name in {"raises", "warns"}
                ):
                    error_assert_count += 1
            if isinstance(node, ast.With):
                for item in node.items:
                    ctx = item.context_expr
                    name = _dotted(ctx.func) if isinstance(ctx, ast.Call) else _dotted(ctx)
                    if name.endswith("raises") or name.endswith("warns"):
                        error_assert_count += 1
        if test_count >= 3 and error_assert_count == 0:
            # Only flag if the corresponding source module actually raises.
            stem = path.stem
            if stem.startswith("test_"):
                src_stem = stem[len("test_"):]
            elif stem.endswith("_test"):
                src_stem = stem[: -len("_test")]
            else:
                src_stem = stem
            has_source_raise = any(s == src_stem for s in source_raises)
            if project_pkg and not has_source_raise:
                continue  # no sibling source raises -> no gap to flag
            if not project_pkg:
                # no project package detected: keep at MEDIUM instead of HIGH
                conf = "MEDIUM"
                evidence = f"{test_count} tests, 0 pytest.raises/warns blocks (source coupling not verifiable)"
            else:
                conf = "HIGH"
                evidence = (
                    f"{test_count} tests, 0 pytest.raises/warns blocks; "
                    f"source module '{src_stem}' contains raise statements"
                )
            results.append(Candidate(
                file=rel, line=1,
                category="HAPPY_PATH_ONLY", rule_id="G2",
                confidence=conf,
                evidence=evidence,
            ))

    # G3 — undocumented raise path untested (per source module → sibling test file)
    if project_pkg:
        results.extend(_check_undocumented_raise_untested(project_root, project_pkg))

    return results


def _collect_source_raises(project_root: Path, project_pkg: str) -> set[str]:
    """Return the set of source module stems (file basenames without .py) that
    contain at least one `raise` statement. Used to gate G2 so test files are
    only flagged when the corresponding source actually has error paths."""
    out: set[str] = set()
    pkg_root = (project_root / "src" / project_pkg) if (project_root / "src" / project_pkg).exists() else (project_root / project_pkg)
    if not pkg_root.exists():
        return out
    for py in pkg_root.rglob("*.py"):
        if py.name.startswith("test_") or py.name.endswith("_test.py"):
            continue
        tree = _safe_parse(py)
        if tree is None:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Raise):
                out.add(py.stem)
                break
    return out


def _collect_project_symbols(project_root: Path, project_pkg: str) -> dict[str, set[str]]:
    """Map module dotted-name → set of top-level names defined in that module."""
    out: dict[str, set[str]] = {}

    candidates: list[Path] = []
    src_pkg = project_root / "src" / project_pkg
    if src_pkg.exists():
        candidates.append(src_pkg)
    flat_pkg = project_root / project_pkg
    if flat_pkg.exists():
        candidates.append(flat_pkg)

    for pkg_root in candidates:
        for py in pkg_root.rglob("*.py"):
            tree = _safe_parse(py)
            if tree is None:
                continue
            rel = py.relative_to(pkg_root).with_suffix("")
            parts = list(rel.parts)
            if parts and parts[-1] == "__init__":
                parts = parts[:-1]
            mod = ".".join([project_pkg] + parts) if parts else project_pkg
            names: set[str] = set()
            _collect_names_from_stmts(tree.body, names)
            out[mod] = names
    return out


def _collect_names_from_stmts(stmts: Iterable[ast.stmt], names: set[str]) -> None:
    """Collect top-level-ish names, descending into conditional imports.

    Walks into:
      - `if TYPE_CHECKING:` / `if sys.version_info ...:` branches (both sides)
      - `try: ... except ImportError: ...` blocks (both body and handlers)

    This prevents G1 (BROKEN_IMPORT) false positives on symbols that exist
    only inside a conditional import block.
    """
    for node in stmts:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(node.name)
        elif isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    names.add(target.id)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            names.add(node.target.id)
        elif isinstance(node, ast.ImportFrom):
            for alias in node.names:
                if alias.name != "*":
                    names.add(alias.asname or alias.name)
        elif isinstance(node, ast.Import):
            for alias in node.names:
                top = (alias.asname or alias.name).split(".", 1)[0]
                names.add(top)
        elif isinstance(node, ast.If):
            _collect_names_from_stmts(node.body, names)
            _collect_names_from_stmts(node.orelse, names)
        elif isinstance(node, ast.Try):
            _collect_names_from_stmts(node.body, names)
            for h in node.handlers:
                _collect_names_from_stmts(h.body, names)
            _collect_names_from_stmts(node.orelse, names)
            _collect_names_from_stmts(node.finalbody, names)


def _check_undocumented_raise_untested(project_root: Path, project_pkg: str) -> list[Candidate]:
    """For each public source function with an explicit raise X, check whether
    the sibling test file references pytest.raises(X)."""
    results: list[Candidate] = []

    pkg_root = (project_root / "src" / project_pkg) if (project_root / "src" / project_pkg).exists() else (project_root / project_pkg)
    if not pkg_root.exists():
        return results

    for py in pkg_root.rglob("*.py"):
        if py.name.startswith("test_") or py.name.endswith("_test.py"):
            continue
        tree = _safe_parse(py)
        if tree is None:
            continue
        # Collect public function -> set of raised exception type names
        raises_by_fn: dict[str, set[str]] = {}
        for node in tree.body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and not node.name.startswith("_"):
                exc_names: set[str] = set()
                for sub in ast.walk(node):
                    if isinstance(sub, ast.Raise) and sub.exc is not None:
                        t = sub.exc
                        if isinstance(t, ast.Call):
                            t = t.func
                        name = _dotted(t).split(".")[-1] if _dotted(t) else ""
                        if name:
                            exc_names.add(name)
                if exc_names:
                    raises_by_fn[node.name] = exc_names
        if not raises_by_fn:
            continue

        # Locate likely sibling test file
        test_candidates = list((project_root).rglob(f"test_{py.stem}.py")) + list((project_root).rglob(f"{py.stem}_test.py"))
        if not test_candidates:
            continue
        test_path = test_candidates[0]
        test_tree = _safe_parse(test_path)
        if test_tree is None:
            continue
        tested_excs: set[str] = set()
        for node in ast.walk(test_tree):
            if isinstance(node, ast.Call):
                name = _call_name(node)
                if name == "pytest.raises" or name.endswith("pytest.raises") or name == "raises":
                    if node.args:
                        first = node.args[0]
                        tested_excs.add(_dotted(first).split(".")[-1])
            if isinstance(node, ast.With):
                for item in node.items:
                    ctx = item.context_expr
                    if isinstance(ctx, ast.Call):
                        name = _call_name(ctx)
                        if name.endswith("raises") and ctx.args:
                            tested_excs.add(_dotted(ctx.args[0]).split(".")[-1])

        for fn_name, exc_set in raises_by_fn.items():
            missing = exc_set - tested_excs
            if missing:
                results.append(Candidate(
                    file=str(test_path.relative_to(project_root)),
                    line=1,
                    category="UNDOCUMENTED_RAISE_UNTESTED",
                    rule_id="G3",
                    confidence="MEDIUM",
                    evidence=f"{project_pkg}.{py.stem}.{fn_name} raises {sorted(missing)} but no pytest.raises in sibling tests",
                ))
    return results


# --- Main --------------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-root", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--boundaries", type=Path, default=None,
                    help="Optional file; one additional boundary package per line.")
    args = ap.parse_args()

    root = args.project_root.resolve()
    if not root.is_dir():
        print(f"[analyze] project-root not a directory: {root}", file=sys.stderr)
        return 2

    boundary_allowlist = set(DEFAULT_BOUNDARY_ALLOWLIST)
    if args.boundaries and args.boundaries.exists():
        for line in args.boundaries.read_text(encoding="utf-8").splitlines():
            s = line.strip()
            if s and not s.startswith("#"):
                boundary_allowlist.add(s)

    test_files = list(_iter_test_files(root))
    if not test_files:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text("[]\n", encoding="utf-8")
        print("[analyze] no pytest-style test files found", file=sys.stderr)
        return 0

    project_pkg = _detect_project_package(root)
    print(f"[analyze] project_root={root}", file=sys.stderr)
    print(f"[analyze] project_pkg={project_pkg or '(not detected)'}", file=sys.stderr)
    print(f"[analyze] test files={len(test_files)}", file=sys.stderr)

    prune = check_prune_rules(test_files, root, project_pkg, boundary_allowlist)
    gaps = check_gap_rules(test_files, root, project_pkg, boundary_allowlist)

    # Stable sort by (file, line, rule_id) for diff-friendly output.
    all_candidates = sorted(prune + gaps, key=lambda c: (c.file, c.line, c.rule_id))
    results = [asdict(c) for c in all_candidates]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")

    print(f"[analyze] prune candidates: {len(prune)}", file=sys.stderr)
    print(f"[analyze] gap candidates:   {len(gaps)}", file=sys.stderr)
    print(f"[analyze] wrote: {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
