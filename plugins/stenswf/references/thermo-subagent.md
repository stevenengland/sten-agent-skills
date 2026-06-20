# Thermo subagent — dispatch + harmonization contract

Shared by `review/slice.md` and `review/prd.md`. Runs the aggressive
maintainability review (`thermo-nuclear-code-quality-review`) in an **isolated,
read-only subagent** so its heavy prompt stays out of the main review session
and runs at full strength. Findings are merged into the caller's existing
output — never a separate artifact.

The thermo skill is **code-quality only**: no correctness, security, or
critical-severity scope. Those stay with the native review perspectives/axes.

## Dispatch message template

Substitute `<DIFF_PATH>` (the already-computed diff for this review) and
`<N>` (issue number). Paste verbatim:

```
SKILLS TO LOAD: thermo-nuclear-code-quality-review, brevity

Read-only maintainability audit for issue #<N>. You MUST NOT edit any file or
run state-modifying git/gh. Review ONLY the diff at <DIFF_PATH>; read ranged
hunks and ranged file context — never cat whole files needlessly.

Apply the thermo-nuclear-code-quality-review skill at full strength.

Return findings as a flat list, highest-conviction first. Each finding is a
four-line block, nothing else between blocks:

  severity: high | medium | low
  what: <one line — the structural problem>
  why: <one line — maintainability cost, or the code-judo move that removes it>
  evidence: <file:line(s)>

Severity rule:
- high   — presumptive blockers: a file crosses 1000 lines due to this diff;
           spaghetti branch growth bolted onto unrelated flows; a clear
           missed code-judo simplification; boundary / canonical-layer leak;
           unnecessary abstraction / wrapper / cast / optionality churn that
           obscures the contract; wrong-layer or duplicate-helper logic.
- medium — other real maintainability cost.
- low    — minor (use sparingly; prefer omitting nits).

There is NO critical severity and NO security/correctness scope here. Prefer a
small number of high-conviction findings over a long list of cosmetic notes.

Do NOT flag a `// ponytail:`-marked simplification as under-engineering or
recommend re-adding the abstraction it removed — the marker is the author's
recorded decision.

End with exactly one line:
  THERMO_SUMMARY: <H> high | <M> medium | <L> low

If nothing structural is worth raising, return exactly:
  THERMO_SUMMARY: 0 high | 0 medium | 0 low
```

## Merge / dedup rules (caller-side)

The caller (slice.md or prd.md) parses the returned blocks and folds survivors
into its own output contract:

1. **Dedup against native findings.** A thermo finding *duplicates* a native
   one when it targets the same `file:line` region AND the same structural
   concern (most often the gated Architect perspective / `architectural-coherence`
   axis). Collapse to a single entry: **higher severity wins**; keep the more
   actionable, structural wording.
2. **Fold survivors in** using the caller's native shape (a `## Suggestions`
   item for slice-mode; an `<axis name="architectural-coherence">` `<finding>`
   for PRD-mode). Severity maps 1:1 — `high|medium|low` are identical to the
   slice `**Priority:**` levels and the XML `severity` attribute.
3. **Update the caller's counts** (slice `Summary:` line / PRD `<counts>`) so
   the existing schema self-check stays consistent.
4. **All-zero `THERMO_SUMMARY` → add nothing** (and say so, per the guard).
