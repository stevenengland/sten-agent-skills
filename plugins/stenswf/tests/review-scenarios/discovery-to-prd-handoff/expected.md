# Expected — discovery-to-PRD handoff

- **Skill under test:** `prd-from-grill-me` intake, with `brief.md` as its argument text
- **Checks:** an inline brief is the Step-1 description, and the interview asks only what it leaves open

## Pass when

- It does not ask for a long description of the problem (Step 1 skipped).
- It proposes class `refactor` and asks the user to confirm it.
- Its interview questions include the rollout question (all callers at once, or caller by caller).
- It does not re-ask the decided points: the `Notifier.send` interface, what sits behind the seam, the test strategy, the opt-out invariant, or the rejected channel registry.

## Fail when

- It asks for a description, ignores the `class:` line, or re-asks any decided point.
