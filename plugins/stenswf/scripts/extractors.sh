# Front-matter extractors — canonical shell library for stenswf skills.
#
# This file is intended to be sourced, not executed. From a skill
# directory, use:
#   source ../../scripts/extractors.sh
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
    local script_dir
    script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    printf '%s\n' "$untagged" >&2
    bash "$script_dir/log-issue.sh" contract_violation \
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

# HITL gate status (see ../references/hitl-escape-hatch.md).
#
# Prints exactly one of: not-hitl | open | cleared
# Returns 1 — after logging contract_violation — on self-contradictory
# front-matter or a malformed attestation. Never a quiet "open" in those
# cases: that reads as ordinary unresolved work and would send the user
# back through an interview they already completed.
#
# Self-contained: it normalises the slice type itself, so callers need no
# particular ordering relative to parse_type.
#
# Usage: HITL_STATE=$(hitl_status "$BODY") || <route heavy; already logged>
hitl_status() {
  local body="$1" t disq att open_n res_n claimed

  _hitl_bad() {
    printf 'stenswf: %s\n' "$1" >&2
    local d; d=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    bash "$d/log-issue.sh" contract_violation \
      "hitl contract violated on #${ARGUMENTS:-?}" "$1"
  }

  t=$(get_fm type "$body" | sed 's/–/—/g; s/--/—/g; s/ *— */ — /g')
  disq=$(get_fm disqualifier "$body")
  att=$(get_fm hitl_resolved "$body")

  if [ "$t" != "slice — HITL" ]; then
    # hitl-cat3 means "HITL is the only blocker" — meaningless off a HITL
    # slice, and it must not buy a free pass past the envelope.
    if [ "$disq" = "hitl-cat3" ]; then
      _hitl_bad "hitl-cat3 on a non-HITL slice ($t)"; return 1
    fi
    printf 'not-hitl'; return 0
  fi

  # Count real entries, not boilerplate: a bullet whose text is bolded.
  open_n=$(extract_section 'Open judgment calls' "$body" \
    | grep -c '^[[:space:]]*-[[:space:]]\+\*\*' || true)
  res_n=$(extract_section 'Resolved judgment calls' "$body" \
    | grep -c '^[[:space:]]*-[[:space:]]\+\*\*' || true)

  # Nothing attested and nothing resolved → ordinary unresolved HITL work.
  if [ -z "$att" ] && [ "$res_n" -eq 0 ]; then printf 'open'; return 0; fi

  # Half an attestation carries no decisions into the spec.
  [ -n "$att" ] || {
    _hitl_bad "resolved judgment calls without hitl_resolved"; return 1; }
  [ "$res_n" -gt 0 ] || {
    _hitl_bad "hitl_resolved without any resolved decision"; return 1; }
  # The two sections are exclusive — the hatch swaps one for the other.
  [ "$open_n" -eq 0 ] || {
    _hitl_bad "both open and resolved judgment calls present"; return 1; }

  # Only the hatch writes this field, so the form is strict.
  printf '%s' "$att" | grep -Eq \
    '^[0-9]{4}-[0-9]{2}-[0-9]{2} — [0-9]+ judgment calls? resolved via hitl-escape-hatch$' || {
    _hitl_bad "hitl_resolved not in canonical form: $att"; return 1; }

  claimed=$(printf '%s' "$att" | sed -E 's/^[0-9-]+ — ([0-9]+) .*/\1/')
  [ "$claimed" -eq "$res_n" ] || {
    _hitl_bad "hitl_resolved claims $claimed call(s), body records $res_n"; return 1; }

  printf 'cleared'
}
