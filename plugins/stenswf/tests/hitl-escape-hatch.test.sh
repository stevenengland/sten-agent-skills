#!/usr/bin/env bash
# Behavior + wiring tests for the HITL escape hatch.
#
# Two things here fail silently in production, which is why they are tested
# rather than eyeballed:
#
#   1. The `source_signature` is computed at THREE sites (plan-light's
#      artifacts.md, ship-light Phase 0.5, ship-light Phase 4). If they list
#      different sections, every plan-light artifact reads as permanently
#      stale — and ship-light's response to a stale plan is to shrug and carry
#      on. No error, just a planning phase that quietly stopped counting.
#   2. The HITL gate state. `hitl_status` decides whether unresolved judgment
#      calls can reach the lite path; a wrong `open`/`cleared`/`not-hitl` is
#      invisible until work ships unreviewed.
#
# The gate logic lives in scripts/extractors.sh, so it is tested directly.
# The skills are checked only for wiring — that they call the helper and
# defer to it.
#
# Run: bash plugins/stenswf/tests/hitl-escape-hatch.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
FIX="$HERE/fixtures"
REF="references/hitl-escape-hatch.md"

# shellcheck source=../scripts/extractors.sh
source "$ROOT/scripts/extractors.sh"
export ARGUMENTS=0

PASS=0
FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()    { [ "$2" = "$3" ] && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
assert_match() { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || { fail "$1"; printf '    missing %q in: %s\n' "$3" "$2"; }; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# 1. hitl_status — the gate, table-driven
# ---------------------------------------------------------------------------

ATT='hitl_resolved: 2026-08-15 — 1 judgment call resolved via hitl-escape-hatch\n'
RES='\n## Resolved judgment calls\n\n- **A** → x. Anchor: D1.\n'
OPEN='\n## Open judgment calls\n\n- **C** — still pending\n'

body() {  # $1 type, $2 extra front-matter, $3 trailing sections → path
  printf '<!-- stenswf:v1\ntype: %b\n%b-->\n\n## What to build\n\nx\n%b' \
    "$1" "$2" "$3" > "$WORK/b.md"
  printf '%s' "$WORK/b.md"
}
status() { hitl_status "$1" 2>/dev/null || printf 'INVALID'; }

# label | type | extra front-matter | trailing sections | expected
while IFS='|' read -r label typ fm sect want; do
  [ -n "${label// /}" ] || continue
  assert_eq "$label" "$(status "$(body "$typ" "$fm" "$sect")")" "$want"
done <<TABLE
an AFK slice is outside this gate|slice — AFK|||not-hitl
a spike slice is outside this gate|slice — spike|||not-hitl
hitl-cat3 on an AFK slice is rejected|slice — AFK|disqualifier: hitl-cat3\n||INVALID
hitl-cat3 on a spike slice is rejected|slice — spike|disqualifier: hitl-cat3\n||INVALID
an untouched HITL slice reads open|slice — HITL|||open
an en-dash HITL slice still reads open|slice – HITL|||open
a double-hyphen HITL slice still reads open|slice -- HITL|||open
hitl-cat3 on a HITL slice is legitimate|slice — HITL|disqualifier: hitl-cat3\n||open
a full valid attestation clears|slice — HITL|${ATT}|${RES}|cleared
an attestation with no decisions is rejected|slice — HITL|${ATT}||INVALID
decisions with no attestation are rejected|slice — HITL||${RES}|INVALID
a boilerplate-only resolved section is rejected|slice — HITL|${ATT}|\n## Resolved judgment calls\n\n<!-- comment -->\n|INVALID
a count mismatch is rejected|slice — HITL|${ATT}|${RES}- **B** → y. Anchor: D2.\n|INVALID
a non-canonical attestation is rejected|slice — HITL|hitl_resolved: yes, all done\n|${RES}|INVALID
a missing date in the attestation is rejected|slice — HITL|hitl_resolved: 1 judgment call resolved via hitl-escape-hatch\n|${RES}|INVALID
wrong wording with a matching count is rejected|slice — HITL|hitl_resolved: 2026-08-15 — 1 call resolved manually\n|${RES}|INVALID
a wrong-format date is rejected|slice — HITL|hitl_resolved: 15-08-2026 — 1 judgment call resolved via hitl-escape-hatch\n|${RES}|INVALID
open and resolved together are rejected|slice — HITL|${ATT}|${RES}${OPEN}|INVALID
TABLE

# The real fixtures must agree with the table.
assert_eq "the resolved fixture reads cleared" \
  "$(status "$FIX/issue-slice-hitl-resolved.md")" "cleared"
assert_eq "the open fixture reads open" \
  "$(status "$FIX/issue-slice-hitl-open.md")" "open"
assert_eq "an ordinary lite slice is outside this gate" \
  "$(status "$FIX/issue-slice-lite.md")" "not-hitl"

# A combined-blocker slice keeps its envelope disqualifier, so the envelope
# check routes heavy before the hatch is ever reached.
assert_eq "a combined-blocker slice keeps its envelope disqualifier" \
  "$(get_fm disqualifier "$FIX/issue-slice-hitl-open.md")" "files>15"
assert_match "…and states its open calls for the hatch to read" \
  "$(extract_section 'Open judgment calls' "$FIX/issue-slice-hitl-open.md")" \
  "Retry backoff strategy"
assert_eq "a resolved slice no longer carries an open section" \
  "$(extract_section 'Open judgment calls' "$FIX/issue-slice-hitl-resolved.md")" ""

# ---------------------------------------------------------------------------
# 2. source_signature parity across all three computation sites
# ---------------------------------------------------------------------------

# ship-light computes the signature inline from section names.
sig_shiplight() {
  awk '
    /SIG=\$\( \{/       { inblock=1; list=""; next }
    inblock && /sha256sum/ { print list; inblock=0; next }
    inblock && match($0, /extract_section '"'"'[^'"'"']+'"'"'/) {
      s=substr($0, RSTART, RLENGTH)
      sub(/^extract_section '"'"'/, "", s); sub(/'"'"'$/, "", s); gsub(/\\/, "", s)
      list = (list=="" ? s : list "|" s)
    }
  ' "$ROOT/skills/ship-light/SKILL.md"
}
# plan-light hashes temp files; map each back to the section Phase 0 wrote it from.
sig_planlight() {
  local list="" section
  while read -r sfx; do
    [ -n "$sfx" ] || continue
    section=$(awk -v sfx="-$sfx.md" '
      index($0, sfx) && match($0, /extract_section '"'"'[^'"'"']+'"'"'/) {
        s=substr($0, RSTART, RLENGTH)
        sub(/^extract_section '"'"'/, "", s); sub(/'"'"'$/, "", s); gsub(/\\/, "", s)
        print s; exit }' "$ROOT/skills/plan-light/SKILL.md")
    list="${list:+$list|}${section:-UNMAPPED:$sfx}"
  done < <(awk '
    /SIG=\$\( \{/ { inblock=1 } inblock && /sha256sum/ { inblock=0 }
    inblock && match($0, /-[a-z]+\.md/) { print substr($0, RSTART+1, RLENGTH-4) }
  ' "$ROOT/skills/plan-light/artifacts.md")
  printf '%s\n' "$list"
}

mapfile -t SL < <(sig_shiplight)
PL=$(sig_planlight)
assert_eq "ship-light computes the signature at exactly two sites" "${#SL[@]}" "2"
assert_eq "ship-light's two signature sites list identical sections" "${SL[0]:-A}" "${SL[1]:-B}"
assert_eq "plan-light hashes the same sections ship-light recomputes" "$PL" "${SL[0]:-}"
assert_match "the resolved-judgment-calls section is part of the signature" \
  "$PL" "Resolved judgment calls"
assert_eq "every plan-light temp file maps to a known section" \
  "$(printf '%s' "$PL" | grep -c 'UNMAPPED' || true)" "0"

# Adding the 4th section must not disturb slices the hatch never touched.
sig3() { { extract_section 'What to build' "$1"; extract_section 'Conventions \(from PRD\)' "$1"; extract_section 'Acceptance criteria' "$1"; } 2>/dev/null | sha256sum | cut -d' ' -f1; }
sig4() { sig3 "$1" >/dev/null; { extract_section 'What to build' "$1"; extract_section 'Conventions \(from PRD\)' "$1"; extract_section 'Acceptance criteria' "$1"; extract_section 'Resolved judgment calls' "$1"; } 2>/dev/null | sha256sum | cut -d' ' -f1; }
for f in issue-slice-lite.md issue-slice-override.md issue-slice-heavy.md \
         issue-slice-override-rejected.md; do
  assert_eq "adding the 4th section leaves $f's signature unchanged" \
    "$(sig4 "$FIX/$f")" "$(sig3 "$FIX/$f")"
done
R="$FIX/issue-slice-hitl-resolved.md"
[ "$(sig4 "$R")" != "$(sig3 "$R")" ] \
  && ok "resolutions are spec-bearing: editing them stales the plan" \
  || fail "resolutions are spec-bearing: editing them stales the plan"

# ---------------------------------------------------------------------------
# 3. Wiring — skills defer to the helper; producers emit its input
# ---------------------------------------------------------------------------

[ -f "$ROOT/$REF" ] && ok "$REF exists" || fail "$REF exists"

for skill in skills/plan-light/SKILL.md skills/ship-light/SKILL.md; do
  # Match the ASSIGNMENT, not a mention — the helper's name also appears in
  # prose and comments, so a bare grep survives the call being deleted.
  grep -Eq 'HITL_STATE=\$\(hitl_status ' "$ROOT/$skill" \
    && ok "$skill gates via the shared hitl_status" \
    || fail "$skill gates via the shared hitl_status"
  grep -Fq 'hitl-escape-hatch.md' "$ROOT/$skill" \
    && ok "$skill links the escape-hatch protocol" \
    || fail "$skill links the escape-hatch protocol"
  # The gate classifies; it must not overwrite the envelope result.
  grep -Eq 'HITL_STATE[^\n]*LITE=' "$ROOT/$skill" \
    && fail "$skill keeps HITL_STATE from assigning LITE" \
    || ok "$skill keeps HITL_STATE from assigning LITE"
done

for skill in skills/prd-to-issues/SKILL.md skills/triage-issue/SKILL.md; do
  grep -Fq '## Open judgment calls' "$ROOT/$skill" \
    && ok "$skill emits ## Open judgment calls" \
    || fail "$skill emits ## Open judgment calls"
done
grep -Fq 'Open judgment calls' "$ROOT/references/issue-template.md" \
  && ok "the issue template documents the open-calls section" \
  || fail "the issue template documents the open-calls section"
grep -Fq 'hitl_resolved' "$ROOT/references/front-matter-schema.md" \
  && ok "the schema documents hitl_resolved" \
  || fail "the schema documents hitl_resolved"
grep -Fq 'hitl_status' "$ROOT/references/extractors.md" \
  && ok "extractors.md documents the validity contract" \
  || fail "extractors.md documents the validity contract"

# The safety argument: HITL is cleared only as the SOLE remaining blocker,
# and an interview does not make a one-way door reversible.
for clause in 'sole remaining blocker' 'schema-migration' 'arch-unknown' \
              'STENSWF_UNATTENDED' 'decision-weighting.md' 'decision-escalation.md'; do
  grep -Fq "$clause" "$ROOT/$REF" \
    && ok "the hatch still documents its \"$clause\" boundary" \
    || fail "the hatch still documents its \"$clause\" boundary"
done

# ---------------------------------------------------------------------------
# 4. One bail threshold, one value
# ---------------------------------------------------------------------------

# Filter whole LINES to the ones about judgment calls before pulling the
# number — the README says "more than one agent session" elsewhere.
thresholds() {
  grep -Ehi 'more than' "$@" | grep -Ei 'judgment|call|them\.' \
    | grep -Eohi 'more than \*{0,2}(one|two|three|four|[0-9]+)' \
    | sed -E 's/.*more than \*{0,2}//I; s/one/1/; s/two/2/; s/three/3/; s/four/4/' \
    | sort -u
}
assert_eq "every bail threshold states the same value" \
  "$(thresholds "$ROOT/$REF" "$ROOT/README.md" | grep -c .)" "1"
assert_eq "…and that value is 3" \
  "$(thresholds "$ROOT/$REF" "$ROOT/README.md")" "3"
for vague in 'a handful' 'one or two' 'a few'; do
  grep -Fqi "$vague" "$ROOT/$REF" \
    && fail "no vague call-count quantifier (\"$vague\")" \
    || ok "no vague call-count quantifier (\"$vague\")"
done

# ---------------------------------------------------------------------------
# 5. Links
# ---------------------------------------------------------------------------

BROKEN=0
while read -r target; do
  [ -n "$target" ] || continue
  [ -e "$ROOT/references/$target" ] || { BROKEN=$((BROKEN + 1)); printf '    broken: %s\n' "$target"; }
done < <(grep -o '](\.\{0,2\}/\?[A-Za-z0-9./_-]*\.md)' "$ROOT/$REF" | sed 's/^](//;s/)$//')
assert_eq "every link in the hatch reference resolves" "$BROKEN" "0"

printf '\n1..%s\n# pass %s fail %s\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
