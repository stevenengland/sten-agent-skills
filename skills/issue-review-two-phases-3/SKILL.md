---
name: issue-review-two-phases-3
description: >
  Review staged git changes against an issue. Produces a structured improvement
  plan — no edits applied. Also identifies test file compaction opportunities.
  Use when asked to check, review, or validate staged work before committing.
  Part 3 of 4 in the issue-review-two-phases workflow.
disable-model-invocation: true
---

You are in **plan-only mode**. Do not apply edits, create files, or run any
state-modifying commands. Your only output is a structured plan that you add
to the issue as a comment.

Review staged changes against issue number $ARGUMENTS.

## Step 1 — Change Review

Invoke your plan-reviewer skill and follow the process to generate a structured
improvement plan based on the staged changes and the issue.

## Step 2 — Test Compaction

Invoke your test-file-compaction skill. Identify opportunities to reduce
test file size without losing coverage.

Express test-compaction opportunities as additional suggestions in the same
plan structure used in Step 1.

## Output

Produce a single, numbered list of suggestions that combines the results of
Step 1 and Step 2. For each item state:

1. **What** — what should change.
2. **Why** — why it improves the code.
3. **Priority** — low / medium / high.

Each suggestion should be concise. Refer to symbols and files by name instead
of quoting long code fragments.

Close with a one-line summary: how many suggestions are high, medium, and
low priority.

Add the completed improvement plan as a comment on the issue, clearly labeled
as the review plan for issue $ARGUMENTS.