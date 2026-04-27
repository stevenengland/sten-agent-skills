# Front-matter extractors

Canonical shell snippets for reading stenswf front-matter from an issue
body. All lifecycle skills use these — do not write your own.

Schema: [front-matter-schema.md](front-matter-schema.md).

## Fetch issue body into scratch

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS.md
wc -l /tmp/slice-$ARGUMENTS.md   # confirm; do not cat
```

## Version-guard

Abort if the body lacks the expected opener:

```bash
if ! head -5 /tmp/slice-$ARGUMENTS.md | grep -q '^<!-- stenswf:v1'; then
  echo "issue #$ARGUMENTS has no stenswf:v1 front-matter — re-run prd-to-issues or prd-from-grill-me" >&2
  exit 1
fi
```

## Extract the whole front-matter block

```bash
sed -n '/^<!-- stenswf:v1/,/^-->/p' /tmp/slice-$ARGUMENTS.md \
  > /tmp/slice-$ARGUMENTS-fm.txt
```

## Read a single key

```bash
get_fm() {
  local key="$1" body="$2"
  sed -n '/^<!-- stenswf:v1/,/^-->/p' "$body" \
    | sed -n 's/^'"$key"':[[:space:]]*\(.*\)$/\1/p' \
    | head -1
}

TYPE=$(get_fm type /tmp/slice-$ARGUMENTS.md)
LITE=$(get_fm lite_eligible /tmp/slice-$ARGUMENTS.md)
CONV_SRC=$(get_fm conventions_source /tmp/slice-$ARGUMENTS.md)
PRD_REF=$(get_fm prd_ref /tmp/slice-$ARGUMENTS.md)
DISQ=$(get_fm disqualifier /tmp/slice-$ARGUMENTS.md)
CLASS=$(get_fm class /tmp/slice-$ARGUMENTS.md)        # PRD/bug-brief only
BUG_REF=$(get_fm bug_ref /tmp/slice-$ARGUMENTS.md)    # slice (optional)
AFFECTS_PRD=$(get_fm affects_prd /tmp/slice-$ARGUMENTS.md)  # bug-brief (optional)
```

## Extract body sections (post-front-matter)

Section-heading scraping is still used for long body sections
(`## What to build`, `## Acceptance criteria`, `## Conventions (from
PRD)`, `## Files (hint)`). Use this robust extractor — the end regex
excludes the opening heading so the awk range does not self-terminate:

```bash
extract_section() {
  local heading="$1" body="$2"
  awk -v h="^## $heading" '
    $0 ~ h { inside=1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$body"
}

extract_section 'Acceptance criteria'    /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-acs.md
extract_section 'What to build'          /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-what.md
extract_section 'Conventions \(from PRD\)' /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-conv.md
extract_section 'Files \(hint\)'          /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-files.md
```

The `next` / `exit` pattern skips the opening heading line itself and
terminates at the next `## ` — no `| sed '$d'` or `tail -n +3` hacks.

## Slice-type parser

```bash
# TYPE is the literal front-matter value, e.g. "slice — AFK" or "PRD".
# Normalize dash variants to U+2014 em-dash before matching (Postel's law):
# accepts "slice -- AFK" (double-hyphen) or "slice – AFK" (en-dash).
TYPE=$(printf '%s' "$TYPE" | sed 's/–/—/g; s/--/—/g; s/ *— */ — /g')
case "$TYPE" in
  PRD) MODE=prd ;;
  bug-brief) MODE=bug-brief ;;
  "slice — HITL"|"slice — AFK"|"slice — spike")
    MODE=slice
    SLICE_TYPE=${TYPE#slice — }   # HITL | AFK | spike
    ;;
  *) echo "unrecognised type: $TYPE" >&2; exit 1 ;;
esac
```

## PRD base SHA

Resolved exclusively from the PRD issue front-matter:

```bash
PRD_BASE=$(get_fm prd_base_sha /tmp/slice-$ARGUMENTS.md)
[ -n "$PRD_BASE" ] || { echo "PRD #$ARGUMENTS missing prd_base_sha in front-matter" >&2; exit 1; }
```

## AC-tag extractor (TDD-as-lens)

Reads the `## Acceptance criteria` section, assigns positional IDs
(`AC1`, `AC2`, …), and emits one TSV record per AC with the parsed
tag. **Untagged ACs trip a hard error inside the function itself** —
`extract_acs` writes the offending row(s) to stderr, logs
`contract_violation` via `log-issue.sh`, and exits non-zero. Callers
need only invoke it; no external guard required. See
[behavior-change-signal.md](behavior-change-signal.md).

```bash
extract_acs() {
  # Usage: extract_acs <issue-body-path> > /tmp/acs.tsv
  # Output: <id>\t<tag:behavior|structural>\t<text>
  # Exits 1 (after logging contract_violation) if any AC is untagged.
  local body="$1"
  local tsv
  tsv=$(extract_section 'Acceptance criteria' "$body" \
    | awk '
        /^[[:space:]]*-[[:space:]]+\[[ xX]\][[:space:]]+/ {
          n++
          line=$0
          # strip checkbox prefix
          sub(/^[[:space:]]*-[[:space:]]+\[[ xX]\][[:space:]]+/, "", line)
          tag="UNTAGGED"
          rest=line
          # Portable POSIX awk: match() returns position; RSTART/RLENGTH set.
          # Alternation inside ERE is portable across mawk/gawk/BWK awk.
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

# Canonical caller pattern — `extract_acs` itself stops on untagged ACs.
ACS_TSV=$(extract_acs /tmp/slice-$ARGUMENTS.md) || exit 1

# Convenience: space-separated AC id lists by tag.
BEHAVIOR_ACS=$(printf '%s\n' "$ACS_TSV" \
  | awk -F'\t' '$2=="behavior"  {print $1}' | tr '\n' ' ' | sed 's/ *$//')
STRUCTURAL_ACS=$(printf '%s\n' "$ACS_TSV" \
  | awk -F'\t' '$2=="structural"{print $1}' | tr '\n' ' ' | sed 's/ *$//')
```

The documentation task added by `plan` (`T<last>`) is hardcoded
`behavior_change: false` in the manifest — it has no AC of its own,
so this extractor does not see it.
