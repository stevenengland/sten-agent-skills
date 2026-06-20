# Ponytail pass — subtractive self-review

Single source for the ponytail (YAGNI / laziest-that-works) self-review
pass. It adds a **subtractive** lens to the reflection seams stenswf already
has: question whether code needs to exist, reach for stdlib before custom
code, native platform features before dependencies, one line before fifty.

It strictly **adds to** `clean-code` and `tdd` — it never overrides them.
Everything below exists to guarantee that.

Loaded lazily by `plan` (pre-finalize reflection), `plan-light` (Phase-4
reflection), `ship` (Phase-2 refactor pass), `ship-light` (Phase-3
rubberduck), and `apply` (anti-balloon guard). `review/slice.md` and
`references/thermo-subagent.md` honor the marker below but do **not** run
the pass — keeping the subtractive lens out of the same pass as the
opposite-pole `thermo-nuclear` maintainability lens.

---

## The ladder

Stop at the first rung that holds:

1. **Does this need to exist at all?** Speculative need → cut it.
2. **Stdlib does it?** Use the stdlib call.
3. **Native platform feature covers it?** Use the platform (DB constraint
   over app code, CSS over JS, etc.).
4. **Already-installed dependency solves it?** Use it. Never add a new one
   for what a few lines do.
5. **Can it be one line?** One line.
6. **Only then:** the minimum code that works.

The ladder is a reflex, not a research project. It runs at `full` intensity
always — no dial.

---

## Precedence — the non-contradiction rule

> **Ponytail never overrides a recorded decision.** Not an active
> `decisions.md` anchor, not a `conventions.md` line, not a deliberately
> chosen architecture pattern, not a `clean-code` readability extraction,
> not test coverage for a `(behavior)` AC.

It cuts only **unjustified, unrecorded speculation**. A recorded decision is
the author's answer; ponytail does not re-litigate it. This is the same
spirit as ADRs (`architecture` skill): recorded decisions are not silently
reversed.

---

## Per-finding classifier

Each finding is **safe** or **contentious**. Default to contentious on any
uncertainty (mirrors the behavior-change ladder's "default `true`").

### Safe — auto-apply in any mode

ALL of these must hold:

- Behavior is **provably identical** — a black-box public-interface test
  passes unchanged before and after.
- The cut **touches nothing recorded** — no active `decisions.md` anchor, no
  `conventions.md` line, no chosen architecture pattern, no readability
  extraction.
- **No test** covering a `(behavior)` AC is added, weakened, or removed.
- The full suite **stays green**.

AND the finding is one of:

- `stdlib:` replace hand-rolled logic with a standard-library call, behavior
  identical. Name the function.
- `shrink:` same logic, fewer lines. Show the shorter form.
- `delete:` **provably** unreferenced dead code — no static caller, not
  exported, not dynamically dispatched / reflected / registered.
- `yagni:` inline a single-caller / single-implementation wrapper that
  exists only as speculative indirection.

### Contentious — gate by slice TYPE

ANY of:

- Touches something recorded (decision / convention / architecture pattern /
  readability extraction).
- `native:` that **removes a dependency** (supply-chain / version /
  edge-behavior call).
- Behavior-identity is not provable.
- Inlining a helper with **>1 caller**, or one extracted for
  readability / naming.
- Any change to a test, or a cut that would break a test → route to the
  **bad-test audit** (`behavior-change-signal.md`); never classified safe.

---

## Cut-handling by slice TYPE

Reachability comes from the slice TYPE front-matter, the existing
is-user-available signal:

- **HITL** (`slice — HITL`, or `ship-light` invoked directly by a user) →
  user reachable.
- **AFK** (`slice — AFK`, or any pass dispatched under `slice-e2e`) → not
  reachable.

Then:

- **Safe finding** → apply it, mark it (below). No decision entry.
- **Contentious finding, user reachable** → stop. Present `what / why /
  net lines / what it touches`. Wait for a decision. Apply nothing without
  sign-off.
- **Contentious finding, not reachable** → flag-only: write it to the PR
  body and as a pending note in `decisions.md`. Apply nothing.

---

## Recording

- A **contentious** cut — applied after sign-off (reachable) or left as a
  pending note (not reachable) — writes one `decision` entry under the
  **host seam's** source (`plan` / `plan-light` / `ship` / `ship-light`)
  per [decision-anchor-link.md](decision-anchor-link.md). There is no
  `ponytail` source; provenance stays with the seam that ran the pass.
- A **safe** cut writes no decision entry — it gets only the marker below
  plus the one-line summary under Visibility. (Safe cuts are
  behavior-identical and touch nothing recorded; recording each one would
  flood `decisions.md`, especially on the silent `plan-light` seam.)
- Mark each deliberate simplification left in the code with a marker
  comment (below).

## Marker

`// ponytail: <ceiling>, <upgrade path>` (comment syntax per language) names
the known ceiling of a shortcut and how to lift it, e.g.
`# ponytail: global lock, per-account locks if throughput matters`.

It is **not** an ID (clears `local-id-hygiene`) and it is a *why*-comment
(clears `clean-code`'s comment rules). `review` and the thermo subagent MUST
NOT flag a `ponytail:`-marked simplification as under-engineering, nor
recommend re-adding the abstraction it removed — the marker is the author's
recorded decision.

## Ordering inside a pass

1. Classify each finding (safe / contentious).
2. Apply safe cuts.
3. Re-run the suite. Any test that breaks was implementation-coupled → route
   to the bad-test audit (`behavior-change-signal.md`). **No
   green-by-deletion of a behavior test** — behavior coverage MUST NOT drop.
4. Lint (apply `lint-escape` if blocked).
5. Surface output (below).

## Visibility

- Safe cuts → one summary line in the self-critique / refactor commit body
  and the PR body: `ponytail: -<N> lines — <tag> <thing>, …`.
- Contentious → presented to the user (reachable) or written to the PR body
  (not reachable).
- Nothing to cut → `ponytail: lean already` and move on.

---

## Per-seam behavior

- **`plan`** (interactive interview — user reachable) — apply the ladder to
  the *plan itself*: a task
  that builds a one-consumer abstraction, a dependency for what
  stdlib/native covers, speculative file-structure. Contentious leanings
  become interview points; safe leanings simplify the plan in place.
- **`plan-light`** (AFK / silent) — same target; safe leanings applied
  silently; a genuine build-vs-skip fork → `## Assumptions` or the existing
  `ROUTE_HEAVY`.
- **`ship` Phase-2 refactor pass** — run over the combined subagent diff
  (`$BASE_SHA..HEAD`). The orchestrator (a fresh session, not the
  implementer) is the fresh lens. TYPE drives reachability.
- **`ship-light` Phase-3 rubberduck** — extend the Scope-drift bullet into
  the full ladder over `$BASE_SHA..HEAD`. Direct invocation = reachable;
  under `slice-e2e` = not.
- **`apply`** — anti-balloon guard only. Before applying a suggestion, check
  it does not grow into an unrequested abstraction; prefer the one-line /
  stdlib / native form. Does **not** run the full ladder.

## Out of scope

Whole-repo audit; an intensity dial (always `full`).
