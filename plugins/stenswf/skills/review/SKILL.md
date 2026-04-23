---
name: review
description: Review changes against an issue/pr. 
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` sibling skill now, before the first response.**
It governs reasoning and status updates during the review. The review-plan
comment posted to the issue is a full-prose artifact (already excluded by
`brevity`'s Scope section) — write it normally.

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