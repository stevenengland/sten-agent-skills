# Shared drift-check procedure

Used by `ship`, `ship-light` (Phase 0.5), `review`, and `apply`.
Re-hash the current issue body and compare to the plan-time hash.

## Inputs

- `$ARGUMENTS` — issue number.
- `$D` = `.stenswf/$ARGUMENTS`.
- `$D/manifest.json` with `.concept_sha256` (heavy path).
- Or `$D/plan-light.json` with `.source_signature` (lite path).

## Check (heavy path)

```bash
gh issue view $ARGUMENTS --json body -q .body > /tmp/slice-$ARGUMENTS-now.md
NOW_SHA=$(sha256sum /tmp/slice-$ARGUMENTS-now.md | cut -d' ' -f1)
PLAN_SHA=$(jq -r .concept_sha256 "$D/manifest.json")

CLAUDE_NOW=$(git log -1 --format=%H -- CLAUDE.md AGENTS.md 2>/dev/null | head -1)
CLAUDE_PLAN=$(jq -r .claude_md_sha "$D/manifest.json")
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
compare to `plan-light.json:source_signature`:

```bash
CUR_SIG=$( { \
  extract_section 'What to build'            /tmp/slice-$ARGUMENTS-now.md; \
  extract_section 'Conventions \(from PRD\)' /tmp/slice-$ARGUMENTS-now.md; \
  extract_section 'Acceptance criteria'      /tmp/slice-$ARGUMENTS-now.md; \
} | sha256sum | cut -d' ' -f1)
PLAN_SIG=$(jq -r .source_signature "$D/plan-light.json")
```

Lite drift is silent: if `CUR_SIG != PLAN_SIG`, ignore the plan and
proceed from the issue body. Do not prompt, do not delete the plan.

`extract_section` is defined in [extractors.md](extractors.md).
