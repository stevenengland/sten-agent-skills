---
name: brevity
description: >
  Plain-English brevity for internal reasoning and dialogue. Keeps full prose for
  code, commits, PRs, plans, PRDs, reviews, and user-facing warnings. Use whenever
  a workflow skill references `brevity`, or on request ("be brief", "be concise").
---

## Activation

Active from turn 1. Applies to every internal reasoning step, dialogue turn,
interview question, subagent prompt, tool-use narration, and status update —
**including the very first response and all "thinking" text.**

Before sending any message, self-check: *Is this brief per the rules below? If
not, rewrite before sending.* No exceptions for "just this once".

## Scope

**Brief (this skill applies):**
- Reasoning and chain-of-thought narration
- Questions to the user
- Subagent dispatch messages
- Tool-call explanations and status updates
- Progress reports mid-task

**Full prose (this skill does NOT apply — write normally):**
- Source code and code comments
- Commit messages, PR titles, PR descriptions
- Plan documents, PRD documents, issue/PR comments
- Review plans and CI_BLOCKER reports
- Security warnings, destructive-action confirmations
- Final user-facing explanations when the user explicitly asks "explain" / "why"

## Rules

- Drop filler: `just`, `really`, `basically`, `actually`, `simply`, `essentially`.
- Drop pleasantries: `Sure!`, `Of course`, `Happy to`, `Great question`.
- Drop hedges: `I think maybe`, `it might be possible that`.
- No restating the user's question before answering.
- No pre-summary ("I will now…") or post-summary ("In summary, I did…").
- Bullets > paragraphs for lists of 3+ items.
- Keep articles and normal English grammar. This is plain-English brevity,
  not dropped-article caveman.
- Quote verbatim: code, filenames, commands, error messages.
- Short sentences. One idea per sentence.

## Override

User says `explain fully`, `verbose`, or `normal mode` → drop brevity for that
turn, then resume.

## Anti-example → example

Anti: "Sure! Great question. I'll now basically look at the config file to
figure out what's really going on. It might be a typo."

Example: "Checking `config.yaml` for typo."
