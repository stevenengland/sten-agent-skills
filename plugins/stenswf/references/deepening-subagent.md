# Deepening subagent — dispatch + harmonization contract

Shared by `review/slice.md` (when `DEEPEN_HIT` is set) and `review/prd.md`
(Axis 3, every review). Applies the `codebase-design` lens — module,
interface, depth, seam, adapter, leverage, locality and the deletion test —
in an **isolated, read-only subagent**, so it can read the modules a diff
touches and their callers without bloating the main review session. Findings
are merged into the caller's existing output — never a separate artifact.

The lens owns **module structure**: whether a module, adapter or pass-through
earns its keep, what leaks through an interface, coupling between modules,
and which module owns a piece of logic. Code-level quality — file size,
branching growth, types, duplicated helpers — belongs to the thermo pass
([thermo-subagent.md](thermo-subagent.md)). No correctness, security or
critical-severity scope. It never interviews the user: grilling a candidate belongs to `/stenswf:improve-codebase-architecture`.

Each review dispatches it at most once; `review-loop` dispatches it only on its first pass.

## Dispatch message template

Substitute `<DIFF_PATH>` (the already-computed diff for this review), `<N>`
(issue number) and `<MODE>` (`slice` or `prd`). Paste verbatim:

```
SKILLS TO LOAD: codebase-design, brevity

Read-only deepening review for issue #<N> (<MODE> mode). You MUST NOT edit any
file or run state-modifying git/gh. Review the diff at <DIFF_PATH>; read ranged
hunks and ranged file context — never cat whole files needlessly.

Inspect broadly: for every module the diff touches, read the module and its callers (git grep for call sites), whether or not its interface changed.

Read the decision context before judging, when present. Issue <I>'s anchor is
.stenswf/<I>/decisions.md, else the newest .stenswf/.archive/<I>-*/decisions.md (shipping archives it dated).
- every active entry in <N>'s anchor, of any category (skip struck-through ~~D<n>~~ entries)
- for an inherited entry, its full text in the parent's file: Source #<P>/D<n> means entry D<n> in <P>'s anchor
- in prd mode, each slice's anchor
- ADRs in docs/adr/ or any docs/**/decisions/ directory
- the glossary: GLOSSARY.md, CONTEXT.md or UBIQUITOUS_LANGUAGE.md

Apply the codebase-design skill. Use its terms exactly — module, interface,
implementation, depth, deep, shallow, seam, adapter, leverage, locality —
and never substitute component, service, unit, API, signature, boundary,
layer or wrapper. Its rules are questions, not verdicts: a single-adapter
seam can earn its keep.

Diff attribution: raise a finding only for a problem the diff introduced or materially worsened.
Friction the diff did not introduce or worsen is never a finding; list it as a follow-up line instead.

Severity follows demonstrated consequence, not how strongly you would recommend the change:
- high   — the diff introduces or materially worsens a duplicated business rule, an invariant leaking across an interface, a change that must propagate through callers, or a materially obscured contract.
- medium — a real but contained cost, such as a new pass-through module that the deletion test removes.
- low    — a minor cost.

Confidence decides only whether to publish: every finding needs file:line evidence from the diff or the callers you read.
Never emit a speculative redesign; it belongs to /stenswf:improve-codebase-architecture.
Every recommendation names the invariants it must keep (transaction boundaries, error behaviour, authorization, ordering) when the module carries any.

Do not re-litigate a recorded decision: skip a candidate that a decision
entry or an ADR already settled, unless the friction is real enough to
reopen it — then name that entry or ADR in why.
Do NOT flag a `// ponytail:`-marked simplification as under-engineering or
recommend re-adding the abstraction it removed — the marker is the author's
recorded decision.

Return findings as a flat list, highest severity first. Each finding is a
four-line block, nothing else between blocks:

  severity: high | medium | low
  what: <one line — the structural problem, in codebase-design terms>
  why: <one line — its consequence, and the deletion-test result where it applies>
  evidence: <file:line(s)>

There is NO critical severity.

End the findings with exactly one line:
  DEEPENING_SUMMARY: <H> high | <M> medium | <L> low

Then at most three follow-up lines, one per module, most costly first:
  follow-up: <module> — <friction> — /stenswf:improve-codebase-architecture <module>

If nothing is worth raising, return exactly:
  DEEPENING_SUMMARY: 0 high | 0 medium | 0 low
followed by any follow-up lines.
```

## Merge / dedup rules (caller-side)

The caller (slice.md or prd.md) parses the returned blocks and folds survivors
into its own output contract, exactly as it does for the thermo pass:

1. **Dedup across Architect, thermo and deepening.** A deepening finding
   duplicates another when it targets the same `file:line` region AND the
   same structural concern. Collapse to a single entry: **higher severity
   wins**; when the concern is module structure, keep the codebase-design
   wording.
2. **Fold survivors in** using the caller's native shape (a `## Suggestions`
   item for slice-mode; an `<axis name="architectural-coherence">` `<finding>`
   for PRD-mode). Severity carries over unchanged — `high|medium|low` are
   identical to the slice `**Priority:**` levels and the XML `severity`
   attribute.
3. **Update the caller's counts** (slice `Summary:` line / PRD `<counts>`) so
   the existing schema self-check stays consistent.
4. **Follow-up lines are not findings.** They never enter the counts and
   never become PR threads. The caller lists them where its output section
   says: slice-mode under `## Follow-ups (not counted)`, PRD-mode as
   `<follow-up>` elements in the architectural-coherence axis.
5. **All-zero `DEEPENING_SUMMARY` → add no findings** (and say so, per the
   guard).
