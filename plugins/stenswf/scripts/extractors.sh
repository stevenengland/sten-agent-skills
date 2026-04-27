# Front-matter extractors — canonical shell library for stenswf skills.
#
# This file is intended to be sourced, not executed:
#   source plugins/stenswf/scripts/extractors.sh
#
# Documentation lives in ../references/extractors.md. Function bodies
# below are the single source of truth — do not duplicate them
# elsewhere.

# Read a single front-matter key.
get_fm() {
  local key="$1" body="$2"
  sed -n '/^<!-- stenswf:v1/,/^-->/p' "$body" \
    | sed -n 's/^'"$key"':[[:space:]]*\(.*\)$/\1/p' \
    | head -1
}

# Extract a markdown section by heading. Skips the heading line and
# terminates at the next `## `.
extract_section() {
  local heading="$1" body="$2"
  awk -v h="^## $heading" '
    $0 ~ h { inside=1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$body"
}

# AC-tag extractor (TDD-as-lens). Reads `## Acceptance criteria`,
# assigns positional IDs (AC1, AC2, …) and emits one TSV record per
# AC: <id>\t<tag>\t<text>. Untagged ACs are a hard error: the
# function logs contract_violation via log-issue.sh and returns 1.
extract_acs() {
  local body="$1"
  local tsv
  tsv=$(extract_section 'Acceptance criteria' "$body" \
    | awk '
        /^[[:space:]]*-[[:space:]]+\[[ xX]\][[:space:]]+/ {
          n++
          line=$0
          sub(/^[[:space:]]*-[[:space:]]+\[[ xX]\][[:space:]]+/, "", line)
          tag="UNTAGGED"
          rest=line
          if (match(line, /^\((behavior|structural)\)[[:space:]]+/)) {
            span=substr(line, RSTART, RLENGTH)
            sub(/^\(/, "", span); sub(/\).*$/, "", span)
            tag=span
            rest=substr(line, RSTART+RLENGTH)
          }
          printf "AC%d\t%s\t%s\n", n, tag, rest
        }')
  local untagged
  untagged=$(printf '%s\n' "$tsv" | awk -F'\t' '$2=="UNTAGGED"')
  if [ -n "$untagged" ]; then
    printf '%s\n' "$untagged" >&2
    bash plugins/stenswf/scripts/log-issue.sh contract_violation \
      "untagged AC on #${ARGUMENTS:-?}" "$untagged"
    echo "stenswf: untagged AC(s) — edit the issue body or re-run prd-to-issues / triage-issue" >&2
    return 1
  fi
  printf '%s\n' "$tsv"
}

# Slice-type parser. Reads `$TYPE` (set by the caller via get_fm),
# normalises dash variants, and exports MODE (+ SLICE_TYPE for slices).
parse_type() {
  TYPE=$(printf '%s' "${TYPE:-}" | sed 's/–/—/g; s/--/—/g; s/ *— */ — /g')
  case "$TYPE" in
    PRD) MODE=prd ;;
    bug-brief) MODE=bug-brief ;;
    "slice — HITL"|"slice — AFK"|"slice — spike")
      MODE=slice
      SLICE_TYPE=${TYPE#slice — }
      ;;
    *) echo "unrecognised type: $TYPE" >&2; return 1 ;;
  esac
}
