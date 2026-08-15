# Front-matter extractors

Documentation for the canonical shell helpers used by every stenswf
lifecycle skill to read front-matter and section bodies from issues.

> **Canonical source.** Function bodies live in
> [`../scripts/extractors.sh`](../scripts/extractors.sh). Skills source
> that file — do not duplicate the function definitions here or in
> any skill.

Schema: [front-matter-schema.md](front-matter-schema.md).

## Sourcing in a skill

```bash
source ../../scripts/extractors.sh
```

After sourcing, the helpers below are available.

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

## `get_fm <key> <body-path>`

Read a single front-matter key. Examples:

```bash
TYPE=$(get_fm type /tmp/slice-$ARGUMENTS.md)
LITE=$(get_fm lite_eligible /tmp/slice-$ARGUMENTS.md)
CONV_SRC=$(get_fm conventions_source /tmp/slice-$ARGUMENTS.md)
PRD_REF=$(get_fm prd_ref /tmp/slice-$ARGUMENTS.md)
DISQ=$(get_fm disqualifier /tmp/slice-$ARGUMENTS.md)
CLASS=$(get_fm class /tmp/slice-$ARGUMENTS.md)        # PRD/bug-brief only
BUG_REF=$(get_fm bug_ref /tmp/slice-$ARGUMENTS.md)    # slice (optional)
AFFECTS_PRD=$(get_fm affects_prd /tmp/slice-$ARGUMENTS.md)  # bug-brief (optional)
```

## `extract_section <heading> <body-path>`

Print the body of `## <heading>` up to the next `## ` heading (the
opening heading line itself is excluded).

```bash
extract_section 'Acceptance criteria'      /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-acs.md
extract_section 'What to build'            /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-what.md
extract_section 'Conventions \(from PRD\)' /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-conv.md
extract_section 'Files \(hint\)'           /tmp/slice-$ARGUMENTS.md > /tmp/slice-$ARGUMENTS-files.md
```

## `parse_type` (optional helper)

Reads the caller's `$TYPE` (set via `get_fm type …`), normalises dash
variants (Postel's law: `--` and `–` both fold to `—`), and exports
`MODE` (`prd | bug-brief | slice`) plus `SLICE_TYPE` (`HITL | AFK |
spike`) when applicable. Returns non-zero on an unrecognised type.

```bash
TYPE=$(get_fm type /tmp/slice-$ARGUMENTS.md)
parse_type
echo "MODE=$MODE${SLICE_TYPE:+ SLICE_TYPE=$SLICE_TYPE}"
```

## `hitl_status <body-path>` (HITL escape hatch)

Single source for **the HITL gate's state and what a valid attestation is**.
Prints exactly one of:

| State | Meaning |
|---|---|
| `not-hitl` | Not a HITL slice — this gate has nothing to say. |
| `open` | HITL, judgment calls unresolved. Caller runs the hatch (available) or routes heavy (unattended). |
| `cleared` | HITL, calls resolved and attested. Caller continues. |

Self-contained: it normalises the slice type itself (folding `--` and `–` to
`—`), so callers need no particular ordering relative to `parse_type`.

A contradictory or malformed slice is a **hard error inside the function** —
it logs `contract_violation` via `log-issue.sh` and returns non-zero rather
than printing `open`. That distinction matters: a quiet `open` looks like
ordinary unresolved work and would send the user back through an interview
they already completed. Rejected:

- `disqualifier: hitl-cat3` on a non-HITL slice — the marker means "HITL is
  the only blocker", so off a HITL slice it is meaningless and must not buy a
  free pass past the envelope.
- `hitl_resolved` with no resolved decision recorded (including a section
  holding only its boilerplate comment), or decisions recorded with no
  `hitl_resolved`.
- `## Open judgment calls` and `## Resolved judgment calls` both present —
  the hatch swaps one for the other, so they are mutually exclusive.
- An attestation not in canonical form. Only the hatch writes this field, so
  the form is strict:
  `<YYYY-MM-DD> — <n> judgment call(s) resolved via hitl-escape-hatch`
- A stated count that disagrees with the number of decisions recorded.

A "decision" is a bullet whose text is bolded (`- **…**`), matching the shape
in [hitl-escape-hatch.md](hitl-escape-hatch.md).

```bash
HITL_STATE=$(hitl_status /tmp/slice-$ARGUMENTS.md) || exit 1   # already logged
```

## PRD base SHA

Resolved exclusively from the PRD issue front-matter:

```bash
PRD_BASE=$(get_fm prd_base_sha /tmp/slice-$ARGUMENTS.md)
[ -n "$PRD_BASE" ] || { echo "PRD #$ARGUMENTS missing prd_base_sha in front-matter" >&2; exit 1; }
```

## `extract_acs <body-path>` (TDD-as-lens)

Reads `## Acceptance criteria`, assigns positional IDs (`AC1`, `AC2`,
…), and emits one TSV record per AC: `<id>\t<tag>\t<text>`.

**Untagged ACs are a hard error inside the function itself** —
`extract_acs` writes the offending row(s) to stderr, logs
`contract_violation` via `log-issue.sh`, and returns non-zero. Callers
need only invoke it; no external guard required. See
[behavior-change-signal.md](behavior-change-signal.md).

```bash
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
