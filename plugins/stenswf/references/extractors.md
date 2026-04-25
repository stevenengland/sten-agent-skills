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
