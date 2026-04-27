---
name: triage-issue
description: Triage a raw GitHub bug-report issue into REJECT or a stenswf-shaped bug-brief + slice. No quick-fix lane.
disable-model-invocation: true
---

**Load and apply `brevity` now.** See
[../../references/brevity-load.md](../../references/brevity-load.md).

Apply context-hygiene per
[../../references/context-hygiene.md](../../references/context-hygiene.md).

Triage a raw GitHub bug-report issue (issue number `$ARGUMENTS`) into
one of two outcomes:

**Ceremony invariant (TDD-as-lens).** This skill MUST NOT (a) emit
untagged ACs on bug-brief or slice ACs (every AC carries
`(behavior)` or `(structural)`), (b) instruct skipping tests for
ACs annotated `(behavior)`, (c) remove `tdd` from any SKILLS TO
LOAD list, (d) accept `manual check` or "rely on existing suite"
as completion evidence for a `(behavior)` AC, or (e) emit guidance
that contradicts `tdd/SKILL.md`. See
[../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).

- **REJECT** — duplicate, out-of-scope (matches persistent rejection
  memory), or needs-info.
- **CONVERT** — emit a bug-brief issue + one or more slice issues that
  the existing `plan-light` / `plan` / `ship-light` / `ship` pipeline
  accepts. Close and cross-link the original.

There is **no quick-fix lane.** Every accepted bug becomes a slice.

If during triage the issue turns out to be a feature/refactor request
rather than a bug, exit with a routing recommendation
(`/stenswf:prd-from-grill-me <N>`) — do not invoke that skill.

Recommended model: **Opus**. Phase 3 root-cause investigation is the
expensive part; backward tracing through unfamiliar code is the same
workload `plan` and `review` are routed to Opus for.

## Audience

`triage-issue` is the front door for bug intake. It is **never**
invoked by another skill — only by a human running
`/stenswf:triage-issue <issue-number>`.

It does **not**:

- mutate the original issue body (it stays as the durable intake
  record);
- run TDD or open a fix PR (no quick-fix lane);
- invoke `grill-me` or `prd-from-grill-me` (escalation is a routing
  recommendation, not a chained call).

It does:

- run dedup against open issues and persistent rejection memory;
- dispatch Explore subagents for reproduction and root-cause;
- on CONVERT, create a bug-brief artifact + slice(s) and seed
  `.stenswf/<bug-brief-N>/` identically to a PRD;
- close the original issue last, after both derived artifacts exist
  and reference each other;
- emit a soft handover prompt to `plan-light` / `plan`.

---

## Phase 0 — Preflight

```bash
export STENSWF_SKILL=triage-issue
export STENSWF_ISSUE=$ARGUMENTS
export STENSWF_PHASE=preflight

FB_LOG=".stenswf/_feedback/$(date -u +%F).jsonl"
mkdir -p "$(dirname "$FB_LOG")"
SESSION_START_N=$(wc -l < "$FB_LOG" 2>/dev/null || echo 0)
export SESSION_START_N
```

(Boundary ping at exit per
[../../references/feedback-session.md](../../references/feedback-session.md).)

### 0.1 Tooling check

```bash
command -v gh >/dev/null 2>&1 || {
  bash plugins/stenswf/scripts/log-issue.sh tool_failure "gh CLI missing"
  echo "stenswf: gh CLI not available — present formatted bodies for manual creation; write nothing." >&2
  exit 1
}
```

### 0.2 Fetch the issue

```bash
gh issue view "$ARGUMENTS" --json number,title,body,state,author,comments \
  > /tmp/triage-$ARGUMENTS.json
gh issue view "$ARGUMENTS" --json body -q .body > /tmp/triage-$ARGUMENTS-body.md
gh issue view "$ARGUMENTS" --json title -q .title > /tmp/triage-$ARGUMENTS-title.txt
wc -l /tmp/triage-$ARGUMENTS-body.md   # confirm fetch; do not cat
```

### 0.3 Already-triaged guard

If the body already contains stenswf:v1 front-matter, exit. Re-triage
is a contract violation.

```bash
if head -5 /tmp/triage-$ARGUMENTS-body.md | grep -q '^<!-- stenswf:v1'; then
  bash plugins/stenswf/scripts/log-issue.sh contract_violation \
    "issue already has stenswf:v1 front-matter"
  echo "Issue #$ARGUMENTS is already triaged. Use /stenswf:plan-light or /stenswf:plan." >&2
  exit 1
fi
```

### 0.4 Pre-triage classification (step-back)

Per
[../../references/reasoning-effects.md](../../references/reasoning-effects.md)
(*step-back* template):

> Before running dedup or reproduction, step back and identify what
> *type* of issue this is. Read the title and body. Classify as one of:
> **bug** (broken behavior described), **feature/refactor request**
> (new capability or structural change requested), **support/question**
> (user needs help, not a code change), or **noise**.
>
> Name the class first; only then decide whether to continue triage.

Action by class:

| Class | Action |
|---|---|
| `bug` | Continue to Phase 1. |
| `feature/refactor request` | Print: *"This looks like a feature/refactor request, not a bug. Recommended: `/stenswf:prd-from-grill-me $ARGUMENTS`."* Ask user to confirm class. If confirmed, exit. If user disputes, continue as bug. |
| `support/question` | Suggest the user answer the reporter directly. Ask user to confirm. If confirmed, exit (no derived artifacts, no close — leaves the question to humans). |
| `noise` | Treat as a candidate REJECT (out-of-scope or duplicate); proceed to Phase 1 to verify. |

---

## Phase 1 — Dedup

Per [../../references/out-of-scope-memory.md](../../references/out-of-scope-memory.md).

### 1.1 Extract title nouns

```bash
TITLE=$(cat /tmp/triage-$ARGUMENTS-title.txt)
NOUNS=$(printf '%s' "$TITLE" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -c 'a-z0-9' ' ' \
  | tr ' ' '\n' \
  | grep -Ev '^(a|an|the|in|on|at|to|of|for|with|when|while|is|are|was|fails|fail|error|errors|bug|bugs|broken|cannot|cant|doesnt|does|not)$' \
  | grep -E '.{3,}' \
  | head -3 \
  | tr '\n' ' ' \
  | sed 's/[[:space:]]*$//')
echo "triage: dedup nouns = ${NOUNS:-<none>}"
```

### 1.2 GitHub search (open + closed)

Guard the empty-nouns case — an empty search would return every issue
in the repo and is not a useful dedup signal.

```bash
if [ -n "$NOUNS" ]; then
  gh issue list --state all --search "$NOUNS is:issue" --limit 10 \
    --json number,title,state,closedAt > /tmp/triage-$ARGUMENTS-dups.json
else
  echo "triage: title has no searchable nouns; skipping GitHub dedup"
  echo '[]' > /tmp/triage-$ARGUMENTS-dups.json
fi
```

Filter to issues other than `$ARGUMENTS`. Read the candidates' bodies
on demand (do not bulk-load). For each, decide whether the **root
cause** matches (not just the symptom or keyword overlap).

### 1.3 Out-of-scope memory grep

```bash
OOS_HITS=""
if [ -d .stenswf/.out-of-scope ]; then
  for n in $NOUNS; do
    grep -i -l -E "^(title|reason):.*$n" .stenswf/.out-of-scope/*.md \
      2>/dev/null
  done | sort -u > /tmp/triage-$ARGUMENTS-oos.txt
  OOS_HITS=$(wc -l < /tmp/triage-$ARGUMENTS-oos.txt | tr -d ' ')
fi
echo "triage: out-of-scope hits = ${OOS_HITS:-0}"
```

### 1.4 Dedup verdict

If GitHub search produced an open issue with a *plausibly matching
root cause*, propose REJECT (`duplicate`).

If `.out-of-scope/` produced a hit, propose REJECT (`out-of-scope`).

User confirms in Phase 4 — do not auto-close here.

---

## Phase 2 — Reproduction (Explore subagent)

Skip if Phase 1 already proposed REJECT (`duplicate`) and the user is
likely to accept — but if uncertain, still run Phase 2 so REJECT
candidates are not based on title-noun overlap alone.

Dispatch ONE `Explore` subagent (thoroughness: medium, ≤300 words):

> Read GitHub issue #$ARGUMENTS body and comments at
> `/tmp/triage-$ARGUMENTS.json`. Attempt to identify the failing code
> path from the report.
>
> Return a ≤300-word report with these fields verbatim:
>
>   repro_status: confirmed | likely | cannot-locate
>   suspected_root_cause: <≤2 sentences>
>   affected_modules: <comma-separated top-level dirs>
>
> Do not paste file contents. Symbol paths only. Do not run tests.
> Thoroughness: medium.

If `repro_status: cannot-locate`, **skip Phase 3** and proceed to
Phase 4 with REJECT(`needs-info`) as the only available CONVERT
alternative.

---

## Phase 3 — Root cause (Explore subagent, conditional)

Run only when Phase 2 returned `confirmed` or `likely`.

Per
[../../references/reasoning-effects.md](../../references/reasoning-effects.md)
(*constraint-repetition*):

> Reminder before proceeding: **no fixes without confirmed root cause.**
> The Phase 5 CONVERT path requires a root cause stated as a
> falsifiable claim with a cited origin and symptom site.

Dispatch ONE `Explore` subagent (thoroughness: thorough, ≤500 words):

> Backward trace from the symptom in #$ARGUMENTS to its origin.
> Cite `file:line` for both the origin and the symptom site.
>
> Return a ≤500-word report with these fields verbatim:
>
>   confirmed_root_cause: <≤3 sentences, falsifiable>
>   origin: <file:line>
>   symptom: <file:line>
>   affected_files: <≤15 file paths, one per line>
>   fix_shape_summary: <≤3 sentences, no code>
>   judgment_calls: <list of design decisions the fix would touch, or "none">
>
> Do not write code. Do not paste file contents beyond cited line numbers.
> Thoroughness: thorough.

Persist to `/tmp/triage-$ARGUMENTS-rca.md` for Phase 5.

---

## Phase 4 — Triage decision (USER CONFIRMS)

Always ask. Triage decisions are durable.

### 4.1 Present the decision panel

Render verbatim (substitute fields from prior phases):

```
Triage panel — issue #<N>: <title>

Class:                <bug | other from Phase 0.4>
Dedup:                <duplicate of #X | out-of-scope match | clean>
Repro status:         <confirmed | likely | cannot-locate>
Root cause:           <one-line summary | n/a>
Affected modules:     <comma list>
Affected files:       <count> (<≤15 ideal>)
Judgment calls:       <list | none>

Available outcomes:

  [R-dup]   REJECT — duplicate of #X. Comment + close.
  [R-oos]   REJECT — out-of-scope (matches <file>). Comment + close.
  [R-info]  REJECT — needs-info. Post structured request, leave open.
  [C-1]     CONVERT — single slice (default).
  [C-N]     CONVERT — fan-out (multiple slices via prd-to-issues).
  [E-prd]   ESCALATE — looks like feature/refactor → recommend
            /stenswf:prd-from-grill-me <N> and exit.

Pick one. Default: <C-1 if Phase 3 ran cleanly, else R-info>.
```

Hide outcomes that are not available (e.g. `R-dup` only when Phase 1
found one; `C-1`/`C-N` only when `repro_status != cannot-locate`).

### 4.2 Apply outcome

| Outcome | Action |
|---|---|
| `R-dup` | Comment "Duplicate of #X — see there for status." Close with `gh issue close "$ARGUMENTS" --reason "not planned"`. **Do not** write an out-of-scope memory file (GitHub already records duplicates). |
| `R-oos` | Comment with the rejection reason and link the prior decision. Close with `gh issue close "$ARGUMENTS" --reason "not planned"`. **If** this is a novel rejection (not just hitting an existing memory file), write a new file under `.stenswf/.out-of-scope/<N>.md` per [../../references/out-of-scope-memory.md](../../references/out-of-scope-memory.md). |
| `R-info` | Post the structured needs-info comment (template below). **Do not** close. Exit. |
| `C-1` | Continue to Phase 5 single-slice. |
| `C-N` | Continue to Phase 5 fan-out. |
| `E-prd` | Print the routing recommendation and exit. Log `user_override` if Phase 0.4 had classified as `bug` and the user disagreed. |

### 4.3 Needs-info comment template

```
Thanks for filing this. Triage cannot reproduce the failure from the
information provided. Please provide:

- Expected behavior
- Actual behavior (what you saw)
- Minimal reproduction steps
- Environment: OS / runtime version / project version
- Relevant logs or stack traces

Re-running `/stenswf:triage-issue` after the report is updated will
re-attempt reproduction.
```

### 4.4 Forced CONVERT despite cannot-locate

If the user picks `C-1` or `C-N` while `repro_status: cannot-locate`,
proceed but log `user_override` with evidence
`"forced CONVERT despite repro_status=cannot-locate"`. The resulting
slice will be `type: slice — HITL` (human judgment is required to
verify the fix, since no automated repro exists).

---

## Phase 5 — Convert (REJECT outcomes do not reach this phase)

Convert is **ordered** — bug-brief is created before the slice; the
original is closed last. This guarantees the original always points to
durable artifacts.

### 5.1 Resolve base SHA

```bash
export STENSWF_PHASE=convert
git fetch --quiet
PRD_BASE=$(git rev-parse --verify '@{upstream}' 2>/dev/null || {
  D=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)
  [ -n "$D" ] && git rev-parse "origin/$D"
})
[ -n "$PRD_BASE" ] || {
  bash plugins/stenswf/scripts/log-issue.sh tool_failure "cannot resolve base SHA"
  echo "stenswf: cannot resolve base SHA — set upstream or pass explicitly" >&2
  exit 1
}
```

### 5.2 Decide single-slice vs fan-out

Single slice is the default. **Fan-out only when ALL THREE hold:**

1. Affected files >15 OR cross-module OR schema migration implied.
2. Genuine **chain** of root causes (not one cause manifesting in
   many places — a chain means each cause is independently
   falsifiable).
3. Each potential slice can be tested independently of the others.

If only #1 holds (large blast radius, single root cause) → one HITL
slice (`lite_eligible: false`, `disqualifier: files>15`). Fan-out
would force an artificial dependency chain.

### 5.3 Write bug-brief body (using prd-template.md + bug-brief-class.md)

Build the bug-brief body in `/tmp/triage-$ARGUMENTS-brief.md`. Use
[../../references/prd-template.md](../../references/prd-template.md)
with the `class: bug-brief` overrides documented in
[../../references/bug-brief-class.md](../../references/bug-brief-class.md).

Required body sections (copy verbatim shape, fill from earlier phases):

- `## Problem Statement` — one paragraph paraphrased from the bug body.
- `## Root Cause` — from Phase 3 (`confirmed_root_cause`, `origin`, `symptom`).
- `## Implementation Decisions` — `fix_shape_summary` + module list. No code, no file paths.
- `## Invariants Preserved` — explicit list (e.g. "public API stable", "existing green tests stay green", "no schema change").
- `## Conventions` — new rules introduced to prevent recurrence, or `None — slice-local decisions only.`
- `## Out of Scope` — adjacent defects observed but deferred.
- `## Testing Decisions` — regression test placement and what it pins.

Front-matter:

```
<!-- stenswf:v1
type: bug-brief
class: bug-brief
prd_base_sha: <PRD_BASE>
# affects_prd: <N>      # only if Phase 3 identified a feature PRD whose scope contains this defect
-->
```

### 5.4 Create the bug-brief issue

```bash
BB_TITLE="bug-brief: <one-line summary derived from the original title>"
BB_URL=$(gh issue create --title "$BB_TITLE" \
  --body-file /tmp/triage-$ARGUMENTS-brief.md)
BB_NUM=$(basename "$BB_URL")
echo "triage: bug-brief = #$BB_NUM"
```

If `gh` cannot create issues (auth, network), abort *before* writing
any local state. Print the body for manual creation.

### 5.5 Seed local state for the bug-brief

Mirrors `prd-from-grill-me` step 5 verbatim, with `kind: "bug-brief"`.

```bash
mkdir -p ".stenswf/$BB_NUM"
gh issue view "$BB_NUM" --json body -q .body > ".stenswf/$BB_NUM/concept.md"
CONCEPT_SHA=$(sha256sum ".stenswf/$BB_NUM/concept.md" | awk '{print $1}')
cat > ".stenswf/$BB_NUM/manifest.json" <<EOF
{
  "issue": $BB_NUM,
  "kind": "bug-brief",
  "base_sha": "$PRD_BASE",
  "concept_sha256": "$CONCEPT_SHA",
  "plan_created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "slices": [],
  "review_step": {"status": "pending", "sha": null},
  "bug_ref": $ARGUMENTS
}
EOF

cat > ".stenswf/$BB_NUM/decisions.md" <<EOF
# Decisions — #$BB_NUM

<!-- Seeded by triage-issue. Schema: plugins/stenswf/README.md#decision-anchor-contract -->
EOF
```

**Seed anchor entries** per
[../../references/decision-anchor-link.md](../../references/decision-anchor-link.md):

- One `arch` entry: the confirmed root cause (Phase 3) — title summary,
  rationale = origin/symptom citation.
- One `decision` entry per item in `## Conventions` of the bug-brief
  (skip if `None — slice-local decisions only.`).

Use the canonical append snippet from the Decision Anchor Contract.

### 5.6 Create slice(s)

#### Single-slice path (`C-1`)

Slice front-matter (use [../../references/issue-template.md](../../references/issue-template.md)):

```
<!-- stenswf:v1
type: slice — AFK
lite_eligible: <true|false>
conventions_source: bug-brief#<BB_NUM>
prd_ref: <BB_NUM>
bug_ref: <ARGUMENTS>
# disqualifier: ...      # required when lite_eligible: false
-->
```

`type` selection:

- `slice — HITL` if Phase 3 reported `judgment_calls` ≠ none, **or** if
  Phase 4 had a `user_override` for forced-CONVERT.
- `slice — AFK` otherwise.

`lite_eligible` follows the existing envelope from
`prd-to-issues` step 4: ≤15 files, single top-level module, no schema
migration, no unresolved arch decisions.

Build the slice body in `/tmp/triage-$ARGUMENTS-slice.md` (mirror
Phase 5.3's bug-brief body construction). Use
[../../references/issue-template.md](../../references/issue-template.md)
as the section skeleton.

Body sections:

- `## Parent PRD` — `#<BB_NUM>` (yes, the bug-brief; the heading name
  remains "Parent PRD" for compatibility with existing extractors).
- `## What to build` — restoration of the broken behavior described in
  the bug-brief, with reference to its Implementation Decisions.
- `## Conventions (from PRD)` — verbatim copy of the bug-brief's
  `## Conventions` (contents only).
- `## Acceptance criteria` — derived from `## Invariants Preserved`
  (one `(structural)` checkbox each: "invariant X holds") plus one
  or more `(behavior)` regression-test ACs that pin the original
  bug. Every AC MUST carry a `(behavior)` or `(structural)` tag as
  its first parenthesised token, per
  [../../references/behavior-change-signal.md](../../references/behavior-change-signal.md).
  Untagged ACs are a hard error — log `contract_violation` and
  refuse to create the slice.
- `## User stories addressed` — `Restoration: <one-line>`.
- `## Files (hint)` — Phase 3's `affected_files` (≤15).
- `## Invariants preserved` — verbatim from the bug-brief.

Create:

```bash
SLICE_URL=$(gh issue create --title "<slice title derived from bug>" \
  --body-file /tmp/triage-$ARGUMENTS-slice.md)
SLICE_NUM=$(basename "$SLICE_URL")
echo "triage: slice = #$SLICE_NUM"
```

Update the bug-brief manifest with the slice number:

```bash
jq --argjson s "$SLICE_NUM" \
  '.slices = ((.slices // []) + [$s] | unique)' \
  ".stenswf/$BB_NUM/manifest.json" > /tmp/bb-manifest.json \
  && mv /tmp/bb-manifest.json ".stenswf/$BB_NUM/manifest.json"
```

#### Fan-out path (`C-N`)

Do **not** create slices directly. Instead:

1. Update the bug-brief manifest as ready for slicing.
2. Print:

   > Bug-brief #<BB_NUM> created. This bug warrants fan-out (chain of
   > root causes, independently testable).
   >
   > Continue directly into slicing now? Saves ~5K tokens vs a fresh
   > run.
   >   [y]es → /stenswf:prd-to-issues <BB_NUM>  (bug-brief mode)
   >   [N]o, I'll review first
   >
   > Default: N

3. **HARD STOP.** On `y` → invoke `prd-to-issues` starting at its
   **Step 3 (HITL triage)**, with bug-brief-mode active (the parent's
   `class: bug-brief` triggers default-1-slice behavior, see
   [../../skills/prd-to-issues/SKILL.md](../prd-to-issues/SKILL.md)).
   Any other message → exit; original issue stays untouched (the user
   will close it after slicing).

### 5.7 Cross-link

```bash
gh issue comment "$BB_NUM"   --body "Slice: #$SLICE_NUM. Original bug report: #$ARGUMENTS."
gh issue comment "$SLICE_NUM" --body "Bug-brief: #$BB_NUM. Original bug report: #$ARGUMENTS."
```

### 5.8 Close the original (LAST)

Only after both derived artifacts exist:

```bash
gh issue comment "$ARGUMENTS" --body \
"Triaged → bug-brief #$BB_NUM, slice #$SLICE_NUM.
The original report is preserved here as the durable intake record.
Status updates will appear on the slice."
gh issue close "$ARGUMENTS" --reason completed
```

For the fan-out path, do **not** close the original here — let
`prd-to-issues` close it after the slices are created (or leave it to
the user, since fan-out is a multi-step interaction).

---

## Phase 6 — Soft handover

For `C-1` only (fan-out path handed off in Phase 5.6 already):

```
Bug-brief #<BB_NUM> created. Slice #<SLICE_NUM> created. Original #<ARGUMENTS> closed.

Continue directly into planning now? Saves ~5K tokens vs a fresh run.
  [y]es → /stenswf:plan-light <SLICE_NUM>
          (or /stenswf:plan if lite_eligible: false)
  [N]o, I'll review first

Default: N
```

**HARD STOP.** Do not invoke any planner. Do not dispatch a subagent.
Do not read further files. End the turn now and wait for the user's
literal next message.

**On the next user message:**

- `y`, `yes`, `proceed`, `go` (case-insensitive, trimmed) → invoke
  `plan-light <SLICE_NUM>` if `lite_eligible: true`, else `plan
  <SLICE_NUM>`. Treat the slice's preflight as the entry point.
- Any other message → end. Do not plan.

---

## Pre-finalize reflection (before Phase 4 user prompt)

Per
[../../references/reasoning-effects.md](../../references/reasoning-effects.md)
(*pre-finalize-reflection*):

> Before presenting the triage panel, pause and step back:
>
> - Did Phase 2's `repro_status` actually rule out a duplicate I missed
>   (e.g. same symptom, different root cause)?
> - Is the `judgment_calls` list really empty, or did I quietly defer a
>   design decision into the slice that should be a HITL signal?
> - Did Phase 3's `affected_files` exceed 15 silently, which should
>   force `lite_eligible: false`?
> - Have I conflated symptom with root cause? (Look for "X happens
>   because Y is unhandled" — if `Y` is itself unexplained, the root
>   cause is incomplete.)
>
> If any answer changes the panel, revise before presenting.

---

## Feedback

Log workflow friction per
[../../references/feedback-session.md](../../references/feedback-session.md)
with `STENSWF_SKILL=triage-issue`.

Categories used by this skill:

- `contract_violation` — already-triaged issue retriaged (Phase 0.3).
- `missing_artifact` — bug body lacks expected/actual/repro (surfaces
  in Phase 4's needs-info comment).
- `tool_failure` — gh CLI absent, base-SHA unresolvable, issue create
  failed.
- `user_override` — forced CONVERT despite `repro_status:
  cannot-locate`; class disagreement at Phase 0.4.
- `ambiguous_instruction` — Phase 3 root-cause came back without a
  cited origin or symptom site.

Boundary ping at exit (per feedback-session.md).

---

## Out of scope (this skill)

- Quick-fix lane — explicitly excluded (every accepted bug becomes a
  slice).
- Auto-`wontfix` — never decided by the agent. If the agent suspects
  "valid but shouldn't fix", it routes back to the user as a question.
- Severity / priority routing — not modeled. All accepted bugs go
  through identical pipeline.
- Mutating the original issue body — the original stays as the
  intake record.
- Invoking `grill-me` or `prd-from-grill-me` — escalation is a
  recommendation, not a chained call.
- Refactor *requests* — handled by `prd-from-grill-me` Phase 0
  (issue-intake mode), not here.
