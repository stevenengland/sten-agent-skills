---
name: visual-pr
description: Create or update a pull request description that explains why the change exists and shows its shape with show-me-style visual outlines.
---

# Describe a Pull Request

Create or update the pull request for the current task with a concise description that helps a reviewer understand why the change exists and the shape of the implementation.

Two modes:

- **Standalone** — invoked directly (`/visual-pr`). Follow the workflow below.
- **Body-only** — a stenswf shipper (`ship`, `ship-light`, apply PRD-mode) says "Load `visual-pr` in body-only mode" and passes five inputs. Follow [Body-only mode](#body-only-mode) instead.

## Workflow

1. Read the description template:

   `Read(references/pr_description_template.md)`

2. Identify or create the pull request:
   - Check the current branch for a PR with `gh pr view --json url,number,title,state,baseRefName,headRefName 2>/dev/null`.
   - If no PR exists, first check whether a stenswf workflow owns the branch:

     ```bash
     bash scripts/workflow-issue.sh
     ```

     If it prints `<skill> <N>`, stop: tell the user the branch belongs to stenswf issue #N and ships through `/stenswf:<skill>`, which owns its commits, decision trailers, CI, and merge. Do not commit, push, or create a PR.
   - Otherwise, inspect `git status --short --branch` and the commits on the current branch.
   - Commit task-related changes when needed, push the branch with an upstream, and create a PR for it. Follow the repository's git safety protocol.
   - Ask the user to select a PR only when the current branch has no relevant work and there is no safe current-branch PR to create.

3. Gather only the context needed to explain the change:
   - Read the ticket and any relevant task artifacts. For a stenswf PR, the ticket is the issue in its `Closes #N` line, and `.stenswf/<N>/` holds its local artifacts.
   - Read the complete PR diff and enough surrounding code to understand behavior and ownership.
   - Use `gh pr view` to collect PR metadata and changed files.
   - Read `references/show-me.md` for the visual-outline conventions used in the PR body.

4. Write the PR description using the template:
   - Keep **Why the change** to exactly one sentence.
   - Keep **Special things to note** to 1-3 bullets. Prioritize reviewer warnings, migrations, compatibility constraints, deliberate omissions, or surprising decisions. Write `- None.` when there are no special considerations.
   - Make **Change outline** a compact, `/show-me`-inspired structural view rather than prose or a file-by-file changelog.
   - When no view helps — a wording fix, a one-line configuration change — one or two plain sentences are enough. Never draw a diagram for its own sake.
   - Describe the change actually delivered. A PRD or slice `## Change outline` may lend vocabulary, but it illustrates the plan, not the result.
   - Include only the views that help explain this PR:
     - SQL table and endpoint contract changes, plus pseudocode for business logic.
     - key data structure / type changes
     - A shallow file tree showing changed responsibilities.
     - React component tree changes, including important hooks, state, and package boundaries.
     - Call-tree, call-stack, control-flow, or data-flow changes.
   - Prefer `diff` blocks when showing changes to an existing shape. Show the complete target shape when most of it is new or diff notation would obscure ownership or order.
   - Keep each view focused on what a reviewer needs. Omit categories that did not change.
   - optional: if you are aware of a ticket id/url, a stenswf issue, PRD, or slice url, related plan/document urls, or other relevant links, include them in the header, otherwise omit the header

5. Save and publish the description:
   - Pick the local files: for a PR that closes a stenswf issue `<N>`, `.stenswf/<N>/pr-description.md` and `.stenswf/<N>/pr-region.md`; otherwise `.stenswf/pr-{number}/description.md` and `.stenswf/pr-{number}/region.md`. Create the folder first — it is excluded from git for this clone, even where stenswf's bootstrap never ran:

     ```bash
     bash ../../scripts/ensure-stenswf-dir.sh <N>   # or pr-{number}
     ```

   - Write the sections this skill owns — **Why the change**, **Special things to note**, and **Change outline** — without the markers, to the region file.
   - A PR you just created: compose the whole description at the description path, then publish it:

     ```bash
     bash scripts/pr-body.sh compose --out {description-path} --region {region-path} --closing "Closes #<N>"
     gh pr edit {number} --body-file {description-path}
     ```

     Add `--header {header-path}` when you wrote a links line; drop `--closing` when the PR closes no issue.
   - An existing PR: replace only the region. The links header, closing line, evidence sections, and `## Decisions` block stay untouched, and the complete result is saved at the description path:

     ```bash
     bash scripts/pr-body.sh pr {number} {region-path} {description-path}
     ```

     A body that already follows the upstream template is migrated; any other unmarked body gets the region prepended; a body with broken markers is refused — report it and stop.
   - Confirm the update succeeded.

6. Report completion:
   - Read `references/describe_pr_final_answer.md`.
   - Respond using that final answer template with the PR URL, saved description path, and concise list of changed files.

Always read and follow `references/pr_description_template.md`. Do not expand the PR body beyond that template and the caller's evidence sections.

Write as one human talking to another: avoid jargon and slang, and use simple, coherent, concise language.

## Body-only mode

`ship`, `ship-light`, and apply PRD-mode load this skill to write their PR description. They pass five inputs and create the PR themselves:

- **issue context** — a local file holding the issue body
- **base ref** — the PR's target, e.g. `origin/<default>`; `git diff "<base ref>...HEAD"` is the same comparison GitHub shows
- **evidence** — the caller's evidence file
- **closing line** — for example `Closes #<N>`
- **output** — where the description goes

In this mode, make no `gh` calls, discover no workflow state, and produce no HTML — nobody is there to open it; use the closest view GitHub renders instead.

1. Read `references/pr_description_template.md`, `references/show-me.md`, the issue context, and the complete diff: `git diff "<base ref>...HEAD"`.
2. Write the three sections this skill owns to `pr-region.md` next to the output, following step 4's rules. If you know relevant links, write them as one line to `pr-header.md` next to it.
3. Compose — the evidence is appended byte for byte, never retyped:

   ```bash
   bash scripts/pr-body.sh compose --out <output> --region <output-dir>/pr-region.md --closing "<closing line>" --evidence <evidence>
   ```

   Add `--header <output-dir>/pr-header.md` when you wrote one.
4. Return to the caller. It appends the `## Decisions` block and creates the PR.
