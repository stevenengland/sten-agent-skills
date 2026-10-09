#!/usr/bin/env bash
# Behavior tests for the shared scripts show-me and visual-pr rely on:
#
#   1. ensure-stenswf-dir.sh — local state must be git-ignored before the
#      first write, even where bootstrap never ran and in worktrees (where
#      `.git` is a file). Otherwise a standalone run commits its artifacts.
#   2. open-html.sh — the opener is chosen by platform, never by PATH
#      order (on Debian-family Linux `open` is openvt), and a headless box
#      gets the path back instead of a failure.
#
# Run: bash plugins/stenswf/tests/show-me.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENSURE="$HERE/../scripts/ensure-stenswf-dir.sh"

PASS=0
FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()      { [ "$2" = "$3" ] && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
assert_match()   { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || { fail "$1"; printf '    missing %q in: %s\n' "$3" "$2"; }; }
assert_nomatch() { printf '%s' "$2" | grep -qF -- "$3" && { fail "$1"; printf '    unexpected %q in: %s\n' "$3" "$2"; } || ok "$1"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- 1. ensure-stenswf-dir.sh ------------------------------------------------
gitc() { git -c user.name=t -c user.email=t@example.com "$@"; }
excludes() { grep -cxF '.stenswf/' "$1" 2>/dev/null; }

# 1a. A repository where bootstrap never ran.
REPO="$WORK/plain"
git init -q -b master "$REPO" && mkdir -p "$REPO/src"
OUT=$( cd "$REPO/src" && bash "$ENSURE" 42 ); RC=$?
assert_eq "ensure exits 0" "$RC" "0"
assert_eq "ensure prints the directory at the repository root" "$OUT" "$REPO/.stenswf/42"
assert_eq "ensure creates the directory" "$([ -d "$REPO/.stenswf/42" ] && echo yes || echo no)" "yes"
assert_eq "ensure adds one exclusion line" "$(excludes "$REPO/.git/info/exclude")" "1"
assert_eq "git now ignores the directory" "$(git -C "$REPO" check-ignore -q .stenswf/42/x && echo ignored || echo tracked)" "ignored"
( cd "$REPO" && bash "$ENSURE" .show-me ) >/dev/null
assert_eq "a second run adds no second line" "$(excludes "$REPO/.git/info/exclude")" "1"

# 1b. Already ignored (e.g. by .gitignore): nothing is written.
REPO2="$WORK/ignored"
git init -q -b master "$REPO2" && printf '.stenswf/*\n' > "$REPO2/.gitignore"
cp "$REPO2/.git/info/exclude" "$WORK/exclude.before"
( cd "$REPO2" && bash "$ENSURE" 7 ) >/dev/null
assert_eq "an already-ignored .stenswf gets no exclusion write" \
  "$(cmp -s "$REPO2/.git/info/exclude" "$WORK/exclude.before" && echo same || echo changed)" "same"

# 1c. A worktree, where .git is a file: the exclusion goes to --git-path.
MAIN="$WORK/main"
git init -q -b master "$MAIN" && gitc -C "$MAIN" commit -q --allow-empty -m base
git -C "$MAIN" worktree add -q "$WORK/tree" -b feat 2>/dev/null
OUT=$( cd "$WORK/tree" && bash "$ENSURE" 9 ); RC=$?
assert_eq "ensure works inside a worktree" "$RC" "0"
assert_eq "the worktree gets its own .stenswf directory" "$OUT" "$WORK/tree/.stenswf/9"
assert_eq "the exclusion lands in the --git-path exclude file" "$(excludes "$MAIN/.git/info/exclude")" "1"
assert_eq "git ignores .stenswf inside the worktree" \
  "$(git -C "$WORK/tree" check-ignore -q .stenswf/9/x && echo ignored || echo tracked)" "ignored"

# 1d. Outside git: only the directory.
NOGIT="$WORK/nogit"; mkdir -p "$NOGIT"
OUT=$( cd "$NOGIT" && GIT_CEILING_DIRECTORIES="$WORK" bash "$ENSURE" .show-me ); RC=$?
assert_eq "outside git ensure still exits 0" "$RC" "0"
assert_eq "outside git ensure creates the directory under the cwd" "$OUT" "$NOGIT/.stenswf/.show-me"

( bash "$ENSURE" ) >/dev/null 2>&1; RC=$?
assert_eq "ensure without an argument is a usage error" "$RC" "2"

printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
