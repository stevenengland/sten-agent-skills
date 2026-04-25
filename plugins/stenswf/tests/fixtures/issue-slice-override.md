<!-- Expected: type="slice — AFK"; lite_eligible="false";
     disqualifier="files>15"; lite_override non-empty
     → plan-light / ship-light Phase 0 honor override, log
     `user_override`, and proceed on the lite path. -->

<!-- stenswf:v1
type: slice — AFK
lite_eligible: false
conventions_source: prd
prd_ref: "42"
disqualifier: files>15
lite_override: mechanical rename via codemod — no behavioral change, existing tests pin behavior
prd_base_sha: 0123456abcdef
-->

## What to build

Rename the legacy `UserAccount` symbol to `User` across the codebase
via a single AST codemod. Touches ~100 files. No behavioral change.

## Acceptance criteria

- [ ] All references to `UserAccount` are renamed to `User`.
- [ ] No semantic edits leak into the diff (only renames).
- [ ] Full existing test suite stays green.

## Conventions (from PRD)

None — slice-local decisions only.

## Files (hint)

- codemod script
- ~100 files matching `UserAccount`

## Blocked by

None.

## Parent PRD

#42
