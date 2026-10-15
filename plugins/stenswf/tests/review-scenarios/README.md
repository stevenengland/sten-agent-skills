# Review scenarios

Sample changes, each with the verdict a good reviewer should reach. They check
the *judgments* the review instructions produce; the bash tests in `tests/`
only check that the instructions exist. They are not part of the bash suite: a
model's answer varies from run to run, so they cannot be a pass/fail gate.

## When to run

Whenever the reviewer instructions change — `references/deepening-subagent.md`,
`references/thermo-subagent.md`, `skills/codebase-design/`,
`skills/thermo-nuclear-code-quality-review/`, `skills/review/`, or the intake
of `skills/prd-from-grill-me/`. Never during a normal review.

## Scenarios

| Scenario | Checks |
|---|---|
| `redundant-pass-through` | deepening flags a new pass-through; thermo stays out of module structure |
| `single-implementation-domain-port` | a single-adapter seam that keeps vendor types out of domain code is not flagged |
| `coupling-behind-unchanged-interface` | new coupling is caught although no interface changed |
| `pre-existing-shallow-module` | older friction is a follow-up line, never a finding |
| `decision-settled-abstraction` | an inherited decision is resolved through its `Source:`, from a dated archive, and respected |
| `discovery-to-prd-handoff` | `prd-from-grill-me` takes the brief and asks only what it leaves open |

## How to run

Run from the repo root of the checkout under test. Never show `expected.md` to the reviewer; read it only to judge the answer.

1. Build the scenario's repo (all scenarios except `discovery-to-prd-handoff`):

   ```bash
   S=plugins/stenswf/tests/review-scenarios/<scenario>
   W=$(mktemp -d)
   cp -R "$S/before/." "$W/"
   [ -d "$W/dot-stenswf" ] && mv "$W/dot-stenswf" "$W/.stenswf"
   git -C "$W" init -q && git -C "$W" add -A
   git -C "$W" -c user.email=s@s -c user.name=s commit -qm before
   git -C "$W" apply "$PWD/$S/diff.patch" && git -C "$W" add -A
   git -C "$W" diff --staged > "$W.patch"
   echo "repo: $W  diff: $W.patch"
   ```

   `dot-stenswf/` holds a scenario's decision files under a neutral name, because many clones git-ignore every `.stenswf/` directory.

2. For each reviewer the scenario's `expected.md` names, dispatch one fresh, read-only subagent with the dispatch template from `references/deepening-subagent.md` or `references/thermo-subagent.md`, substituting `<DIFF_PATH>=$W.patch`, `<N>=900` and `<MODE>=slice`. Append two lines to the template: `Work only inside $W (cd there first).` and `Read the skills named in SKILLS TO LOAD from this checkout's plugins/stenswf/skills/, not from the installed plugin.` The scenarios test the checkout, not the release.

3. For `discovery-to-prd-handoff`, dispatch one fresh subagent with: `Read plugins/stenswf/skills/prd-from-grill-me/SKILL.md from this checkout and follow it with $ARGUMENTS set to the brief below. Skip Step 2: this scenario has no codebase. Do not run gh, create issues or write files. Stop when you would send your first message to the user, and return that message verbatim.` followed by the text of `brief.md`.

4. Compare each answer with the scenario's `expected.md`. A scenario passes when every **Pass when** item holds and no **Fail when** item does.

## Recording results

One row per scenario:

| Scenario | Result | Note |
|---|---|---|
| `<scenario>` | pass / fail | <one line: what the reviewer said> |

When the run belongs to a PR, put the table in the PR description under `## Review scenarios`. A failing scenario means the instructions need fixing before merge — unless the scenario itself is wrong, which the PR must then say and fix.
