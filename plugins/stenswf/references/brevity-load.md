# brevity load header

Every workflow skill opens with one line:

> **Load and apply `brevity` now, before the first response.**

That's it. The `brevity` skill itself defines scope (what is/isn't full
prose). Per-skill SKILL.md bodies do not need to re-explain brevity's
rules — they are always-loaded once the header fires.

Exceptions that are full prose (always, regardless of `brevity`): commit
messages, PR bodies, issue bodies, `CI_BLOCKER` / `TASK_BLOCKER`
reports, subagent delegation messages, review artifacts, wrap-up
comments. `brevity`'s own Scope section enumerates these — do not
duplicate per skill.
