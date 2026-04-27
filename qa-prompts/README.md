# QA Prompts

Reusable quality-assurance prompts fired regularly against this repository.

Each file is a single, self-contained prompt with:
- **Purpose** — what bug class it hunts.
- **Inputs** — variables to fill in before sending.
- **Prompt** — paste-ready body.

Conventions:
- QA prompts are **read-only**: agents must not modify files in the repo.
- Findings must cite `path/file.md#Lx` so claims are auditable.
- When two agents are dispatched, both must run the **same test matrix** so their
  reports are diff-able.
