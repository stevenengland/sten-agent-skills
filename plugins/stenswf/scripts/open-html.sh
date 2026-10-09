#!/usr/bin/env bash
# Open a local HTML file in the user's browser, and always print its path.
#
# The opener is chosen by platform, never by PATH order: on Debian-family
# Linux `open` is openvt, so probing PATH would launch the wrong tool. A
# headless box, a missing opener or a failing opener is not an error — the
# caller gets the absolute path back to hand to the user.
#
# Usage:
#   open-html.sh <path>
#
#   Darwin                    → open
#   Linux on WSL              → wslview, else xdg-open
#   other Linux               → xdg-open
#   anything else             → none (path printed only)
#
# WSL is detected from ${STENSWF_PROC_VERSION:-/proc/version} (overridable
# for tests).
set -eu

[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: open-html.sh <path>" >&2; exit 2; }
F=$1
[ -f "$F" ] || { echo "open-html: no such file: $F" >&2; exit 1; }

ABS="$(CDPATH= cd -- "$(dirname -- "$F")" && pwd)/$(basename -- "$F")"

case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin) CANDIDATES="open" ;;
  Linux)
    if grep -qi microsoft "${STENSWF_PROC_VERSION:-/proc/version}" 2>/dev/null; then
      CANDIDATES="wslview xdg-open"
    else
      CANDIDATES="xdg-open"
    fi ;;
  *) CANDIDATES="" ;;
esac

for O in $CANDIDATES; do
  command -v "$O" >/dev/null 2>&1 || continue
  "$O" "$ABS" >/dev/null 2>&1 || true
  break
done
echo "$ABS"
