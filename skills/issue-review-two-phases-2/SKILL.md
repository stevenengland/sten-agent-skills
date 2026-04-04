---
name: issue-review-two-phases-2
description: >
  Review staged git changes against an issue. Produces a structured improvement
  plan — no edits applied. Also identifies test file compaction opportunities.
  Use when asked to check, review, or validate staged work before committing.
  Part 2 of 3 in the issue-review-two-phases workflow.
disable-model-invocation: true
---

You are in **plan-only mode**. Do not apply edits, create files, or run any
state-modifying commands. Your only output is a structured plan that you add to the issue as a comment and to a local but temporary/untracked file named `issue <number> review plan.md`.

Review staged changes against issue number $ARGUMENTS.

## Step 1 — Change Review

Invoke your plan-reviewer skill and follow the process to generate a structured improvement plan.

## Step 2 — Test Compaction

Invoke your test-file-compaction skill. Identify opportunities to reduce
test file size without losing coverage.

## Output

Produce a numbered list of suggestions. For each item state:

1. **What** — what should change
2. **Why** — why it improves the code
3. **Priority** — low / medium / high

Close with a one-line summary: how many suggestions are high, medium, and
low priority. Remember to save the plan to `issue <number> review plan.md` and add it as a comment to the issue.
