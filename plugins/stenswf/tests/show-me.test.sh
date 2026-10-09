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

# --- 2. open-html.sh -----------------------------------------------------------
# A sealed PATH: only the tools the script needs, plus whichever fake
# platform tools a case installs. Real openers on the host never leak in.
# Fakes use "#!$BASH" because `env` cannot find bash on the sealed PATH.
OPENER="$HERE/../scripts/open-html.sh"
BIN="$WORK/bin"
mkdir -p "$BIN" "$WORK/pages"
for T in grep dirname basename cat; do ln -s "$(command -v "$T")" "$BIN/$T"; done
LOG="$WORK/opened"
PAGE="$WORK/pages/show-me-demo.html"
echo '<html><body>demo</body></html>' > "$PAGE"
PROC="$WORK/proc-version"

platform() {   # platform <uname -s output> <proc/version text>
  printf '#!%s\necho %s\n' "$BASH" "$1" > "$BIN/uname"; chmod +x "$BIN/uname"
  printf '%s\n' "$2" > "$PROC"
}
opener() {     # opener <name> <exit code>: logs "<name> <args>" to $LOG
  printf '#!%s\necho "%s $*" >> "%s"\nexit %s\n' "$BASH" "$1" "$LOG" "$2" > "$BIN/$1"
  chmod +x "$BIN/$1"
}
reset() { rm -f "$BIN/open" "$BIN/xdg-open" "$BIN/wslview" "$BIN/uname" "$LOG"; }
# The graphical session is the test's choice, never the developer's shell's.
SESSION="DISPLAY=:0"   # empty = a headless box
run() { ( unset DISPLAY WAYLAND_DISPLAY; cd "$WORK" && env $SESSION PATH="$BIN" STENSWF_PROC_VERSION="$PROC" "$BASH" "$OPENER" "$@" ); }
opened() { cat "$LOG" 2>/dev/null; }

# 2a. macOS
reset; platform Darwin "Darwin Kernel Version 23.0.0"; opener open 0
OUT=$(run pages/show-me-demo.html); RC=$?
assert_eq "macOS exits 0" "$RC" "0"
assert_eq "macOS opens the absolute path with open" "$(opened)" "open $PAGE"
assert_eq "macOS prints the absolute path" "$OUT" "$PAGE"

# 2b. WSL
WSL="Linux version 6.6.87.2-microsoft-standard-WSL2"
reset; platform Linux "$WSL"; opener wslview 0; opener xdg-open 0
run "$PAGE" >/dev/null
assert_eq "WSL prefers wslview" "$(opened)" "wslview $PAGE"
reset; platform Linux "$WSL"; opener xdg-open 0
run "$PAGE" >/dev/null
assert_eq "WSL falls back to xdg-open without wslview" "$(opened)" "xdg-open $PAGE"

# 2c. Plain Linux
reset; platform Linux "Linux version 6.1.0-13-amd64 (Debian)"; opener open 0; opener xdg-open 0
run "$PAGE" >/dev/null
assert_eq "Linux opens with xdg-open" "$(opened)" "xdg-open $PAGE"
assert_eq "Linux never runs open (openvt on Debian)" "$(grep -c '^open ' "$LOG" 2>/dev/null)" "0"
reset; platform Linux "Linux version 6.1.0-13-amd64 (Debian)"; opener xdg-open 0
SESSION="WAYLAND_DISPLAY=wayland-0" run "$PAGE" >/dev/null
assert_eq "Linux under Wayland opens with xdg-open" "$(opened)" "xdg-open $PAGE"

# 2c'. Headless: xdg-open would hand the page to a text browser that holds
#      the caller's terminal, so a box with no display only gets the path
reset; platform Linux "Linux version 6.1.0-13-amd64 (Debian)"; opener open 0; opener xdg-open 0
OUT=$(SESSION="" run "$PAGE"); RC=$?
assert_eq "headless Linux exits 0" "$RC" "0"
assert_eq "headless Linux runs no opener" "$([ -e "$LOG" ] && opened || echo none)" "none"
assert_eq "headless Linux prints the absolute path" "$OUT" "$PAGE"
reset; platform Linux "$WSL"; opener wslview 0
SESSION="" run "$PAGE" >/dev/null
assert_eq "WSL needs no display for wslview" "$(opened)" "wslview $PAGE"

# 2d. No opener, failing opener
reset; platform Linux "Linux version 6.1.0-13-amd64 (Debian)"
OUT=$(run "$PAGE"); RC=$?
assert_eq "no opener still exits 0" "$RC" "0"
assert_eq "no opener prints the absolute path" "$OUT" "$PAGE"
reset; platform Darwin "Darwin Kernel Version 23.0.0"; opener open 1
OUT=$(run pages/show-me-demo.html); RC=$?
assert_eq "a failing opener still exits 0" "$RC" "0"
assert_eq "a failing opener prints the absolute path" "$OUT" "$PAGE"

# 2e. Missing file
reset; platform Darwin "Darwin Kernel Version 23.0.0"; opener open 0
ERR=$(run pages/nope.html 2>&1 >/dev/null); RC=$?
assert_eq "a missing file exits 1" "$RC" "1"
assert_match "a missing file says which file" "$ERR" "pages/nope.html"
assert_eq "a missing file runs no opener" "$([ -e "$LOG" ] && echo ran || echo none)" "none"

printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
