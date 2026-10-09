#!/usr/bin/env bash
# Create a local stenswf state directory that git ignores for this clone.
#
# Skills such as show-me and visual-pr write under `.stenswf/` outside a
# workflow run, where `bootstrap` may never have excluded it. Without the
# exclusion a later `git add -A` commits local artifacts. The exclusion goes
# to `git rev-parse --git-path info/exclude`, which also resolves in git
# worktrees (where `.git` is a file, not a directory).
#
# Usage:
#   ensure-stenswf-dir.sh <sub>    # <sub>: issue number, .show-me, pr-<number>
#
# Prints the absolute directory path on stdout. Outside git it only creates
# the directory under the current working directory.
set -eu

[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: ensure-stenswf-dir.sh <sub>" >&2; exit 2; }
sub=$1

if TOP=$(git rev-parse --show-toplevel 2>/dev/null); then
  in_git=1
else
  TOP=$PWD
  in_git=0
fi

mkdir -p "$TOP/.stenswf/$sub"

if [ "$in_git" -eq 1 ] && ! git -C "$TOP" check-ignore -q -- ".stenswf/$sub"; then
  EX=$(git -C "$TOP" rev-parse --git-path info/exclude)
  case $EX in /*) ;; *) EX="$TOP/$EX" ;; esac
  mkdir -p "$(dirname -- "$EX")"
  if [ -s "$EX" ] && [ -n "$(tail -c1 "$EX")" ]; then echo >> "$EX"; fi
  echo '.stenswf/' >> "$EX"
fi

printf '%s\n' "$TOP/.stenswf/$sub"
