# Shared drift-check procedure

Used by `ship`, `ship-light` (Phase 0.5), `review`, and `apply`.
Re-hash the current issue body and compare to the plan-time hash.

## Inputs

- `$ARGUMENTS` — issue number.
- `$D` = `.stenswf/$ARGUMENTS`.
- `$D/manifest.json` with `.concept_sha256` (heavy path).
- Or `$D/plan-light.json` with `.source_signature` (lite plan-ahead).
- Or `$D/anchor.json` with `.source_signature` (lite shortest —
  seeded by `ship-light` Phase 4 when no prior plan exists).

## Check (heavy path)

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS-now.md
NOW_SHA=$(sha256sum /tmp/slice-$ARGUMENTS-now.md | cut -d' ' -f1)
PLAN_SHA=$(jq -r .concept_sha256 "$D/manifest.json")

# CLAUDE/AGENTS comparison is best-effort: legacy manifests created
# before claude_md_sha was seeded carry no value. In that case skip
# the comparison and warn once — do NOT treat absent as drift.
CLAUDE_NOW=$(git log -1 --format=%H -- CLAUDE.md AGENTS.md 2>/dev/null | head -1)
CLAUDE_PLAN=$(jq -r '.claude_md_sha // ""' "$D/manifest.json")
if [ -z "$CLAUDE_PLAN" ] || [ "$CLAUDE_PLAN" = "null" ]; then
  echo "warn: $D/manifest.json predates claude_md_sha seeding; CLAUDE/AGENTS drift not checked" >&2
  CLAUDE_PLAN="$CLAUDE_NOW"   # neutralize the comparison below
fi
```

If `NOW_SHA != PLAN_SHA` OR `CLAUDE_NOW != CLAUDE_PLAN`, show:

```
⚠  Issue #$ARGUMENTS body has changed since plan was written.
   Changed sections: <comma-separated list>
   [diff of changed sections, capped at ~30 lines]

   (r) re-plan       — run /stenswf:plan $ARGUMENTS --resume
   (c) continue      — proceed with stale plan
   (a) abort
```

Actions:

- `r` → stop, tell user to run `plan --resume`.
- `c` → proceed. Append one `decision` meta-entry to
  `$D/decisions.md` (source `<current-skill>`, title `Drift accepted —
  no replan`, rationale names the changed sections) — see
  [Decision Anchor Contract](decision-anchor-link.md).
- `a` → stop.

## Check (lite path)

Recompute the source signature over the three canonical sections and
compare to `plan-light.json:source_signature` (lite plan-ahead) or
`anchor.json:source_signature` (lite shortest, seeded by `ship-light`):

```bash
CUR_SIG=$( { \
  extract_section 'What to build'            /tmp/slice-$ARGUMENTS-now.md; \
  extract_section 'Conventions \(from PRD\)' /tmp/slice-$ARGUMENTS-now.md; \
  extract_section 'Acceptance criteria'      /tmp/slice-$ARGUMENTS-now.md; \
} | sha256sum | cut -d' ' -f1)

if   [ -s "$D/plan-light.json" ]; then
  PLAN_SIG=$(jq -r .source_signature "$D/plan-light.json")
elif [ -s "$D/anchor.json" ]; then
  PLAN_SIG=$(jq -r .source_signature "$D/anchor.json")
else
  PLAN_SIG=""
fi
```

Lite drift is silent: if `CUR_SIG != PLAN_SIG`, ignore the plan and
proceed from the issue body. Do not prompt, do not delete the plan.
If no anchor exists at all (no plan-light, no anchor), skip the lite
check — the slice was shipped before drift anchors were introduced
or `bootstrap` has not run.

`extract_section` is defined in [extractors.md](extractors.md).
