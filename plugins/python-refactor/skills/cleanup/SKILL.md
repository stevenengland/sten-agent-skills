---
name: cleanup
description: Remove all python-refactor plugin output and project-root tool caches. Deletes the entire .python-refactor/ directory (all runs, all deliverables) and project-root tool caches (.hypothesis/, .pytest_cache/, .semgrep/, .skylos_cache/) unconditionally. This is a hard nuke — use when you are done with all analysis and want a clean project root. Safe to run multiple times. Does not touch global tool caches or filed issues.
---

# python-refactor: Cleanup

Remove all plugin output and tool caches from the project root.

Announce: "Using python-refactor:cleanup to remove all analysis artifacts."

**Platform note:** Claude Code tool names used. On Copilot CLI: Bash -> runCommand.

---

## 1. Inventory what exists

Use Bash to check what will be deleted:

  OUTPUT_DIR="PROJECT_ROOT/.python-refactor"
  TOOL_CACHES=(.hypothesis .pytest_cache .semgrep .skylos_cache)

  echo "=== Plugin output ==="
  if [ -d "$OUTPUT_DIR" ]; then
    find "$OUTPUT_DIR" -type f | head -50
    echo "---"
    du -sh "$OUTPUT_DIR"
  else
    echo "No .python-refactor/ directory found — nothing to clean."
  fi

  echo ""
  echo "=== Tool caches ==="
  for d in "${TOOL_CACHES[@]}"; do
    if [ -d "PROJECT_ROOT/$d" ]; then
      echo "$d/ exists ($(du -sh "PROJECT_ROOT/$d" | cut -f1))"
    fi
  done

Print the inventory to the user.

---

## 2. Delete plugin output

  if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
    echo "Deleted $OUTPUT_DIR"
  fi

---

## 3. Delete project-root tool caches

  for d in "${TOOL_CACHES[@]}"; do
    if [ -d "PROJECT_ROOT/$d" ]; then
      rm -rf "PROJECT_ROOT/$d"
      echo "Deleted $d/"
    fi
  done

---

## 4. Summary

Print what was deleted:

```
python-refactor:cleanup complete

Deleted:
  .python-refactor/     — all plugin output (metrics, reports, tests, manifests)
  .hypothesis/          — Hypothesis counterexample database (if existed)
  .pytest_cache/        — pytest result cache (if existed)
  .semgrep/             — semgrep local cache (if existed)
  .skylos_cache/        — skylos analysis cache (if existed)

Global tool caches (~/.semgrep/ etc.) were NOT touched.
Filed issues were NOT affected.
```

Only list directories that actually existed and were deleted.
