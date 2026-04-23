#!/usr/bin/env bash
# List full GitHub URLs for all SKILL.md files in this repo (excluding 3rd party frameworks).
#
# Usage: ./tools/list-skill-urls.sh [--raw] [--all]
#   --raw  Output raw.githubusercontent.com URLs instead of blob URLs
#   --all  Include files under frameworks/ (3rd party upstream clones)

set -euo pipefail

REPO_OWNER="stevenengland"
REPO_NAME="sten-agent-skills"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)"

MODE="blob"
INCLUDE_ALL=0
for arg in "$@"; do
    case "$arg" in
        --raw) MODE="raw" ;;
        --all) INCLUDE_ALL=1 ;;
        -h|--help)
            sed -n '2,7p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

if [[ "$MODE" == "raw" ]]; then
    BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"
else
    BASE="https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/${BRANCH}"
fi

# Use git ls-files to respect .gitignore and only list tracked files.
mapfile -t FILES < <(git ls-files '*SKILL.md' | sort)

for f in "${FILES[@]}"; do
    if [[ $INCLUDE_ALL -eq 0 && "$f" == frameworks/* ]]; then
        continue
    fi
    echo "${BASE}/${f}"
done
