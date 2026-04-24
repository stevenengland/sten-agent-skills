#!/usr/bin/env bash
# Seed inherited PRD decision stubs into each slice's decisions.md.
# Usage: inherit-decisions.sh <prd-number> <slice-number> [<slice-number>...]
#
# Called by prd-to-issues Step 7b. Active PRD entries only (strikethrough
# ~~D<n>~~ excluded). Inherited stubs preserve Category metadata — readers
# still hop to the PRD anchor for full rationale.
set -eu

PRD="${1:-}"
shift || true
if [ -z "$PRD" ] || [ "$#" -eq 0 ]; then
  echo "usage: inherit-decisions.sh <prd-number> <slice-number> [<slice-number>...]" >&2
  exit 2
fi

PRD_SRC=".stenswf/$PRD/decisions.md"
[ -s "$PRD_SRC" ] || exit 0

for N in "$@"; do
  D=".stenswf/$N"
  mkdir -p "$D"
  if [ ! -f "$D/decisions.md" ]; then
    cat > "$D/decisions.md" <<EOF
# Decisions — #$N

<!-- Seeded by prd-to-issues from #$PRD. Schema: plugins/stenswf/references/decision-anchor-link.md -->

EOF
  fi

  # Extract active (non-strikethrough) entries, preserving Category, Source, Refs.
  awk -v P="$PRD" '
    # Start an entry at "### D<n> <title>" (not strikethrough).
    /^### D[0-9]+ / {
      if (inblock) { print buf; print "---\n" }
      hdr = $0
      sub(/^### /, "", hdr)
      id = hdr; sub(/ .*/, "", id)
      title = hdr; sub(/^[^ ]+ — /, "", title)
      buf = sprintf("### %s — %s (inherited from #%s)\n\n- **Category:** inherited\n- **Source:** #%s/%s\n", id, title, P, P, id)
      inblock = 1
      have_refs = 0
      next
    }
    # Skip strikethrough entries entirely.
    /^### ~~D[0-9]+/ { inblock = 0; next }
    # End block at next header of any kind.
    inblock && /^### / {
      print buf
      print "---\n"
      inblock = 0
      next
    }
    # Preserve Refs line verbatim.
    inblock && /^- \*\*Refs:\*\*/ {
      buf = buf $0 "\n"
      have_refs = 1
      next
    }
    END {
      if (inblock) { print buf; print "---" }
    }
  ' "$PRD_SRC" >> "$D/decisions.md"
done
